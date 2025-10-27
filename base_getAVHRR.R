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
path <- "/cluster01/Projects/USA_IDA_AICCRA/1.Data/RAW/AVHRR/"
if(!dir.exists(path)) dir.create(path, recursive = TRUE)

token <- readLines("~/.earthdata_token")  # Make sure this file exists

seasonStart <- "03-01"
seasonEnd   <- "08-31"
sYear <- 2025
eYear <- 2025

# --- 3. Function to request AVHRR NDVI subset ---
getAVHRR_subset <- function(start_date, end_date, bbox_str, path, token) {

  short_name <- "AVHRR_NDVI_CDR"
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





















#===================================================================

rm(list=ls(all=TRUE))
g <- gc(reset = T); 
#install.packages("remotes")
#remotes::install_github("rspatial/luna")
list.of.packages <- c("luna","terra","geodata")
new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]
if(length(new.packages)) install.packages(new.packages, dependencies = T)
lapply(list.of.packages, require, character.only = TRUE)

path <-  '/cluster01/Projects/USA_IDA_AICCRA/1.Data/RAW/AVHRR/'
seasonStart <- "03-01"
seasonEnd   <- "08-31"
sYear <- "2000"
eYear <- "2025"


#' List all AVHRR files available for download
#' This could be an internal function to download AVHRR files
#'	
.listAVHRR <- function(path, update=FALSE, baseurl) {
  cat("Creating index of available AVHRR files on", as.character(Sys.Date()), "\n")
  # Two-day delay in ingestion
  filename <- paste0("avhrr_files_", Sys.Date(),".rds")
  filename <- file.path(path, filename)
  
  if (!file.exists(filename) | update){
    startyear <- 1981
    endyear <- format(as.Date(Sys.Date(), format="%d/%m/%Y"),"%Y")
    years <- seq(startyear, endyear)
    
    ff <- list()
    for (i in 1:length(years)){
      url <- file.path(baseurl, years[i])
      wp <- xml2::read_html(url)
      dvns <- rvest::html_attr(rvest::html_nodes(wp, "a"), "href")
      #VIIRS-Land_v001-preliminary_NPP13C1_S-NPP_20190101_c20220418131738.nc	
      
      
      ds <- grep("AVHRR-Land|VIIRS-Land_*.*.nc", dvns, value = TRUE)#grep("^AVHRR-Land_*.*.nc", dvns, value = TRUE)
      ff[[i]] <- ds
    }
    ff <- unlist(ff)
    dates <- sapply(strsplit(ff,"_"), "[[", 5)
    dates <- as.Date(dates, format = "%Y%m%d")
    ff <- data.frame(filename = ff, date = dates, stringsAsFactors = FALSE, row.names = NULL)
    saveRDS(ff, filename)
  } else {
    ff <- readRDS(filename)
  }
  return(ff)
}


getAVHRR <- function(start_date, end_date, path, overwrite = FALSE, update = FALSE, ...) {
  
  if(missing(start_date)) stop("provide a start_date")
  if(missing(end_date)) stop("provide an end_date")
  
  baseurl <- "https://www.ncei.noaa.gov/data/land-normalized-difference-vegetation-index/access"
  # url to access 8 different ways of downloading the data
  # baseurl <- "https://www.ncei.noaa.gov/thredds/catalog/cdr/ndvi/files"
  #path <- .getPath(path)
  
  # list of AVHRR files
  pp <- .listAVHRR(path = path, baseurl = baseurl, update = FALSE)
  
  # TODO: alternate search through CMR
  # https://cmr.earthdata.nasa.gov/search/concepts/C1277746140-NOAA_NCEI
  
  # subset the files by dates
  pp <- pp[pp$date >= start_date & pp$date <= end_date, ]
  
  if(nrow(pp) == 0) {stop("No AVHRR file available for the date range provided")}
  
  # to store output file names
  
  for (i in 1:nrow(pp)){
    ff <- pp[i,]
    fname <- ff$filename
    #year <- .yearFromDate(ff$date)
    year <- format(as.Date(ff$date, format="%d/%m/%Y"),"%Y")
    furl <- file.path(baseurl, year, fname)
    filename <- file.path(path, fname)
    
    # is ok, if file exists or overwrite is TRUE
    #ok <- (file.exists(filename) | overwrite)
    
    # what if the download is bad; less than 50 mb
    # there must be a better way
    if(file.exists(filename)){
      fsz <- round(file.size(filename)/(1024^2))
      if (fsz < 50) ok <- FALSE
    }
    
    if (!file.exists(filename)){
      cat("Downloading AVHRR tile for", as.character(ff$date), "\n")
      ff <- try(utils::download.file(furl, filename, mode = "wb", quiet = TRUE)) 
    } 
    
    if (inherits(ff, "try-error")) next
  }
}

years <- as.character(sYear:eYear)
for(y in years){
    print(paste('Started donwloading seasons in year: ', y))
    start <- paste(y, seasonStart, sep="-")
    end <- paste(y, seasonEnd,sep="-")
    getAVHRR(start_date=start, end_date= end, path = path)
}
