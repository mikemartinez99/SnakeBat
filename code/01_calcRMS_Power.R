#----- Suppress package startup messages and warnings
suppressPackageStartupMessages({
  library(seewave, quietly = TRUE, warn.conflicts = FALSE)
  library(lubridate, quietly = TRUE, warn.conflicts = FALSE)
  library(tuneR, quietly = TRUE, warn.conflicts = FALSE)
  library(tools, quietly = TRUE, warn.conflicts = FALSE)
})
# Suppress package warnings globally, but allow our custom warnings
old_warn <- getOption("warn")
options(warn = -1)

source("code/BatFunctions.R")

#----- Set command line arguments
args <- commandArgs(trailingOnly = TRUE)

#----- Check that all arguments are supplied
if (length(args) < 7 | length(args) > 7) {
    stop("Usage: RScript 01_calcRMS_Power.R <dataDir> <segmentDuration> <fileType> <samplingRate> <bwFilterFrom> <bwFilterTo> <outputDir>")  
}

#----- Set variables based on command line arguments
dataDir = args[1]
segmentDuration = as.numeric(args[2])
fileType = args[3]
samplingRate = as.numeric(args[4])
bwFilterFrom = as.numeric(args[5])
bwFilterTo = as.numeric(args[6])
outputDir = args[7]

#----- Validate input directory
if (!dir.exists(dataDir)) {
    stop(paste("ERROR: Data directory does not exist:", dataDir))
}

#----- Display configuration
message("========================================")
message("RMS Power Calculation Pipeline")
message("========================================")
message("Configuration:")
message(paste("  Data Directory:    ", dataDir))
message(paste("  Segment Duration:  ", segmentDuration, "seconds"))
message(paste("  File Type:         ", fileType))
message(paste("  Sampling Rate:     ", samplingRate, "Hz"))
message(paste("  Band-pass Filter:  ", bwFilterFrom, "-", bwFilterTo, "Hz"))
message(paste("  Output Directory:  ", outputDir))
message("========================================")

#----- Run the function
rmsPower(dataDir = dataDir,
        segmentDuration = segmentDuration,
        fileType = fileType,
        samplingRate = samplingRate,
        bwFilterFrom = bwFilterFrom,
        bwFilterTo = bwFilterTo,
        outputDir = outputDir)

#----- Organize output files by date
message("\n----------------------------------------")
message("Organizing output files by date")
message("----------------------------------------")

#----- List the files
files <- list.files(outputDir, full.names = TRUE)
suppressPackageStartupMessages({
  library(parallel, quietly = TRUE)
})

nCores <- min(4, detectCores())
mclapply(files, function(i) {
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
}, mc.cores = nCores)

#----- Clean files
csv_files <- list.files(outputDir, pattern = "\\.csv$", full.names = TRUE)
file.remove(csv_files)

#----- Collate results by date
message("\n----------------------------------------")
message("Collating results by date")
message("----------------------------------------")
subdirs <- list.dirs(outputDir, recursive = FALSE, full.names = TRUE)
message(paste("Processing", length(subdirs), "date subdirectories"))

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
mclapply(names(subdirs), function(dateName) {
    folder <- subdirs[dateName]
    total <- calcTotalRMSE(folder, dateName)
    write.csv(total, file = paste0(resultsPath, dateName, "_total_RMSE.csv"))
}, mc.cores = nCores)

# Restore warning level
options(warn = old_warn)

message("\n========================================")
message("Pipeline completed successfully")
message("========================================")