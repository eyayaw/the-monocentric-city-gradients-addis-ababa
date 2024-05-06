library(geodata)
library(sf)

gadm(country = "et", level = 3, "./data/geodata/")
osm("et", "places", "./data/geodata/")


eth_gadm = readRDS("./data/geodata/gadm/gadm41_ETH_3_pk.rds") |>
  terra::unwrap() |>
  st_as_sf()

names(eth_gadm) = tolower(names(eth_gadm))
addis = eth_gadm[eth_gadm$name_1 == "Addis Abeba", grep("_3$", names(eth_gadm))]
addis = addis[, "name_3"]

# Clean up some of the admin names
addis$name_3 = tolower(addis$name_3)
addis$name_3[addis$name_3 %like% "akak[iy]"] = "akaki kality"
addis$name_3[addis$name_3 %like% "kolfe"] = "kolfe keranio"
addis$name_3[addis$name_3 %like% "n[ei]fas"] = "nifas silk-lafto"

st_write(addis, "./data/geodata/addis_gadm_3.gpkg", append = FALSE)

# ocha
# https://data.humdata.org/dataset/cod-ab-eth
url = "https://data.humdata.org/dataset/cb58fa1f-687d-4cac-81a7-655ab1efb2d0/resource/63c4a9af-53a7-455b-a4d2-adcc22b48d28/download/eth_adm_csa_bofedb_2021_shp.zip"
filename = file.path("./data/geodata/", tools::file_path_sans_ext(basename(url)), basename(url))
if (!file.exists(filename) && !dir.exists(dirname(filename))) {
  download.file(url, filename)
  unzip(filename, exdir = dirname(filename))
}

new_boundary = st_read(
  file.path(dirname(filename), "eth_admbnda_adm3_csa_bofedb_2021.shp"),
  quiet = TRUE
)
new_boundary = new_boundary[new_boundary$ADM1_EN == "Addis Ababa", "ADM3_EN"]
names(new_boundary)[1] = "name_3"
new_boundary$name_3 = tolower(new$name_3)
new_boundary$name_3[new_boundary$name_3 %like% "akak[iy]"] = "akaki kality"
new_boundary$name_3[new_boundary$name_3 %like% "kolfe"] = "kolfe keranio"
new_boundary$name_3[new_boundary$name_3 %like% "n[ei]fas"] = "nifas silk-lafto"
st_write(new_boundary, "./data/geodata/addis_ocha_3.gpkg", append = FALSE)
