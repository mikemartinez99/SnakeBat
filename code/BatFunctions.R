#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ READ ME ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
#
# Title: Bat_Functions.R
# Author: Mike Martinez
# Lab: Kloepper
# Date Created: July 20th, 2025
#
# Changelog: 
#   Sunday July 27th, 2025: 
#     - Changed short name to just file basename to avoid malformed output path
#     - Preallocated vector in inner loop to prevent re-reading growing vector into memory with each iteration
#     - Added progress bar for aesthetics 
#     - Added tryCatch block to skip corrupted files
#     - Added check to not re-run files that were already processed
#       
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

#----- Function to calculate RMS Power
rmsPower <- function(dataDir, 
                     segmentDuration, 
                     fileType,
                     samplingRate, 
                     bwFilterFrom, 
                     bwFilterTo,
                     outputDir) {
  #----- Check raw data dir exists
  if (!dir.exists(dataDir)) {
    stop("Data directory does not exist!")
  } else {
    message("Raw data directory located!")
  }
  
  #----- Check output directory exists, if not, create
  if (!dir.exists(outputDir)) {
    dir.create(outputDir)
  } else {
    message("Output directory located!")
  }
  
  #----- Check that file type is valid option
  #if (fileType != "WAV" | fileType != "wav") {
  #  stop("fileType must be one of WAV or wav!")
  #}
  
  #----- List files
  message("Loading in data files...")
  dataFiles <- list.files(dataDir,
                          pattern = fileType,
                          full.names = TRUE,
                          recursive = TRUE)
  
  #----- Initialize progress tracking
  numFiles <- length(dataFiles)
  message(paste0("Found ", numFiles, " files to process"))
  
  #----- Check if running interactively to decide on progress bar
  useProgressBar <- interactive()
  
  #----- Initialize progress bar only if interactive
  if (useProgressBar) {
    pb <- txtProgressBar(min = 0, max = numFiles, style = 3)
  }
  
  #----- Set up periodic status updates (every 10% or every 25 files, whichever is more frequent)
  statusInterval <- max(1, min(floor(numFiles * 0.1), 25))
  startTime <- Sys.time()
  
  #----- Iterate through the files
  for (f in seq_along(dataFiles)) {
    i <- dataFiles[f]
    
    #----- Show periodic status updates
    if (f == 1 || f %% statusInterval == 0 || f == numFiles) {
      elapsed <- as.numeric(difftime(Sys.time(), startTime, units = "secs"))
      percent <- round((f / numFiles) * 100, 1)
      message(paste0(">>> Progress: ", f, "/", numFiles, " files (", percent, "%) | Elapsed: ", round(elapsed, 1), "s"))
    }
    
    message(paste0("[", f, "/", numFiles, "] Processing: ", basename(i)))
    
    #----- Drop extension
    #short_name <- tools::file_path_sans_ext(i)
    short_name <- tools::file_path_sans_ext(basename(i))
    
    #----- Check if output file already exists
    out_file <- file.path(outputDir, paste0(short_name, "_RMSPower_1Second.csv"))
    if (file.exists(out_file)) {
      message(paste("  -> File already exists. Skipping:", basename(out_file)))
      if (useProgressBar) setTxtProgressBar(pb, f)
      next
    }
    
    #----- Read in the file
    raw.wav <- tryCatch({
      tuneR::readWave(i)
    }, error = function(e) {
      if (grepl("non-conformable arguments", e$message)) {
        warning(paste("  -> Skipping file due to readBin error:", basename(i)))
      } else {
        warning(paste("  -> Skipping file due to unknown error:", basename(i), "\nError:", e$message))
      }
      if (useProgressBar) setTxtProgressBar(pb, f)
      NULL  # Return NULL on error
    })
    
    # Check if readWave failed
    if (is.null(raw.wav)) {
      next  # Now safe to use next here (inside loop)
    }
    

    #----- Apply band-pass filter around echolocation range
    wav <- bwfilter(raw.wav, 
                    f = samplingRate, # sampling rate in Hz
                    from = bwFilterFrom, # lower limit of band-pass filter in Hz
                    to = bwFilterTo, # upper limit of band-pass filter in Hz
                    bandpass = T,#indicates whether band-pass (T) or band-stop filter (Null)
                    output = "Wave") 
    
    #----- Number of measurements that will be taken for each audio file
    num_segments <- floor(seewave::duration(wav) / segmentDuration) 
    message(paste0("  -> Number of segments: ", num_segments))
    
    #----- Preallocate results vector
    rmsenergy <- numeric(num_segments) 
    
    #----- Loop through all segments
    for (j in 1:num_segments) {
      #----- Start of each measurement
      start_time <- (j - 1)*segmentDuration
      
      #----- End of each measurement
      end_time <- j * segmentDuration
      
      #----- Calculating the measurement length and location with audio file
      segment <- wav[round(start_time*samplingRate):round(end_time*samplingRate)]
      
      #----- Divide segments by 32768 to get a value in the -1 to 1 range
      MLV <- (segment@left)/32768
      
      #----- Take rms measurement of converted -1 to 1 segments
      rms_energy <- rms(MLV)
      
      #----- Convert to decibels and make relative to loudest possible signal (1)
      rel_rmsenergy <- 10*log((rms_energy/1),base=10)
      
      # Save results
      rmsenergy[j] <- rel_rmsenergy
    }
    
    write.csv(rmsenergy, out_file)
    message(paste0("  -> Output saved: ", basename(out_file)))
    
    # Update progress bar after each file (only if interactive)
    if (useProgressBar) setTxtProgressBar(pb, f)
    
  }
  
  # Close progress bar only if it was created
  if (useProgressBar) close(pb)
  
  #----- Final status message
  totalTime <- as.numeric(difftime(Sys.time(), startTime, units = "secs"))
  message("--------------------------------------------------")
  message(paste0(">>> COMPLETED: Processed ", numFiles, " files in ", round(totalTime, 1), " seconds (", round(totalTime/60, 1), " minutes)"))
  message("--------------------------------------------------")
  
  
  

  
}


#----- Function to calculate total RMSE
calcTotalRMSE <- function(dataDirs, date) {
  #----- Create empy list to store data
  dataList <- list()
  
  #-----Create a vector called date, containing the date of the files we are working on 
  date <- c(date)
 
  #----- List each file in the directory
  files <- list.files(dataDirs, full.names=TRUE) 
    
  
  #-----iterate through each file in the i-th directory
  for (j in files) {
    #----- Read in the j-th dataframe as x
    x <- read.csv(j, header=TRUE)
    
    #----- Optional debugging sanity checks
    #check dimensions of the j-th dataframe
    #print(dim(x))
    
    #----- Check that each dataframe has at least 1 row of data, skip empty dataframes
    if (nrow(x) == 0) {
      message(paste(j, " has 0 rows."))
      next()
    }
    
    #----- Check that column names needed for summation are present part 1
    neededCols1 <- c("rmsEnergy")
    if (!neededCols1 %in% colnames(x)) {
      stop("rmsEnergy missing in data")
    } 
    
    #----- Check that column names needed for summation are present part 2
    neededCols2 <- c("AdjustedValue")
    if (!neededCols2 %in% colnames(x)) {
      stop("AdjustedValue missing in data")
    } 

    #-----create a new column called date.   
    date <- as.character(date)
    parts <- strsplit(date, "")[[1]]
    year <- paste(parts[1:4], collapse = "")
    month <- paste(parts[5:6], collapse = "")
    day <- paste(parts[7:8], collapse = "")
    formatDate <- paste(year, month, day, sep = "-")
    x$date <- formatDate
    x$Julian <- lubridate::yday(formatDate)
    
    #print(colnames(x))
    #print(unique(x$date))
    
    #-----Add dataframe to list
    dataList[[j]] <- x
  }
  
  fullResults <- do.call(rbind, dataList)
  
  fullResults$total_raw_rmse <- sum(fullResults$rmsEnergy)
  
  #----- Create a new column for the sum of the adj. RMSE
  fullResults$total_adj_rmse <- sum(fullResults$AdjustedValue)
  
  return(fullResults)
  
}