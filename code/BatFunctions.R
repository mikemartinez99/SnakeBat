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
  
  #----- Initialize progress bar for file processing
  numFiles <- length(dataFiles)
  pb <- txtProgressBar(min = 0, max = numFiles, style = 3)
  
  #----- Iterate through the files
  for (f in seq_along(dataFiles)) {
    i <- dataFiles[f]
    message(paste0("Processing", i))
    
    #----- Drop extension
    #short_name <- tools::file_path_sans_ext(i)
    short_name <- tools::file_path_sans_ext(basename(i))
    
    #----- Check if output file already exists
    out_file <- file.path(outputDir, paste0(short_name, "_RMSPower_1Second.csv"))
    if (file.exists(out_file)) {
      message(paste("File already exists. Skipping:", out_file))
      setTxtProgressBar(pb, f)
      next
    }
    
    #----- Read in the file
    raw.wav <- tryCatch({
      tuneR::readWave(i)
    }, error = function(e) {
      if (grepl("non-conformable arguments", e$message)) {
        warning(paste("Skipping file due to readBin error:", i))
      } else {
        warning(paste("Skipping file due to unknown error:", i, "\nError:", e$message))
      }
      setTxtProgressBar(pb, f)
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
    num_segments <- floor(duration(wav) / segmentDuration) 
    message(paste0("Number of segments: ", num_segments))
    
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
    message(paste0("Output saved to ", outputDir))
    
    # Update progress bar after each file
    setTxtProgressBar(pb, f)
    
  }
  
  close(pb)
  
  
  

  
}




#-----