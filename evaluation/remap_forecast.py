import logging
import multiprocessing

import numpy as np
import xarray as xr
from tqdm import tqdm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

_WORKER_MAPPER = None


def _init_worker(latitudes: int, longitudes: int, nside: int) -> None:
    """Create a HEALPix remapper in each multiprocessing worker."""
    global _WORKER_MAPPER
    import data_processing.remap.healpix as hpx

    _WORKER_MAPPER = hpx.HEALPixRemap(
        latitudes=latitudes,
        longitudes=longitudes,
        nside=nside,
        verbose=False,
    )


def _remap_hpx_slice(data: np.ndarray) -> np.ndarray:
    return _WORKER_MAPPER.hpx2ll(data)


def _iter_step_slices(fcst: xr.DataArray, time_index: int, step_start: int, step_stop: int):
    for step_index in range(step_start, step_stop):
        yield fcst.isel(time=time_index, step=step_index).values


def _create_output_file(
    outfile: str,
    var: str,
    time: xr.DataArray,
    step: xr.DataArray,
    latitudes: int,
    longitudes: int,
    time_chunk: int,
    step_chunk: int,
    chunk_ds: bool,
) -> None:
    """Write coordinate metadata, then add a chunked data variable without filling it."""
    import netCDF4 as nc4

    n_time = len(time)
    n_step = len(step)
    template = xr.Dataset(
        coords={
            "time": time,
            "step": step,
            "lat": ("lat", np.arange(90, -90.1, -1)),
            "lon": ("lon", np.arange(0, 360, 1)),
        }
    )
    template.to_netcdf(outfile)

    chunksizes = None
    if chunk_ds:
        chunksizes = (
            min(max(time_chunk, 1), n_time),
            min(max(step_chunk, 1), n_step),
            latitudes,
            longitudes,
        )

    with nc4.Dataset(outfile, "a") as ds:
        ds.createVariable(
            var,
            "f4",
            ("time", "step", "lat", "lon"),
            chunksizes=chunksizes,
            fill_value=False,
            zlib=False,
        )


def _remap_step_range(
    fcst: xr.DataArray,
    mapper,
    pool,
    time_index: int,
    step_start: int,
    step_stop: int,
    out: np.ndarray,
) -> None:
    n_step = step_stop - step_start
    if n_step <= 0:
        return
    if pool is None:
        for local_j, j in enumerate(range(step_start, step_stop)):
            out[local_j] = mapper.hpx2ll(fcst.isel(time=time_index, step=j).values)
        return

    remapped_steps = pool.imap(
        _remap_hpx_slice,
        _iter_step_slices(fcst, time_index, step_start, step_stop),
        chunksize=1,
    )
    for local_j, remapped in enumerate(remapped_steps):
        out[local_j] = remapped
    if local_j + 1 != n_step:
        raise RuntimeError(
            f"Expected {n_step} remapped steps, received {local_j + 1} "
            f"for time index {time_index}, steps [{step_start}:{step_stop}]."
        )


def main(
    infile: str,
    outfile: str,
    var: str,
    poolsize: int = 1,
    time_chunk: int = 1,
    step_chunk: int = 1,
    chunk_ds: bool = True,
    latitudes: int = 181,
    longitudes: int = 360,
    nside: int = 64,
) -> None:
    """
    Remap forecast data from healpix to lat lon grid. Assumes HPX64 input and 1-degree lat lon output.

    Processes (time, step) tiles so neither a long initialization axis nor a long lead-time
    axis needs to fit in memory at once. Optional multiprocessing remaps lead times within
    each step tile in parallel.

    param infile: path to input healpix forecast file
    param outfile: path to output lat lon remapped forecast file
    param var: variable name to remap
    param poolsize: number of worker processes; values < 2 run sequentially
    param time_chunk: number of initialization times to buffer before each netCDF write
    param step_chunk: number of lead times to buffer before each netCDF write
    param chunk_ds: write the output variable with netCDF chunks for lazy reads
    """
    try:
        import data_processing.remap.healpix as hpx
        import netCDF4 as nc4
    except ImportError as e:
        logger.error(
            "Failed to import remapping dependencies. Run this utility from the project "
            "root directory (DLESyM/) with the repo on PYTHONPATH, and ensure netCDF4 is installed."
        )
        raise ImportError(str(e)) from e

    mapper = hpx.HEALPixRemap(
        latitudes=latitudes,
        longitudes=longitudes,
        nside=nside,
        verbose=False,
    )

    ds_in = xr.open_dataset(infile)
    if var is None:
        raise ValueError(
            f"No variable specified for remapping. Available variables are: {list(ds_in.data_vars.keys())}"
        )
    if var not in ds_in.data_vars:
        raise ValueError(
            f"Variable {var} not found in forecast file. Available variables are: {list(ds_in.data_vars.keys())}"
        )
    fcst = ds_in[var]

    if "height" in fcst.sizes and fcst.sizes["height"] != nside:
        logger.warning(
            "Input height=%s does not match nside=%s; remapping with nside=%s",
            fcst.sizes["height"],
            nside,
            nside,
        )

    time = fcst["time"]
    step = fcst["step"]
    n_time = len(time)
    n_step = len(step)
    time_chunk = max(int(time_chunk), 1)
    step_chunk = max(int(step_chunk), 1)

    logger.info(
        "Remapping %s from healpix to lat-lon "
        "(times=%s, steps=%s, poolsize=%s, time_chunk=%s, step_chunk=%s)",
        var,
        n_time,
        n_step,
        poolsize,
        time_chunk,
        step_chunk,
    )
    _create_output_file(
        outfile=outfile,
        var=var,
        time=time,
        step=step,
        latitudes=latitudes,
        longitudes=longitudes,
        time_chunk=time_chunk,
        step_chunk=step_chunk,
        chunk_ds=chunk_ds,
    )

    tile_times = min(time_chunk, n_time)
    tile_steps = min(step_chunk, n_step)
    try:
        write_buffer = np.zeros(
            (tile_times, tile_steps, latitudes, longitudes),
            dtype=np.float32,
        )
    except MemoryError as e:
        logger.error(
            "Not enough memory for time_chunk=%s, step_chunk=%s. Reduce those values "
            "(each tile holds time_chunk x step_chunk x %s x %s).",
            time_chunk,
            step_chunk,
            latitudes,
            longitudes,
        )
        raise MemoryError(str(e)) from e

    pool = None
    if poolsize >= 2:
        pool = multiprocessing.Pool(
            processes=poolsize,
            initializer=_init_worker,
            initargs=(latitudes, longitudes, nside),
        )

    try:
        with nc4.Dataset(outfile, "a") as ds_out:
            out_var = ds_out.variables[var]
            pbar_time = tqdm(total=n_time, desc="Time", unit="init")
            try:
                for i0 in range(0, n_time, time_chunk):
                    i1 = min(i0 + time_chunk, n_time)
                    n_t = i1 - i0
                    pbar_step = tqdm(
                        total=n_step,
                        desc=f"Step (t={i0}:{i1})",
                        unit="step",
                        leave=False,
                    )
                    try:
                        for j0 in range(0, n_step, step_chunk):
                            j1 = min(j0 + step_chunk, n_step)
                            n_s = j1 - j0
                            for local_i, i in enumerate(range(i0, i1)):
                                _remap_step_range(
                                    fcst=fcst,
                                    mapper=mapper,
                                    pool=pool,
                                    time_index=i,
                                    step_start=j0,
                                    step_stop=j1,
                                    out=write_buffer[local_i, :n_s],
                                )
                            out_var[i0:i1, j0:j1, :, :] = write_buffer[:n_t, :n_s]
                            ds_out.sync()
                            pbar_step.update(n_s)
                    finally:
                        pbar_step.close()
                    pbar_time.update(n_t)
            finally:
                pbar_time.close()
    finally:
        if pool is not None:
            pool.terminate()
            pool.join()
        ds_in.close()

    logger.info("Wrote remapped forecast data to %s", outfile)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Remap forecast data from healpix to lat-lon grid."
    )
    parser.add_argument(
        "--infile",
        type=str,
        required=True,
        help="Path to input healpix forecast file.",
    )
    parser.add_argument(
        "--outfile",
        type=str,
        required=True,
        help="Path to output lat-lon remapped forecast file.",
    )
    parser.add_argument(
        "--var",
        type=str,
        required=True,
        help="Variable name to remap.",
    )
    parser.add_argument(
        "--poolsize",
        type=int,
        default=1,
        help="Number of processes for parallel remapping of lead times. "
        "Values < 2 run sequentially (same as data_processing.remap.healpix).",
    )
    parser.add_argument(
        "--time-chunk",
        type=int,
        default=1,
        help="Number of initialization times to hold in memory and write together. "
        "Use 1 to minimize memory (default).",
    )
    parser.add_argument(
        "--step-chunk",
        type=int,
        default=1,
        help="Number of lead times (step) to hold in memory and write together. "
        "Use this for single-initialization forecasts with many steps. "
        "Use 1 to minimize memory (default).",
    )
    parser.add_argument(
        "--chunk-ds",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Write the output NetCDF variable in chunks for lazy reads "
        "(same option as HEALPixRemap.remap). Default: enabled.",
    )

    args = parser.parse_args()

    main(
        infile=args.infile,
        outfile=args.outfile,
        var=args.var,
        poolsize=args.poolsize,
        time_chunk=args.time_chunk,
        step_chunk=args.step_chunk,
        chunk_ds=args.chunk_ds,
    )
