library(seewave)
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
for (i in files) {

    #----- Get the file basename
    fname <- basename(i)

    #----- Extract date using regex _YYYYMMDD_
    date <- sub(".*_(\\d{8})_.*", "\\1", fname)

    #----- Create a subfolder for this date
    dateDir <- file.path(outputDir, date)
    if (!dir.exists(dateDir)) {
        dir.create(dateDir)
    } 
    
    #----- Read and clean
    curFile <- read.csv(i)
    colnames(curFile) <- c("X", "rmsEnergy")
    
    #----- Remove NAs
    curFile <- na.omit(curFile)

    #----- Check for empty files
    if (nrow(curFile) == 0) {
        message(paste("Skipping empty file:", i))
    next
    }
    
    #----- Remove X or X.1 columns if present
    if ("X" %in% colnames(curFile)) curFile$X <- NULL
    if ("X.1" %in% colnames(curFile)) {
        rownames(curFile) <- curFile$X.1
        curFile$X.1 <- NULL
    }
    
    #----- Ensure column name is rmsEnergy
    if ("rmsenergy" %in% colnames(curFile)) colnames(curFile) <- c("rmsEnergy")
    
    #----- Adjust RMS
    minValue <- min(curFile$rmsEnergy)
    absValue <- abs(minValue)
    curFile$AdjustedValue <- absValue + curFile$rmsEnergy
    
    #----- Save
    write.csv(curFile, file = file.path(dateDir, fname), row.names = TRUE)
}

#----- Clean files
csv_files <- list.files(outputDir, pattern = "\\.csv$", full.names = TRUE)
file.remove(csv_files)

#----- Adjust RMS files
message("--------------------------------------------------")
message("Collating results...")
message("--------------------------------------------------\n")

#----- List subdirectories
subdirs <- list.dirs(outputDir, recursive = FALSE, full.names = TRUE)
message(subdirs)

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
for (i in subdirs) {
    message(paste("Calculating daily total for ", i))
    date <- dates[i]
    folder <- subdirs[i]
    dateName <- basename(i)

    #----- Apply the function
    total <- calcTotalRMSE(i, dateName)

    #----- Save csv
    write.csv(total, file = paste0(resultsPath, dateName, "_total_RMSE.csv"))

}