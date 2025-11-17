# Load necessary packages
rm(list = ls(all = TRUE))
gc(reset = TRUE)
library(terra)
NODATA_VALUE = -9999
# ==============================
# 1. Read multiband GeoTIFF
# ==============================
root <- 'D:/OneDrive - CGIAR/Initiatives_Projects/iSPARK/Data/images/'
outputs <- 'D:/OneDrive - CGIAR/Initiatives_Projects/iSPARK/Draft Products/ADRI/'
#County boundaries
counties<- vect('D:/OneDrive - CGIAR/Data/Admin/Kenya_county_dd.shp')
lakes <- vect('D:/OneDrive - CGIAR/Data/KEN_Physical Features/Lakes and Major Dams.shp')
lake_vict <- lakes[lakes$NAME=="Lake Victoria" ,]
bdy <- counties[counties$COUNTY_NAM=="Kisumu",]

#Soil moisture
sm_path <- paste0(root, "FLDAS_sm_2000_2025_tiles/tile_0000.tif")
sm <- rast(sm_path)
bands <- names(sm)
sm <- crop(sm, bdy)
sm <- mask(sm, lakes, inverse =T)
NAflag(sm) <- NODATA_VALUE
names(sm) <- bands
cat("Loaded", nlyr(sm), "bands for FEWSNET Soil moisture\n")
names(sm)


#Precipitation
chrp_path <- paste0(root,"CHIRPS_precip_2000_2025_tiles/tile_0000.tif")
chrp <- rast(chrp_path)
bands <- names(chrp)
chrp <- crop(chrp, bdy)
chrp <- mask(chrp, lakes, inverse =T)
NAflag(chrp) <- NODATA_VALUE
names(chrp) <- bands
cat("Loaded", nlyr(chrp), "bands CHIRPS precip\n")
names(chrp)

#MODIS NDVI
ndvi_path <- paste0(root,"MODIS_NDVI_2000_2025_tiles/tile_0000.tif")
ndvi <- rast(ndvi_path)
bands <- names(ndvi)
ndvi <- crop(ndvi, bdy)
ndvi <- mask(ndvi, lakes, inverse =T)
NAflag(ndvi) <- NODATA_VALUE
names(ndvi) <- bands
cat("Loaded", nlyr(ndvi), "bands for MODIS LST\n")
names(ndvi)

#MODIS LST
lst_path <- paste0(root,"MODIS_LST_2000_2025_tiles/tile_0000.tif")
lst <- rast(lst_path)
bands <- names(lst)
lst <- crop(lst, bdy)
lst <- mask(lst, lakes, inverse =T)
NAflag(lst) <- NODATA_VALUE
names(lst) <- bands
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

# ==============================
# 3. Aggregate March–August (1–6) per year
# ==============================

temporal <- function(band_info, image){
  years <- sort(unique(band_info$year))
  yearly_means <- list()
  
  for (yr in years) {
    idx <- which(band_info$year == yr & band_info$month >= 1 & band_info$month <= 6)
    if (length(idx) == 0) next
    
    # Compute mean across March–August bands
    subset_r <- image[[idx]]
    yearly_mean <- mean(subset_r, na.rm = TRUE)
    yearly_means[[as.character(yr)]] <- yearly_mean
  }
  
  cat("Generated", length(yearly_means), "yearly composites\n")
  return(yearly_means)  
}

#band names
sm_info <- parse_band_info(names(sm))
chrp_info <- parse_band_info(names(chrp))
ndvi_info <- parse_band_info(names(ndvi))
lst_info <- parse_band_info(names(lst))

#tempral averages
sm_temp <- temporal(sm_info, sm)
chrp_temp <- temporal(chrp_info, chrp)
ndvi_temp <- temporal(ndvi_info, ndvi)
lst_temp <- temporal(lst_info, lst)

# ==============================
# Compute indices
# ==============================
# 1.0 Vegetation Condition Index
VCI <- function(ndvi){
  ndvi_temp <- rast(ndvi)
  ndvi_min <- app(ndvi_temp, fun = min, na.rm = TRUE)
  ndvi_max <- app(ndvi_temp, fun = max, na.rm = TRUE)
  
  # ------------------------------------------
  # Compute VCI = 100 * (NDVI - NDVImin) / (NDVImax - NDVImin)
  # ------------------------------------------
  # Avoid division by zero
  range_diff <- ndvi_max - ndvi_min
  range_diff[range_diff == 0] <- NA
  
  # Compute VCI for each band
  vci <- ((ndvi_temp - ndvi_min) / range_diff )* 100
  
  # ------------------------------------------
  # Keep the same band names
  # ------------------------------------------
  names(vci) <- names(ndvi_temp)
  
  # ------------------------------------------
  # 4. Inspect result
  # ------------------------------------------
  print(vci)
  return(vci)
}

#2.0 Temperature Condition Index (TCI)

TCI <- function(lst){
  lst_temp <- rast(lst)
  lst_min <- app(lst_temp, fun = min, na.rm = TRUE)
  lst_max <- app(lst_temp, fun = max, na.rm = TRUE)
  # ------------------------------------------
  # Compute TCI = 100 * (NDVI - NDVImin) / (NDVImax - NDVImin)
  # ------------------------------------------
  # Avoid division by zero
  range_diff <- lst_max - lst_min
  range_diff[range_diff == 0] <- NA
  
  # TCI for each band
  tci <- ((lst_max - lst_temp) / range_diff )* 100
  
  # ------------------------------------------
  # Keep the same band names
  # ------------------------------------------
  names(tci) <- names(lst_temp)
  
  # ------------------------------------------
  # 4. Inspect result
  # ------------------------------------------
  print(tci)
  return(tci)
}

# VCI
vci <- VCI(ndvi_temp)
plot(vci[[1]])

#Precipitation Condition Index  (PCI) computed like VCI
pci <- VCI(chrp_temp)
plot(pci[[1]])

#Soil Condition Index (SCI)
sci <- VCI(sm_temp)
plot(sci[[1]])

#Temperature Condition Index (TCI)
tci <- TCI(lst_temp)
plot(tci[[1]])

#Compute Advance Drought Response Index (ADRI) 

ADRI <- function(vci, tci, pci, sci, c=0.01, L=0.25){
  temp1 <- L*vci
  sum_1 <- tci+pci+sci
  denom <- L*(vci+sum_1+c)
  bracket <- c+((1/denom)*sum_1)
  adri <- temp1 * bracket
  return(adri)
}

adri <- ADRI(vci, tci, pci, sci, c=0.01, L=0.25)
writeRaster(adri, paste0(outputs,'vci.tif'), overwrite = TRUE)
# ==============================
# 4. Compute long-term mean (2000–2024) and 2025 deviation
# ==============================
# deviation <- function(yearly_means, band_info, current_year=2025){
#   
#   years <- sort(unique(band_info$year))
#   historical_years <- years[years < current_year]
#   
#   if (!as.character(current_year) %in% names(yearly_means)) {
#     stop("Current year 2025 not found in the image bands.")
#   }
#   
#   # Stack historical years and compute mean
#   historical_stack <- rast(yearly_means[as.character(historical_years)])
#   historical_mean <- mean(historical_stack, na.rm = TRUE)
#   
#   # Deviation (2025 - long-term mean)
#   dev <- yearly_means[[as.character(current_year)]] - historical_mean
#   return(dev)
#   
# }
# sm_dev <- deviation(sm_temp, sm_info, 2025)
# chrp_dev <- deviation(chrp_temp, chrp_info, 2025)
# ndvi_dev <- deviation(ndvi_temp, ndvi_info, 2025)
# lst_dev <- deviation(lst_temp, lst_info, 2025)

#band names should be correspond to years
deviations <- function(index, current_year){ 
  current <- as.character(current_year)
  bands <- names(index)
  hist <- index[[bands[bands < current]]]
  hist_mean <- mean(hist, na.rm = TRUE)
  dev <- index[[current]] - hist_mean
  return(dev)
}
vci_dev <- deviations(vci, 2025)
pci_dev <- deviations(pci, 2025)
tci_dev <- deviations(tci, 2025)
sci_dev <- deviations(sci, 2025)

# Plots
png(
  filename = paste0(outputs, "Deviations_fromLongTermmean.png"),
  width  = 8 * 300,   # pixels
  height = 8 * 300,   # pixels
  res = 300        # DPI
)


par(mfrow = c(2, 2),
    oma = c(1, 1, 1, 1),
    mar = c(2.5, 2.5, 2.5, 3.5)  # smaller margins
) # outer margins
plot(vci_dev, main='VCI')
plot(pci_dev, main='PCI')
plot(tci_dev, main='TCI')
plot(sci_dev, main='SCI')
dev.off()


# ==============================
# 5. Save output rasters
# ==============================
writeRaster(vci, paste0(outputs,'vci.tif'), overwrite = TRUE)
writeRaster(pci, paste0(outputs,'pci.tif'), overwrite = TRUE)
writeRaster(tci, paste0(outputs,'tci.tif'), overwrite = TRUE)
writeRaster(sci, paste0(outputs,'sci.tif'), overwrite = TRUE)



