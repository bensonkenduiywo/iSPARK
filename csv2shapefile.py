import pandas as pd
import geopandas as gpd
from shapely.geometry import Point

# Load the Excel file
df = pd.read_excel("farmer_location.xlsx", engine="openpyxl")
df.head()
df.tail()
# Create Point geometries from Longitude and Latitude
geometry = [Point(xy) for xy in zip(df["Longitude"], df["Latitude"])]

# Create a GeoDataFrame with WGS84 CRS
gdf = gpd.GeoDataFrame(df, geometry=geometry, crs="EPSG:4326")
gdf.head()
# Convert CRS to a projected system suitable for buffering (e.g., UTM Zone 36N for Kenya)
gdf_projected = gdf.to_crs(epsg=32736)

# Create 2.5 km buffer polygons
gdf_projected["geometry"] = gdf_projected.buffer(2500)
# Convert back to WGS84 for saving
gdf_buffered = gdf_projected.to_crs(epsg=4326)
gdf_buffered.head()
# Save the buffered polygons to a shapefile
path_out = "/home/bkenduiywo/iSPARK/shapefiles/farmer_buffers_2_5km.shp"
gdf_buffered.to_file(path_out)

print(f"Shapefile with 2.5 km buffer polygons has been saved as {path_out}.")