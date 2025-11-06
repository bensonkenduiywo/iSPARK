#!/usr/bin/env python
# coding: utf-8

# Code reference: <a href="https://githubtocolab.com/giswqs/geemap/blob/master/examples/notebooks/46_local_rf_training.ipynb" target="_parent"><img src="https://colab.research.google.com/assets/colab-badge.svg" alt="Open in Colab"/></a>

# ## Set up Librareis and variables

# Export Images from GEE using: https://code.earthengine.google.com/74ceb413aa5dfdfe044e22f0b128625d
# 
# Before starting, assumming you are working in Linux, server do the following:
# 1. Create a virtual environment e.g. `conda create -n my-env` where `my-env` is the name of the virtual environment,
# 2. Activate the environment and install Jupyter notebooks `pip3 install --user ipykernel` and check if installed by running `which jupyter`,
# 3. Associate the notebook with your environment `python -m ipykernel install --user --name=crops-env`.
# 4. Install necessary packages (amongs others), e.g.`conda install -c conda-forge google-colab`, `conda install geemap -c conda-forge`, `conda install -c conda-forge matplotlib`, `conda install -c conda-forge earthengine-api` and `conda install --channel conda-forge geopandas`. Then set-up a service account for GEE cloud service account.
import os
import ee
import geemap
from google.oauth2 import service_account
import timeit
import time
from datetime import datetime

start_time = timeit.default_timer()

# ==============================
# 1. AUTHENTICATION
# ==============================
SERVICE_ACCOUNT_KEY = "private_key.json"

credentials = service_account.Credentials.from_service_account_file(
    SERVICE_ACCOUNT_KEY,
    scopes=[
        "https://www.googleapis.com/auth/earthengine",
        "https://www.googleapis.com/auth/drive"
    ]
)

ee.Initialize(credentials)
print("Earth Engine initialized successfully!")

geemap.ee_initialize()
print("GeeMap initialized!")

# ==============================
# 2. PARAMETERS
# ==============================
sResolution = 5000  # CHIRPS native resolution ~5km
start_year = 2000
end_year = 2025
season_start = 3   # March
season_end = 8     # August
timeField = 'system:time_start'

gee_project = "projects/cropmapping-365811"
asset_folder = "rwanda"
filename = f"CHIRPS_precip_{start_year}_{end_year}"
asset_id = f"{gee_project}/assets/{asset_folder}/{filename}"

# ==============================
# 3. REGION OF INTEREST
# ==============================
cList = ['Kisumu']
ROI = ee.FeatureCollection('users/bensonkemboi/Ke_admin/Kenya_county_dd')
ROI = ROI.filter(ee.Filter.inList('COUNTY_NAM', cList))

# ==============================
# 4. OPTIONAL CROPLAND MASK
# ==============================
esalandcover = ee.ImageCollection("ESA/WorldCover/v200").first()
datamask = (
    esalandcover.select('Map')
    .eq(90).add(esalandcover.select('Map').eq(40))
    .add(esalandcover.select('Map').eq(60))
    .add(esalandcover.select('Map').eq(30))
    .selfMask()
    .rename('cropland')
)

# ==============================
# 5. LOAD CHIRPS DAILY PRECIP
# ==============================
chirps = ee.ImageCollection('UCSB-CHG/CHIRPS/DAILY').filterDate(
    ee.Date.fromYMD(start_year, season_start, 1),
    ee.Date.fromYMD(end_year, season_end, 31)
)

print("CHIRPS daily data loaded successfully.")

# ==============================
# 6. COMPUTE TOTAL MONTHLY PRECIP
# ==============================
def monthly_total_precip(collection, start_year, end_year, month_start, month_end, mask=None):
    """Compute total monthly precipitation between given months."""
    images = []
    for year in range(start_year, end_year + 1):
        for month in range(month_start, month_end + 1):
            start = ee.Date.fromYMD(year, month, 1)
            end = start.advance(1, 'month')
            monthly_sum = collection.filterDate(start, end).sum()
            if mask is not None:
                monthly_sum = monthly_sum.updateMask(mask)
            monthly_sum = monthly_sum.set({
                'year': year,
                'month': month,
                'system:time_start': start.millis()
            })
            images.append(monthly_sum)
    return ee.ImageCollection(images)

precip_monthly = monthly_total_precip(chirps, start_year, end_year, season_start, season_end)
print(f"Monthly composites created: {precip_monthly.size().getInfo()}")

# ==============================
# 7. STACK INTO SINGLE MULTIBAND IMAGE
# ==============================
imageList = precip_monthly.toList(precip_monthly.size())
nMonths = precip_monthly.size().getInfo()

first_img = ee.Image(imageList.get(0))
year0 = ee.Number(first_img.get('year')).format()
month0 = ee.Number(first_img.get('month')).subtract(season_start).add(1).format()
bandNames0 = first_img.bandNames().map(
    lambda b: ee.String('rain_').cat(year0).cat('_').cat(month0)
)
bandStack = first_img.rename(bandNames0)

for i in range(1, nMonths):
    img = ee.Image(imageList.get(i))
    year = ee.Number(img.get('year')).format()
    monthIndex = ee.Number(img.get('month')).subtract(season_start).add(1).format()
    newNames = img.bandNames().map(
        lambda b: ee.String('rain_').cat(year).cat('_').cat(monthIndex)
    )
    renamed = img.rename(newNames)
    bandStack = bandStack.addBands(renamed)

# Optional: Apply cropland mask and clip
# bandStack = bandStack.updateMask(datamask).clip(ROI)

# ==============================
# 8. EXPORT TO ASSET
# ==============================
# Delete existing asset if exists
try:
    ee.data.deleteAsset(asset_id)
    print("Existing asset deleted for overwrite.")
except Exception:
    print("No existing asset found; proceeding to export.")

export_task = ee.batch.Export.image.toAsset(
    image=bandStack.clip(ROI),
    description=filename,
    assetId=asset_id,
    region=ROI.geometry(),
    scale=sResolution,
    crs='EPSG:4326',
    maxPixels=1e13
)

export_task.start()
print(f"Export task '{filename}' started...")

# ==============================
# 9. MONITOR EXPORT STATUS
# ==============================
while export_task.active():
    print("Export in progress... waiting 30s...")
    time.sleep(30)

status = export_task.status()
print(f"Export task completed with status: {status['state']}")

if status['state'] == 'FAILED':
    print(f"Error message: {status.get('error_message', 'No error message provided.')}")

print(f"Pre-processed raster saved to {asset_id}")
print("Elapsed time (hours):", (timeit.default_timer() - start_time) / 3600.0)
