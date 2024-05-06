library(data.table)
library(jsonlite)
library(readr, include.only = "parse_number")
source("./script/helpers/helpers.R")
source("./script/helpers/parse_property_attributes.R")

set_col_order = function(data, ...) {
  col_order = c(
    "file", "provider", "id", "property_type", "listing_type",
    "title", "description", "address", "lat", "lng",
    "price", "price_currency", "price_unit", "price_type",
    "size_sqm", "size_unit", "plot_size",
    "num_bedrooms", "num_bathrooms", "num_rooms", "features",
    "date_published", "date_modified", "num_images"
  )
  setcolorder(data, intersect(col_order, names(data)), ...)
}

# Prepend provider to the id
# NB: ids are not unique across providers
prepend_provider = function(id, provider, sep = "/") {
  if (is.null(provider)) {
    return(id)
  }
  return(paste0(provider, sep, id))
}

# `id` is not unique even within the same provider
#  e.g.
## 1. https://www.realethio.com/property/bole-around-edna-mall-office-for-rent-addis-ababa/
## 2. https://www.realethio.com/property/bole-around-edna-mall-office-for-rent-addis-ababa-2/

generate_unique_id = function(ids, suffix = "_uid") {
  if (anyNA(ids)) {
    stop("The ids contain missing values.", call. = FALSE)
  }
  # Duplicate counter for ids
  dup_counter = data.table::rowid(ids)
  # For duplicate ids, a suffix + counter is appended
  # The first occurrence of the id will be kept asis
  dups = which(dup_counter > 1)
  if (length(dups) == 0) {
    return(ids)
  }
  ids[dups] = paste0(ids[dups], suffix, dup_counter[dups] - 1)
  return(ids)
}



# Clean data sets ----
# structure of the data set
## id,url,file
## property_type [house, apartment, etc.]
## type2 [residential, commercial, etc.]
## listing_type [for rent, for sale]
## status [sold, rented, etc.]
## title/name of the property
## description
## date_published
## date_modified/updated
## price [amount, unit[currency, per sqm, monthly]]
## size_sqm[size, unit]
## plot_size
## location/address
## latitude,longitude
## (num)bedrooms
## (num)bathrooms
## features
## furnishing(furnished, semi-furnished, unfurnished)
## furnished[yes,no] ??
## year_built


## afrotie ----
clean_afrotie = function(write = TRUE) {
  message("Cleaning Afrotie data ...")
  paths = list_files(
    "./data/housing/raw/afrotie/", "^house_product-data(_part-\\d+)?.json$"
  )

  clean_data = function(path) {
    json_data = jsonlite::read_json(path)
    json_data_cleaned = vector("list", length(json_data))
    names(json_data_cleaned) = names(json_data)

    for (id in names(json_data_cleaned)) {
      tmp_data = json_data[[id]]
      pic_vars = Filter(\(x) grepl("^(?!KEYFORPROFIL)[A-Z]+PICTURE$", x, perl = TRUE), names(tmp_data))
      pic_vars = tmp_data[pic_vars] != "EMPTY"
      vars = Filter(Negate(\(x) grepl("^([A-Z]+)PICTURE$", x)), names(tmp_data))
      if (is.null(vars)) {
        message(sprintf("The product `%s` has no data.", id))
        json_data_cleaned[[id]] = list(id = id, num_images = sum(pic_vars))
      } else {
        json_data_cleaned[[id]] = c(id = id, tmp_data[vars], num_images = sum(pic_vars))
      }
    }

    data_cleaned = rbindlist(json_data_cleaned, use.names = TRUE, fill = TRUE)
    setnames(data_cleaned, clean_names)
    data_cleaned[, c("live_on_not", "member_since") := NULL]
    data_cleaned[, price_currency := "ETB"]

    old_vars = c(
      "posting_time", "posting_first_category", "posting_city", "location",
      "area", "bedrooms", "bathrooms", "view",
      "saleorrent", "the_name", "phone_number"
    )
    new_vars = c(
      "date_published", "property_type", "region", "address",
      "size_sqm", "num_bedrooms", "num_bathrooms", "num_views",
      "listing_type", "seller_name", "seller_phone"
    )

    setnames(data_cleaned, old_vars, new_vars, skip_absent = TRUE)
    return(data_cleaned)
  }

  data_cleaned = lapply(paths, clean_data) |>
    rbindlist(use.names = TRUE, fill = TRUE, idcol = "file")

  data_cleaned[, price := parse_number(price)]

  # listing types
  data_cleaned[, listing_type := parse_listing_type(listing_type)]

  # timestamp in ms as.POSIXct(hour/1000, tz='GMT')
  # data_cleaned[, date_published := as.POSIXct(as.numeric(hour) / 1000, tz = "GMT")]
  data_cleaned[, date_published := as.Date(date_published, format = "%m/%d/%Y")
  ][, hour := NULL]

  # keep unique values, by all columns
  data_cleaned = unique(data_cleaned, by = setdiff(names(data_cleaned), "file"))
  data_cleaned[!is.na(id), id := generate_unique_id(id)]

  data_cleaned[, id := prepend_provider(id, "afrotie")]
  set_col_order(data_cleaned)

  if (isTRUE(write)) {
    fwrite(
      data_cleaned, ensure_dir("data/housing/processed/afrotie_cleaned.csv")
    )
  }
  return(data_cleaned)
}

## qefira ----
clean_qefira = function(write = TRUE) {
  message("Cleaning Qefira data ...")
  paths = list_files("./data/housing/raw/qefira/", "2023_05_30.json$")

  clean_data = function(path) {
    data = fromJSON(path) |>
      flatten() |>
      as.data.frame()
    names(data) = sub("offers.", "", names(data))
    names(data) = sub("parsed_description.", "", names(data))
    data$`@type` = NULL # contains only "Offer"
    data = setNames(data, clean_names(names(data)))
    old_vars = c(
      "name", "category", "itemcondition", "validfrom", "no_of_bedrooms", "bathrooms",
      "amenities", "pricecurrency", "square_feet", "acre"
    )
    new_vars = c(
      "title", "property_type", "condition", "date_published", "num_bedrooms", "num_bathrooms",
      "features", "price_unit", "size_sqm", "size_sqm" # acre is same as size_sqm depending on the category
    )
    exists = old_vars %in% names(data)
    names(data)[match(old_vars[exists], names(data))] = new_vars[exists]
    return(data)
  }

  data_cleaned = lapply(paths, clean_data) |>
    rbindlist(fill = TRUE, idcol = "file")

  data_cleaned[, c("availability", "pricevaliduntil", "seller_id", "image") := NULL]
  data_cleaned[, condition := basename(condition)
  ][, listing_type := parse_listing_type(property_type)
  ][, property_type := trimws(
    gsub("for\\s*(sale|rent)", "", property_type, ignore.case = T)
  )]

  data_cleaned[, region := sub("^(.+), (.+)$", "\\2", address)]
  data_cleaned[, date_published := as.Date(date_published, "%Y-%m-%d")]


  # keep unique values, by all columns
  data_cleaned = unique(data_cleaned, by = setdiff(names(data_cleaned), "file"))
  data_cleaned[!is.na(id), id := generate_unique_id(id)]

  data_cleaned[, id := prepend_provider(id, "qefira")]
  set_col_order(data_cleaned)

  if (isTRUE(write)) {
    fwrite(data_cleaned, ensure_dir("data/housing/processed/qefira_cleaned.csv"))
  }
  return(data_cleaned)
}


## jiji ----
clean_jiji = function(write = TRUE) {
  message("Cleaning Jiji data ...")
  paths = file.path(
    "./data/housing/processed/jiji/",
    c(
      "houses-apartments-for-rent_2024-03-08.csv",
      "houses-apartments-for-sale_2024-03-08.csv"
    )
  )
  paths = setNames(nm = paths)

  drop_vars = c(
    "category_id", "category_slug", "price_history", "price_obj", "region_name",
    "region_slug", "price_type", "price_title", "price_period", "price_is_closed",
    "date_moderated", "date_edited", "status", "type", "capacity_guests",
    "minimum_rent_time_days", "agent_fee", "agency_fee", "service_charge_fee",
    "caution_fee", "legal_and_agreement_fee", "service_charge_covers",
    "property_use", "estate_name", "parking_spaces", "secure_parking",
    "labels", "guid", "show_apply_discount_button", "show_edit_discount_button",
    "number_of_cars", "listing_by", "discount"
  )

  clean_data = function(path) {
    data = suppressWarnings(fread(path, drop = drop_vars))
    old_vars = c(
      "square_metres_sqm", "address", "parking_spaces", "category_name",
      "region_text", "date_created", "price_value", "bathrooms", "bedrooms", "toilets",
      "count_images", "count_views", "fav_count", "facilities", "price_currency"
    )
    new_vars = c(
      "property_size_sqm", "property_address", "parking_space", "category", "region",
      "date_published", "price", "num_bathrooms", "num_bedrooms", "num_toilets",
      "num_images", "num_views", "num_favs", "features", "price_unit"
    )
    setnames(data, old_vars, new_vars, skip_absent = TRUE)
    setnames(data, \(x) sub("property_(?!type)", "", x, perl = T))
    data[, listing_type := parse_listing_type(category)][, category := NULL][, subtype := NULL]
    return(data)
  }

  data_cleaned = lapply(paths, clean_data) |>
    rbindlist(use.names = TRUE, fill = TRUE, idcol = "file")

  # pets allowed
  data_cleaned[, pets := fcase(
    pets == "Pets Allowed", "Yes",
    pets == "No Pets", "No",
    rep(TRUE, length(pets)), NA_character_
  )]

  data_cleaned[, date_published :=
    as.POSIXct(date_published, format = "%a, %d %b %Y %T", tz = "gmt")
  ][, date_published := as.Date(date_published, format = "%Y-%m-%d")]

  # filter those only in Addis
  data_cleaned = data_cleaned[region %ilike% "Add?is ?Ab(a|e)ba", ]
  data_cleaned[, region := sub(
    "^(Addis Ababa)(?:, )?([a-z -]+)$", "\\2, \\1", region, ignore.case = TRUE
  )][, address := paste0(address, ", ", region)
  ][, region := sub("(.+), (.+)", "\\2", region)] # the city name


  # keep unique values, by all columns
  data_cleaned = unique(data_cleaned, by = setdiff(names(data_cleaned), "file"))
  data_cleaned[!is.na(id), id := generate_unique_id(id)]

  data_cleaned[, id := prepend_provider(id, "jiji")]
  set_col_order(data_cleaned)

  if (isTRUE(write)) {
    fwrite(data_cleaned, "data/housing/processed/jiji_cleaned.csv")
  }
  return(data_cleaned)
}


## zegebeya ----
clean_zegebeya = function(write = TRUE) {
  message("Cleaning Zegebeya data ...")
  paths = list_files("./data/housing/raw/zegebeya/", "(commercial|residential)_\\d{4}-\\d{2}-\\d{2}[.]json$")

  clean_data = function(path) {
    data = fromJSON(path)
    names(data) = clean_names(sub("property_(?!type)", "", names(data), perl = T))
    data$lot_size = NULL
    return(data)
  }

  data_cleaned = lapply(paths, clean_data) |>
    rbindlist(fill = TRUE, idcol = "file")
  # renaming
  old_vars = c(
    "status", "bathrooms", "bedrooms", "total_area", "agent_name",
    "contacts_list", "longitude", "latitude", "car_parking"
  )
  new_vars = c(
    "listing_type", "num_bathrooms", "num_bedrooms", "size_sqm",
    "seller_name", "seller_phone", "lng", "lat", "parking_space"
  )
  setnames(data_cleaned, old_vars, new_vars, skip_absent = TRUE)
  # cleaning
  # styler: off
  data_cleaned[, listing_type := parse_listing_type(listing_type)]
  data_cleaned[, date_published := as.Date(date_published, "%Y-%m-%d")
              ][, size_sqm := sub("_?((Sq ?m)|(Square ?Meters))", "", size_sqm, ignore.case=TRUE)
              ][, size_sqm := parse_number(size_sqm)]
  # parse price
  data_cleaned[, price_currency := fcase(
    grepl("etb|birr|ብር", price, ignore.case=TRUE), "ETB",
    grepl("ዶላር|dollars?|usd|\\$[0-9]{2,}|[0-9]{2,}\\$", price, ignore.case = TRUE), "USD",
    rep(T, length(price)), "ETB"
  )
  ][, price := gsub("ETB|Birr|ብር|ዶላር|dollars?|USD|\\$", "", price)
  ][, price_unit := gsub("[^[:alpha:] ]", "", price)
  ][, price := sub("(\\d+[. ,]\\d+)mil", "\\1e+6", price)
  ][, price_unit := fcase(
    price_unit %ilike% "month", "per month",
    price_unit %ilike% "square meter", "per sqm",
    rep(T, length(price_unit)), price_unit
  )
  ][, price := parse_number(price)
  ][price_unit == "per sqm", `:=`(price = price * size_sqm, price_unit = "total price")
  ][, price_unit := paste(price_currency, price_unit)
  ][, price_currency := NULL] #TODO: keep the currency and unit isolated (across all datasets)

  # parse region
  data_cleaned[, region := zero_len_2na(
    regmatches(address, regexpr("Add?is Ab(a|e)ba", address, ignore.case = TRUE))
  )]
  # styler: on


  # keep unique values, by all columns
  data_cleaned = unique(data_cleaned, by = setdiff(names(data_cleaned), "file"))
  data_cleaned[!is.na(id), id := generate_unique_id(id)]

  data_cleaned[, id := prepend_provider(id, "zegebeya")]
  set_col_order(data_cleaned)

  if (isTRUE(write)) {
    fwrite(
      data_cleaned, ensure_dir("data/housing/processed/zegebeya_cleaned.csv")
    )
  }
  return(data_cleaned)
}


## engocha ----
clean_engocha = function(write = TRUE) {
  message("Cleaning Engocha data ...")
  path = "./data/housing/raw/engocha/engocha_real-estate_2023-10-20.json"

  clean_data = function(path) {
    data = fromJSON(path)
    names(data) = clean_names(names(data))
    return(data)
  }

  data_cleaned = clean_data(path) |> as.data.table()
  data_cleaned[, file := (path)]
  # renaming
  old_vars = c(
    "listingid", "phone", "listingdate", "imagecount", "name", "city", "pricetype"
  )
  new_vars = c(
    "id", "seller_phone", "date_published", "num_images", "seller_name", "region", "price_unit"
  )
  setnames(data_cleaned, old_vars, new_vars, skip_absent = TRUE)

  data_cleaned[, price_unit := paste(currency, price_unit)][, currency := NULL]
  # styler: off
  data_cleaned[, condition := NULL
              ][, randomorder := NULL
              ][, listingimage := NULL
              ][, c("brand", "businessname", "businessid", "featured", "featuredtill", "isfeatured", "timenow") := NULL]
  # styler: on
  data_cleaned[, date_published := as.Date(date_published, "%Y-%m-%d")]

  # clean attributes
  attr_vars = grep("^attr", names(data_cleaned), value = TRUE)
  data_cleaned[, c(attr_vars) := lapply(
    .SD, \(x) sub(r"{^--([^|]+)\|-\*\|\d+\|-\*\|(.+)--$}", "\\2<:>\\1", x)
  ), .SDcols = c(attr_vars)]
  data_cleaned = melt(
    data_cleaned,
    measure.vars = c(attr_vars), variable.name = "attr_name", value.name = "attr_val"
  )
  data_cleaned[, attr_val := tolower(attr_val)]
  data_cleaned[, c("attr_name", "attr_val") := tstrsplit(attr_val, "<:>", fixed = TRUE)]
  data_cleaned[, attr_name := clean_names(attr_name)
  ][, attr_name := sub("floors", "floor", attr_name)]

  data_cleaned = dcast(
    data_cleaned, ... ~ attr_name,
    value.var = "attr_val",
    fun.aggregate = \(x) paste0(x[!is.na(x)], collapse = ", ")
  )
  setnames(data_cleaned, clean_names)
  setnames(
    data_cleaned,
    c("bathrooms", "bedrooms", "area_sqm", "site_location"),
    c("num_bathrooms", "num_bedrooms", "size_sqm", "address")
  )
  data_cleaned[, na := NULL]
  data_cleaned[, size_sqm := parse_number(size_sqm)]
  data_cleaned[num_bedrooms %ilike% "Studio", num_bedrooms := 0]

  setnames(data_cleaned, "propertytype", "property_type")
  data_cleaned[, listing_type := parse_listing_type(property_type)]


  # keep unique values, by all columns
  data_cleaned = unique(data_cleaned, by = setdiff(names(data_cleaned), "file"))
  data_cleaned[!is.na(id), id := generate_unique_id(id)]

  data_cleaned[, id := prepend_provider(id, "engocha")]
  set_col_order(data_cleaned)

  if (isTRUE(write)) {
    fwrite(
      data_cleaned, ensure_dir("./data/housing/processed/engocha_cleaned.csv")
    )
  }
  return(data_cleaned)
}


## realethio ----
clean_realethio = function(write = TRUE) {
  message("Cleaning Realethio data ...")
  path = "./data/housing/raw/realethio/realethio_data.json"

  data_cleaned = fromJSON(path)
  setDT(data_cleaned)
  data_cleaned[, let(price = NULL)] # same as `Price`
  data_cleaned[, let(listing_type = NULL)] # same as `Property Status`
  setnames(data_cleaned, clean_names)
  old = c(
    "property_id", "property_size", "bedrooms", "bathrooms", "rooms", "land_area",
    "property_status", "author", "furnished", "garages"
  )
  new = c(
    "id", "size_sqm", "num_bedrooms", "num_bathrooms", "num_rooms",
    "plot_size", "listing_type", "seller_name", "furnishing", "parking_space"
  )
  setnames(data_cleaned, old, new)

  data_cleaned[, num_images := lengths(images)][, images := NULL]

  data_cleaned[, furnishing := trimws(tolower(furnishing))
  ][, furnishing := fcase(
    furnishing == "yes", "Furnished",
    furnishing == "no", "Unfurnished",
    rep(TRUE, length(furnishing)), furnishing
  )]
  data_cleaned[, property_type := gsub("for\\s*(sale|rent)", "", property_type, ignore.case = TRUE)]
  data_cleaned[, property_type :=
    fcase(
      property_type %ilike% "condo|shared\\s*apartment", "Apartment",
      property_type %ilike% "pent\\s*house|villa|guest\\house|entire\\s*building|new\\s*development", "House",
      rep(TRUE, length(property_type)), property_type
    )]
  # Parse property type from the title
  data_cleaned[
    is.na(property_type) | property_type == "",
    property_type := fcase(
      title %ilike% "apartment" & title %ilike% "house|home", "House, Apartment",
      title %ilike% "apartment" & !title %ilike% "house|home", "Apartment",
      title %ilike% "house|home" & !title %ilike% "apartment", "House",
      rep(TRUE, length(property_type)), NA_character_
    )
  ]
  data_cleaned[, date_published := as.Date(date_published, format = "%Y-%m-%d")]

  # styler: off
  data_cleaned[, num_bedrooms := rowSums(cbind(as.numeric(num_bedrooms), as.numeric(bedroom)), na.rm = T)
  ][, num_bathrooms := rowSums(cbind(as.numeric(num_bathrooms), as.numeric(bathroom)), na.rm = T)
  ][, num_rooms := rowSums(cbind(as.numeric(num_rooms), as.numeric(room)), na.rm = T)
  ]
data_cleaned[, parking_space :=
rowSums(cbind(as.numeric(parking_space), as.numeric(garage), as.numeric(garage_size)), na.rm = T)
]
data_cleaned[, let(bedroom = NULL, bathroom = NULL, room = NULL, garage = NULL, garage_size = NULL)]

  data_cleaned[, size_sqm := parse_number(trimws(gsub("m²", "", size_sqm)))
               ][, plot_size := parse_number(trimws(gsub("m²", "", plot_size)))
                 ][, price_unit := gsub("[0-9,]+", "", price)
                   ][, price := parse_number(price)
                     ][, file := basename(path)]
  # styler: on

  # keep unique values, by all columns
  data_cleaned = unique(data_cleaned, by = setdiff(names(data_cleaned), "file"))
  data_cleaned[!is.na(id), id := generate_unique_id(id)]

  data_cleaned[, id := prepend_provider(id, "realethio")]
  set_col_order(data_cleaned)

  if (isTRUE(write)) {
    fwrite(
      data_cleaned, ensure_dir("./data/housing/processed/realethio_cleaned.csv")
    )
  }
  return(data_cleaned)
}


## livingethio ----
clean_livingethio = function(write = TRUE) {
  message("Cleaning LivingEthio data ...")
  path = "./data/housing/raw/livingethio/livingethio.json"

  data_cleaned = read_json(path)

  extract = function(list) {
    out = vector("list", length(list))
    for (i in seq_along(out)) {
      vals = list[[i]]
      nms = names(vals)
      # status
      if ("status" %in% nms) {
        vals$listing_type = vals$status$name
        vals$status = NULL
      }
      # label
      if ("label" %in% nms) {
        vals$furnishing = vals$label$name
        vals$label = NULL
      }
      # location
      if (is.null(vals$address) && "location" %in% nms) {
        vals$address = vals$location$name
        vals$location = NULL
      }
      # author
      # if ("author" %in% nms) {
      #   vals$seller_name = paste(vals$author$firstname, vals$author$lastname)
      #   vals$seller_phone = paste(vals$author$phone, collapse = ";")
      #   vals$author = NULL
      # }
      # type
      if ("type" %in% nms) {
        vals$property_type = tryCatch(vals$type[[1]]$name, error = \(e) NULL)
        vals$type = NULL
      }
      # num images
      if ("images" %in% nms) {
        vals$num_images = length(lapply(vals$images, `[[`, "url"))
        vals$images = NULL
      }
      # features
      if ("features" %in% nms) {
        vals$features = paste0(vals$features, "; ")
        vals$features = NULL
      }
      out[[i]] = vals
    }
    out = lapply(out, \(x) Filter(\(v) !(is.null(v) | is.list(v)), x))
    return(out)
  }

  data_cleaned = rbindlist(extract(data_cleaned), use.names = T, fill = T)
  old = c(
    "content", "bedrooms", "bathrooms", "longitude", "latitude", "createdAt",
    "updatedAt", "area", "land_area", "contact_name", "contact_phone", "garage"
  )
  new = c(
    "description", "num_bedrooms", "num_bathrooms", "lng", "lat", "date_published",
    "date_modified", "size_sqm", "plot_size", "seller_name", "seller_phone", "parking_space"
  )
  setnames(data_cleaned, old, new)
  data_cleaned[, c(
    "statusId", "status_id", "labelId", "label_id", "locationId", "location_id",
    "userId", "user_id", "note", "isfeatured", "contact", "post_status"
  ) := NULL]

  data_cleaned[, price := parse_number(price)]

  # size_sqm is a bit confused with plot_size
  data_cleaned[is.na(size_sqm) & !is.na(plot_size), size_sqm := plot_size]

  data_cleaned[is.na(price_prefix), price_prefix := ""
  ][is.na(price_suffix), price_suffix := ""
  ][, price_suffix := gsub("[0-9,.]+", "", price_suffix)
  ][
    price_prefix == "USD" & (!is.na(price) & !is.na(price_usd)),
    price_unit := paste("ETB", price_suffix)
  ]
  data_cleaned[is.na(price_unit), price_unit := paste0(price_prefix, price_suffix)
  ][, let(price_usd = NULL, price_prefix = NULL, price_suffix = NULL)
  ][, file := basename(path)]

  data_cleaned[, date_published := as.Date(date_published, format = "%Y-%m-%d")]

  # keep unique values, by all columns
  data_cleaned = unique(data_cleaned, by = setdiff(names(data_cleaned), "file"))
  data_cleaned[!is.na(id), id := generate_unique_id(id)]

  data_cleaned[, id := prepend_provider(id, "livingethio")]
  set_col_order(data_cleaned)

  if (isTRUE(write)) {
    fwrite(
      data_cleaned, ensure_dir("./data/housing/processed/livingethio_cleaned.csv")
    )
  }
  return(data_cleaned)
}


## beten ----
clean_beten = function(write = TRUE) {
  message("Cleaning Beten data ...")
  path = "./data/housing/raw/beten/beten_data.json"
  data = read_json(path)

  rel_time_to_seconds = function(rel_time) {
    stopifnot(length(rel_time) == 1L)
    rel_time = strsplit(rel_time, " ")[[1]][1:2]
    val = as.numeric(substr(rel_time[[1]], 2, nchar(rel_time[[1]])))
    unit = rel_time[[2]]
    unit_en = switch(unit,
      "ደቂቃ" = "mins",
      "ሰዓት" = "hours",
      "ቀን" = "days",
      "ሳምንት" = "weeks",
      "ወር" = "mons",
      "አመት" = "years",
      stop("Unrecognized time unit.")
    )

    val_secs = switch(unit_en,
      mins = val * 60,
      hours = val * 60 * 60,
      days = val * 24 * 60 * 60,
      weeks = val * 7 * 24 * 60 * 60,
      mons = val * 30 * 24 * 60 * 60,
      years = val * 365.25 * 24 * 60 * 60
    )
    return(val_secs)
  }
  calc_date_published = function(rel_time, ref_time) {
    date_published = format.Date(as.POSIXct(ref_time) - rel_time_to_seconds(rel_time), format = "%Y-%m-%d")
    return(date_published)
  }
  # parse date from image url, calculate from the relative time otherwise
  out = vector("list", length(data))
  for (i in seq_along(out)) {
    vals = data[[i]]
    vals$date_published = unique(
      with(vals, regmatches(property_images, regexpr("\\d{4}-\\d{2}-\\d{2}", property_images)))
    )

    if (length(vals$date_published) == 0) {
      vals$date_published = calc_date_published(vals$created_at, vals$retrieved_at)
    }
    vals$created_at = NULL
    vals$retrieved_at = NULL

    vals$num_images = length(vals$property_images)
    vals$property_images = NULL

    vals$address = paste(vals$location_name, vals$village_name)
    vals$region = with(vals, paste(kebele, wereda, subcity, city))
    vals$address = gsub("(?i)^(.+)\\s*\\1{1,}$", "\\1", vals$address, perl = T)
    vals$region = gsub("(?i)^(.+)\\s*\\1{1,}$", "\\1", vals$region, perl = T)
    vals[c("location_name", "village_name", "kebele", "wereda", "subcity", "city")] = NULL

    vals$seller_name = tryCatch(vals$owner_id[[1]][[1]], error = \(e) vals$owner_name)
    vals$seller_phone = tryCatch(vals$owner_id[[1]][[3]], error = \(e) vals$owner_phone_number)
    vals$owner_id = NULL

    vals$property_type = vals$property_category_id$name
    vals$property_category_id = NULL
    vals$listing_type = vals$property_type_id$description
    vals$property_type_id = NULL

    vals = lapply(vals, zero_len_2na)
    out[[i]] = vals
  }

  data_cleaned = rbindlist(out, use.names = T, fill = T)

  data_cleaned[, c(
    "owner_name", "owner_phone_number", "order_number", "old_price", "property_video",
    "latitude", "longitude", "number_of_saloons", "number_of_living_rooms", "floor_plan"
  ) := NULL]

  setnames(data_cleaned, "car_parking", "parking_space")
  data_cleaned[, price := parse_number(price)]

  data_cleaned[, date_published := as.Date(date_published, format = "%Y-%m-%d")]

  feature_vars = c(
    "fire_place", "air_conditioning", "free_wifi", "spa", "swimming_pool",
    "owners_living_there"
  )

  data_cleaned[, features := paste(feature_vars[as.numeric(.SD) > 1L], collapse = "; "),
    .I,
    .SDcols = (feature_vars)
  ][, (feature_vars) := NULL]

  data_cleaned[, url := paste0("https://betenethiopia.com/singleproperties/detail/", id)]

  data_cleaned[, listing_type := tools::toTitleCase(listing_type)]

  old = c(
    "number_of_bed_rooms", "number_of_baths", "total_number_of_rooms", "area", "status"
  )
  new = c("num_bedrooms", "num_bathrooms", "num_rooms", "size_sqm", "is_verified")
  setnames(data_cleaned, old, new)

  data_cleaned[, is_verified := NULL] # all approved

  # keep unique values, by all columns
  data_cleaned = unique(data_cleaned, by = setdiff(names(data_cleaned), "file"))
  data_cleaned[!is.na(id), id := generate_unique_id(id)]

  data_cleaned[, id := prepend_provider(id, "beten")]
  set_col_order(data_cleaned)

  if (isTRUE(write)) {
    fwrite(data_cleaned, "./data/housing/processed/beten_cleaned.csv")
  }
  return(data_cleaned)
}

## loozap ----
clean_loozap = function(write = TRUE) {
  message("Cleaning loozap data ...")
  path = "./data/housing/raw/loozap/loozap_data.json"
  clean_data = function(path) {
    data = jsonlite::fromJSON(path, flatten = TRUE)
    setDT(data)
    setnames(data, clean_names)
    names(data) = sub("additional_details_", "", names(data))
    old = c(
      "reference_number", "location", "surface_sqm", "rooms", "furnished", "building_type", "parking", "features"
    )
    new = c(
      "id", "address", "size_sqm", "num_bedrooms", "furnishing", "property_type", "parking_space", "tags"
    )
    setnames(data, old, new, skip_absent = TRUE)

    return(data)
  }

  data_cleaned = clean_data(path)

  # replace empty strings with NA
  chr_vars = names(sapply(data_cleaned, is.character))
  data_cleaned[, c(chr_vars) := lapply(.SD, \(x) fifelse(x == "", NA, x)), .SDcols = c(chr_vars)]

  if (typeof(data_cleaned$image_urls) != "list") {
    warning("The image_urls column is not a list.", call. = FALSE)
  }
  data_cleaned[, num_images := lengths(image_urls)
  ][, image_urls := NULL]

  data_cleaned[, date_published := as.Date(as.POSIXct(date_published))]

  # remove fixed columns
  for (var in c("reviews", "ratings", "seller_rating")) {
    n = nrow(data_cleaned[!is.na(get(var)), .N, get(var)])
    if (n == 1L) {
      message(paste0("The ", var, " column has only a fixed value."))
      data_cleaned[, (var) := NULL]
    }
  }

  # price unit, currency, and type
  data_cleaned[, price_unit := parse_price_unit(price)
  ][, price_currency := parse_price_currency(price)
  ][, price_type := parse_price_type(price)
  ][, price := parse_number(price)]

  # size
  data_cleaned[, size_unit := parse_size_unit(size_sqm)
  ][, size_sqm := parse_number(size_sqm)]

  # listing type
  data_cleaned[, listing_type := parse_listing_type(listing_type)
  ][, transaction_type := NULL]

  # # deduplicate tags
  # re = c(
  #   "listing(s?360)?",
  #   "comprar\\s*e\\s*vender",
  #   "le\\s*bon\\s*coin",
  #   "let'?s?\\s*go",
  #   "property\\s*rentals?\\s*sales?(addis\\s*ababa)?",
  #   "property\\s*sales?\\s*rentals?(addis\\s*ababa)?",
  #   # "(apartments?|houses?)\\s*for\\s*(sale|rent))",
  #   "buy\\s*these\\s*(apartments?|houses?)",
  #   "location\\s*\\d*\\s*times?\\s*matters\\s*the\\s*most",
  #   "best\\s*investment\\s*opportunities",
  #   "other\\s*locations?"
  # )
  # clean_tags = function(text, split = "; ", fixed = TRUE) {
  #   text = gsub(paste0(re, collapse = "|"), " ", text, ignore.case = TRUE)
  #   tags = strsplit(text, split = split, fixed = fixed)
  #   tags = lapply(tags, \(x) {
  #     x = tolower(trimws(x))
  #     x = x[!grepl("olx", x)]
  #     x[!duplicated(x)]
  #   })
  #   clean_text = vapply(tags, \(x) paste0(x, collapse = split), character(1))
  #   return(clean_text)
  # }
  # # the first element of the tags is usually the title
  # # data_cleaned[, tags := unlist(Map(
  # #   \(p, t) gsub(paste0("\\Q", p, "\\E"), "", t, ignore.case = TRUE),
  # #   str_squish(title), str_squish(tags)
  # # ))
  # # ]
  # data_cleaned[, tags := clean_tags(tags)]
  #
  data_cleaned[, file := basename(path)]

  # keep unique values, by all columns
  data_cleaned = unique(data_cleaned, by = setdiff(names(data_cleaned), "file"))
  data_cleaned[!is.na(id), id := generate_unique_id(id)]

  data_cleaned[, id := prepend_provider(id, "loozap")]
  set_col_order(data_cleaned)

  if (isTRUE(write)) {
    fwrite(data_cleaned, "./data/housing/processed/loozap_cleaned.csv")
  }
  return(data_cleaned)
}


## ethiopian properties ----
clean_ethiopianproperties = function(write = TRUE) {
  message("Cleaning EthiopianProperties data ...")
  path = "./data/housing/raw/ethiopianproperties/any_any_2024_02_04.json"
  data = fromJSON(path)

  setDT(data)
  setnames(data, tolower)
  sqm_vars = grep("(?i)sq", names(data), value = TRUE)
  data[, temp := fcoalesce(.SD[, sqm_vars, with = FALSE])]
  setnames(data, "temp", "size_sqm")
  data = data[, !(sqm_vars), with = FALSE] # can't use `:=` coz there are duplicates
  setnames(
    data,
    c("bathrooms", "bedrooms", "garages"),
    c("num_bathrooms", "num_bedrooms", "parking_space")
  )
  data[, num_bathrooms := fcoalesce(num_bathrooms, bathroom)
  ][, bathroom := NULL
  ][, num_bedrooms := fcoalesce(num_bedrooms, bedroom)
  ][, bedroom := NULL
  ][, parking_space := fcoalesce(parking_space, garage)
  ][, garage := NULL
  ]

  old = c(
    "property_id", "property_status", "property_url", "agent-name", "agent-address", "latitude", "longitude"
  )
  new = c(
    "id", "listing_type", "url", "seller_name", "seller_address", "lat", "lng"
  )
  setnames(data, old, new)

  data[, date_published := as.Date(date_published, format = "%Y-%m-%d")]
  data[, num_images := lengths(images)][, images := NULL]
  data[, additional_details := NULL]

  # price type, currency, and unit
  data[, price_unit := parse_price_unit(price)
  ][, price_currency := parse_price_currency(price)
  ][, price_type := parse_price_type(price)
  ][, price := parse_number(price)]

  data[, listing_type := parse_listing_type(listing_type)]
  data[, file := basename(path)]

  # What?
  data = data[!description %ilike% r"(not\s*a\s*real\s*listing)", ]

  # keep unique values, by all columns
  data = unique(data, by = setdiff(names(data), "file"))
  data[, id := generate_unique_id(id)]

  data[, id := prepend_provider(id, "ethiopianproperties")]
  set_col_order(data)

  if (isTRUE(write)) {
    fwrite(data, "./data/housing/processed/ethiopianproperties_cleaned.csv")
  }
  return(data)
}

## ethiopiapropertycentre ----
clean_ethiopiapropertycentre = function(write = TRUE) {
  message("Cleaning EthiopiaPropertyCentre data ...")
  paths = list_files(
    "./data/housing/raw/ethiopiapropertycentre/",
    "product_data_from_file.*\\.json$"
  )
  data_cleaned = lapply(paths, fromJSON) |>
    rbindlist(use.names = T, fill = T, idcol = "file")
  setnames(data_cleaned, clean_names)

  data_cleaned[, file_path := NULL]
  data_cleaned[, title := paste(
    page_title, "---",
    Map(\(x, y) gsub(x, "", y, fixed = TRUE), page_title, content_title)
  )
  ][, content_title := NULL][, page_title := NULL]
  old = c(
    "bedrooms", "bathrooms", "toilets", "total_area", "property_description",
    "property_ref", "last_updated", "market_status", "type", "product_url",
    "covered_area", "price_naira_equiv"
  )

  new = c(
    "num_bedrooms", "num_bathrooms", "num_toilets", "plot_size", "description",
    "id", "date_published", "status", "property_type", "url",
    "size_sqm", "price_etb_equiv"
  )
  setnames(data_cleaned, old, new, skip_absent = TRUE)

  # Date of publication
  data_cleaned[, date_published := fcoalesce(date_published, added_on)
  ][, date_published := as.Date(date_published, format = "%d %b %Y")
  ][, added_on := NULL]

  # Parse listing type
  data_cleaned[, listing_type := parse_listing_type(url)] # title is equally ok

  # Price currency
  data_cleaned[, price_currency := parse_price_currency(price_currency)
  ][, price := parse_number(price)]

  # Size and size unit
  data_cleaned[, size_unit := parse_size_unit(size_sqm)
  ][, size_sqm := parse_number(size_sqm)
  ][, plot_size := parse_number(plot_size)]
  # Whichever is smaller is the floorspace
  data_cleaned[, size_sqm := fifelse(size_sqm > plot_size, plot_size, size_sqm)
  ][, size_sqm := fcoalesce(size_sqm, plot_size)]

  # Parking space
  # data_cleaned[, parking_space := fcoalesce(parking_space, parking_spaces)]
  data_cleaned[, parking_space := parking_spaces][, parking_spaces := NULL]

  # Come in plural/singular
  # data_cleaned[, num_bedrooms := fcoalesce(num_bedrooms, bedroom)][, bedroom := NULL]
  # data_cleaned[, num_bathrooms := fcoalesce(num_bathrooms, bathroom)][, bathroom := NULL]
  # data_cleaned[, num_toilets := fcoalesce(num_toilets, toilet)][, toilet := NULL]

  # Images
  data_cleaned[, num_images := lengths(image_urls)][, image_urls := NULL]

  data_cleaned[, service_charge := NULL][, sharing := NULL]

  # Keep unique values, by all columns
  data_cleaned = unique(data_cleaned, by = setdiff(names(data_cleaned), "file"))
  data_cleaned[, id := generate_unique_id(id)]
  data_cleaned[, id := prepend_provider(id, "ethiopiapropertycentre")]
  set_col_order(data_cleaned)

  if (isTRUE(write)) {
    fwrite(data_cleaned,
      "./data/housing/processed/ethiopiapropertycentre_cleaned.csv")
  }

  return(data_cleaned)
}



# Run cleaners ----
# List of providers to be cleaned
providers = c(
  "afrotie", "qefira", "jiji", "engocha", "zegebeya", "realethio",
  "livingethio", "beten", "loozap", "ethiopianproperties",
  "ethiopiapropertycentre"
) |> setNames(nm = _)


# A helper function to clean dataset by provider
clean_provider = function(provider, ...) {
  get(paste0("clean_", provider), mode = "function")(...)
}

# A wrapper to handle errors while cleaning for each provider
handle_error_with_warning = function(fun, provider, ...) {
  tryCatch(fun(provider, ...),
    error = function(e) {
      message("ATTENTION: Cleaning for ", provider, " failed. Try again.")
      return(data.table())
    })
}

# Clean datasets
cleaned_datasets = vector("list", length(providers))
names(cleaned_datasets) = names(providers)
for (provider in providers) {
  cleaned_datasets[[provider]] = handle_error_with_warning(clean_provider, provider)
}


# Stack all
cleaned_datasets = cleaned_datasets |>
  rbindlist(fill = TRUE, idcol = "provider")

set_col_order(cleaned_datasets)

fwrite(
  cleaned_datasets,
  "data/housing/processed/listings_cleaned.csv"
)
