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
import json
from google.auth import credentials
from google.oauth2 import service_account
import timeit
import time
start_time = timeit.default_timer() 
# Path to your service account key JSON file
SERVICE_ACCOUNT_KEY = "private_key.json"
 
# Load credentials from the service account file
credentials = service_account.Credentials.from_service_account_file(
    SERVICE_ACCOUNT_KEY,
    scopes=['https://www.googleapis.com/auth/earthengine', 'https://www.googleapis.com/auth/drive']  # Add Drive scope if needed
)
 
# Initialize Earth Engine API
ee.Initialize(credentials)
 
# Verify successful initialization
print("Earth Engine initialized successfully!")


import ee
import geemap
from datetime import datetime

# Initialize Earth Engine
geemap.ee_initialize()
print('GeeMap initialized!')

# ============================================
# Parameters
# ============================================
sResolution = 1000
start_year = 2000
end_year = 2025
#transition_year = 2012
season_start = 3   # March
season_end = 8    # August
timeField = 'system:time_start'

filename = f'MODIS_LST_{start_year}_{end_year}'
gee_project = "projects/cropmapping-365811"
asset_folder = "rwanda"
s1_asset_id = f"{gee_project}/assets/{asset_folder}/{filename}"
# ============================================
# Load ROI and display
# ============================================
cList = ['Kisumu']
ROI = ee.FeatureCollection('users/bensonkemboi/Ke_admin/Kenya_county_dd')
ROI = ROI.filter(ee.Filter.inList('COUNTY_NAM', cList))
# ============================================
# MASK CROPLANDS: Optional
# ============================================
esalandcover = ee.ImageCollection("ESA/WorldCover/v200").first()
datamask = (
    esalandcover.select('Map')
    .eq(90).add(esalandcover.select('Map').eq(40))
    .add(esalandcover.select('Map').eq(60))
    .add(esalandcover.select('Map').eq(30))
    .selfMask()
    .rename('cropland')
)
# ============================================
# MODIS Monthly LST (terra: MOD13A3 and aqua: MYD13A3
# ============================================
terra = (
    ee.ImageCollection("MODIS/061/MOD11A2")
    .filter(ee.Filter.date(
        ee.Date.fromYMD(start_year, season_start, 1),
        ee.Date.fromYMD(end_year, season_end, 31)
    ))
    .select('LST_Day_1km')
    .map(lambda img: img.multiply(0.02)
         .subtract(273.15)
         .copyProperties(img, ['system:time_start']))
)
aqua = (
    ee.ImageCollection("MODIS/061/MYD11A2")
    .filter(ee.Filter.date(
        ee.Date.fromYMD(start_year, season_start, 1),
        ee.Date.fromYMD(end_year, season_end, 31)
    ))
    .select('LST_Day_1km')
    .map(lambda img: img.multiply(0.02)
         .subtract(273.15)
         .copyProperties(img, ['system:time_start']))
)

modis = terra.merge(aqua)
# ============================================
# Monthly composites: if aqua and terra are merged!
# ============================================
def monthly_composites(collection, start_year, end_year, month_start, month_end, mask=None):
    """Compute monthly mean LST composites between given months."""
    images = []
    for year in range(start_year, end_year + 1):
        for month in range(month_start, month_end + 1):
            start = ee.Date.fromYMD(year, month, 1)
            end = start.advance(1, 'month')
            monthly = collection.filterDate(start, end).mean()
            if mask is not None:
                monthly = monthly.updateMask(mask)
            monthly = monthly.set({
                'year': year,
                'month': month,
                'system:time_start': start.millis()
            })
            images.append(monthly)
    return ee.ImageCollection(images)
modis_monthly = monthly_composites(modis, start_year, end_year,
                                   season_start, season_end)
# ============================================
# CHECK RESULTS
# ============================================
print(f'MODIS Aqua {start_year} – {end_year} composites:', aqua.size().getInfo())
print(f'MODIS Terra {start_year} – {end_year} composites:', terra.size().getInfo())
print(f'Combined MODIS {start_year} – {end_year} composites:', modis_monthly.size().getInfo())

# ============================================
# Stack images by renaming bands with month index
# ============================================
# Convert ImageCollection to list
imageList = modis_monthly.toList(modis_monthly.size())
nMonths = modis_monthly.size().getInfo()

# Initialize band stack with the first image
first_img = ee.Image(imageList.get(0))
year0 = ee.Number(first_img.get('year')).format()
month0 = ee.Number(first_img.get('month')).subtract(season_start).add(1).format()
bandNames0 = first_img.bandNames().map(
    lambda b: ee.String('LST_').cat(year0).cat('_').cat(month0)
)
bandStack = first_img.rename(bandNames0)

# Loop through remaining images and rename accordingly
for i in range(1, nMonths):
    img = ee.Image(imageList.get(i))
    year = ee.Number(img.get('year')).format()
    monthIndex = ee.Number(img.get('month')).subtract(season_start).add(1).format()
    newNames = img.bandNames().map(
        lambda b: ee.String('LST_').cat(year).cat('_').cat(monthIndex)
    )
    renamed = img.rename(newNames)
    bandStack = bandStack.addBands(renamed)

# Optional: mask to croplands and clip to ROI
#bandStack = bandStack.updateMask(datamask).clip(ROI)
# ============================================
# Export asset
# ============================================
# Define the Asset ID path
s1_asset_id = f"{gee_project}/assets/{asset_folder}/{filename}"

# Delete existing asset if exists (overwrite support)
try:
    ee.data.deleteAsset(s1_asset_id)
    print("Existing asset deleted to allow overwrite.")
except Exception as e:
    print("No existing asset to delete (safe to proceed).")

# Define Export Task
export_task = ee.batch.Export.image.toAsset(
    image=bandStack.clip(ROI),
    description=filename,
    assetId=s1_asset_id,
    region=ROI.geometry(),
    scale=sResolution,
    crs='EPSG:4326',
    maxPixels=1e13
)

# Start Task
export_task.start()
print(f"Export task '{filename}' started...")

# Monitor Task Status
while export_task.active():
    print("Export in progress... waiting 30s...")
    time.sleep(30)

# Final status
status = export_task.status()
print(f"Export task completed with status: {status['state']}")

# Handle potential failure
if status['state'] == 'FAILED':
    print(f"Error message: {status.get('error_message', 'No error message provided.')}")

print(f"Pre-processed raster saved to {s1_asset_id}")
print("Elapsed time (hours):", (timeit.default_timer() - start_time) / 3600.0)