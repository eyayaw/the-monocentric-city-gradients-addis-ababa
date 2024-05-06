library(data.table)
source("./script/helpers/helpers.R")
source("./script/helpers/parse_property_attributes.R")
source("./script/constants.R")

# sets column order inplace
set_col_order = function(dt) {
  if (!data.table::is.data.table(dt)) {
    stop("`dt` must be a data.table.", call. = FALSE)
  }
  patterns = c(
    "^(provider|id)$",
    "(listing|property).*type",
    "^price.*$",
    "^size.*$", "plot.*size",
    "^address.*$", "^lat|lo?ng$", "region",
    "date_.*", "description|title", "time|year|quarter|month",
    "(.*rooms)|(features.*)",
    "(.*condition)|(furnishing)",
    "num_images"
  )

  main_vars = sapply(patterns, \(p) grep(p, names(dt), value = TRUE, ignore.case = TRUE))

  data.table::setcolorder(dt, unlist(main_vars))
}


# Define thresholds
property_types = c("house", "apartment")
listing_types = c("for sale", "for rent")

exchangeRate = fread(
  "./data/housing/interbank_exchange_rates.csv",
  select = c("Weighted_Average_Rate", "time")
)
setnames(exchangeRate, c("Weighted_Average_Rate", "time"), c("exchange_rate", "date"))
exchangeRate[, date := as.Date(date, "%m/%d/%Y")
              ][, exchange_rate := readr::parse_number(exchange_rate)]

rdate = data.table(date=seq.Date(as.Date('2015-01-01'), as.Date('2024-04-15'), by = "day"))
exchangeRate[rdate, on = "date"]

# fill for missing days locf/nocb
exchangeRate[, exchange_rate := nafill(nafill(exchange_rate, "locf"), "nocb")]

mean_exchange_rate = exchangeRate[year(date)>=2019, mean(exchange_rate, na.rm = T)]

convert_to_etb = function(amount, currency) {
  if (length(amount) != 1 || length(currency) != 1) {
    stop("`amount` and `currency` must be scalars.", call. = FALSE)
  }
  currency = match.arg(currency, valid_currencies)
  # Average exchanges rates over the last few years
  exchange_rates = c(etb = 1, usd = 50, euro = 55, gbp = 60)
  return(amount * exchange_rates[currency])
}

convert_to_monthly_rate = function(amount, period) {
  conversion_factors = c(day = 30, week = 4, month = 1, year = 1 / 12)
  matched_period = match(period, valid_periods)
  valid_amount = which(!is.na(matched_period))
  amount[valid_amount] = amount[valid_amount] * conversion_factors[matched_period[valid_amount]]
  return(amount)
}

# A helper to make a default value coalesce-able
# list("no", "yes", "no") -> "yes" if "no" is treated as missing
fcoalesce_default = function(..., default = "no") {
  if (length(default) != 1L) {
    stop("Default must be a scalar.", call. = FALSE)
  }
  # Accept a single ... list/data.frame as an input
  if (...length() == 1L && (is.list(...) || is.data.frame(...))) {
    vals = c(...)
  } else {
    # stop("Input must be a list if len 1.", call. = FALSE)
    vals = list(...)
  }
  vals = lapply(
    vals,\(x) fifelse(tolower(x) == tolower(default) | x == "", NA_character_, x)
  )

  fcoalesce(fcoalesce(vals), default)
}

# Import scraped data ---- ads from all providers
# not useful
drop = c(
  "file", "p", "seller_type", "seller_phone", "seller_name", "url", "status",
  "num_favs", "num_views", "year_built", "date_modified", "num_rooms",
  "basement", "tags", "price_etb_equiv"
)

property_data = fread(
  "./data/housing/processed/listings_cleaned.csv",
  na.strings = "", drop = drop
)


# Import data ---- gemini-pro `extracted` attributes
flist = c(
  "listings_cleaned__extracted_property_attributes__gemini__tidy.csv",
  "loozap_cleaned__extracted_property_attributes__gemini__tidy.csv",
  "ethiopianproperties_cleaned__extracted_property_attributes__gemini__tidy.csv",
  "ethiopiapropertycentre_cleaned__extracted_property_attributes__gemini__tidy.csv"
)
extracted_attrs = lapply(flist, \(f) fread(
  file.path("./data/housing/processed/structured/tidy/", f), na.strings = ""
)) |>
  rbindlist(use.names = TRUE, fill = TRUE)
extracted_attrs[, provider := sub("(?i)^([a-z]+)/(.+)$", "\\1", id, perl = TRUE)]

# Set keys
keys = c("provider", "id")
setkeyv(property_data, keys)
setcolorder(property_data, keys)
setkeyv(extracted_attrs, keys)
setcolorder(extracted_attrs, keys)

# Missing (NA) stats ---
setNames(nm = setdiff(names(property_data), keys)) |>
  lapply(\(var) property_data[, na_stats(get(var)), provider]) -> missing_stats


# Pre cleaning ----
setnames(
  extracted_attrs,
  c(
    "type", "listing", "price.amount", "price.type", "price.unit", "price.currency",
    "size.floor_area", "size.plot_area", "size.unit", "address.original", "address.trans",
    "construction.condition", "features.counts.bedrooms", "features.counts.bathrooms",
    "additional.furnishing", "location.floor", "features.counts.floors"
  ),
  c(
    "property_type", "listing_type", "price", "price_type", "price_unit",
    "price_currency", "size_sqm", "plot_size", "size_unit", "address_extracted", "address_extracted_transliterated",
    "condition", "num_bedrooms", "num_bathrooms", "furnishing", "floor", "num_floors"
  ),
  skip_absent = TRUE
)

# Type matching
num_vars = c("price", "size_sqm", "plot_size", "num_bedrooms", "num_bathrooms")
property_data[, (num_vars) := lapply(.SD, parse_number2), .SDcols = num_vars]
extracted_attrs[, (num_vars) := lapply(.SD, parse_number2), .SDcols = num_vars]
property_data[, price := as.double(price)]
extracted_attrs[, price := as.double(price)]

# price, floor area size
property_data[, price := parse_number2(price) # price is already numeric
                  ][, size_sqm := parse_number2(size_sqm)]
# size_sqm in Engocha,livingethio is engulfed with NAs
# property_data[, na_stats(size_sqm), provider]

extracted_attrs[, price := parse_number2(price)
                ][, size_sqm := parse_number2(size_sqm)]

# price unit, type and currency
# price_unit in the original data contains price type and currency info
# and the latter should be defined for the replacement `mapping` below
property_data[, price_type := fcoalesce_default(price_type, parse_price_type(price_unit), default = "other")
][, price_currency := fcoalesce_default(price_currency, parse_price_currency(price_unit), default = "other")
][, price_unit := parse_price_unit(price_unit)]

# price unit, type and currency
extracted_attrs[, price_unit := parse_price_unit(price_unit)
                ][, price_type := parse_price_type(price_type)
                  ][, price_currency := parse_price_currency(price_currency)]


# NB: In the extracted data, if the unit is per sqm, then price is per sqm.
# So multiply the price by property size, to get the total price.
# TODO: confirm this with a sample of observations

# Fill missing property sizes with a reasonable value
# TODO: use the average size of the property type by type/listing/provider?


# Handle unit/currency of price ----
property_data = merge(
  property_data,
 exchangeRate, by.x = "date_published", by.y = "date", all.x = TRUE
)

extracted_attrs[, oid := gsub("_(multi|expand)_suffix_\\d+$", "", id)]

extracted_attrs = merge(
  extracted_attrs,
  unique(property_data[, .(oid=id, date_published, exchange_rate)], by = "oid"),
  "oid", all.x = TRUE
)
extracted_attrs[, `:=`(oid = NULL, date_published = NULL)]

convert_units = function(data, size_sqm_fill_value = SIZE_SQM_FILL_VALUE, strict = FALSE) {
  data = copy(data)
  # Convert to monthly
  data[price_unit != "per month", `:=`(
    price = convert_to_monthly_rate(price, price_unit),
    price_unit = fcase(
      price_unit %in% valid_periods, "per month",
      rep(TRUE, length(price_unit)), price_unit
    )
  )]

  cond1 = data[, price_unit == "per sqm"]
  data[
    cond1 & price < max_per_sqm_price_etb, # higher price doesn't make sense for per sqm
    `:=`(
      price = price * fcoalesce(size_sqm, size_sqm_fill_value),
      price_unit = "total price"
    )
  ]
  if (strict) {
    warning(sprintf("The price unit changed to `total price` from `per sqm` since the price is greater than %.2f.", max_per_sqm_price_etb), call. = FALSE)
    data[cond1 & price >= max_per_sqm_price_etb, price_unit := "total price"]
  }

  # Convert the price in foreign currency into the local currency (ETB)
  currencies = c("usd", "euro", "gbp")
  for (cur in currencies) {
    cond_cur = data[, price_currency == (cur)]
    data[
      cond_cur & price < max_price_USD,
      `:=`(
        price = price/exchange_rate, # = Vectorize(convert_to_etb)(price, price_currency),
        price_currency = "etb"
      )
    ]
    if (strict) {
      warning(sprintf("The price currency changed to `etb` from `%s`, since the price is greater than %.2f.", cur, max_price_USD), call. = FALSE)
      data[cond_cur & price >= max_price_USD, price_currency := "etb"]
    }
  }

  return(data)
}

property_data = convert_units(property_data, strict = TRUE)
extracted_attrs = convert_units(extracted_attrs, strict = TRUE)

# combine vars
feature.vars = c("features.specifics", "features.amenities", "features.utilities")
extracted_attrs[, features :=
  apply(.SD[, feature.vars, with = FALSE], 1, \(x) paste0(na.omit(x), collapse = "|")
        )][, (feature.vars) := NULL
           ][, features.description := NULL]

# floors or num of floors
try({
  extracted_attrs[, floor := fcoalesce(floor, as.character(num_floors))
                  ][, num_floors := NULL]
}, silent = TRUE)



## Imputation ----
# Define mapping: missing in `main` will be replaced with `extracted` if applicable
mapping = fread(
"main,extracted
listing_type,listing_type
property_type,property_type
price,price
price_type,price_type
price_unit,price_unit
price_currency,price_currency
size_sqm,size_sqm
num_bedrooms,num_bedrooms
num_bathrooms,num_bathrooms
features,features
condition,condition
furnishing,furnishing
"
)

# Replace missing values for a variable in df_main (given in vars_map$main)
# by values in df_extracted (given in vars_map$extracted), if applicable.
# na_strings: In addition to an explicit NA, what else to consider as NA?
# styler: off
replace_missings = function(df_main, df_extracted, vars_map = mapping, na_strings = NULL) {
    if (!is.list(vars_map) || !all(c("main", "extracted") %in% names(vars_map))) {
      stop("vars_map must be a list with 'main' and 'extracted' elements", call. = FALSE)
    }

    # Check if 'id' column exists in both data frames
    if ("id" %notin% names(df_main) || "id" %notin% names(df_extracted)) {
      stop("Both dataframes should include 'id' column.", call. = FALSE)
    }

    # `fread` may have not read "" as NA
    if ("" %notin% na_strings) {
      na_strings = c(na_strings, "")
    }

    df_main = copy(df_main)
    df_extracted = copy(df_extracted)

    message("Please wait ... This process may take some time as we replace missing values.")
    for (i in seq_along(vars_map$main)) {
      main_var = vars_map$main[[i]]
      extracted_var = vars_map$extracted[[i]]

      if (main_var %notin% names(df_main) || extracted_var %notin% names(df_extracted)) {
        warning("Either", main_var, "or", extracted_var, "not found in the data frames. Skipping...")
        next
      }
      main_var_v = get(main_var, df_main)
      # Ids of elements that need replacing, if applicable
      missings = if (is.character(main_var_v)) {
        which(is.na(main_var_v) | tolower(main_var_v) %in% tolower(na_strings))
      } else {
        which(is.na(main_var_v))
      }

      if (length(missings) == 0L) {
        message("No missing found for var `", main_var, "`. Skipped.")
        next
      }
      # Get the replacement values
      # replacement = sapply(
      #   df_main[missings, id], \(.id) zero_len_2na(df_extracted[id == .id, get(extracted_var)])
      # )
      # data.table's join does it more efficiently
      replacement = df_extracted[df_main[missings, .(id)], on = .(id), get(extracted_var), nomatch = NA]
      if (all(is.na(replacement))) {
        message(
          sprintf("No replacement found for missings in `%s` from `%s`.", main_var, extracted_var)
        )
        next
      }
      if (is.numeric(main_var_v)) {
        replacement = withCallingHandlers(
          parse_number2(replacement),
          message = function(m) {
            m$message = paste0("In `", main_var, "`: ", tolower(m$message))
            message(m)
            invokeRestart("muffleMessage") # Suppress the original message
          }
        )
      }
      df_main[missings, (main_var) := ..replacement]
    }
    df_main
  }
# styler: on

# Define NA strings based on what the parsers flag as uncertain
na_strings = c("", "no", "other", "unknown", "for sale/rent", "unfurnished", "building")

# Make more NA (explicit value that do not make sense)
# Fret not, the original value will be put back after imputation if no replacement is found.
misclassified_or_outliers = function(data, flag_NA_size_sqm = TRUE) {
  data = copy(data)
  data[, price_currency := tolower(price_currency)]

  cond1 = data[, size_sqm < min_size_sqm | (price < min_price_etb & price_currency != 'usd')]
  if (flag_NA_size_sqm) {
    # Their size maybe NA, but price is too high, we may find correct attrs in the extracted data.
    # E.g.: https://et.loozap.com/ads/120.6-sqm-apartment-for-sale-compaund-bole-zz/26810049.html
    # price is originally given as "Br551,879,389" and size_sqm is NA,
    # but in the ad text we can see that price=$124,563.40 and size_sqm=120.6.
    # So, allowing high price but missing size_sqm to be included in the condition allows
    # price to be corrected to 124,563.40 * usd_exchange_rate which is a reasonable value.
    cond2 = data[, price_currency != 'usd' & price >= max_sale_etb & (size_sqm < max_size_sqm | is.na(size_sqm))]
  } else {
    cond2 = data[, price_currency != 'usd' & price >= max_sale_etb & size_sqm < max_size_sqm]
  }

  cond3 = data[, size_sqm < min_size_sqm2 & property_type == "house"]
  cond4 = data[, price_unit == "per month" & listing_type == "for sale"]

  cond5 = data[, price_currency == "etb" & listing_type == "for rent" & price < max_rent_usd] # must be in USD
  cond6 = data[, price_currency == "etb" & listing_type == "for sale" & price < min_sale_etb]

  # Define misclassified data conditions
  # A property can be flagged as an outlier for its excessively high price due to its type or listing category. However, we can identify the correct type/listing attributes that make the price reasonable. For example, a high-priced apartment for sale may actually be an apartment building. See https://betenethiopia.com/singleproperties/detail/1254

  misclassified_sale = data[, price_currency != 'usd' & listing_type == "for sale" & price < min_sale_etb]
  misclassified_rent = data[, price_currency != 'usd' & listing_type == "for rent" & price >= max_rent_etb]
  misclassified_land = data[, price_currency != 'usd' & property_type == "land" & listing_type == "for rent"]
  misclassified_building = data[, price_currency != 'usd' & property_type == "building" & price < min_sale_etb_building & listing_type == "for sale"]

  combined_conds = (cond1 | cond2 | cond3 | cond4 | cond5 | cond6 |
                    misclassified_rent | misclassified_land | misclassified_building)
  return(combined_conds)
}

# Try to replace missing values (defined by na_strings) with non-missing values of
# extracted attributes
# The parsers flag uncertain values (i.e., for sale/rent, other, etc.,) available for imputation
property_data[, property_type := parse_property_type(property_type)
              ][, listing_type := parse_listing_type(listing_type)]

misclassified_or_outliers_idx = which(misclassified_or_outliers(property_data))
property_data[misclassified_or_outliers_idx, misclassified_or_outliers_flag := "yes"
              ][-misclassified_or_outliers_idx, misclassified_or_outliers_flag := "no"]
untouched = copy(property_data)[, c("id", mapping$main, "misclassified_or_outliers_flag"), with = FALSE]

property_data[misclassified_or_outliers_idx, (mapping$main) := NA]

# Impute missing values
imputed_data = replace_missings(
  property_data[id %in% extracted_attrs$id, c("id", mapping$main), with = FALSE],
  extracted_attrs[, c("id", mapping$extracted), with = FALSE],
  na_strings = na_strings
)

idx = which(property_data$id %in% imputed_data$id)
property_data_merged = merge(
  property_data[idx, !(mapping$main), with = FALSE], imputed_data, "id"
)
property_data = rbind(
  property_data[-idx, ], property_data_merged
)

# Put back their original values for rows that had their value artificially set as NA
#TODO: use joins instead
for (var in mapping$main) {
  property_data[misclassified_or_outliers_flag == "yes" & is.na(get(var)),
                (var) :=
    untouched[misclassified_or_outliers_flag == "yes", c("id", var), with=FALSE
              ][.SD[, .(id)], on = "id", get(var), nomatch=NA]
  ]
}

rm(untouched, idx, property_data_merged, misclassified_or_outliers_idx)

# Add the address variables.
# Not only for ads that have missing addresses, but the extracted address variables
# should also be kept in full since they are useful for geocoding.
property_data = merge(
  property_data,
  extracted_attrs[, .(id, address_extracted, address_extracted_transliterated)],
  "id", all.x = TRUE
)


# The Gemini Pro Extractor is designed to return multiple records if the ad text
# has several values for a given attribute. Suppose there is an ad that says,
# "A nice property for sale in Bole, located in an apartment building.
# The price for the 2-bedroom unit is x, and the price for the 3-bedroom unit is y."
# In this case, the extractor would return:

# -  {"price": x, "bedrooms": 2}
# -  {"price": y, "bedrooms": 3}
#
# However, if only one price (such as per sqm) was given, we enter the case of expansion. For example:
#
# -  {"price": x, "bedrooms": [2,3]}
#
# In this case, the records would be expanded into:
#
# -  {"price": x, "bedrooms": 2}
# -  {"price": x, "bedrooms": 3}
#
# In such cases, a new ID will be created with the format trueID_(multi|e_suffix_dup_counter), where dup_counter is a counter for the number of duplicates. The original ID will be given to the first record, and the new ID will be given to the rest of the records.
# The following function fills the missing variables and values for the duplicated records with their corresponding records from the original data. The first records directly matched in the imputation above.

complete_cases_for_special_ids = function(extracted_data, original_data) {
  # Get the multi/expand IDs
  # These suffixes are defined in ./script/tidy__extracted_property_attributes__gemini.py
  pattern = "_(multi|expand)_suffix_\\d+$"

  multi_expand_ids = setdiff(extracted_data$id, original_data$id)
  multi_expand_ids = multi_expand_ids[multi_expand_ids %ilike% pattern]
  original_ids = gsub(pattern, "", multi_expand_ids)

  if (length(multi_expand_ids) == 0) {
    message("No multi-expand IDs found. Returning the extracted data as is.")
    return(extracted_data)
  }

  # Subset for ids we care about
  mapping = data.table(multi_expand_id = multi_expand_ids, original_id = original_ids)
  complete_data = extracted_data[mapping, on = .(id == multi_expand_id), nomatch = NULL]
  original_data = original_data[mapping, on = .(id == original_id), nomatch = NULL]


  # Get common to both and original only variables
  common_vars = intersect(names(complete_data), names(original_data))
  original_only_vars = setdiff(names(original_data), names(complete_data))
  for (var in common_vars) {
    # Get the original data values for NA values in extracted data
    ov = original_data[complete_data[, .(id)], on = .(multi_expand_id == id), get(var), nomatch = NA]
    # Replace NA values in common_vars with corresponding original_row values
    # fcoalesce requires the same type
    complete_data[, (var) := fcoalesce(get(var), ..ov)]
  }
  # Append vars that are only in the original data to extracted data
  complete_data[, (original_only_vars) :=
    original_data[complete_data[, .(id)], on = .(multi_expand_id == id), mget(original_only_vars), nomatch = NA]]

  # There is no `address_extracted` in the original data.
  # If it is not missing, we use it since the multiple cases may have different addresses.
  complete_data[!is.na(address_extracted),
  address := fifelse(address != address_extracted, address_extracted, address)
  ]

  return(complete_data[, -"multi_expand_id"])
}

completed_data = complete_cases_for_special_ids(extracted_attrs, property_data)

# Append to the original data
property_data = rbind(
  property_data,
  completed_data[, names(property_data), with = FALSE],
  use.names = TRUE
)

set_col_order(property_data)


# Post cleaning ----

#### property and listing type --------
# Afrotie's property type is generic, so we use the extracted property type
tmp = property_data[provider == "afrotie", ]
tmp2 = extracted_attrs[provider == "afrotie", .(id, property_type)]
tmp = merge(tmp, tmp2, "id", all.x = TRUE)
tmp[, property_type := fcoalesce(property_type.x, property_type.y)
    ][, property_type := fcoalesce_default(property_type, property_type.y, default = "house")]
tmp[, property_type.x := NULL][, property_type.y := NULL]
property_data = rbind(property_data[provider != "afrotie"], tmp, use.names = TRUE)
rm(tmp)

property_data[, property_type := parse_property_type(property_type)]
property_data[, listing_type := parse_listing_type(listing_type)]


#### price type, currency, unit
# If price is not given, ignored
property_data[is.na(price), let(price_currency = NA, price_unit = NA, price_type = NA)]
extracted_attrs[is.na(price), let(price_currency = NA, price_unit = NA, price_type = NA)]

# If misclassified or outliers, replace the original data with the extracted data
misclassified_or_outliers_idx = which(misclassified_or_outliers(property_data))
tmp = merge(
  property_data[misclassified_or_outliers_idx, ], extracted_attrs, "id", all.x = TRUE
)
vars = grep("\\.(x|y)$", names(tmp), value = TRUE)
for (var in gsub("(.+)\\.(x|y)$", "\\1", vars)) {
  tmp[, (var) := fcoalesce(get(paste0(var, ".y")), get(paste0(var, ".x")))]
}
tmp[, (vars) := NULL]
tmp = tmp[, names(property_data), with = FALSE]
property_data = rbind(
  property_data[-misclassified_or_outliers_idx, ], tmp,use.names = TRUE
)
rm(tmp)

property_data = convert_units(property_data, strict = TRUE)
property_data[, property_type := parse_property_type(property_type)]
property_data[, listing_type := parse_listing_type(listing_type)]


#### address ----
# NB: addresses are cleaned properly for geocoding in a separate script
property_data[address == "", address := NA
                  ][is.na(address), address := address_extracted]

#### region ----
property_data[, region := parse_region(region)
                  ][provider %in% c("realethio", "livingethio"), region := "addis ababa"]

#### condition ----
property_data[, condition := parse_condition(condition)]

### features ----

#### parking ----
property_data[,
  parking_space := str_squish(tolower(parking_space))
][, parking := fcase(
  as.numeric(parking_space) >= 1 | parking_space == "yes", "yes",
  as.numeric(parking_space) == 0 | parking_space == "no", "no",
  rep(TRUE, length(parking_space)),
  fcoalesce_default(
    lapply(list(features, description, title), \(x) parse_features(x, "parking"))
  )
)][, parking_space := NULL]

#### garden ----
property_data[, garden := str_squish(tolower(garden))
][, garden := fcase(
  as.numeric(garden) == 1 | garden == "yes", "yes",
  as.numeric(garden) == 0 | garden == "no", "no",
  rep(TRUE, length(garden)),
  fcoalesce_default(
    lapply(list(features, description, title), \(x) parse_features(x, "garden"))
  )
)]

#### pets ----
property_data[, pets := str_squish(tolower(pets))
][, pets := fcase(
  as.numeric(pets) == 1 | pets == "yes", "yes",
  as.numeric(pets) == 0 | pets == "no", "no",
  rep(TRUE, length(pets)), "no"
)]


#### other features ----
feature_vars = setdiff(names(parse_features("")), names(property_data))
temp = property_data[, parse_features(features, feature_vars)]
property_data[, (feature_vars) := (temp)]
# if the feature does not exit for the property in 'features',
# then extract from other variables
for (var in feature_vars) {
  property_data[
    get(var) != "yes",  fcoalesce_default(
      lapply(list(description, title), \(x) parse_features(x, var))
    )
  ]}
rm(temp)

#### furnished ----
property_data[, furnishing := fcase(
  tolower(furnishing) == "yes", "furnished",
  tolower(furnishing) == "no", "unfurnished",
  furnishing %ilike% "^semi", "semi-furnished",
  rep(TRUE, length(furnishing)),
  # extract from other variables
  fcoalesce_default(
    lapply(list(features, description, title), parse_furnishing_level)
  )
)]

# #### basement ----
# property_data[
#   provider == "engocha",
#   basement := fifelse(basement %ilike% r"(\w+\s*basements?)", "yes", NA_character_)
# ]


# Missing values ----
# ads with missing price and date are not useful
property_data = property_data[!is.na(price), ][!is.na(date_published), ]

## Impute size sqm
# floor area (size_sqm) vs plot size
property_data[is.na(size_sqm), size_sqm := fcase(
  property_type == "land", plot_size,
  property_type %in% c("apartment", "house") & plot_size <= 250, plot_size,
  rep(TRUE, .N), NA_real_
)]

# use median because larger sizes are not removed
property_data[, size_sqm_is_imputed := fifelse(is.na(size_sqm), "yes", "no")]
property_data[,
  size_sqm := fill_na_const(size_sqm, median, na.rm = TRUE),
  .(listing_type, property_type)
]


# Transformation ----
property_data[, year := year(date_published)
              ][, quarter := paste0(year, "_", quarter(date_published))
                ][, time := ym_date(as.Date(date_published))] # year-month-01
setcolorder(property_data, c("time", "year", "quarter"), after = "date_published")


## Adjust for inflation ----
cpi = fread("./data/housing/cpi-ethiopia_base2016m12.csv")

property_data[, ym := format.Date(date_published, "%Y_%m")]

setnames(cpi, c("date", "value"), c("ym", "cpi"))
cpi[, ym := format(as.Date(sub("M", "01", ym), "%Y%d%m"), "%Y_%m")]

# fill for missing months -- locf/nocb
rng = range(as.Date(property_data$date_published), na.rm = TRUE)
full_period = data.table(ym = format(seq.Date(rng[1], rng[2], by = "month"), "%Y_%m"))
cpi = cpi[full_period, on = "ym"]
setorder(cpi, ym)
cpi[, cpi_filled := nafill(nafill(cpi, "locf"), "nocb")]
# Re-express in 2018 March prices, a healthy time (just before Abiy came to power)
# cpi[, cpi_filled := 100 * cpi_filled / cpi_filled[ym == "2018_03"]]
property_data = merge(
  property_data, cpi[, .(ym, cpi_filled)], by = "ym", all.x = TRUE
)

property_data[, price_adj := price / (cpi_filled / 100)
              ][,`:=`(cpi_filled = NULL, ym = NULL)]


property_data[, price_sqm := price / size_sqm
              ][, price_adj_sqm := price_adj / size_sqm]

# remove infinite values due to small size
property_data = property_data[!(is.infinite(price_adj_sqm) | is.na(price_adj_sqm)), ]

try(property_data[, exchange_rate := NULL])
property_data = merge(
  property_data, exchangeRate, by.x = "date_published", by.y = "date", all.x = TRUE
)


# Problematic/outliers ----
# Correcting numerical errors spotted accidentally
property_data[id == "beten/351", price := 9.5e6 # maybe removed
  ][
    id %in% c("qefira/5516748", "qefira/5516748_multi_suffix_1"),
    let(price = c(29, 15) * 1e6, size_sqm = c(450, 225))
  ][id == "qefira/5532787_multi_suffix_1", price := 270 * 1e6
    ][id == "jiji/737432_multi_suffix_1", price := 65 * 1e+6] # maybe removed

# Top outliers with visual inspection
problematic_outliers = c(
  "loozap/381162", # size = 165, but it says also 256 in the description
  "loozap/382151", # size = 100, but it says also 1000
  # few over 100k per sqm
  "loozap/381470",
  "loozap/381148",
  "loozap/376430",
  "loozap/382170",
  "loozap/62187249" # wrong price reported
)
property_data = property_data[id %notin% problematic_outliers, ]


# Correct misclassified data further
property_data[
  listing_type == "for rent" & property_type %in% property_types & price >= max_rent_etb, let(listing_type = "for sale", listing_type_fixed = "yes")
] # TODO: there are few obs where the price are phone number

property_data[
  listing_type == "for sale" & property_type %in% property_types & price < min_sale_etb, let(listing_type = "for rent", listing_type_fixed = "yes")
]
property_data[
  listing_type == "for sale" & property_type %in% property_types & price >= max_sale_etb, let(property_type = "building", property_type_fixed = "yes")
]
property_data[
  property_type == "building" & price < max_rent_etb & listing_type == "for rent",
  let(property_type = "house", property_type_fixed = 'yes')
]

property_data[
  property_type == "land" & listing_type == "for rent",
  `:=`(
    property_type = fifelse(price < min_sale_etb, "house", property_type),
    listing_type = fifelse(price >= min_sale_etb, "for sale", listing_type),
    property_type_fixed = 'yes', listing_type_fixed = 'yes'
  )
]


# Outlier removal ----
# https://www.numbeo.com/property-investment/in/Addis-Ababa
# https://github.com/eyayaw/cleaning-RWI-GEO-RED?tab=readme-ov-file#features
# ABRS (2020) for germany

# Filter out unlikely data, upfront
property_data = property_data[between(size_sqm, size_ll, size_ul),]
property_data = property_data[price_adj_sqm < sale_ul | price < max_sale_etb, ]

property_data = property_data[, .SD[!is_outlier(price_adj_sqm, na.rm = T)], .(listing_type, property_type)]


price = property_data[
  listing_type == "for sale" & (price_adj_sqm >= sale_ll & price_adj_sqm <= sale_ul)
]
rent = property_data[
  listing_type == "for rent" & (price_adj_sqm >= rent_ll & price_adj_sqm <= rent_ul)
]

property_data = rbind(price, rent, use.names = TRUE)


# Remove duplicates ----
# Cross-posting is rampant
# Although, "id" is a unique identifier for the ad, but by other attributes,
# there are duplicates.
# The same ad could be posted on various platforms on different dates, but at least
# should be unique in a given month.
cols = c(
  "listing_type", "property_type", "address", "address_extracted",
  "price", "size_sqm", "num_bedrooms", "num_bathrooms", "num_images",
  "time", "title", "description"
)
try({
  problematic = property_data[property_type_fixed == "yes" |
                                listing_type_fixed == "yes" |
                                size_sqm_is_imputed == "yes", which = TRUE]
  # Prefer the untouched ones if they happen to be duplicates
  property_data_unique = unique(property_data[-problematic,], by = cols)
  property_data_unique = rbind(property_data_unique, unique(property_data[problematic,], by = cols))
}
)
property_data_unique = unique(property_data, by = cols)


#TODO: de-clutter by removing unnecessary vars

set_col_order(property_data_unique)

# Write to file ----
dir.create("data/housing/processed/tidy", showWarnings = FALSE)
fwrite(
  property_data_unique,
  "data/housing/processed/tidy/listings_cleaned_tidy.csv"
)
