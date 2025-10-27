import rasterio
from rasterio.enums import Resampling

path_in = "tile_0000.tif"
path_out = "tile_0000_named.tif"

with rasterio.open(path_in) as src:
    meta = src.meta.copy()
    meta.update(driver="GTiff")

    band_count = src.count
    new_names = [f"NDVI_{2000 + i//6}_{(i % 6) + 3}" for i in range(band_count)]

    with rasterio.open(path_out, "w", **meta) as dst:
        for i in range(1, band_count + 1):
            dst.write(src.read(i), i)
            dst.set_band_description(i, new_names[i - 1])
