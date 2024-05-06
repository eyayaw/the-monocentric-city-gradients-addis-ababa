library(sf)

# Corner coordinates, wider than the actual boundary
southwest = c(lng = 38.5951, lat = 8.7825)
northeast = c(lng = 38.9760, lat = 9.2320)

create_addis_polygon = function() {
  # Define the polygon corners
  southeast = c(lng = northeast["lng"], lat = southwest["lat"])
  northwest = c(lng = southwest["lng"], lat = northeast["lat"])

  polygon_coords = rbind(southwest, southeast, northeast, northwest, southwest)
  polygon = sf::st_polygon(list(polygon_coords))
  polygon = sf::st_sfc(polygon, crs = 4326)
  return(polygon)
}

.addis_polygon = create_addis_polygon()

# Stricter version
.admin_areas = st_read("./data/geodata/addis_ocha_3.gpkg", quiet = TRUE)

# Helper to check if a point(lng,lat) is within Addis Ababa
is_within_addis = function(lng, lat) {
  points = st_as_sf(data.frame(lng, lat), coords = c("lng", "lat"), crs = 4326)
  # Ensure the CRS matches for both geometries
  if (st_crs(points) != st_crs(.admin_areas)) {
    points = st_transform(points, st_crs(.admin_areas))
  }

  intersects = st_intersects(st_geometry(points), .admin_areas)
  return(lengths(intersects) > 0)
}

is_within_addis2 = function(lng, lat) {
  # Create sf point
  points = st_as_sf(data.frame(lng, lat), coords = c("lng", "lat"), crs = 4326)
  # Ensure the CRS matches for both geometries
  if (st_crs(points) != st_crs(.addis_polygon)) {
    points = st_transform(point, st_crs(.addis_polygon))
  }
  # Check if the point intersects with the polygon
  intersects = sf::st_intersects(points, .addis_polygon)
  lengths(intersects) > 0
}

