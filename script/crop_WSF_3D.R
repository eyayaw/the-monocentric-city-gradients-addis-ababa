library(terra)

# Define the extent for Addis Ababa
# The values should be in the same crs as the raster
SW = c(8.7, 38.5) |> rev()
NE = c(9.21, 39.1) |> rev()
addis_extent = terra::ext(c(SW[1], NE[1], SW[2], NE[2]))

crop_file = function(file, extent, out_file = NULL) {
  # Load the raster file
  input = rast(file)
  # Crop the raster by extent
  cropped = crop(input, extent)
  # Write the cropped raster to a new file
  if (is.null(out_file)) {
    out_file = paste0(
      tools::file_path_sans_ext(file), "_cropped.", tools::file_ext(file)
    )
  }
  terra::writeRaster(cropped, out_file, overwrite = TRUE)
  invisible(cropped)
}

flist = list.files(
  path = "./data/geodata/DLR/wsf-3d/",
  pattern = "Building[A-Z][a-z]+.tif$",
  full.names = TRUE
)

for (file in flist) {
  crop_file(file, addis_extent)
}
