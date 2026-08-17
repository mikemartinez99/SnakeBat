#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ READ ME ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
#
# Title: 02_collateSummary.R
# Author: Mike Martinez
# Lab: Kloepper
# Date Created: August 17th, 2026
#
# Collates every per-date file written to Total_RMSE/ into one summary table,
# with a row per sample per night. Run by `rule collate_summary`.
#
# Usage: Rscript 02_collateSummary.R <totalsDir> <outputFile>
#
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

suppressPackageStartupMessages({
  library(tools, quietly = TRUE)
})
old_warn <- getOption("warn")
options(warn = -1)

source("code/BatFunctions.R")

#----- Set command line arguments
args <- commandArgs(trailingOnly = TRUE)

if (length(args) != 2) {
    stop("Usage: Rscript 02_collateSummary.R <totalsDir> <outputFile>")
}

totalsDir  <- args[1]
outputFile <- args[2]

runStart <- Sys.time()

logBanner("SnakeBat  |  collate nightly totals")
logField("Started",      format(runStart, "%Y-%m-%d %H:%M:%S"))
logField("Input folder", totalsDir)
logField("Output file",  outputFile)

if (!dir.exists(totalsDir)) {
    stop(paste("ERROR: totals directory does not exist:", totalsDir))
}

#----- One sub-folder per sample, one CSV per date inside it
sampleDirs <- list.dirs(totalsDir, recursive = FALSE, full.names = TRUE)
if (length(sampleDirs) == 0) {
    stop(paste("ERROR: no sample folders found in", totalsDir))
}

logSection(sprintf("Reading %s sample folder(s)", fmtCount(length(sampleDirs))))

#----- Columns every per-date file is expected to carry
requiredCols <- c("rmsEnergy", "AdjustedValue", "date", "Julian",
                  "total_raw_rmse", "total_adj_rmse")

rows <- list()
nFiles <- 0L
nSkipped <- 0L

for (sampleDir in sampleDirs) {
    #----- RMS_Power/<sample>.RMS_Power -> <sample>
    sampleName <- sub("\\.RMS_Power$", "", basename(sampleDir))

    files <- list.files(sampleDir, pattern = "_total_RMSE\\.csv$", full.names = TRUE)
    if (length(files) == 0) {
        logField(sampleName, "no _total_RMSE.csv files - skipped")
        next
    }

    for (f in files) {
        x <- read.csv(f)

        missingCols <- setdiff(requiredCols, colnames(x))
        if (nrow(x) == 0 || length(missingCols) > 0) {
            nSkipped <- nSkipped + 1L
            message("  WARNING: skipping ", basename(f),
                    if (nrow(x) == 0) " (empty)"
                    else paste0(" (missing column(s): ", paste(missingCols, collapse = ", "), ")"))
            next
        }

        #----- total_raw_rmse / total_adj_rmse are constant down the file, so
        #      one value per night is all that needs carrying forward.
        rows[[length(rows) + 1L]] <- data.frame(
            sample          = sampleName,
            date            = as.character(x$date[1]),
            Julian          = x$Julian[1],
            n_seconds       = nrow(x),
            total_raw_rmse  = x$total_raw_rmse[1],
            total_adj_rmse  = x$total_adj_rmse[1],
            mean_rmsEnergy  = mean(x$rmsEnergy),
            min_rmsEnergy   = min(x$rmsEnergy),
            max_rmsEnergy   = max(x$rmsEnergy),
            stringsAsFactors = FALSE
        )
        nFiles <- nFiles + 1L
    }

    logField(sampleName, sprintf("%s night(s)", fmtCount(length(files))))
}

if (length(rows) == 0) {
    stop("ERROR: no usable _total_RMSE.csv files were found - nothing to collate")
}

summary <- do.call(rbind, rows)

#----- Stable ordering: by sample, then chronologically
summary <- summary[order(summary$sample, summary$date), ]
rownames(summary) <- NULL

#----- Make sure the output folder exists
outDir <- dirname(outputFile)
if (outDir != "." && !dir.exists(outDir)) {
    dir.create(outDir, recursive = TRUE)
}

write.csv(summary, file = outputFile, row.names = FALSE)

#----- Report what was written
logSection("Summary")
logField("Samples",       fmtCount(length(unique(summary$sample))))
logField("Nights",        fmtCount(nrow(summary)))
logField("Files read",    fmtCount(nFiles))
if (nSkipped > 0) logField("Files skipped", fmtCount(nSkipped))
logField("Date range",    paste(min(summary$date), "to", max(summary$date)))
logField("Seconds total", fmtCount(sum(summary$n_seconds)))
logField("Written to",    outputFile)

message("")
message("  ", formatC("sample",   width = -18),
             formatC("date",      width = -13),
             formatC("seconds",   width = -11),
             formatC("total raw RMSE", width = -19),
             "total adj RMSE")
message("  ", strrep("-", 78))
for (k in seq_len(nrow(summary))) {
    message("  ", formatC(summary$sample[k],                    width = -18),
                 formatC(summary$date[k],                       width = -13),
                 formatC(fmtCount(summary$n_seconds[k]),        width = -11),
                 formatC(fmtValue(summary$total_raw_rmse[k]),   width = -19),
                 fmtValue(summary$total_adj_rmse[k]))
}

options(warn = old_warn)

runEnd <- Sys.time()
message("")
logBanner(sprintf("Finished %s   |   total %s",
                  format(runEnd, "%Y-%m-%d %H:%M:%S"),
                  fmtDuration(as.numeric(difftime(runEnd, runStart, units = "secs")))))
