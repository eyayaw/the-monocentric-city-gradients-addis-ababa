download_wsf = function(in_subdir = FALSE, lng_lat_range = "38_8", year, v) {
  base_url = if (in_subdir)
    glue::glue("https://download.geoservice.dlr.de/WSF{year}/files/WSF{year}_v{v}_{lng_lat_range}/")
  else
    glue::glue("https://download.geoservice.dlr.de/WSF{year}/files")
  files = c(
    "WSF{year}_v{v}_{lng_lat_range}.tif",
    "WSF{year}_v{v}_{lng_lat_range}_overview.png",
    "WSF{year}_v{v}_{lng_lat_range}_thumbnail.png",
    "WSF{year}_v{v}_{lng_lat_range}_overview.png.aux.xml",
    "WSF{year}_v{v}_{lng_lat_range}_thumbnail.png.aux.xml",
    "WSF{year}_v{v}_{lng_lat_range}_metadata.xml",
    "WSF{year}_v{v}_{lng_lat_range}_stac.json",
    "WSF{year}_README.txt"
  )
  outdir = glue::glue("./data/geodata/DLR/wsf/{year}_v{v}/")
  dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
  for (file in files) {
    file = glue::glue(file, year = year, v = v, lng_lat_range = lng_lat_range)
    url = glue::glue("{base_url}{file}", base_url = base_url, file = file)
    if (file.exists(glue::glue("{outdir}/{file}"))) {
      next
    }
    tryCatch(
      download.file(url, destfile = glue::glue("{outdir}/{file}"), mode = "wb"),
      error = function(e) {
        message(glue::glue("Failed to download {url}: {e$message}"))
      }
    )
  }
}

# Download WSF data for Addis Ababa
download_wsf(year = 2019, v = 1)
download_wsf(in_subdir = T, year = 2015, v = 2)
