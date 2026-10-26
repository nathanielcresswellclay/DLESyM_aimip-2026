#!/usr/bin/env python3
"""Linear trend of seasonal averages along the forecast step axis.

For a long simulation the ``step`` dimension spans many calendar years. This
utility keeps only timesteps that fall in a requested season (DJF, MAM, JJA,
SON), averages each available season-year, and fits a linear trend of those
seasonal means versus year. The resulting slope maps are written as a 3-D
NetCDF with dimensions ``('time', 'lat', 'lon')`` — one time level per season.

``step`` may be datetime (valid time already) or timedelta (lead time). In the
timedelta case valid time is ``init time + step``.
"""

from __future__ import annotations

import logging
from typing import Iterable, Sequence

import numpy as np
import pandas as pd
import xarray as xr

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SEASONS = ("DJF", "MAM", "JJA", "SON")
SEASON_MONTHS = {
    "DJF": (12, 1, 2),
    "MAM": (3, 4, 5),
    "JJA": (6, 7, 8),
    "SON": (9, 10, 11),
}
# Canonical dates so the output time axis is datetime64, not season strings.
SEASON_TIME = {
    "DJF": np.datetime64("2000-01-15"),
    "MAM": np.datetime64("2000-04-15"),
    "JJA": np.datetime64("2000-07-15"),
    "SON": np.datetime64("2000-10-15"),
}


def _is_datetime_coord(coord: xr.DataArray) -> bool:
    return np.issubdtype(coord.dtype, np.datetime64)


def _is_timedelta_coord(coord: xr.DataArray) -> bool:
    return np.issubdtype(coord.dtype, np.timedelta64)


def _rename_latlon(da: xr.DataArray) -> xr.DataArray:
    rename = {}
    if "latitude" in da.dims:
        rename["latitude"] = "lat"
    if "longitude" in da.dims:
        rename["longitude"] = "lon"
    return da.rename(rename) if rename else da


def assign_valid_time(da: xr.DataArray) -> xr.DataArray:
    """Return a DataArray whose time axis is valid datetime along ``step``.

    - Datetime ``step``: treat it as valid time.
    - Timedelta ``step``: valid time is init ``time`` + ``step``.
    - Singleton init ``time`` is squeezed so the result is 3-D (time, lat, lon)
      after renaming ``step`` -> ``time``.
    """
    if "step" not in da.dims:
        if "time" in da.dims and _is_datetime_coord(da["time"]):
            return da
        raise ValueError(
            "Input must have a 'step' dimension, or a datetime 'time' dimension. "
            f"Got dims {tuple(da.dims)}."
        )

    step = da["step"]
    init = da["time"] if "time" in da.coords else None

    if _is_timedelta_coord(step):
        if init is None:
            raise ValueError(
                "Timedelta 'step' requires an initialization 'time' coordinate "
                "so valid time can be computed as time + step."
            )
        if "time" in da.dims:
            if da.sizes["time"] != 1:
                raise ValueError(
                    "Seasonal trends are computed for a single long simulation "
                    f"(one initialization). Got time size {da.sizes['time']}."
                )
            init_value = da["time"].values[0]
            da = da.isel(time=0, drop=True)
        else:
            init_value = np.asarray(init.values).reshape(-1)[0]
            da = da.drop_vars("time") if "time" in da.coords else da
        da = da.assign_coords(step=init_value + da["step"])
    elif _is_datetime_coord(step):
        if "time" in da.dims:
            if da.sizes["time"] != 1:
                raise ValueError(
                    "Seasonal trends are computed for a single long simulation "
                    f"(one initialization). Got time size {da.sizes['time']}."
                )
            da = da.isel(time=0, drop=True)
        elif "time" in da.coords:
            da = da.drop_vars("time")
    else:
        raise ValueError(
            f"Unsupported 'step' dtype {step.dtype}; expected datetime64 or timedelta64."
        )

    return da.rename({"step": "time"})


def _season_year(times: np.ndarray) -> np.ndarray:
    """Year label for a season instance. DJF is labelled by the January year."""
    t = pd.to_datetime(np.asarray(times))
    year = t.year.to_numpy()
    month = t.month.to_numpy()
    return np.where(month == 12, year + 1, year)


def complete_season_years(times: np.ndarray, months: Sequence[int]) -> list[int]:
    """Years that contain every month of the season."""
    t = pd.to_datetime(np.asarray(times))
    month = t.month.to_numpy()
    season_year = _season_year(times)
    keep = np.isin(month, months)
    months_by_year: dict[int, set[int]] = {}
    for sy, m, ok in zip(season_year, month, keep):
        if not ok:
            continue
        months_by_year.setdefault(int(sy), set()).add(int(m))
    needed = set(months)
    return sorted(year for year, present in months_by_year.items() if present == needed)


def seasonal_means(da: xr.DataArray, season: str) -> xr.DataArray:
    """Yearly mean of ``da`` over one meteorological season."""
    if season not in SEASON_MONTHS:
        raise ValueError(f"Unknown season {season!r}; choose from {SEASONS}.")
    months = SEASON_MONTHS[season]
    in_season = da.time.dt.month.isin(list(months))
    da_season = da.where(in_season, drop=True)
    if da_season.sizes.get("time", 0) == 0:
        raise ValueError(f"No timesteps found for season {season}.")

    years = complete_season_years(da_season.time.values, months)
    if len(years) < 2:
        raise ValueError(
            f"Need at least two complete {season} seasons to fit a trend; "
            f"found {len(years)}."
        )

    season_year = xr.DataArray(
        _season_year(da_season.time.values),
        dims=("time",),
        coords={"time": da_season.time},
        name="season_year",
    )
    da_season = da_season.assign_coords(season_year=season_year)
    yearly = da_season.groupby("season_year").mean("time")
    yearly = yearly.sel(season_year=years)
    yearly = yearly.rename({"season_year": "year"})
    logger.info(
        "Season %s: %s complete years (%s–%s)",
        season,
        yearly.sizes["year"],
        int(yearly.year.min()),
        int(yearly.year.max()),
    )
    return yearly


def linear_trend(yearly: xr.DataArray) -> xr.DataArray:
    """Slope of yearly seasonal means versus year (units of the field per year)."""
    yearly = yearly.compute()
    fit = yearly.polyfit(dim="year", deg=1)
    slope = fit.polyfit_coefficients.sel(degree=1, drop=True)
    slope = slope.astype(np.float32)
    units = yearly.attrs.get("units")
    slope.attrs["long_name"] = f"linear trend of seasonal mean {yearly.name}"
    slope.attrs["units"] = f"{units} year-1" if units else "year-1"
    return slope


def seasonal_trends(
    da: xr.DataArray,
    seasons: Iterable[str] = SEASONS,
) -> xr.DataArray:
    """Trend maps for each season, concatenated along ``time``."""
    da = _rename_latlon(assign_valid_time(da))
    if "lat" not in da.dims or "lon" not in da.dims:
        raise ValueError(
            f"Expected lat/lon (or latitude/longitude) dimensions, got {tuple(da.dims)}."
        )

    maps = []
    season_names = []
    for season in seasons:
        yearly = seasonal_means(da, season)
        slope = linear_trend(yearly)
        slope = slope.expand_dims(time=[SEASON_TIME[season]])
        maps.append(slope)
        season_names.append(season)

    out = xr.concat(maps, dim="time")
    out = out.assign_coords(season=("time", season_names))
    out = out.transpose("time", "lat", "lon")
    if da.name is not None:
        out.name = f"{da.name}_trend"
    else:
        out.name = "trend"
    out.attrs["description"] = (
        "Linear trend of yearly seasonal averages along the forecast step axis."
    )
    return out


def _open_chunks(time_chunk: int, step_chunk: int) -> dict[str, int]:
    chunks: dict[str, int] = {}
    if time_chunk is not None:
        chunks["time"] = max(int(time_chunk), 1)
    if step_chunk is not None:
        chunks["step"] = max(int(step_chunk), 1)
    return chunks


def main(
    input_file: str,
    output_file: str,
    var: str | None = None,
    seasons: Sequence[str] = SEASONS,
    time_chunk: int = 1,
    step_chunk: int = 512,
    remove_zonal_mean = False, 
) -> None:
    chunks = _open_chunks(time_chunk, step_chunk)
    logger.info("Opening %s with chunks %s", input_file, chunks)
    ds = xr.open_dataset(input_file, chunks=chunks)

    if var is None:
        variables = list(ds.data_vars)
        if len(variables) != 1:
            raise ValueError(
                "Specify --var; available variables are: "
                f"{variables}"
            )
        var = variables[0]
    if var not in ds.data_vars:
        raise ValueError(
            f"Variable {var} not found. Available variables: {list(ds.data_vars)}"
        )

    seasons = tuple(season.upper() for season in seasons)
    unknown = [season for season in seasons if season not in SEASON_MONTHS]
    if unknown:
        raise ValueError(f"Unknown season(s) {unknown}; choose from {SEASONS}.")

    logger.info("Computing seasonal trends for %s, seasons=%s", var, list(seasons))
    trend = seasonal_trends(ds[var], seasons=seasons)

    n_time, n_lat, n_lon = (trend.sizes["time"], trend.sizes["lat"], trend.sizes["lon"])
    encoding = {
        trend.name: {
            "dtype": "float32",
            "zlib": False,
            "chunksizes": (n_time, n_lat, n_lon),
        }
    }

    if remove_zonal_mean:
        # Zonal (east-west) mean of the trend at each latitude and season.
        # An unweighted mean over lon is exact on a regular lat-lon grid, since
        # all grid cells along a latitude circle have equal area. skipna=True
        # so masked (NaN) cells, e.g. ocean-only fields over land, are ignored.
        logger.info("Removing zonal-mean trend from %s", trend.name)
        name, attrs = trend.name, dict(trend.attrs)
        zonal_mean = trend.mean(dim="lon", skipna=True)
        # Broadcasts over lon: each latitude row minus its own zonal mean.
        trend = (trend - zonal_mean).astype(np.float32)
        trend = trend.transpose("time", "lat", "lon")
        trend.name = name
        trend.attrs = attrs
        trend.attrs["long_name"] = (
            f"{attrs.get('long_name', 'linear trend')} (zonal mean removed)"
        )
        trend.attrs["zonal_mean_removed"] = "true"

    logger.info("Writing %s to %s", trend.name, output_file)
    trend.to_dataset(name=trend.name).to_netcdf(output_file, encoding=encoding)
    ds.close()
    logger.info("Done.")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description=(
            "Calculate the linear trend of seasonal averages over the step "
            "dimension of a long forecast/simulation and save a 3-D NetCDF "
            "(time, lat, lon)."
        )
    )
    parser.add_argument(
        "--input-file",
        "--infile",
        dest="input_file",
        type=str,
        required=True,
        help="Path to the input forecast/simulation NetCDF.",
    )
    parser.add_argument(
        "--output-file",
        "--outfile",
        dest="output_file",
        type=str,
        required=True,
        help="Path to the output trend NetCDF (time, lat, lon).",
    )
    parser.add_argument(
        "--var",
        type=str,
        default=None,
        help="Variable to process. Required if the file has more than one data variable.",
    )
    parser.add_argument(
        "--season",
        dest="seasons",
        nargs="+",
        default=list(SEASONS),
        choices=list(SEASONS),
        help="Season(s) to include. Default: DJF MAM JJA SON (one output time per season).",
    )
    parser.add_argument(
        "--time-chunk",
        type=int,
        default=1,
        help="Dask/xarray chunk size along the initialization time axis when reading.",
    )
    parser.add_argument(
        "--step-chunk",
        type=int,
        default=512,
        help="Dask/xarray chunk size along the step/lead-time axis when reading.",
    )
    parser.add_argument(
        "--remove-zonal-mean",
        action='store_true',
        default=False,
        help="Whether to remove zonal mean from calculation of linear trends. Flag indicates true",
    )
    args = parser.parse_args()
    main(
        input_file=args.input_file,
        output_file=args.output_file,
        var=args.var,
        seasons=args.seasons,
        time_chunk=args.time_chunk,
        step_chunk=args.step_chunk,
        remove_zonal_mean=args.remove_zonal_mean,
    )