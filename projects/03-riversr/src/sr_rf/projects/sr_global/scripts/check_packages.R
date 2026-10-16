pkgs <- c(
  "terra", "sf", "raster", "data.table", "dplyr",
  "ranger", "randomForest", "caret", "future", "furrr",
  "arrow", "optparse"
)

cat("R version:\n")
print(R.version.string)

cat("\nPackage availability:\n")
print(sapply(pkgs, requireNamespace, quietly = TRUE))

cat("\nTry loading key packages:\n")
library(terra)
library(sf)
library(ranger)
library(data.table)
library(dplyr)

cat("\nAll key packages loaded successfully.\n")

cat("\nSession info:\n")
sessionInfo()
