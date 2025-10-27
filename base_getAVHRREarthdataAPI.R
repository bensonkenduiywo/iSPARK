#' ############################################################################################
#' Author: Benson Kenduiywo
#' ############################################################################################
#echo "YOUR EARTHDATA LOGIN" > ~/.earthdata_token
# Clear workspace
rm(list = ls(all = TRUE))
gc(reset = TRUE)

# --- Install and load packages ---
list.of.packages <- c("terra", "httr", "jsonlite")
new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[, "Package"])]
if (length(new.packages)) install.packages(new.packages, dependencies = TRUE)
lapply(list.of.packages, require, character.only = TRUE)


# --- 1. Get Kisumu County boundary from GADM ---
cat("Fetching Kisumu County boundary from GADM...\n")

# Level 1 = Counties in Kenya
kisumu <- terra::vect('/home/bkenduiywo/admin/Kenya_county_dd.shp')
kisumu <- kisumu[kisumu$COUNTY_NAM == "Kisumu", ]

# Bounding box for API query
bbox <- ext(kisumu)
lon_min <- bbox[1]
lat_min <- bbox[3]
lon_max <- bbox[2]
lat_max <- bbox[4]
bbox_str <- paste(lon_min, lat_min, lon_max, lat_max, sep = ",")

cat("Kisumu County bounding box:", bbox_str, "\n")

# --- 2. Define parameters ---
path <- "/home/bkenduiywo/temp/"#"/cluster01/Projects/USA_IDA_AICCRA/1.Data/RAW/AVHRR_subsets/"
if(!dir.exists(path)) dir.create(path, recursive = TRUE)

token <- readLines("~/.earthdata_token")  # Make sure this file exists

seasonStart <- "03-01"
seasonEnd   <- "08-31"
sYear <- 2025
eYear <- 2025

# --- 3. Function to request AVHRR NDVI subset ---
getAVHRR_subset <- function(start_date, end_date, bbox_str, path, token) {

  short_name <- "VNP13A2"
  base_url <- "https://n5eil02u.ecs.nsidc.org/egi/request"

  params <- list(
    short_name = short_name,
    temporal = paste(start_date, "/", end_date, sep = ""),
    bbox = bbox_str,
    format = "NetCDF4"
  )

  query_url <- httr::modify_url(base_url, query = params)
  out_file <- file.path(path, paste0("AVHRR_", gsub("-", "", start_date), "_", gsub("-", "", end_date), "_Kisumu.nc"))

  cat("Requesting AOI subset for", start_date, "to", end_date, "\n")

  resp <- httr::GET(
    query_url,
    httr::add_headers(Authorization = paste("Bearer", token)),
    httr::write_disk(out_file, overwrite = TRUE),
    timeout(300)
  )

  if (httr::status_code(resp) == 200) {
    cat("✅ Saved:", out_file, "\n")
  } else {
    cat("❌ Request failed:", httr::status_code(resp), "\n")
  }
}

# --- 4. Loop over years and download ---
years <- sYear:eYear
for (y in years) {
  cat("\n=== Processing Year:", y, "===\n")
  start <- paste(y, seasonStart, sep = "-")
  end <- paste(y, seasonEnd, sep = "-")
  getAVHRR_subset(start, end, bbox_str, path, token)
}

# --- 5. Optional: mask downloaded data to exact Kisumu boundary ---
cat("\nMasking downloaded subsets to exact Kisumu boundary...\n")
files <- list.files(path, pattern = "\\.nc$", full.names = TRUE)

for (f in files) {
  cat("Masking:", f, "\n")
  r <- try(rast(f))
  if (!inherits(r, "try-error")) {
    crs(r) <- "EPSG:4326"
    r_crop <- crop(r, kisumu_vect)
    r_mask <- mask(r_crop, kisumu_vect)
    out_tif <- gsub("\\.nc$", "_mask.tif", f)
    writeRaster(r_mask, out_tif, overwrite = TRUE)
  }
}
cat("✅ All done.\n")

