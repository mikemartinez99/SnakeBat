#----- Suppress package startup messages and warnings
suppressPackageStartupMessages({
  library(seewave, quietly = TRUE, warn.conflicts = FALSE)
  library(lubridate, quietly = TRUE, warn.conflicts = FALSE)
  library(tuneR, quietly = TRUE, warn.conflicts = FALSE)
  library(tools, quietly = TRUE, warn.conflicts = FALSE)
  library(parallel, quietly = TRUE)
})
# Suppress package warnings globally, but allow our custom warnings
old_warn <- getOption("warn")
options(warn = -1)

source("code/BatFunctions.R")

#----- Set command line arguments
args <- commandArgs(trailingOnly = TRUE)

#----- Check that all arguments are supplied
if (length(args) != 8) {
    stop("Usage: RScript 01_calcRMS_Power.R <dataDir> <segmentDuration> <fileType> <samplingRate> <gainOffset> <bwFilterFrom> <bwFilterTo> <outputDir>")
}

#----- Set variables based on command line arguments
dataDir = args[1]
segmentDuration = as.numeric(args[2])
fileType = args[3]
samplingRate = as.numeric(args[4])
gainOffset = as.numeric(args[5])
bwFilterFrom = as.numeric(args[6])
bwFilterTo = as.numeric(args[7])
outputDir = args[8]

#----- Sample name, for the log header (RMS_Power/<sample>.RMS_Power -> <sample>)
runStart <- Sys.time()
sampleName <- sub("\\.RMS_Power$", "", basename(outputDir))

#----- Display configuration
logBanner(sprintf("SnakeBat  |  RMS power  |  sample: %s", sampleName))
logField("Started",         format(runStart, "%Y-%m-%d %H:%M:%S"))
logField("Input folder",    dataDir)
logField("Output folder",   outputDir)
logField("Segment length",  paste(segmentDuration, "s"))
logField("File type",       fileType)
logField("Sampling rate",   paste(fmtCount(samplingRate), "Hz"))
logField("Band-pass filter", sprintf("%s - %s Hz", fmtCount(bwFilterFrom), fmtCount(bwFilterTo)))
logField("Gain offset",     sprintf("%+.1f dB", gainOffset))
logField("R version",       paste(R.version$major, R.version$minor, sep = "."))

#----- Validate input directory
if (!dir.exists(dataDir)) {
    stop(paste("ERROR: Data directory does not exist:", dataDir))
}

#----- Run the function
rmsStats <- rmsPower(dataDir = dataDir,
        segmentDuration = segmentDuration,
        fileType = fileType,
        samplingRate = samplingRate,
        gainOffset = gainOffset,
        bwFilterFrom = bwFilterFrom,
        bwFilterTo = bwFilterTo,
        outputDir = outputDir)

#----- Organize output files by date
logSection("Organising output files by date")

#----- List the files
files <- list.files(outputDir, full.names = TRUE)

nCores <- min(4, detectCores())
logField("Parallel workers", nCores)

dated <- unlist(mclapply(files, function(i) {
    fname <- basename(i)
    date <- sub(".*_(\\d{8})_.*", "\\1", fname)
    dateDir <- file.path(outputDir, date)
    if (!dir.exists(dateDir)) dir.create(dateDir)

    curFile <- read.csv(i)
    colnames(curFile) <- c("X", "rmsEnergy")
    curFile <- na.omit(curFile)
    if (nrow(curFile) == 0) return(NULL)

    if ("X" %in% colnames(curFile)) curFile$X <- NULL
    if ("X.1" %in% colnames(curFile)) {
        rownames(curFile) <- curFile$X.1
        curFile$X.1 <- NULL
    }
    if ("rmsenergy" %in% colnames(curFile)) colnames(curFile) <- c("rmsEnergy")

    curFile$AdjustedValue <- curFile$rmsEnergy + abs(min(curFile$rmsEnergy))
    write.csv(curFile, file = file.path(dateDir, fname), row.names = TRUE)
    date
}, mc.cores = nCores))

dateList <- sort(unique(dated))
logField("Files organised", fmtCount(length(dated)))
logField("Date folder(s)", sprintf("%s  [%s]", fmtCount(length(dateList)),
                                   paste(dateList, collapse = ", ")))
if (length(files) > length(dated)) {
    logField("Empty, skipped", fmtCount(length(files) - length(dated)))
}

#----- Clean files
csv_files <- list.files(outputDir, pattern = "\\.csv$", full.names = TRUE)
removed <- file.remove(csv_files)
logField("Staging files cleared", fmtCount(sum(removed)))

#----- Collate results by date
logSection("Collating nightly totals")

subdirs <- list.dirs(outputDir, recursive = FALSE, full.names = TRUE)

#----- Create a vector of dates that correspond to the subFolders
dates <- basename(subdirs)
names(subdirs) <- dates
names(dates) <- dates

#----- New output dir
opDir <- "Total_RMSE/"
if (!dir.exists(opDir)) {
    dir.create(opDir)
}
sample <- basename(outputDir)
resultsPath <- paste0(opDir, sample, "/")
if (!dir.exists(resultsPath)) {
    dir.create(resultsPath)
}

#----- Apply function to all subFolders
summaries <- mclapply(names(subdirs), function(dateName) {
    folder <- subdirs[dateName]
    total <- calcTotalRMSE(folder, dateName)
    if (is.null(total) || nrow(total) == 0) return(NULL)
    write.csv(total, file = paste0(resultsPath, dateName, "_total_RMSE.csv"))
    data.frame(date = dateName,
               rows = nrow(total),
               raw  = total$total_raw_rmse[1],
               adj  = total$total_adj_rmse[1],
               stringsAsFactors = FALSE)
}, mc.cores = nCores)

summaries <- do.call(rbind, Filter(Negate(is.null), summaries))

#----- Per-date table, so the totals are visible without opening the CSVs
if (!is.null(summaries) && nrow(summaries) > 0) {
    message("")
    message("  ", formatC("date",       width = -12),
                 formatC("seconds",     width = -12),
                 formatC("total raw RMSE", width = -20),
                 "total adj RMSE")
    message("  ", strrep("-", 62))
    for (k in seq_len(nrow(summaries))) {
        message("  ", formatC(summaries$date[k],              width = -12),
                     formatC(fmtCount(summaries$rows[k]),     width = -12),
                     formatC(fmtValue(summaries$raw[k]),      width = -20),
                     fmtValue(summaries$adj[k]))
    }
    message("")
    logField("Nightly files", sprintf("%s written to %s",
                                      fmtCount(nrow(summaries)), resultsPath))
} else {
    message("")
    message("  WARNING: no nightly totals were written - every date folder was empty.")
}

# Restore warning level
options(warn = old_warn)

runEnd <- Sys.time()
message("")
logBanner(sprintf("Finished %s   |   total %s",
                  format(runEnd, "%Y-%m-%d %H:%M:%S"),
                  fmtDuration(as.numeric(difftime(runEnd, runStart, units = "secs")))))
