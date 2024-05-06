source("./script/helpers/helpers.R")

# Attribute parsers ----

bool2YesNo = function(x) {
  true = vapply(x, isTRUE, NA)
  false = vapply(x, isFALSE, NA)
  out = character(length(x))
  out[true] = "yes"
  out[false] = "no"
  out[out == ""] = NA_character_
  out
}

## parsers ----

parse_price_unit = function(x) {
  x = str_squish(x) |> tolower()
  price_unit = fcase(
    x %plike% paste0(
      c(
        r"{\b((per|/)\W*(sqm|m2|(k|c)ar(e|i)))\b}",
        r"{\b(be\s*(k|c)ar(e|i))\b}",
        r"{(በካሬ\s*(ሜ(ትር)?)?)}"
      ),
      collapse = "|"
    ), "per sqm",
    x %plike% paste0(
      c(
        r"{\b((per|/)\W*(month(ly)?)|monthly)\b}",
        r"{\b(be\s*w(e|o)re?)\b}",
        r"{(በወር|በ?ወራዊ|በ?ወር(ሃ|ሀ)ዊ)}"
      ),
      collapse = "|"
    ), "per month",
    x %plike% "\\b((per|/|be)?\\W*year(ll?y)?|annum|annual(ly)?|ametawi|amet)\\b|[በየ]አመት|[በየ]አመታዊ", "per year",
    x %plike% "\\b((per|/|be)?\\W*day(ly)?|qen|ken)\\b|[በየ]ቀን", "per day",
    x %plike% "\\b((per|/)?\\W*week(ly)?|sam[ie]nt(awi)?)\\b|[በየ]?ሳምንት|[የበ]?ሳምንታዊ", "per week",
    x %plike% "\\b(total\\W*(price)?)\\b", "total price",
    rep(TRUE, length(x)), "other"
  )
  price_unit
}

parse_price_type = function(x) {
  x = str_squish(x) |> tolower()
  price_type = fcase(
    x %plike% "negotiable", "negotiable",
    x %plike% "fixed", "fixed",
    rep(TRUE, length(x)), "other"
  )
  price_type
}

parse_price_currency = function(x) {
  x = str_squish(x) |> tolower()
  price_currency = fcase(
    x %plike% "ብር|(ethiopian.*birr|etb|birr|br)", "etb",
    x %plike% "ዶላር|(usd|dollars?|\\$)", "usd",
    x %plike% "ዩሮ|(eur(os)?|€)", "euro",
    x %plike% "ፓውንድ|(gbp|pounds?|sterling|£)", "gbp",
    rep(TRUE, length(x)), "other"
  )
  price_currency
}

parse_size_unit = function(x) {
  x = str_squish(x) |> tolower()
  size_unit = fcase(
    x %plike% "sqm|(c|k)ar(e|i).*(meter)?|k/c.*are|m2|meters?|m|sq|ካሬ\\s*(ሜ(ትር)?)?", "sqm",
    x %plike% "square.*(feet|ft)|sqr?.*ft|sqf", "sqrft",
    x %plike% "hectares?|(ሔ|ሄ)ክታር", "hectare",
    x %plike% "acres?", "acre",
    rep(TRUE, length(x)), "other"
  )
  size_unit
}

parse_listing_type = function(x) {
  x = str_squish(x) |> tolower()

  listing_type = fcase(
    x %plike% "(for)?\\s*(sale|sell|purchase)" &
      x %plike% "(for)?\\s*(rent)", "for sale/rent",
    x %plike% "(for)?\\s*(sale|sell|purchase)|የ[ሚም]ሸጥ|ለ?[ሽሺ]ያ[ጭጪጥ]", "for sale",
    x %plike% "(for)?\\s*(rent)|(የ[ሚም])?[ከክኪ]ራይ|ለ(ኪክ)ራይ", "for rent",
    x %plike% "(for)?\\s*(lease)", "for lease",
    rep(TRUE, length(x)), "unknown"
  )

  listing_type
}

parse_property_type = function(x) {
  x = gsub("for\\s*(sale|rent|lease)", "", tolower(x)) |> str_squish()
  house_re = paste0(
    c(
      "^(houses?|villa)$", "^residential$",
      "^((villa|furnish(ed)?).*houses?)$", "vill?a\\s*(houses?|homes?|bete?)?",
      "houses?.*(residen.*(villa)?|villa)",
      "(guest|town|terrace|duplex|bungalow|mansion|maisonette)\\s*(houses?)?",
      "(?<!ሳር|ሳር )((?:የ?መኖሪያ\\s*)?(ቤት|ቤቶች))",
      "(ቪ|ቢ)ላ\\s*(ቤት)?", "(ሰርቢስ|ክፍል|ፓላስ)"
    ),
    collapse = "|"
  )
  apart_re = paste0(
    c(
      "^(apartments?|studio)$", "(flats?|condo|bed\\s*sitters?)",
      "(40\\s*/\\s*60|20\\s*/\\s*80|10\\s*/\\s*90)", # condominium schemes
      "(shared|studio|furnish(ed)?|resid)[^,]*apartments?",
      "(apartments?[^,]*(furnish(ed)?|resid|houses?))",
      "duplex\\s*(apartments?|houses?)?", "pent\\s*(houses?|homes?)",
      "አ(ፓ|ፖ)ር(ታ|ት)(ማ|መንት)", "[ከኮ]ን?[ዶደዴ][ሚምመ](ንየ|ኔ|ነ)ም", "[ስሰ]ቱ(ድ|ዲ)ዮ([ዎወ]ች)?"
    ),
    collapse = "|"
  )


  commercial_property_re = paste0(
    c(
      "^(commercial.*(building|property)?)$",
      "\\b(office|shop|store|ware\\s*house)s?\\b",
      "(መ(ገ|ጋ)ዘን|(?:የ?ንግድ)?\\s*(ሱቅ|ቤት|ህንፃ)|መናፈሻ)",
      "(service.*(station|house|quarter))",
      "\\b(corporate|business|company|industrial|factory|cooperative)\\b",
      "\\b(school|hotels?|motels?|resorts?|cafe|bar|restaurant)\\b",
      "\\b(spa|massage|pension|game|clinic|hospital|foundation|farm\\s*house)\\b"
    ),
    collapse = "|"
  )

  building_re = paste0(
    c(
      "(^((entire\\s*)?build(ing)?)$|ህንፃ)",
      "\\b(residen[^.]*(house|apartment)[^,]*build(ing)?)\\b",
      "\\b(reside[^,]build(ing)?)\\b",
      "((residential|apartment)[^,]*build(ing)?)",
      "\\b(build(ing)?[^,]*(apartment|house))\\b"
    ), collapse = "|"
  )

  land_re = c(
    "\\b(vacant)?\\s*(land|plot)\\b",
    "(ባዶ|እርሻ|ክፍት|የ?ቢዝነስ|የ?(?:ንግድ|ሱቅ))?\\s*(መሬት|ቦታ)"
  ) |> paste0(collapse = "|")

  property_type = fcase(
    x %plike% house_re, "house",
    x %plike% apart_re, "apartment",
    x %plike% land_re, "land",
    x %plike% commercial_property_re, "commercial",
    x %plike% building_re, "building",
    rep(TRUE, length(x)), "other"
  )
  property_type
}

parse_region = function(x) {
  x = str_squish(x)
  region = fcase(
    x %ilike% "addis\\s*ab(a|e)ba|አዲስ\\s*አበባ|ለሚ\\s*ኩራ", "addis ababa",
    x %ilike% "sheger city|adama|oromia", "outside addis",
    rep(TRUE, length(x)), x
  )
  region
}

parse_furnishing_level = function(x) {
  x = str_squish(x) |> tolower()
  furnishing = fcase(
    x %plike% "(nicely|well|fully?).*furnish(ed)?", "furnished",
    x %plike% "(semi|partial(ly)?).*furnish(ed)?", "semi-furnished",
    x %plike% "(not|un).*furnish(ed)?", "unfurnished",
    x %plike% "furnish(ed)?", "furnished",
    rep(TRUE, length(x)), NA_character_
  )
  furnishing
}

parse_features = function(x, feature_name = NULL) {
  x = str_squish(x) |> tolower()
  check_presence = function(pattern) {
    return(grepl(pattern, x, perl = TRUE))
  }
  # availability/accessibility of features
  patterns = list(
    parking = "(parking(\\s*(lot|space)s?)?)",
    kitchen = "(?<!ሎ)(ኩሽና|(ኪ|ክ)(ች|ሽ)ን)|kitchen",
    elevator = "(elevators?|lifts?|ሊፍ(ት|ቶች)|አሳንሱ(ር|ሮች)|(ኤ|እ)ሊቬተ(ር|ሮች))",
    balcony = "(balcony|(?<!gojjam)\\sberenda|ባልኮኒ|(?<!ጎጃም)\\sበረንዳ)",
    garden = "(garden|backyard|patio|yard|outdoor\\s*(space)?|landscaping|lawn|terrace|ጓሮ|ባክያርድ|ቴራስ|ሰገነት|መናፈሻ)",
    water = paste0(
      c(
        "(ንፁህ|የ?ከርሰ\\s*ምድር|የመጠጥ)\\s*ው(ሃ|ሀ|ሓ|ሐ)",
        "የ?ው(ሃ|ሀ|ሓ|ሐ)\\*(ታንከር|ቦኖ|አገልግሎት)",
        "(water\\s*(access(ibility)?|tanker|service))"
      ),
      collapse = "|"
    ),
    power = "(power|electric(ity)?|light|generator)"
  )

  if (!is.null(feature_name)) {
    # Check if feature_name exists in patterns
    exist = feature_name %in% names(patterns)
    if (!all(exist)) {
      stop(
        sprintf(
          "The feature(s): [%s] does not exist.", paste(feature_name[which(!exist)], collapse = ",")
        ),
        call. = FALSE
      )
    }
    patterns = patterns[feature_name]
  }

  if (length(patterns) == 1) {
    features = check_presence(patterns) |> bool2YesNo()
  } else {
    features = lapply(patterns, check_presence) |> lapply(bool2YesNo)
  }

  return(features)
}

parse_condition = function(x) {
  x = tolower(x) |> str_squish()
  new_re = paste0(
    c(
      "^((brand)?.*new|finished|built|completed|constructed|done|modern|luxurious)$",
      "(new\\s*condition|newly.*built)",
      # >= 85% considered as New
      "(([8[5-9]|9[0-9]|100|fully?|almost|well).*(finish(ed)?|complet(ed|e)|constructed|buil(t|d)|done))",
      "(move.*in)"
    ),
    collapse = "|"
  )
  under_construction = paste0(
    c(
      "(under.*(construction))",
      "((not|un|\\d+).*complet(e|ed)|off.*plan)",
      "(not|un|partially|semi|\\d+|half).*(constructed|finish(ed)?|complet(ed|e)|buil(t|d)|done)",
      "(pending|underway|progress|finishing|skeleton|structure.*finished|undeveloped)"
    ),
    collapse = "|"
  )
  used_re = paste0(
    c(
      "^(old|good)$",
      "((us|renovat|renew|remodel|maintain|demolish)(ed)?|renovation)",
      "(existing)"
    ),
    collapse = "|"
  )

  condition = fcase(
    x %plike% new_re, "new",
    x %plike% under_construction, "under construction",
    x %plike% used_re, "used",
    rep(TRUE, length(x)), NA_character_
  )
  condition
}
