library(sf)
library(terra)
library(ggplot2)
library(rayshader)
library(data.table)
utm_zone_37N = "EPSG:32637"

read_building_stat = function(building_stat) {
  file = paste0(
    "./data/geodata/DLR/wsf-3d/WSF3D_V02_Building",
    tools::toTitleCase(building_stat), "_cropped.tif"
  )
  img = rast(file)
  img = project(img, utm_zone_37N)
  names(img) = "value"
  return(img)
}

# Read the administrative areas, cbds
admin_areas = st_read("./data/geodata/addis_ocha_3.gpkg", quiet = TRUE) |>
  st_transform(utm_zone_37N)
cbds = read.csv("./data/geodata/cbds.txt") |>
  st_as_sf(coords = c("lng", "lat"), crs = 4326) |>
  st_transform(utm_zone_37N)


# Create grid cells of size 100m
RES = c(100, 100)
grid = st_make_grid(admin_areas, cellsize = RES, square = TRUE) |> st_as_sf()
st_geometry(grid) = "geometry"

# ggplot() +
#   geom_sf(data = grid, fill = "red", color = NA, alpha = 0.1) +
#   geom_sf(data = admin_areas, fill = NA) +
#   theme_void()

grid$grid_id = seq_len(nrow(grid))
dists = st_distance(st_centroid(grid), cbds) |>
  as.data.table() |>
  setNames(paste0("dist_", gsub("\\s+", "_", tolower(cbds$short_name))))

grid = cbind(grid, dists)

# Google open buildings ----
open_buildings = data.table::fread("./data/geodata/open-buildings/open_buildings_v3_polygons_your_own_wkt_polygon.csv")

buildings = open_buildings[confidence >= 0.75, -c("latitude", "longitude"), with = FALSE] |>
  st_as_sf(wkt = "geometry", crs = 4326)

# Ensure buildings are in a projected CRS that uses meters
buildings = st_transform(buildings, crs = utm_zone_37N)
buildings = buildings[grid, ] # crop buildings to the extent of the grid
# Find the buildings that intersect with the grid
intersections = st_intersection(buildings, grid)
intersections$intersected_area = as.numeric(st_area(intersections))
intersections$coverage_fraction = intersections$intersected_area / intersections$area_in_meters

gl_data = st_drop_geometry(intersections) |> as.data.table()
# Count the number of buildings that intersect with each grid cell
gl_data = gl_data[, .(
  gl_count = .N,
  gl_count_exact = sum(coverage_fraction, na.rm = TRUE),
  gl_area = sum(area_in_meters, na.rm = TRUE),
  gl_area_exact = sum(intersected_area, na.rm = TRUE),
  gl_fraction = 100 * sum(intersected_area / prod(RES), na.rm = TRUE)
), by = grid_id
]


# ggplot() +
#   geom_sf(data = grids[grids$gl_count>0, ], aes(fill = gl_count), color=NA) +
#   scale_fill_viridis_c(direction = -1) +
#   theme_void() +
#   labs(fill = "# Buildings")

# DLR WSF 3D Datasets ----
building_stats = setNames(nm = c("area", "fraction", "height", "volume"))
img_list = lapply(building_stats, read_building_stat)
img_list$built_up = rast("./data/geodata/DLR/wsf/2019_v1/WSF2019_v1_38_8.tif") |>
  project(utm_zone_37N)
img_list = lapply(img_list, function(img) {
  img = crop(img, grid) |> mask(grid)
  return(img)
})
img_list$built_up = ifel(img_list$built_up == 255, img_list$built_up, NA) # clamp(img_list$built_up, lower=255, values=F)

# Extract the values that fall within grid cells
extract_values = function(img, drop_NAs = TRUE, ...) {
  extracted = exactextractr::exact_extract(img, grid, ...)
  extracted = data.table::rbindlist(extracted, idcol = "grid_id")
  if (drop_NAs) {
    extracted = extracted[!is.na(value), ]
  }
  return(extracted)
}
# TODO: speed up by passing summary functions directly to exact_extract
extracted = vector("list", length(img_list))
names(extracted) = names(img_list)
for (i in seq_along(extracted)) {
  extracted[[i]] = extract_values(img_list[[i]])
}

dlr_data = vector("list", length(building_stats))
names(dlr_data) = names(building_stats)

dlr_data$height = extracted$height[, .(
  height_mean = weighted.mean(value, coverage_fraction, na.rm = TRUE),
  height_max = max(value, na.rm = TRUE)
), by = grid_id]

dlr_data$area = extracted$area[,
  .(
    area_exact = sum(value * coverage_fraction, na.rm = TRUE),
    area  = sum(value, na.rm = TRUE)
  ),
  by = grid_id
]
dlr_data$fraction = extracted$fraction[,
  .(
    fraction_mean = weighted.mean(value, coverage_fraction, na.rm = TRUE)
  ),
  by = grid_id
]
dlr_data$volume = extracted$volume[,
  .(
    volume_sum = sum(value * coverage_fraction, na.rm = TRUE),
    volume_max = max(value, na.rm = TRUE),
    volume_mean = weighted.mean(value, coverage_fraction, na.rm = TRUE)
  ),
  by = grid_id
]

dlr_data$built_up = extracted$built_up[,
  .(
    count_exact = sum(coverage_fraction, na.rm = TRUE),
    count = .N),
  by = grid_id
]

# Merge the extracted values
dlr_data = Reduce(function(x, y) merge(x, y, by = "grid_id", all = TRUE), dlr_data)
setnames(
  dlr_data,
  setdiff(names(dlr_data), "grid_id"),
  paste0("dlr_", setdiff(names(dlr_data), "grid_id"))
)

# Merge the extracted values with the grid
buildings_data = merge(gl_data, dlr_data, by = "grid_id", all = TRUE)
buildings_data = merge(grid, buildings_data, by = "grid_id", all = TRUE)

st_write(buildings_data, "./data/geodata/buildings_data.gpkg", append = FALSE)

# Filter out buildings outside Addis Ababa
# buildings_data = buildings_data[admin_areas, ]
# Allow some buffer (100m) around the boundary
lst = st_is_within_distance(buildings_data, admin_areas, 100)
buildings_data = buildings_data[lengths(lst) > 0, ]
st_write(
  buildings_data, "./data/geodata/buildings_data_within.gpkg", append = FALSE
)

# Make 3d map ----
# mat = raster_to_matrix(img_list$height)
# palette = rev(hcl.colors(10, "reds"))
# rgl::close3d()
# texture = grDevices::colorRampPalette(palette)(256)
# mat |>
#   height_shade(texture = texture) |>
#   plot_3d(
#     heightmap = mat,
#     zscale = 0.8,
#     solid = FALSE,
#     shadowdepth = 0
#   )
#
# render_camera(theta = 0, phi = 15, zoom = .5)
# render_snapshot()
