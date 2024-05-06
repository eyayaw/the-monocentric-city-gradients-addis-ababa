library(data.table)
source("./script/helpers/helpers.R")
source("./script/helpers/property_address_cleaning_helpers.R")
source("./script/helpers/helpers_geo.R")

# Helper functions ----
get_address_vars = function(df) {
  vars = grep("^address", names(df), value = TRUE, ignore.case = TRUE)
  if (length(vars) == 0) {
    stop("No address variable(s) found in the data", call. = FALSE)
  }
  return(vars)
}

trim_id_suffix = function(id) {
  gsub("_(multi|expand)_suffix_\\d+$", "", id, perl = TRUE)
}


# Does further cleaning after clean_address
cleanse_text = function(text) {
  reserved_marks = "+,./|'\"-"
  # Add space around numbers attached to amharic words/chaaacters
  text = pgsub("([0-9]+)(\\p{Ethiopic})", "\\1 \\2", text)
  text = pgsub("(\\p{Ethiopic})([0-9]+)", "\\1 \\2", text)

  # Remove unwanted characters, including Amharic punctuation marks
  re = sprintf("[^a-zA-Z0-9\\p{Ethiopic}%s]|[\u135D-\u1368]+", reserved_marks)
  text = pgsub(re, " ", text) |>
    str_squish() |>
    trim_punct()
  # Remove short words: two-letter words (en), and one-letter words (am)
  text = pgsub("^([a-zA-Z]{1,2}|\\p{Ethiopic})$", "", text)
  # Remove the reserved marks if they are two or more
  text = pgsub(sprintf("([%s]{2,})|([\\s,]{2,})", reserved_marks), " ", text)

  return(str_squish(text))
}

# Define sub cities + outside addis
sub_cities = read.csv2(
  text = "
  name;en;am;label
  bole;bole;ቦሌ;inside
  yeka;yeka;የካ;inside
  kirkos;kirkos;ቂርቆስ;inside
  arada;arada;አራዳ;inside
  lideta;l[ie]?deta;ልደታ;inside
  nifas silk-lafto;nifas.*?s(i|e)lk.*?la(f|ph?)to;ንፋስ.*?ስልክ.*?ላፍቶ;inside
  nifas silk-lafto;nifas.*?s(i|e)lk;ንፋስ.*?ስልክ;inside
  akaki kality;akak[iy]\\s*kal[iy]t[iy];አቃቂ\\s*ቃሊቲ;inside
  akaki kality;akak[iy];አቃቂ;inside
  kolfe keranio;kolfe\\s*keranio;ኮልፌ\\s*(ቀራንዮ|ቀራኒዮ);inside
  kolfe keranio;kolfe;ኮልፌ;inside
  gulele;gull?ell?i?e;ጉለሌ;inside
  addis ketema;addis\\s*ket[ea]ma;አዲስ\\s*ከተማ;inside",
  strip.white = TRUE
)

addis_ababa = read.csv2(
  text = "
  name;en;am;label
  addis ababa;(ethiopia)?[\\s[:punct:]]*addis\\s*ababa[\\s[:punct:]]*(ethiopia)?|(oromia)?[\\s[:punct:]]*finfinn?e[\\s[:punct:]]*(oromia)?;[\\s(ኢትዮጵያ)?[:punct:]]*አዲስ\\s*አበባ[\\s[:punct:]]*(ኢትዮጵያ)?|(ኦሮሚያ)?[\\s[:punct:]]*ፊንፊኔ[\\s[:punct:]]*(ኦሮሚያ)?;inside",
  strip.white = TRUE
)

outside_addis = read.csv2(
  text = "
  name;en;am;label
  amhara;amhara;አማራ;outside
  oromia;oromia;ኦሮሚያ;outside
  nazret;nazh?[ie]?ret[ ,]*(oromia)?;ናዝሬት;outside
  adama;adama[ ,]*(oromia)?;አዳማ[ ,]*(ኦሮሚያ)?;outside
  bishoftu;bish[eo]ftu[ ,]*(oromia)?;ቢ[ሸሾ]ፍቱ[ ,]*(ኦሮሚያ)?;outside
  debre zeit;debre[ -]*zeit[ ,]*(oromia)?;ደብረ[ -]*ዘይት[ ,]*(ኦሮሚያ)?;outside
  dukem;dukem[ ,]*(oromia)?;ዱከም[ ,]*(ኦሮሚያ)?;outside
  mojo;mojo[ ,]*(oromia)?;ሞጆ[ ,]*(ኦሮሚያ)?;outside
  sebeta;sebett?a[ ,]*(oromia)?;ሰበታ[ ,]*(ኦሮሚያ)?;outside
  holeta;holl?ett?a[ ,]*(oromia)?;ሆለታ[ ,]*(ኦሮሚያ)?;outside
  hawassa;hawass?a;[ሐሀአ]ዋሳ;outside",
  strip.white = TRUE
)

address_labels = rbind(sub_cities, addis_ababa, outside_addis)

# Identify road addresses ----
full_match = function(re) {
  return(sprintf("^(%s)$", re))
}

get_broad_name = function(address, patterns) {
  if (is.na(address) || address == "") {
    return(NA_character_)
  }

  matches = vector("character", length(patterns))
  names(matches) = names(patterns)
  for (name in names(patterns)) {
    re = full_match(patterns[[name]])
    if (grepl(re, address, perl = T, ignore.case = T)) {
      matches[name] = name
    }
  }
  matches = matches[matches != ""]
  if (length(matches) == 0) {
    return("Not broad address")
  } else if (length(matches) == 1) {
    return(matches)
  } else {
    warining("Only the first element is considered, as multiple matches were found for the address: ", address)
    return(matches[1])
  }
}
get_broad_label = function(broad_name) {
  if (is.na(broad_name)) {
    return(NA_character_)
  }
  if (broad_name == "Not broad address" || broad_name %notin% address_labels$name) {
    return("inside")
  }
  return(address_labels$label[match(broad_name, address_labels$name)])
}

get_broad_address_label = function(address) {
  address = tolower(address) |> str_squish()
  # Define pattern for Addis Ababa
  addis_re = c(addis_ababa$en, addis_ababa$am) |>
    combine_regex() |>
    embrace_regex()

  suffix = "(?:sub[./ -]*city|(ክፍለ|ክ)[./ -]*(ከተማ|ከ))?"
  delim = "[./ ,-]*"

  # Create regex for the sub cities
  re1 = sprintf(
    "(%s%s%s%s%s%s%s|%s%s%s%s%s%s%s)",
    paste0(addis_re, "?"), delim, sub_cities$en, delim, suffix, delim, paste0(addis_re, "?"),
    paste0(addis_re, "?"), delim, sub_cities$am, delim, suffix, delim, paste0(addis_re, "?")
  )
  re2 = sprintf(
    "(%s%s%s%s%s%s%s\\s*[|]\\s*%s%s%s%s%s%s%s)",
    paste0(addis_re, "?"), delim, sub_cities$en, delim, suffix, delim, paste0(addis_re, "?"),
    paste0(addis_re, "?"), delim, sub_cities$am, delim, suffix, delim, paste0(addis_re, "?")
  )
  sub_cities_re = Map(\(x, y) combine_regex(c(x, y)), re1, re2)
  names(sub_cities_re) = sub_cities$name

  # Create regex for outside Addis locations
  outside_addis_re = sprintf("(%s|%s)", outside_addis$en, outside_addis$am) |> as.list()
  names(outside_addis_re) = outside_addis$name

  addis_re = setNames(addis_re, addis_ababa$name) |> as.list()
  patterns = c(sub_cities_re, addis_re, outside_addis_re)


  broad_names = vapply(address, \(x) get_broad_name(x, patterns), character(1))
  broad_labels = vapply(broad_names, get_broad_label, character(1))
  return(list(broad_name = broad_names, broad_label = broad_labels))
}


# Remove number only addresses, except for some known numeric addresses
remove_number_only = function(address) {
  exceptions = as.integer(c(22, 24, 7, 18, 49, 71, 72, 41, 3, 140, 30))
  address_trimmed = str_squish(address)
  numeric_only = grepl("^\\d+$", address_trimmed)
  exceptions_found = as.integer(address_trimmed) %in% exceptions
  address[numeric_only & !exceptions_found] = NA_character_
  return(address)
}


# Remove leftover unnecessary symbols, punctuation, and spaces
# Cleanse and remove number only addresses
clean_pipeline = function(address) {
  cleaned_address = clean_address(address) |>
    cleanse_text() |>
    clean_text() |>
    remove_number_only() |>
    tolower() |>
    str_squish()
  cleaned_address = fifelse(cleaned_address == "", NA_character_, cleaned_address)
  return(cleaned_address)
}

# import data ----
## all providers
# raw property addresses as given by the providers
propertyAddresses = fread(
  "./data/housing/processed/tidy/listings_cleaned_tidy.csv",
  select = c("id", "address", "address_extracted", "title", "description", "lng", "lat"),
  na.strings = ""
)

# includes manually corrected addresses for properties
corrected_addresses = fread(
  "./data/geodata/geocode/mule/corrected-addresses.csv", na.strings = ""
)

# cleaning ----
propertyAddresses[, (get_address_vars(propertyAddresses)) :=
  lapply(.SD, \(a) fifelse(trim_punct(a) == "", NA, a)),
.SDcols = get_address_vars(propertyAddresses)
]

corrected_addresses[, (get_address_vars(corrected_addresses)) :=
  lapply(.SD, \(a) fifelse(trim_punct(a) == "", NA, a)),
.SDcols = get_address_vars(corrected_addresses)
]

# Use the gmaps autocomplete for the addresses that are not corrected
corrected_addresses[, use_api :=
  fifelse(
    address == address_corrected | is.na(address_corrected), "autocomplete", "search"
  )]

# merge corrected addresses with the original addresses
propertyAddresses = merge(
  propertyAddresses, corrected_addresses[, .(id, address_corrected, use_api)], "id", all.x = TRUE
  # `all.x = TRUE` is important as we do not have all the addresses in the `corrected_addresses`.
)
setcolorder(propertyAddresses, "address_corrected", after = "address")
# For multi/expand suffixes, get the corrected address from the original's.
propertyAddresses[, id2 := trim_id_suffix(id)]
propertyAddresses[
  id %ilike% "_(multi|expand)_suffix",
  address_corrected := fifelse(
    address == propertyAddresses[id == id2[1]]$address,
    propertyAddresses[id == id2[1]]$address_corrected, address_corrected
  )
][, id2 := NULL]

# The gmaps autocomplete api provides better result than the geocode api
propertyAddresses[is.na(use_api), use_api := "autocomplete"]

# - Replace addresses that are "NA" in the corrected address with the original address.
# - This is because for manually uncorrected addresses, the corrected address is "NA" (empty string coerced to "NA" above).
propertyAddresses[is.na(address_corrected), address_corrected := copy(address)
][is.na(address), address := copy(address_corrected)]

# Some providers provide exact (lat/long) addresses. (zegebeya, realethio, livingethio)
# addresses = addresses[id %like% "^(zegebeya|realethio|livingethio)", ]
within_addis_idx = propertyAddresses[!is.na(lng) & !is.na(lat), ][is_within_addis(lng, lat), id]
propertyAddresses = propertyAddresses[id %notin% within_addis_idx, ][, c("lat", "lng") := NULL]

## address cleaning ----
vars = c("address_corrected", "address_extracted")
vars = setNames(paste0(vars, "_clean"), vars)
propertyAddresses[, (vars) := lapply(.SD, clean_pipeline), .SDcols = names(vars)]

# Split addresses into English and Amharic (only the manually corrected addresses have "en | am" addresses)
propertyAddresses[, address_corrected_clean := sub("===", " | ", gsub("\\|", "===", address_corrected_clean))]
propertyAddresses[, c("address_corrected_clean_en", "address_corrected_clean_am") :=
  tstrsplit(address_corrected_clean, "|", fixed = TRUE)]
propertyAddresses[is.na(address_corrected_clean_en),
  address_corrected_clean_en := copy(address_corrected_clean_am)
]
setcolorder(propertyAddresses, get_address_vars(propertyAddresses), after = "address")

# -  NB: If the *_cleaned address is empty, it means that the `clean_address` function returned an empty string after cleaning. This is different from "NA".
# For some ads whose addresses were not given, their addresses have been
# extracted from the description and title (manually or using gemini pro)
propertyAddresses[
  str_squish(address_corrected_clean_en) == "", address_corrected_clean_en := NA
][
  str_squish(address_extracted_clean) == "", address_extracted_clean := NA
][
  is.na(address_corrected_clean_en),
  address_corrected_clean_en := copy(address_extracted_clean)
][
  is.na(address_extracted_clean),
  address_extracted_clean := copy(address_corrected_clean_en)
]


# This is clearly outside Addis Ababa.
# It has nothing to do with Istanbul Cafe/Restaurant in Addis.
propertyAddresses = propertyAddresses[!(address_corrected_clean %like% "ኢስታንቡል.*ቱርክ"), ]

# " - bole addis ababa" is extraneous
propertyAddresses[, address_corrected_clean_en :=
  gsub("-\\s*bole\\s*(addis\\s*ababa)?", " addis ababa ", address_corrected_clean_en)
][, address_extracted_clean :=
  gsub("-\\s*bole\\s*(addis\\s*ababa)?", " addis ababa ", address_extracted_clean)]


# Run the pipeline again to squash escaped patterns
propertyAddresses[, address_corrected_clean_en := clean_pipeline(address_corrected_clean_en)
][, address_extracted_clean := clean_pipeline(address_extracted_clean)]



# unique addresses ----
propertyAddresses = propertyAddresses[!is.na(id), ] # should not happen, for safety

addresses_unique = copy(propertyAddresses)[,
  .(id,
    address_main = str_squish(address_corrected_clean_en),
    address_alt = str_squish(address_extracted_clean),
    use_api
  )
]

# One more time
addresses_unique[address_main == "", address_main := NA
][address_alt == "", address_alt := NA]

addresses_unique[, address_main := fcoalesce(address_main, address_alt)
][, address_alt := fcoalesce(address_alt, address_main)]

# We need how many addresses are not empty for the analysis, but ignore in the geocoding
# addresses_unique = addresses_unique[!is.na(address_main), ]

addresses_unique[, c("broad_name_main", "broad_label_main") :=
  get_broad_address_label(address_main)
][, c("broad_name_alt", "broad_label_alt") :=
  get_broad_address_label(address_alt)]

not_broad_name = "Not broad address"
not_broad_label = "inside"
stopifnot(not_broad_name %in% unique(addresses_unique$broad_name_main))
addresses_unique[
  broad_name_main != not_broad_name,
  address_main := broad_name_main
][
  broad_name_alt != not_broad_name,
  address_alt := broad_name_alt
]

# we keep those with non-empty addresses for descriptive analysis, ignore in geocoding
addresses_unique = addresses_unique[
  broad_label_main == "outside", address_main := NA_character_
][broad_label_alt == "outside", address_alt := NA_character_
]
addresses_unique = addresses_unique[
  !is.na(address_main) & !is.na(address_alt),
]

addresses_unique[, address_main := fcoalesce(address_main, address_alt)
][, address_alt := fcoalesce(address_alt, address_main)]

addresses_unique[
  broad_name_main != not_broad_name,
  address_main := fcase(
    broad_name_alt == not_broad_name, address_alt,
    rep(TRUE, length(address_main)), address_main
  )
]

addresses_unique[
  broad_name_alt != not_broad_name & broad_name_main == not_broad_name,
  address_alt := address_main
]

# Prefer sub city name however broad
addresses_unique[
  address_main == "addis ababa", address_main := address_alt
]


# - The `ids` column is a comma-separated list of ids that have the same address.
addresses_unique = addresses_unique[, .(
  ids = paste0(unique(id), collapse = ","),
  unique_address_grp = .GRP, N = .N
),
.(address_main, address_alt, use_api)
]


# addresses_unique[, address_main := gsub("መድሀኒአለም", "መድኃኒዓለም", address_main)
# ][, address_alt := gsub("መድሀኒአለም", "መድኃኒዓለም", address_alt)]

# write ----
# for geocoding in python
fwrite(
  addresses_unique, "./data/geodata/geocode/property_addresses__unique.csv"
)
