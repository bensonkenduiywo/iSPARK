import rasterio
import numpy as np
import matplotlib.pyplot as plt

# Path to your multiband GeoTIFF
tif_path = "/cluster01/Projects/USA_IDA_AICCRA/1.Data/RAW/ispark/MODIS_NDVI_2000_2025_tiles/tile_0000.tif"

# Open the GeoTIFF
with rasterio.open(tif_path) as src:  # loads in bands, rows, cols
    print("File info:")
    print(f"  CRS: {src.crs}")
    print(f"  Width x Height: {src.width} x {src.height}")
    print(f"  Band count: {src.count}")
    print(f"  Data type: {src.dtypes[0]}")
    print(f"  No data value: {src.nodata}")
    print(f"  Bands: {src.descriptions}")

    # Read first three bands
    bands = src.read([1, 2, 3]).astype(float)

    # Mask out no-data values (-9999)
    nodata = src.nodata if src.nodata is not None else -9999
    bands[bands == nodata] = np.nan

    # Clip values between 0 and 1
    bands = np.clip(bands, 0, 1)

    # Normalize each band to 0–1 range (optional but helps visualization)
    bands = np.nan_to_num(bands)
    bands_min = np.nanmin(bands, axis=(1, 2), keepdims=True)
    bands_max = np.nanmax(bands, axis=(1, 2), keepdims=True)
    rgb = (bands - bands_min) / (bands_max - bands_min + 1e-6)

    # Transpose to (height, width, 3)
    rgb = np.transpose(rgb, (1, 2, 0))  # plots in rows, cols, bands

# Display RGB composite
plt.figure(figsize=(8, 8))
plt.imshow(rgb)
plt.title("RGB Composite (Bands 1–3)")
plt.axis('off')
plt.show()
