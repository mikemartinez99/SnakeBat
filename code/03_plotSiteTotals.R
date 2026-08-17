#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ READ ME ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
#
# Title: 03_plotSiteTotals.R
# Author: Mike Martinez / Megan Graham
# Lab: Kloepper
# Date Created: August 17th, 2026
#
# Plots nightly adjusted RMS energy against Julian date for one site.
# Run by `rule plot_site_totals`.
#
# Usage: Rscript 03_plotSiteTotals.R <combinedCsv> <sampleName> <outputPng>
#
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

suppressPackageStartupMessages({
  library(ggplot2, quietly = TRUE, warn.conflicts = FALSE)
})
old_warn <- getOption("warn")
options(warn = -1)

source("code/BatFunctions.R")

#----- Set command line arguments
args <- commandArgs(trailingOnly = TRUE)

if (length(args) != 3) {
    stop("Usage: Rscript 03_plotSiteTotals.R <combinedCsv> <sampleName> <outputPng>")
}

combinedCsv <- args[1]
sampleName  <- args[2]
outputPng   <- args[3]

#----- Plot appearance. Adjust here rather than in the ggplot call below.
BASE_SIZE  <- 20      # was 28.5; 20 stays poster-legible at the size below
PLOT_WIDTH <- 10
PLOT_HEIGHT<- 7
PLOT_DPI   <- 300
POINT_FILL <- "#E8A33D"
SMOOTH_COL <- "#029475"
Y_LABEL    <- "RMS Amplitude (V)"

runStart <- Sys.time()

logBanner(sprintf("SnakeBat  |  nightly RMS plot  |  sample: %s", sampleName))
logField("Started",     format(runStart, "%Y-%m-%d %H:%M:%S"))
logField("Input file",  combinedCsv)
logField("Output file", outputPng)

if (!file.exists(combinedCsv)) {
    stop(paste("ERROR: input file does not exist:", combinedCsv))
}

x <- read.csv(combinedCsv)

requiredCols <- c("Julian", "date", "total_adj_rmse", "total_raw_rmse")
missingCols <- setdiff(requiredCols, colnames(x))
if (length(missingCols) > 0) {
    stop(paste("ERROR: missing column(s) in", combinedCsv, ":",
               paste(missingCols, collapse = ", ")))
}

#----- The combined file holds one row PER SECOND, but total_adj_rmse is a
#      nightly constant repeated down every row. Plotting it as-is would stack
#      thousands of identical points on top of each other, so reduce to one
#      row per night first.
x$Site <- sampleName
plotData <- unique(x[, c("Site", "date", "Julian", "total_raw_rmse", "total_adj_rmse")])
plotData <- plotData[order(plotData$Julian), ]

nNights <- nrow(plotData)
logField("Rows read",      fmtCount(nrow(x)))
logField("Nights plotted", fmtCount(nNights))
logField("Julian range",   paste(min(plotData$Julian), "to", max(plotData$Julian)))

#----- geom_smooth(method = "gam") needs more distinct x values than the basis
#      dimension k, and errors outright on a handful of nights. Scale k to the
#      data, and drop the smooth entirely when there is too little to fit.
addSmooth <- nNights >= 4
kVal <- max(3, min(10, nNights - 1))
if (addSmooth) {
    logField("Smooth", sprintf("gam, k = %d", kVal))
} else {
    logField("Smooth", sprintf("skipped - only %d night(s), need 4+", nNights))
}

p <- ggplot(plotData, aes(x = Julian, y = total_adj_rmse)) +
  theme_bw(base_size = BASE_SIZE)

if (addSmooth) {
  p <- p + geom_smooth(method = "gam",
                       formula = y ~ s(x, k = kVal),
                       colour = SMOOTH_COL,
                       fill = SMOOTH_COL,
                       alpha = 0.15,
                       linewidth = 1.1)
}

p <- p +
  geom_point(size = 4, shape = 21, colour = "black",
             fill = POINT_FILL, stroke = 0.9) +
  facet_grid(~ Site) +
  scale_x_continuous(breaks = scales::pretty_breaks(n = 6)) +
  scale_y_continuous(labels = function(v) format(v, big.mark = ",", trim = TRUE)) +
  labs(x = "Julian Date",
       y = Y_LABEL) +
  theme(strip.text = element_text(face = "bold"),
        axis.title = element_text(face = "bold"),
        axis.title.x = element_text(margin = margin(t = 12)),
        axis.title.y = element_text(margin = margin(r = 12)),
        strip.background = element_rect(fill = "white", colour = "black"),
        legend.position = "none",
        panel.grid.minor = element_blank(),
        panel.grid.major.x = element_blank(),
        panel.grid.major.y = element_line(colour = "grey88", linewidth = 0.4),
        panel.background = element_rect(fill = "transparent", colour = NA),
        plot.background = element_rect(fill = "transparent", colour = NA),
        plot.margin = margin(14, 18, 12, 14))

#----- Make sure the output folder exists
outDir <- dirname(outputPng)
if (outDir != "." && !dir.exists(outDir)) {
    dir.create(outDir, recursive = TRUE)
}

ggsave(outputPng, plot = p,
       width = PLOT_WIDTH, height = PLOT_HEIGHT, dpi = PLOT_DPI,
       bg = "transparent")

logSection("Summary")
logField("Written to", outputPng)
logField("Size",       sprintf("%g x %g in at %d dpi", PLOT_WIDTH, PLOT_HEIGHT, PLOT_DPI))
logField("File size",  paste(round(file.size(outputPng) / 1024), "KB"))

options(warn = old_warn)

runEnd <- Sys.time()
message("")
logBanner(sprintf("Finished %s   |   total %s",
                  format(runEnd, "%Y-%m-%d %H:%M:%S"),
                  fmtDuration(as.numeric(difftime(runEnd, runStart, units = "secs")))))
