library(seewave)
library(lubridate)
library(tuneR)
library(tools)

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

#----- Check that dataDir exists
message("--------------------------------------------------")
message("Checking that dataDir exists...")
if (!dir.exists(dataDir)) {
    stop(paste(dataDir, "Does not exist or is empty!\n"))
} else {
    message(paste(dataDir, "exists!\n"))
}
message("--------------------------------------------------\n")

message("--------------------------------------------------")
message("Starting RMS power calculation with the following arguments:")
message(paste("\tdataDir:", dataDir))
message(paste("\tsegmentDuration:", segmentDuration))
message(paste("\tfileType:", fileType))
message(paste("\tsamplingRate:", samplingRate))
message(paste("\tbwFilterFrom:", bwFilterFrom))
message(paste("\tbwFilterTo:", bwFilterTo))
message(paste("\toutputDir:", outputDir))
message("--------------------------------------------------\n")

#----- Run the function
rmsPower(dataDir = dataDir,
        segmentDuration = segmentDuration,
        fileType = fileType,
        samplingRate = samplingRate,
        bwFilterFrom = bwFilterFrom,
        bwFilterTo = bwFilterTo,
        outputDir = outputDir)

#----- Adjust RMS files
message("--------------------------------------------------")
message("Adjusting RMS files in output directory...")
message("--------------------------------------------------\n")

#----- List the files
files <- list.files(outputDir, full.names = TRUE)
library(parallel)

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

#----- Adjust RMS files
message("--------------------------------------------------")
message("Collating results...")
message("--------------------------------------------------\n")

#----- List subdirectories
subdirs <- list.dirs(outputDir, recursive = FALSE, full.names = TRUE)
message(paste0("Found ", length(subdirs), " date subdirectories to process"))

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