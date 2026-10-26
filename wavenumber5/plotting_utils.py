import matplotlib.pyplot as plt
from cartopy import crs as ccrs
import numpy as np

def plot_z250(ds):
    fig = plt.figure(figsize=(12,8))
    ax = fig.add_subplot(1, 1, 1, projection=ccrs.PlateCarree(central_longitude=180))
    im = ds.plot.contourf(ax=ax, transform=ccrs.PlateCarree(), levels=20, cmap="RdBu_r", add_colorbar=False)

    # set extent to 0, 360, 0, 90
    ax.set_extent([-180,180, 0, 90], crs=ccrs.PlateCarree())

    # make colorbar horizontal
    cbar = ax.figure.colorbar(im, ax=ax, orientation="horizontal", shrink=.8)
    cbar.set_label(f"Z250 (m$^2$s$^{-2}$)")

    # set minor lat ticks every 10 and major at 0, 30, 60, 90
    # ax.set_yticks(np.arange(0, 91, 10))
    # ax.set_yticklabels(np.arange(0, 91, 30))

    ax.coastlines()
    # fig.tight_layout()

    return fig, ax

def plot_t2m0(ds):
    fig = plt.figure(figsize=(12,8))
    ax = fig.add_subplot(1, 1, 1, projection=ccrs.PlateCarree(central_longitude=180))
    im = ds.plot.contourf(ax=ax, transform=ccrs.PlateCarree(), levels=20, cmap="RdBu_r", add_colorbar=False)

    # set extent to 0, 360, 0, 90
    ax.set_extent([-180,180, 0, 90], crs=ccrs.PlateCarree())

    # make colorbar horizontal
    cbar = ax.figure.colorbar(im, ax=ax, orientation="horizontal", shrink=.8)
    cbar.set_label(f"T$_2m$ (degrees C)")

    # set minor lat ticks every 10 and major at 0, 30, 60, 90
    # ax.set_yticks(np.arange(0, 91, 10))
    # ax.set_yticklabels(np.arange(0, 91, 30))

    ax.coastlines()
    # fig.tight_layout()

    return fig, ax