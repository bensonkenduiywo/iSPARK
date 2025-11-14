import rasterio
import numpy as np
import re
import matplotlib.pyplot as plt
import os

# ==============================
# 1. Read multiband GeoTIFF
# ==============================
tif_path = "/cluster01/Projects/USA_IDA_AICCRA/1.Data/RAW/ispark/FLDAS_sm_2000_2025_tiles/tile_0000.tif"
with rasterio.open(tif_path) as src:
    data = src.read()  # shape: (bands, rows, cols)
    band_names = src.descriptions  # e.g. ("SM_2000_1", "SM_2000_2", ...)
    profile = src.profile

print(f"Loaded {len(band_names)} bands")

# ==============================
# 2. Parse band names to get year and month
# ==============================
band_info = []
pattern = re.compile(r"SM_(\d{4})_(\d+)")  # extract year and month digit
for i, bname in enumerate(band_names):
    match = pattern.match(bname)
    if match:
        year, month = int(match.group(1)), int(match.group(2))
        band_info.append((i, year, month))
    else:
        raise ValueError(f"Unexpected band name format: {bname}")

# ==============================
# 3. Aggregate March–August (1–6) per year
# ==============================
yearly_means = {}
for year in sorted(set(y for _, y, _ in band_info)):
    # Select all March–August bands for that year
    bands_idx = [i for i, y, m in band_info if y == year and 1 <= m <= 6]
    if not bands_idx:
        continue

    # Compute mean across selected bands
    yearly_stack = data[bands_idx, :, :]
    yearly_mean = np.nanmean(yearly_stack, axis=0)
    yearly_means[year] = yearly_mean

print(f"Generated {len(yearly_means)} yearly composites")

# ==============================
# 4. Compute long-term mean (2000–2024) and 2025 deviation
# ==============================
years_all = sorted(yearly_means.keys())
current_year = 2025
historical_years = [y for y in years_all if y < current_year]

# Stack and compute mean of historical years
historical_stack = np.stack([yearly_means[y] for y in historical_years])
historical_mean = np.nanmean(historical_stack, axis=0)

# Compute deviation (2025 - historical mean)
deviation = yearly_means[current_year] - historical_mean