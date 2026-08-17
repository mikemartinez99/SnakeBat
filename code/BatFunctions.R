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
#   Sunday August 17th, 2026:
#     - Reworked logging: one line per file instead of three, wall-clock stamps,
#       a periodic heartbeat with an ETA, and an end-of-run summary that counts
#       processed / skipped / failed files separately
#     - Removed the interactive progress bar (never active under Rscript, and it
#       interleaved badly with the per-file lines)
#     - Base R only, no new package dependencies
#
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

#-------------------------------------------------------------------------------
# LOGGING HELPERS
#
# All logging goes through message(), i.e. stderr, so that the Snakefile's
# "&> {log}" captures it. Base R only.
#-------------------------------------------------------------------------------

LOG_WIDTH <- 74

#----- Horizontal rule
logRule <- function(char = "-", width = LOG_WIDTH) message(strrep(char, width))

#----- Heavy banner, used at the start and end of a run
logBanner <- function(title, width = LOG_WIDTH) {
  logRule("=", width)
  message("  ", title)
  logRule("=", width)
}

#----- Lighter section heading
logSection <- function(title, width = LOG_WIDTH) {
  message("")
  logRule("-", width)
  message("  ", title)
  logRule("-", width)
}

#----- Aligned "label      value" line
logField <- function(label, value, pad = 20) {
  pad <- max(pad, nchar(label) + 2)
  message("  ", formatC(label, width = -pad), value)
}

#----- Wall-clock stamp that prefixes every per-file line
logStamp <- function() format(Sys.time(), "%H:%M:%S")

#----- Human-readable duration: "6.6s", "1m 15s", "2h 04m 31s"
fmtDuration <- function(secs) {
  secs <- as.numeric(secs)
  if (!is.finite(secs) || secs < 0) return("--")
  h <- floor(secs / 3600)
  m <- floor((secs %% 3600) / 60)
  s <- secs %% 60
  if (h > 0) return(sprintf("%dh %02dm %02ds", h, m, round(s)))
  if (m > 0) return(sprintf("%dm %02ds", m, round(s)))
  sprintf("%.1fs", s)
}

#----- Thousands separators, so "3606 segments" reads as "3,606"
fmtCount <- function(x) formatC(as.integer(x), format = "d", big.mark = ",")
fmtValue <- function(x) formatC(x, format = "f", digits = 1, big.mark = ",")

#----- AudioMoth file names are ~55 characters and mostly boilerplate. Pull out
#      the date_time stamp, which is the part that actually identifies the
#      recording, so the per-file lines stay scannable.
shortId <- function(fname) {
  hit <- regmatches(fname, regexpr("[0-9]{8}_[0-9]{6}", fname))
  if (length(hit) == 1 && nzchar(hit)) return(hit)
  id <- tools::file_path_sans_ext(basename(fname))
  if (nchar(id) > 20) paste0("...", substring(id, nchar(id) - 16)) else id
}

#----- One line per file:
#      [21:14:07]  3/9 ( 33%)  20250529_201424  ok    331 segments in 6.6s
logFileRow <- function(index, total, id, status, detail, idWidth = 16) {
  message(sprintf("[%s] %s/%s (%s%%)  %s  %s  %s",
                  logStamp(),
                  formatC(index, width = nchar(as.character(total))),
                  total,
                  formatC(100 * index / total, format = "f", digits = 0, width = 3),
                  formatC(id, width = -idWidth),
                  formatC(status, width = -4),
                  detail))
}

#----- Periodic heartbeat with an ETA, for runs long enough to warrant one
logHeartbeat <- function(done, total, startTime) {
  elapsed <- as.numeric(difftime(Sys.time(), startTime, units = "secs"))
  eta <- if (done > 0) elapsed / done * (total - done) else NA_real_
  message(sprintf("%s %s%% done | elapsed %s | eta %s %s",
                  strrep("-", 10),
                  formatC(100 * done / total, format = "f", digits = 0),
                  fmtDuration(elapsed),
                  fmtDuration(eta),
                  strrep("-", 10)))
}


#-------------------------------------------------------------------------------
# RMS POWER
#-------------------------------------------------------------------------------

#----- Function to calculate RMS Power
rmsPower <- function(dataDir,
                     segmentDuration,
                     fileType,
                     samplingRate,
                     gainOffset,
                     bwFilterFrom,
                     bwFilterTo,
                     outputDir) {
  #----- Validate directories
  if (!dir.exists(dataDir)) {
    stop("ERROR: Data directory does not exist")
  }

  if (!dir.exists(outputDir)) {
    dir.create(outputDir, recursive = TRUE)
  }

  #----- Discover input files
  dataFiles <- list.files(dataDir,
                          pattern = fileType,
                          full.names = TRUE,
                          recursive = TRUE)

  numFiles <- length(dataFiles)
  if (numFiles == 0) {
    stop("ERROR: No files found matching pattern: ", fileType)
  }

  logSection(sprintf("Processing %s %s file(s)", fmtCount(numFiles), fileType))

  #----- Counters for the end-of-run summary
  nDone <- 0L; nShort <- 0L; nEmpty <- 0L; nCached <- 0L; nFailed <- 0L
  segTotal <- 0
  procSecs <- 0

  #----- Heartbeat every ~10% of a long run; pointless on a short one, where the
  #      per-file lines already fit on one screen
  heartbeat <- if (numFiles >= 25) max(5L, min(as.integer(floor(numFiles / 10)), 50L)) else 0L
  startTime <- Sys.time()

  #----- Iterate through the files
  for (f in seq_along(dataFiles)) {
    i <- dataFiles[f]
    id <- shortId(i)
    fileStart <- Sys.time()

    #----- Drop extension
    short_name <- tools::file_path_sans_ext(basename(i))

    #----- Check if output file already exists
    out_file <- file.path(outputDir, paste0(short_name, "_RMSPower_1Second.csv"))
    if (file.exists(out_file)) {
      nCached <- nCached + 1L
      logFileRow(f, numFiles, id, "skip", "already processed on an earlier run")
      if (heartbeat > 0 && f %% heartbeat == 0) logHeartbeat(f, numFiles, startTime)
      next
    }

    #----- Read audio file
    raw.wav <- tryCatch({
      suppressWarnings(tuneR::readWave(i))
    }, error = function(e) {
      detail <- if (grepl("non-conformable arguments", e$message)) {
        "unreadable (readBin error)"
      } else {
        paste("unreadable:", e$message)
      }
      logFileRow(f, numFiles, id, "FAIL", detail)
      message(strrep(" ", 12), "file: ", basename(i))
      NULL
    })

    #----- Check if readWave failed
    if (is.null(raw.wav)) {
      nFailed <- nFailed + 1L
      if (heartbeat > 0 && f %% heartbeat == 0) logHeartbeat(f, numFiles, startTime)
      next
    }

    #----- An AudioMoth that lost power mid-write leaves a valid header with no
    #      audio behind it. That is a hardware problem, not a short recording,
    #      so call it out separately.
    if (length(raw.wav@left) == 0) {
      nEmpty <- nEmpty + 1L
      logFileRow(f, numFiles, id, "skip", "empty recording - 0 samples (check battery / card)")
      if (heartbeat > 0 && f %% heartbeat == 0) logHeartbeat(f, numFiles, startTime)
      next
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
    fileDur <- suppressWarnings(seewave::duration(wav))
    num_segments <- floor(fileDur / segmentDuration)
    if (num_segments == 0) {
      nShort <- nShort + 1L
      logFileRow(f, numFiles, id, "skip",
                 sprintf("too short: %.2f s recording < %g s segment",
                         fileDur, segmentDuration))
      if (heartbeat > 0 && f %% heartbeat == 0) logHeartbeat(f, numFiles, startTime)
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
      rel_rmsenergy <- 20*log((rms_energy/1),base=10)

      #----- Add gain-offset
      rel_rmsenergy_gainAdj <- rel_rmsenergy + gainOffset

      # Save results
      rmsenergy[j] <- rel_rmsenergy_gainAdj
    }

    write.csv(rmsenergy, out_file)

    elapsedFile <- as.numeric(difftime(Sys.time(), fileStart, units = "secs"))
    nDone <- nDone + 1L
    segTotal <- segTotal + num_segments
    procSecs <- procSecs + elapsedFile
    logFileRow(f, numFiles, id, "ok",
               sprintf("%s segments in %s", fmtCount(num_segments), fmtDuration(elapsedFile)))

    if (heartbeat > 0 && f %% heartbeat == 0) logHeartbeat(f, numFiles, startTime)
  }

  #----- Final summary
  totalTime <- as.numeric(difftime(Sys.time(), startTime, units = "secs"))

  logSection("RMS power summary")
  logField("Files found",      fmtCount(numFiles))
  logField("Processed",        fmtCount(nDone))
  logField("Skipped (cached)", fmtCount(nCached))
  logField("Skipped (short)",  fmtCount(nShort))
  logField("Skipped (empty)",  fmtCount(nEmpty))
  logField("Failed to read",   fmtCount(nFailed))
  logField("Segments written", fmtCount(segTotal))
  logField("Wall time",        fmtDuration(totalTime))
  if (nDone > 0) {
    logField("Mean per file", paste0(fmtDuration(procSecs / nDone), "  (processed files only)"))
  }
  if (nFailed > 0) {
    message("")
    message("  NOTE: ", nFailed, " file(s) could not be read. Search this log for 'FAIL'.")
  }

  if (nEmpty > 0) {
    message("")
    message("  NOTE: ", nEmpty, " recording(s) contained no audio. If this is more than a",
            " couple of\n        files, check the recorder's battery and SD card.")
  }

  invisible(list(found = numFiles, processed = nDone, cached = nCached,
                 short = nShort, empty = nEmpty, failed = nFailed,
                 segments = segTotal, seconds = totalTime))
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