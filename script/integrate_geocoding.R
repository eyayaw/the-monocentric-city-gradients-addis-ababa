library(data.table)
library(sf)
source("./script/helpers/helpers_geo.R")

expand_column = function(dt, col = "ids", new_name = "id") {
  # Split the specified column
  splits_col = strsplit(get(col, dt), ",", fixed = TRUE)

  # Construct the lengths of the split elements
  len_splits = lengths(splits_col)
  # Replicate the other columns according to the lengths
  rows = rep(seq_along(len_splits), len_splits)
  replicated_dt = dt[rows, setdiff(names(dt), col), with = FALSE]

  # Create a new data.table with the split column and the replicated other columns
  expanded_dt = data.table(unlist(splits_col), replicated_dt)
  setnames(expanded_dt, c(new_name, names(replicated_dt)))
  return(expanded_dt)
}

load_geocoded = function(path, ...) {
  # Load the geocoded addresses data
  geocoded = fread(path, ...)

  # Filter successful geocodes for non-unique records
  # NB: The geocoding was rerun for unsuccessful/results==[] addresses, so we may have duplicates by id.
  geocoded = geocoded[, .SD[!(is.na(lng) | is.na(lat)), ][order(file), ][.N, ], id]
  # geocoded = unique(geocoded, by = "id")
  # reruns may have produced good results and this does not work as it keeps the first record
  # Set column order
  setcolorder(geocoded, c("id", "unique_address_grp", "address_main", "address_alt"))
  try(
   {
     setcolorder(geocoded, "suggestion_name", after = "suggestion_suggested_address")
   },
   silent = TRUE
 )
  # geocoded = geocoded[, setdiff(names(geocoded), c("file", "source")), with = FALSE]
  return(geocoded)
}


## import data ----
listings = fread(
  "./data/housing/processed/tidy/listings_cleaned_tidy.csv",
  na.strings = "", drop = c("address_extracted_transliterated")
)

property_addresses = fread("./data/geodata/geocode/property_addresses__unique.csv")


# Paths geocoded addresses
search = "./data/geodata/geocode/geocoded_addresses__search.csv"
autocomplete = "./data/geodata/geocode/geocoded_addresses__autocomplete.csv"

geocoded_search = load_geocoded(search)
geocoded_autocomplete = load_geocoded(autocomplete)

# Expand ids
expand_column(property_addresses) ->
  property_addresses_expanded

# # Filter geocoded addresses to only include those in the property listings
# you can also take care of this in geocod_tidy.py
geocoded_search = geocoded_search[id %in% listings$id, ]
geocoded_autocomplete = geocoded_autocomplete[id %in% listings$id, ]


# For results using the place search api
# We need to check the distance between the suggested address and the geocoded address.
# Sometimes, the geocoding api return completely different lng and lat for an address
# suggested by the place search or autocomplete api.
# The search api returns lng/lat for the suggested address, but autocomplete does not.
# We can use this info to flag inconsistencies in the geocoding.
calc_dist = function(lng1, lat1, lng2, lat2) {
  if (length(lng1) != length(lng2) || length(lat1) != length(lat2)) {
    stop("All inputs must be of equal length.", call. = FALSE)
  }
  if (anyNA(c(lng1, lat1, lng2, lat2))) {
    stop("All inputs must be non-NA.", call. = FALSE)
  }

  # dt = data.table(id_ = seq_along(lng1), lng1, lat1, lng2, lat2)
  # clean_dt = na.omit(dt)

  coords1 = st_as_sf(data.frame(lng1, lat1), coords = c("lng1", "lat1"), crs = 4326)
  coords2 = st_as_sf(data.frame(lng2, lat2), coords = c("lng2", "lat2"), crs = 4326)

  # Calculate distance in kilometers
  dist = as.numeric(st_distance(coords1, coords2, by_element = TRUE)) / 1000

  # dt = merge(dt, clean_dt[, c("id_", "dist")], by = "id_", all.x = T)
  # return(dt)

  return(dist)
}

has_coords = geocoded_search[, .(lng, lat, suggestion_geometry_lng, suggestion_geometry_lat)
                             ][, .(has_coords = !anyNA(.SD)), .I, ]$has_coords
geocoded_search[has_coords,
  accuracy_dist :=
    calc_dist(lng, lat, suggestion_geometry_lng, suggestion_geometry_lat)
]


# The "formatted_address" of a place from the "place search" and "description" from "autocomplete"
# apis are fed to the geocoding api, which returns either Addis's center lng/lat or a completely outside
# However, for some the "name" attribute would have been a better choice.

# unique(geocoded_search, by = 'unique_address_grp')[accuracy_dist > 25, ]
geocoded_search[accuracy_dist > 0.5, `:=`(
  place_name = suggestion_name,
  place_id = suggestion_place_id,
  lng = suggestion_geometry_lng,
  lat = suggestion_geometry_lat,
  plus_code = suggestion_plus_code
)]

# Prefer the autocomplete results for more problematic ones if applicable
above_30 = geocoded_search[accuracy_dist > 30, which = TRUE]
autocomplete_tmp = geocoded_autocomplete[id %in% geocoded_search[above_30, id],]
geocoded_search_tmp = geocoded_search[above_30, ] # if autocomplete does not work, fallback to the search results # then drop them below if outside addis
geocoded = rbind(
  geocoded_search[-above_30],
  autocomplete_tmp,
  geocoded_search_tmp[id %notin% autocomplete_tmp$id,],
  use.names = TRUE, fill = TRUE
  )

# For those where search failed, try autocomplete
search_fails = setdiff(property_addresses_expanded$id, geocoded$id)
geocoded_autocomplete_search_fails = geocoded_autocomplete[id %in% search_fails, ]

geocoded = rbind(
  geocoded,
  geocoded_autocomplete_search_fails,
  use.names = TRUE, fill = TRUE
)

# Match by (address main, address alt) pair for those that have not matched/geocoded
geocoded_match = merge(
  property_addresses_expanded[
    id %notin% geocoded$id, .(id, address_main, address_alt)
  ],
  unique(geocoded[, !"id"], by = c("address_main", "address_alt")),
  by = c("address_main", "address_alt"),
)

geocoded = rbind(
  geocoded,
  geocoded_match,
  use.names = TRUE, fill = TRUE
)

rm(geocoded_match, geocoded_autocomplete_search_fails, geocoded_search_tmp, autocomplete_tmp)

# merge the geocoded addresses with the property data ----
come_with_lnglat = listings[!is.na(lng) & !is.na(lat),
                            ][is_within_addis2(lng, lat)]
if (any(come_with_lnglat$id %in% geocoded$id)) {
  warning("Some of the ones that comes with exact (lng,lat) are already in the geocoded data.", call. = FALSE)
}

listings_geocoded = merge(
  listings[id %notin% come_with_lnglat$id, -c("lng", "lat")],
  geocoded[, .(id, address_main, address_alt, unique_address_grp, lng, lat, place_name, place_id)],
  "id" # all.x should be false for broad addresses below. Do not keep not geocoded ones!
)

listings_geocoded = rbind(
  listings_geocoded, come_with_lnglat, use.names = TRUE, fill = TRUE
)
setorder(listings_geocoded, provider, id)


# Broad addresses ----
broad_addresses = c(
  "Addis Ababa", "Addis Ketema", "Akaki Kality", "Arada", "Bole", "Gulele",
  "Kirkos", "Kolfe Keranio", "Lideta", "Nifas Silk-Lafto", "Yeka"
) |>
  tolower()

property_addresses_broad = property_addresses_expanded[
    address_main %in% broad_addresses & address_alt %in% broad_addresses,
  ]

# Those with broad addresses (addis ababa and its sub cities)
# Randomly draw addresses within the boundary of the sub city for these listings
# otherwise, we will have a lot of listings with the same lng/lat.
# NB: For an ad, its "main address" could be "broad", but its "alternate address" is acceptable,
# and vice versa. Whichever is not broad is used in the geocoding routine.
# Therefore, some ads could be excluded below because they may have been geocoded correctly.

sample_points = function(x, size) {
  if (!inherits(x, "sf") || inherits(sf::st_geometry(x), "sfc_POINT")) {
    stop("x must be an 'sf' object with 'sfc_(MULTI)POLYGON' geometry type")
  }
  if (size < 1) {
    stop("size must be a positive integer")
  }
  # Sample n points within the polygon
  set.seed(202403)
  sampled_points = sf::st_sample(x, size = size, type = "random", exact = TRUE) |>
                   sf::st_coordinates() |>
                   as.data.frame() |>
                   setNames(c("lng", "lat"))
  return(sampled_points)
}

admin_areas = st_read("./data/geodata/addis_ocha_3.gpkg", quiet = TRUE)
names(admin_areas)[1] = "name"
addis_boundary = data.frame("addis ababa", st_union(admin_areas)) |>
  setNames(names(admin_areas)) |>
  st_as_sf() |>
  st_transform(crs = st_crs(admin_areas))
admin_areas = rbind(admin_areas, addis_boundary)
admin_areas$name = tolower(admin_areas$name)

# Sample points for properties within the boundary of the admin area
samplePoints = function(name) {
  if (!(name %in% admin_areas$name)) {
    warning(paste(name, "is not in the admin_areas"), call. = FALSE)
    return(NULL)
  }

  admin_boundary = admin_areas[admin_areas$name == name, ]
  subset = property_addresses_broad[address_main == name, ]
  subset = subset[!id %in% listings_geocoded$id, ] # exclude those already geocoded with its main/alt address that is not broad

  if (length(subset$id) == 0) {
    return(data.frame())
  }

  sampled = sample_points(admin_boundary, length(subset$id))
  sampled = cbind(subset, sampled)
  return(sampled)
}

property_addresses_sampled = lapply(setNames(nm = broad_addresses), samplePoints) |>
  rbindlist(use.names = TRUE)

# Guarding fail in the subsquent step below
if (nrow(property_addresses_sampled) == 0) {
  property_addresses_sampled = data.frame()
  names(property_addresses_sampled) = c("id", "lng", "lat")
}

# Merge the sampled points with the geocoded addresses
listings_geocoded_sampled = merge(
  listings[, !c("lng", "lat")], property_addresses_sampled, "id"
)

listings_geocoded_sampled[, is_lng_lat_sampled := "yes"]
listings_geocoded[, is_lng_lat_sampled := "no"]

listings_geocoded = rbind(
  listings_geocoded, listings_geocoded_sampled,
  use.names = TRUE, fill = TRUE
)

rm(listings_geocoded_sampled, property_addresses_sampled, property_addresses_broad, come_with_lnglat)


# Compute distance to the cbd ----
cbds = read.csv("./data/geodata/cbds.txt")

calc_dist_to_cbd = function(lng, lat, cbds, ...) {
  points = st_as_sf(data.frame(lng, lat), coords = c("lng", "lat"), crs = 4326)
  cbds = st_as_sf(cbds, coords = c("lng", "lat"), crs = 4326)
  dists = vector("list", nrow(cbds))
  for (i in seq_along(dists)) {
    dists[[i]] = as.vector(st_distance(points, cbds[i,], by_element = FALSE, ...))
  }
  names(dists) = paste0("dist_", tolower(gsub("\\s+", "_", cbds$short_name)))
  dists
}

rows = listings_geocoded[!is.na(lng) & !is.na(lat), which = TRUE]
dists = listings_geocoded[rows, I(calc_dist_to_cbd(lng, lat, cbds))]
listings_geocoded[rows, names(dists) := dists]
rm(rows, dists)

# Filter out those outside addis ----
have_lnglat = listings_geocoded[!is.na(lng) | !is.na(lat), which = TRUE]
listings_geocoded = listings_geocoded[have_lnglat, ][is_within_addis(lng, lat), ]

# Add some cols from property_addresses_expanded
incols = setdiff(names(property_addresses_expanded), "id")
listings_geocoded = property_addresses_expanded[listings_geocoded[, !..incols], on = "id"]

setcolorder(listings_geocoded, names(listings))

# Add subcity info ----
admin_areas = st_read("./data/geodata/addis_ocha_3.gpkg", quiet = TRUE) |> st_transform(4326)
names(admin_areas)[1] = "subcity"

listings_geocoded = listings_geocoded |>
  # Keep within Addis
  subset(!is.na(lng) | !is.na(lat)) |>
  # use is_within_addis2 keep those slightly outside Addis
  subset(is_within_addis2(lng, lat)) |>
  # subset(is_within_addis(lng, lat)) |>
  st_as_sf(coords = c("lng", "lat"), crs = 4326)

listings_geocoded = st_join(listings_geocoded, admin_areas, join = st_intersects)

listings_geocoded[, c("lng", "lat")] = st_coordinates(listings_geocoded)
listings_geocoded = listings_geocoded |> st_drop_geometry() |> as.data.table()

# Add not geocoded ----
not_geocoded = merge(
  property_addresses_expanded[id %notin% listings_geocoded$id, ],
  listings
)

listings_geocoded = rbind(
  listings_geocoded, not_geocoded, use.names = TRUE, fill = TRUE
)


# Write ----
fwrite(
  listings_geocoded,
  "./data/housing/processed/tidy/listings_cleaned_tidy__geocoded.csv"
)

# Need manual work

not_geocoded[
    order(address_main),
    .(id, address_main, address_corrected = "", description, title)
  ] |>
    fwrite(
      "./data/housing/processed/tidy/listings_cleaned_tidy__geocoded__failed.csv"
    )
