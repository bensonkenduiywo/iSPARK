# Load necessary packages
rm(list = ls(all = TRUE))
gc(reset = TRUE)
library(terra)

# ==============================
# 1. Read multiband GeoTIFF
# ==============================
root <- 'D:/OneDrive - CGIAR/Initiatives_Projects/iSPARK/Data/images/'
#Soil moisture
sm_path <- paste0(root, "FLDAS_sm_2000_2025_tiles/tile_0000.tif")
sm <- rast(sm_path)
cat("Loaded", nlyr(sm), "bands for FEWSNET Soil moisture\n")
names(sm)
#Precipitation
chrp_path <- paste0(root,"CHIRPS_precip_2000_2025_tiles/tile_0000.tif")
chrp <- rast(chrp_path)
cat("Loaded", nlyr(chrp), "bands CHIRPS precip\n")
names(chrp)
#MODIS NDVI
ndvi_path <- paste0(root,"MODIS_NDVI_2000_2025_tiles/tile_0000.tif")
ndvi <- rast(ndvi_path)
cat("Loaded", nlyr(ndvi), "bands for MODIS LST\n")
names(ndvi)
#MODIS LST
lst_path <- paste0(root,"MODIS_LST_2000_2025_tiles/tile_0000.tif")
lst <- rast(lst_path)
cat("Loaded", nlyr(lst), "bands for MODIS LST\n")
names(lst)

# ==============================
# 2. Parse band names to get year and month
# ==============================
# Expected format: SM_2000_1, SM_2000_2, etc.
parse_band_info <- function(band_names) {
  info <- data.frame(index = seq_along(band_names), year = NA, month = NA)
  for (i in seq_along(band_names)) {
    parts <- strsplit(band_names[i], "_")[[1]]
    if (length(parts) == 3) {
      info$year[i] <- as.integer(parts[2])
      info$month[i] <- as.integer(parts[3])
    } else {
      stop(paste("Unexpected band name format:", band_names[i]))
    }
  }
  return(info)
}

sm_names <- names(sm)
sm_bands <- parse_band_info(band_names)

# ==============================
# 3. Aggregate March–August (1–6) per year
# ==============================
years <- sort(unique(band_info$year))
yearly_means <- list()

for (yr in years) {
  idx <- which(band_info$year == yr & band_info$month >= 1 & band_info$month <= 6)
  if (length(idx) == 0) next
  
  # Compute mean across March–August bands
  subset_r <- r[[idx]]
  yearly_mean <- mean(subset_r, na.rm = TRUE)
  yearly_means[[as.character(yr)]] <- yearly_mean
}

cat("Generated", length(yearly_means), "yearly composites\n")

# ==============================
# 4. Compute long-term mean (2000–2024) and 2025 deviation
# ==============================
current_year <- 2025
historical_years <- years[years < current_year]

if (!as.character(current_year) %in% names(yearly_means)) {
  stop("Current year 2025 not found in the image bands.")
}

# Stack historical years and compute mean
historical_stack <- rast(yearly_means[as.character(historical_years)])
historical_mean <- mean(historical_stack, na.rm = TRUE)

# Deviation (2025 - long-term mean)
deviation <- yearly_means[[as.character(current_year)]] - historical_mean

# ==============================
# 5. Save optional output raster
# ==============================
out_path <- sub("\\.tif$", "_deviation_2025.tif", tif_path)
writeRaster(deviation, out_path, overwrite = TRUE)
cat("Saved deviation raster:", out_path, "\n")

# ==============================
# 6. Plot deviation
# ==============================
dev.new(width = 8, height = 6)
plot(deviation,
     col = hcl.colors(100, "RdBu", rev = TRUE),
     main = "Soil Moisture Deviation (2025 vs. Long-Term Mean)")
