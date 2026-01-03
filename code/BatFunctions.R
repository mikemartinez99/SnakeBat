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
  #----- Validate directories
  if (!dir.exists(dataDir)) {
    stop("ERROR: Data directory does not exist")
  }
  
  if (!dir.exists(outputDir)) {
    dir.create(outputDir, recursive = TRUE)
    message("Created output directory")
  }
  
  #----- Check that file type is valid option
  #if (fileType != "WAV" | fileType != "wav") {
  #  stop("fileType must be one of WAV or wav!")
  #}
  
  #----- Discover input files
  dataFiles <- list.files(dataDir,
                          pattern = fileType,
                          full.names = TRUE,
                          recursive = TRUE)
  
  numFiles <- length(dataFiles)
  if (numFiles == 0) {
    stop("ERROR: No files found matching pattern: ", fileType)
  }
  
  message(paste("Found", numFiles, "audio file(s) to process"))
  
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
      rate <- ifelse(elapsed > 0, round(f / elapsed, 2), 0)
      message(sprintf("Progress: %d/%d files (%.1f%%) | Elapsed: %.1fs | Rate: %.2f files/s", 
                      f, numFiles, percent, elapsed, rate))
    }
    
    message(sprintf("[%d/%d] Processing: %s", f, numFiles, basename(i)))
    
    #----- Drop extension
    #short_name <- tools::file_path_sans_ext(i)
    short_name <- tools::file_path_sans_ext(basename(i))
    
    #----- Check if output file already exists
    out_file <- file.path(outputDir, paste0(short_name, "_RMSPower_1Second.csv"))
    if (file.exists(out_file)) {
      message(sprintf("  Skipping (already processed): %s", basename(out_file)))
      if (useProgressBar) setTxtProgressBar(pb, f)
      next
    }
    
    #----- Read audio file
    raw.wav <- tryCatch({
      suppressWarnings(tuneR::readWave(i))
    }, error = function(e) {
      if (grepl("non-conformable arguments", e$message)) {
        message(sprintf("  WARNING: Skipping file (readBin error): %s", basename(i)))
      } else {
        message(sprintf("  WARNING: Skipping file (error: %s): %s", e$message, basename(i)))
      }
      if (useProgressBar) setTxtProgressBar(pb, f)
      NULL
    })
    
    # Check if readWave failed
    if (is.null(raw.wav)) {
      next  # Now safe to use next here (inside loop)
    }
    

    #----- Apply band-pass filter around echolocation range
    wav <- suppressWarnings({
      bwfilter(raw.wav, 
               f = samplingRate, # sampling rate in Hz
               from = bwFilterFrom, # lower limit of band-pass filter in Hz
               to = bwFilterTo, # upper limit of band-pass filter in Hz
               bandpass = T,#indicates whether band-pass (T) or band-stop filter (Null)
               output = "Wave")
    }) 
    
    #----- Calculate number of segments
    num_segments <- floor(suppressWarnings(seewave::duration(wav)) / segmentDuration)
    if (num_segments == 0) {
      message(sprintf("  WARNING: File too short for processing: %s", basename(i)))
      if (useProgressBar) setTxtProgressBar(pb, f)
      next
    }
    
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
    message(sprintf("  Completed: %s (%d segments)", basename(out_file), num_segments))
    
    # Update progress bar after each file (only if interactive)
    if (useProgressBar) setTxtProgressBar(pb, f)
    
  }
  
  # Close progress bar only if it was created
  if (useProgressBar) close(pb)
  
  #----- Final summary
  totalTime <- as.numeric(difftime(Sys.time(), startTime, units = "secs"))
  avgTime <- totalTime / numFiles
  message("----------------------------------------")
  message(sprintf("COMPLETED: Processed %d file(s)", numFiles))
  message(sprintf("  Total time:   %.1f seconds (%.1f minutes)", totalTime, totalTime/60))
  message(sprintf("  Average time: %.2f seconds per file", avgTime))
  message("----------------------------------------")
  
  
  

  
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
    
    #----- Validate data structure
    if (nrow(x) == 0) {
      message(sprintf("WARNING: Empty file skipped: %s", basename(j)))
      next()
    }
    
    requiredCols <- c("rmsEnergy", "AdjustedValue")
    missingCols <- setdiff(requiredCols, colnames(x))
    if (length(missingCols) > 0) {
      stop(sprintf("ERROR: Missing required columns in %s: %s", basename(j), paste(missingCols, collapse = ", ")))
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