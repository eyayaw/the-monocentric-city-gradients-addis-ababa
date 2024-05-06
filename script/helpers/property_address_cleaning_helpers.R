source("./script/helpers/helpers.R")
source("./script/regular_expressions.R")

# This script contains a set of functions for cleaning property addresses.
# The functions are designed to remove extraneous or distracting strings from addresses,
# such as property characteristics, listing types, property features, construction stages,
# installment payments, distance and direction information, and common address patterns.
# The functions utilize regular expressions to identify and remove the specified patterns from the addresses.


# Helper functions for regular expressions ----
embrace_regex = function(x, non_capturing = FALSE) {
  if (!is.character(x)) stop("`x` must be a character vector", call. = FALSE)
  if (!is.logical(non_capturing)) stop("`non_capturing` must be a logical value", call. = FALSE)
  if (non_capturing) paste0("(?:", x, ")") else paste0("(", x, ")")
}

combine_regex = function(x) {
  if (!is.character(x)) stop("`x` must be a character vector", call. = FALSE)
  paste0(x, collapse = "|")
}

add_boundary = function(text, boundary = c("\\b", "\\s")) {
  if (!is.character(text)) {
    stop("x must be a character vector", call. = FALSE)
  }
  boundary = match.arg(boundary)
  # Ignore those that already have the boundary
  at_start = grepl(r"(^(\^|\$|\\b|\\s))", text)
  at_end = grepl(r"((\^|\$|\\b|\\s)$)", text)
  if (any(at_start, at_end)) {
    warning("One or more of the input may already have a \\b|\\s boundary. Boundary ignored at the start/end of the string..",
      call. = FALSE
    )
  }
  text[!at_start] = paste0(boundary, text[!at_start])
  text[!at_end] = paste0(text[!at_end], boundary)
  return(text)
}


# Clean text by removing emojis, phone numbers, and other symbols
cleanText = function(text) {
  text = as.character(text) # coerce to character

  # Construct regex for emojis and other symbols
  emoji_regex = sprintf("[%s]+", paste0(emojies, collapse = " "))
  other_syms_regex = sprintf("(%s)\\1+", other_syms)
  pattern_vector = c(phone_num_regex, emoji_regex, other_syms_regex)

  # Remove patterns from text iteratively
  for (p in pattern_vector) {
    text = str_squish(gsub(p, " ", text, perl = TRUE))
  }

  # Remove HTML tags
  text = gsub(r"(\<p(\>)?|(\</)?p\>|\<br\>|&nbsp; ?)", " ", text, perl = TRUE)

  # Reduce multiple spaces and trim
  text = str_squish(text)

  return(text)
}

# A gsub wrapper: replace matching patterns with " "
remove_strings = function(text, patterns, combine = FALSE, ...) {
  if (combine) {
    patterns = combine_regex(patterns) |> embrace_regex(T)
  }

  for (pattern in patterns) {
    text = str_squish(gsub(pattern, " ", text, ignore.case = TRUE, perl = TRUE, ...))
  }

  return(text)
}


# This function removes punctuation from a string. Adapted from `base::trimws`.
# which: Where to remove punctuation from - either the left, the right, or at both ends of the string.
# punct: The pattern of punctuation to remove, defaults to the char class [[:punct:]].
trim_punct = function(x, which = c("both", "left", "right"), punct = "[[:punct:]]") {
  which = match.arg(which)
  str_rm = function(re, x) sub(re, " ", x, perl = TRUE) # the space will be trimmed/squished later
  trimmed = switch(which,
    both = str_rm(paste0(punct, "+$"), str_rm(paste0("^", punct, "+"), x)),
    left = str_rm(paste0("^", punct, "+"), x),
    right = str_rm(paste0(punct, "+$"), x)
  )
  str_squish(trimmed)
}


# Address cleaning ---- # starts here

## property characteristics ----
## property types
property_types = c(
  paste0(
    "የ?",
    c(
      "[ከኮ]ን?[ዶደዴ][ሚምመ](ንየ|ኔ|ነ)ም",
      "[ስሰ]ቱ(ድ|ዲ)ዮ([ዎወ]ች)?",
      "አፓር[ታት](ማ|መንት)",
      "(?<!ሳር|ሳር )((?:የ?መኖሪያ\\s*)?(ቤት|ቤቶች))",
      "(ቪ|ቢ)ላ\\s*ቤ(ት|ቶች)?",
      "(ባዶ|እርሻ|ክፍት|የ?ቢዝነስ|የ?(?:ንግድ|ሱቅ))?\\s*(መሬት|ቦታ)",
      "ሆቴል",
      "መ(ገ|ጋ)ዘን",
      "(?:የ?ንግድ)?\\s*ሱቅ",
      "መናፈሻ",
      "ህንፃ"
    )
  ),
  "co[nm]do(minium)?s?",
  "e?st(u|i)di?os?",
  "apartments?|apartama|flats?",
  "homes?|houses?|bet",
  "vill?a\\s*(houses?|homes?|bet)?",
  "pent\\s*(houses?|homes?)",
  "duplex\\s*(apartments?|houses?)?",
  "land",
  "hotels?|motels?|resorts?",
  "ware\\s*houses?",
  "shops?",
  "buildings?"
)
## listing types
listing_types = c(
  "(sale|sell(ing)?)", "rent(ing)?", "leas(e|ing)", "buy(ing)?", "purchas(e|ing)"
)

# create regex patterns
property_types_re = property_types |>
  embrace_regex(T) |>
  combine_regex() |>
  embrace_regex(T)

listing_types_re = listing_types |>
  combine_regex() |>
  embrace_regex(T) |>
  sprintf(fmt = "(for?e?)?\\s*%s") |>
  embrace_regex(T) |>
  add_boundary() |>
  c(
    "የ[ሚም]ሸጥ|ለ?[ሽሺ]ያ[ጭጪጥ]|(የ[ሚም])?[ከክኪ]ራይ|ለ(ኪክ)ራይ" |> embrace_regex(T)
  ) |>
  combine_regex() |>
  embrace_regex(T)

features_re = c(
  "(bath|bed|living)?rooms?", "bdrms?", "shower", "lift", "elevator",
  "star", "(car[ -])?park(ing)?\\s*(space|lot)", "መኝታ|ክፍል|ኮከብ"
) |>
  embrace_regex(T) |>
  combine_regex() |>
  embrace_regex(T)

# floor and story
floor_story_re = c(
  "[gGጅጀ]\\s*[+]\\s*\\d+", # g+1
  "\\d+\\s*(ኛ|st|nd|rd|th)\\s*(ፎቅ|ወለል|ደረጃ|floor|story|level)" # 1st floor
) |>
  embrace_regex(T) |>
  combine_regex() |>
  embrace_regex(T)

# adverb prefixes
adverbs_re = "very|በጣም|እጅግ" |> embrace_regex(T)
descriptors_re = c(
  "ዘመናዊ|አዲስ (?!(ከተማ|አበባ|ሰፈር))|አሮጌ|ያማረ|ቅንጡ|የተሟላ|ያለቀለት|ምቹ|ቆንጆ",
  "modern|new|old|quality|luxur(y|ious)|renovated|renewed|(fully[\\s-]?)?furnished|cozy|clean"
) |>
  embrace_regex(T) |>
  combine_regex() |>
  embrace_regex(T) |>
  # add the optional adverb prefix
  (\(.x) paste0(adverbs_re, "?\\s*", .x))() #|> add_boundary()

## construction/completion percentage ----
constr_stage_re = c(
  "\\d+\\s*(%|percent(age)?|ፐርሰንት)?\\s*(ግንባታው?|construction|ኮንስትራክሽን)?",
  "[በየከ]*\\d+\\s*(%|percent(age)?|ፐርሰንት)?"
) |>
  embrace_regex(T) |>
  paste0(
    "\\s*",
    embrace_regex(
      "(ያለቀ|የቀረው|የደረሰ|የተጠናቀቀ)|(completed|finished|constructed|buil[td]|done)", T
    )
  ) #|> add_boundary()

handover_time_re = c(
  "(በ|ባ)?",
  sprintf("(\\d+|%s)", amharic_nums),
  "(years?|months?|weeks?|days?|[ዓአ]መት|ወር|ሳምንት|ቀን)",
  "(የሚደርስ|የሚያልቅ|የሚረከብ|የሚለቀቅ|የሚጠናቀቅ|የሚጨረስ|የሚተላለፍ)"
) |>
  paste0(collapse = "\\s*") #|> add_boundary()

down_discount_payments_re = c(
  sprintf(
    "[የከበለ]?\\s*\\d+\\s*(%%|percent(age)?)\\s*%s",
    embrace_regex(c(
      "(ቅ(ድ|ደ)(ም|መ|ሚ)ያ?|የመጀመሪያ)\\s*[ክከ]ፍያ",
      "ቅናሽ\\s*(ዋጋ)?|down\\s*payment|installment"
    ), T)
  ),
  embrace_regex("\\d+\\s*(%|perc(ent|age)?)\\s*discounts?|(down|initial|first)\\s*payment", T)
) #|> add_boundary()


# functions to remove strings from address ----

# remove floor/story level from address
rm_floor_story = function(address) {
  # Matches floor/story levels
  remove_strings(address, floor_story_re) |>
    str_squish()
}

# remove property sizes
rm_property_size = function(address) {
  property_size_re = paste0(
    "(area|total|size|buil[dt]\\s*on|ስፋ[ትቱ])?",
    "\\s*",
    "([0-9.]+|[0-9]+\\s*ሺ)\\s*((ካ|ከ|ክ)ሬ\\s*((ሜ|ሚ|ም|መ)ትር)?|[ck]ar[ei]\\s*(meter)?|m²|m\\^2|m2|sqm|msq|square\\s*(meter|feet|ft)|sqr?ft)"
  ) |>
    embrace_regex(T)
  remove_strings(address, property_size_re) |>
    str_squish()
}

# remove property features
rm_features = function(address) {
  # (ባለ)? 3 መኝታ | 3 bedrooms
  # ባለ 3 (መኝታ)? | 3 bedrooms
  pattern = sprintf(
    sprintf("(ባለ)?\\s*(\\d+|%1$s)\\s*%%s|ባለ\\s*(\\d+|%1$s)", amharic_nums), features_re
  ) |> embrace_regex(T)
  remove_strings(address, pattern) |>
    str_squish()
}

# remove property and listing type patterns
rm_type_patterns = function(address) {
  type_patterns = c(
    # new apartment for sale in
    # ዘመናዊ ቤት ሽያጭ
    sprintf(
      "(%s)?\\s*%s\\s*%s(\\s+in\\s+)?",
      descriptors_re, property_types_re, listing_types_re
    ),
    # for sale ((modern) (apartment) in)
    sprintf(
      "%s\\s*(%s)?\\s*(%s)?(\\s+in\\s+)?",
      listing_types_re, descriptors_re, property_types_re
    )
  ) # |> add_boundary()

  remove_strings(address, type_patterns) |>
    str_squish()
}

rm_descriptions = function(address) {
  # Matches:
  # fully-furnished (3 bedroom) apartment
  # apartment (3bdrm) fully-furnished
  patterns = c(
    sprintf(
      "%s\\s*(\\d+\\s*%s\\s*)?%s",
      descriptors_re, features_re, property_types_re
    ),
    sprintf(
      "%s\\s*%s\\s*%s", property_types_re, features_re, descriptors_re
    ), # do not make features_re optional here
    # Gotera Condominium, Addis Ababa | ጎተራ 'ኮንደሚኒየም አዲስ' አበባ

    sprintf("%s\\s*(%s)?\\s*%s", floor_story_re, descriptors_re, property_types_re),
    sprintf("(%s)?\\s*%s\\s*%s", descriptors_re, property_types_re, floor_story_re),
    sprintf("%s\\s*%s\\s*(%s)?", descriptors_re, floor_story_re, property_types_re)
  )
  remove_strings(address, patterns) |>
    str_squish()
}

# remove construction completion stage and handing over time
rm_construction_stage = function(address) {
  remove_strings(address, c(constr_stage_re, handover_time_re)) |>
    str_squish()
}

# remove installment payment
rm_installment_payment = function(address) {
  remove_strings(address, down_discount_payments_re) |>
    str_squish()
}

# remove distance and direction information from an address
rm_dist_direction_info <- function(address) {
  dists = c(
    "(kill?o\\s*met[ei]rs?|kms?)|(met[ei]?re?s?|m)",
    "(ኪሎ\\s*(ሜ|ሚ)ትር|ኪ[./ ]?(ሜ|ሚ)[./ ]?)|((ሜ|ሚ)ትር|ሜ|ሚ)"
  ) |>
    embrace_regex(T) |>
    sprintf(fmt = "(\\d+|few)\\s*%s") |>
    add_boundary()

  roads_en = c(
    "the\\s*(main)?\\s*(as(ph?|f)alt)\\s*(road|way)?",
    "the\\s*(main)?\\s*(road|way)",
    "wanaw\\s*(as(ph?|f)alt)?\\s*(?<!ayer)\\s*menged"
  ) |>
    combine_regex()

  roads_am = c(
    "((ከ|በ|የ)?ሚወስደው)?\\s*(ከ|የ|በ)?\\s*(?:ዋናው?|አዲሱ|ድሮው?|አሮጌው?)\\s*(?:አ?ስ[ፋፓባቫ]ል[ትቱ]|ኮብል\\s*ስቶን)?\\s*(?:[መምሚ]ን[ገግ][ድዱዲ]|አደባባ[ዩይ])\\s*(?:ላይ|ዳር|ጀርባ|በታች)?",
    # above ዋናው should be optional but for now guard against removing መንገድ following አየር
    "((ከ|በ|የ)?ሚወስደው)?\\s*(ከ|የ|በ)?\\s*(?:ዋናው?|አዲሱ|ድሮው?|አሮጌው?)?\\s*(?:አስ[ፋፓባቫ]ል[ትቱ])\\s*(?:ላይ|ዳር|ጀርባ|በታች)?",
    "((ከ|በ|የ)?ሚወስደው)?\\s*(ከ|የ|በ)?\\s*(?:ዋናው?|አዲሱ|ድሮው?|አሮጌው?)\\s*(?:አደባባ[ዩይ])\\s*(?:ላይ|ዳር|ጀርባ|በታች)?"
  ) |>
    embrace_regex(T) |>
    combine_regex()

  from_to = "(away)?\\s*f[ro]{2}m|to|ከ|g[ea]ba\\s*(b[ei]ll?o)?" |> embrace_regex(T)
  direction = "ላይ|[jg]erba|ጀርባ|(ወደ|በስ[ተከ])\\s*(ግራ|ቀኝ|ውስጥ)" |> embrace_regex(T)
  verbs = c(
    "((ወረድ|ገባ|ብሎ)\\s*ብሎ)?የ?ሚገ[ኝይ]",
    "(ወረድ|ገባ|ከፍ)\\s*(ብሎ|እንዳሉ)?\\s*(ያለ|ይላል)",
    "(ወረድ|ገባ|ከፍ)\\s*(ብሎ|እንዳሉ)"
  )
  # combine
  road = c(roads_en, roads_am) |>
    combine_regex() |>
    embrace_regex(T)
  dist = dists |>
    combine_regex() |>
    embrace_regex(T)
  verb = verbs |>
    combine_regex() |>
    embrace_regex(T)
  rxs = c(
    # ከዋናው አስፋልት 100 meters ገባ ብሎ
    sprintf(
      "%s?\\s*%s\\s*%s\\s*(%s)?\\s*%s", from_to, road, dist, direction, verb
    ),
    # 20km from * * *
    sprintf(
      "%s\\s*%s(\\s*%s?\\s*%s?\\s*%s?)?", dist, from_to, road, direction, verb
    ),
    # 20km (from) ገባ ብሎ
    sprintf("%s\\s*%s?\\s*%s?", dist, from_to, road),
    # ዋናው መንገድ ላይ
    sprintf("%s\\s*%s", roads_am, verbs),
    # ወደ "ለጋሃር" በሚወስደው መንገድ
    "ወደ\\s*.*?\\s*(ከ|በ|የ)?(ሚወስደው|ሚያስወርደው)\\s*መንገድ\\s*(ላይ)?",
    "\b(ke|wede).*?menged\b"
  )
  address = remove_strings(address, rxs)
  return(str_squish(address))
}


# Remove them if present anywhere in the address
rx_miscs = c(
  # Numerical expressions related to properties ----
  ## condominium schemes
  "^(40\\s*/?\\s*60|20\\s*/?\\s*80|10\\s*/?\\s*90)\\s*(ቤት|ኮንዶ.*?ም)?$",
  r"{\b(\d*\s*((c|k).a[ei]|sqm|msq|m2))|(((c|k).a[ei]|sqm|msq|m2)\s*\d*)\b}",
  "\\d+\\s*ካሬ|ካሬ\\s*\\d+",
  ".(ካርታው?|ይዞታው?)(\\s*\\d*)*",
  "\\d*\\s*(k|c)arta\\s*\\d*",
  "\\b\\d+\\s*(b|blocks?)\\b",
  "\\d+\\s*(ሜ|ሜትር)\\s*(የያዘው?)",
  "\\d+\\s*ተ?ኛ\\s*(ፎቅ|ወ[ለላል]{2})?\\s*(ላይ\\s*ነው)?",
  "\\s+(ለ|ከ|በ|የ)?(ጂ|ጅ|ጀ|g)\\s*[+]?\\s*\\d*\\s*(ፎቅ|ፎቆች)",
  "\\s+(ለ|ከ|በ|የ)?(ጂ|ጅ|ጀ|g)\\s*[+]?\\s*\\d+",
  "\\b(((and|hult|sost|arat|amst|\\d+)\\s*(e?gna|ኛ)?)\\s*foke?)\\b",
  "\\b(((and|hult|sost|arat|amst|\\d+)\\s*(e?gna|ኛ)?)\\s*(zure?|ዙር))\\b",
  "\\d+\\s*[%]",
  "\\d*\\s*(.መት|ወር)\\s*(የሞላው|የሆነው)",
  "\\b\\d+\\s*mil(lion)?\\b",
  "\\d*\\s*(Birr|ETB|ብር)?\\s*ገቢ\\s*(የ|ያ)ለው",
  "\\b[0-9.,\\s]*(birr|ETB)\\b",
  "ከ\\s*\\d+\\s*ብር\\s*(ጀምሮ|በላይ|በታች)?",
  # Address and location descriptions ----
  "(the)?\\s*new\\s*city",
  "besides?\\s*the\\s*main\\s*road",
  "middle\\s*of|the\\s*middle|in\\s*front\\s*of",
  "(down|mid)\\s*town\\s*(of)?",
  "the\\s*main\\s*road",
  "(be|ye)?\\s*miwesdew|miwosdew",
  "\\d+\\s*(ኪ.?)?\\s*ሜ(ትር)?",
  "የ?\\s*\\d*\\s*(ሰ.ት|ደቂቃ)\\s*(መንገድ)",
  "በ?እግር\\s*የ?\\d*\\s*ደቂቃ\\s*(መንገድ)?",
  "\\d+\\s*(ደ(ቂ|ቃ|ቄ){2}|ሰአት|hours?|minutes?)",
  "(በ|ለ|የ|ከ)?(ሚያ(ስ|ሰ)ወር(ደ|ድ)ው?|ሚወ(ስ|ሰ)(ደ|ድ)ው?|ሚ(ደ|ድ)ርሱበት|ሚገባው?)\\s*(መን(ገ|ግ)ድ)?",
  ".?(ሚ.ስ..?ው|ሚወ..ው|ሚያ.ጣው?|ሚያስ.(ደ|ድ)ው?)\\s*(መንገድ.?\\s*ላይ)?",
  "መ(ወ|ው|ም)(ጫ|(ጭ|ጨ|ጪ)ያ)\\s*(መን(ገ|ግ)ድ)?",
  "(መሄጃ|መውረጃ)\\s*(መን(ገ|ግ)ድ)?",
  ".ሚገኘው\\s*መንገድ\\s*(ዙሪያ|አካባቢ|ሰፈር)?",
  ".ሚያስወጣው\\s*መንገድ",
  "((ከበ|በ|ከ)ስተ)?\\s*(ጀርባ|ጀረባ)\\s*(አካባቢ|ሰፈር|መንደር)?",
  "በስተ\\s*(..)\\s*(መንገድ)?",
  "መስቀለኛው?\\s*(.?መንገድ)?",
  ".ሚነሳው?|.ሚያገኘው|ማእዘን",
  "(በ|የ|ከ)?ሚውስደው?",
  "(የ|ከ|በ|ለ)ሚገኘው?",
  "(ከ|ለ|በ|የ)መንገድ",
  "መንገድን|መንገዱን?",
  "ሌላ\\s*መንገድ\\s*አለው",
  "ከ?መ(ደ|ድ)(ረ|ር)ሱ|ሲ..ሱ|ሳይ..(ስ|ሱ)",
  "(በ?(መ|ም|ማ)(ሃ|ሀ|ሐ)(ከ|ክ)?ል|መካከ?ል)\\s*(?:ከተማ)?",
  ".?(አዲሱ|አሮጌው?|ድሮው?)\\s*ሳይ(ት|ታችን)",
  "የዞረውና?|የዞረና?|የተጠናቀቀው?|የተጠናቀቀና?",
  "ያሉበት\\s*(አካባቢ|ሰፈር|መንደር)",
  ".?(አ|ሀ)(ስ|ሰ)(ፋ|ባ|ፓ|ፖ|ቫ|ፍ).(ት|ቱ)|አስፓል|ስፓልት|አስባል|አስታልት",
  "\\b(as(ph|f|v|b)(a|e|u|i)?le?l?t|asepalet)\\b",
  "(k|c)obb?(e|i)?ll?e?\\s*stones?",
  "ኮብል\\s*ስ(ቶ|ተ)ን\\s*(መንገድ)?",
  "መታጠፊያ",
  "ግልባጭ",
  "ሲ.ዱ",
  "ሲመ(ጣ|ጡ)",
  "እንደተጓዙ",
  "ያገኙታል",
  "እ?ርቀት",
  "የሚርቅ",
  "ወረድ|በ?(ውስጥ|ቅርብ)",
  "(ቅርብ|አቅራቢያ)",
  "((አ|ሀ)(ተ|ጠ|ጥ)(ገ|ግ)ብ)",
  "(ከ|በ)?ፊት\\s*(ለፊ(ት|ቱ))?",
  "መ(ግ|ገ)(ቢ|ብ|ብ)ያ\\s*(መንገድ)?",
  "ቅያስ",
  "ተሻግሮ",
  "እይታ",
  "ፊቱ\\s*(ወደ)?\\s*ፀሀይ",
  "ወደ\\s*ፀሀይ",
  "ግራው.ድ",
  "ድልድዩ\\s*አካባቢ",
  "(ገባ|ከፍ)\\s*(ብለው?|ተ?ብሎ|ብ.)",
  "ተ?ብለው|ተ?ብሎ",
  "ዝቅ",
  "ከፍ",
  "ትይዩ",
  "(ከ|በ|ለ|የ)?ኋላ.?",
  "yemigegne?|yigegnal",
  "^(ሰፈር|sefer)",
  "ሎኬ(ሽ|ሺ)ን",
  "ዳውንታ(ው|ወ)ን",
  # Descriptors, features, and property types
  "(bed|bath|living)?room",
  "(price|rent|urgent|cheap|discount(s|ed)?|map|location|address)",
  "(buil(d|t)\\s*on|constructed|completed|renovated|demolished|h-type|with\\s*services?)",
  "ኤል\\s*ሸፕ|l\\s*(shape|shep)",
  "ኤል\\s*(ላይ)?\\s*ያረፈ",
  "arif\\s*layi?",
  "\\bdo.um.*?t\\b",
  "(ዶ|ደ|ድ)(ክ|ከ)[ሜመማ].*?ት",
  "higawi\\s*karta",
  "\\byell?ema\\s*(sefer)?\\b",
  "le\\s*belete\\s*mereja",
  "mortgage",
  "\\b[cs]en(ter|tral)\\s*bota\\s*(new)?\\b",
  "\\bsafe\\s*(house|bet)\\b",
  "\\bbota\\b",
  "\\bstart\\b",
  "&nbsp; ?",
  "Ejig",
  "betinkaki",
  "\\b(g[ei]ba|b[ie]ll?o)\\b",
  "lok[ie]y?sh[ie]n",
  "layi?\\s*new",
  "\\b(be|ke|le|ye)\\b",
  "\\b(ke\\s*w(e|a)nawu?|fi?t?\\s*lef.?te?)\\b",
  "gilibach|gelebach",
  "konjo",
  "yehone",
  "\\beta\\b",
  "\\b\\d+\\s*(te)?g?na?\\b",
  "\\bzur\\b",
  "\\bbetu?\\b",
  "(በደንብ)?\\s*ተደርጎ\\s*(የ?ተሰራው?)?",
  "(ከ?አዲስ)?\\s*(.ሚሰራው?|.ተሰራው?)",
  "(ከ|በ|የ)ታሪ(ካ|ክ)ዊው?",
  "በ?አፍሪካ\\s*መዲና",
  "(አካባቢ)\\s*(በ|እ?የ|ከ|ለ)?ሆነ(ችው|ው)?|(በ|እ?የ|ከ|ለ)ሆነ(ችው|ው)?",
  "(በ|ከ|ለ|የ)?አስደናቂው?",
  "የቢዚነስ\\s*((ማ|መ)(እ|አ|ኣ)ከል)",
  "^ከተማ$|(ከ|በ|ለ|የ)ከተማዋ?",
  "((^(ቢ|ብ)ሮ\\s+)|(\\s+(ቢ|ብ)ሮ$))",
  "(የ|በ|ከ|ለ)ሚገርም",
  "(በ|የ)?(ርካሽ|ቅናሽ|ማይታመን)\\s*(ዋጋ)?",
  "(ባለ)?\\s*ግርማ\\s*ሞገስ",
  "(በቂ)?\\s*ፓርኪንግ",
  "በ?(ልስን\\s*ደረጃ|ብሎኬት)",
  "ስላብ\\s*.(ተሞላ|ተሞልቶ|ተሞልቷል)",
  "የ?ጣራ\\s*(ቢም)?\\s*የቀረው?",
  "ሴራሚክ\\s*(የቀረው?)?",
  "በመባል\\s*የሚታወቀው\\s*(አካባቢ|ሰፈር|መንደር)",
  "ፊ.*?ሽ.*?ግ\\s*(ብቻ)?\\s*የቀረው",
  "በ?ከተማ(ችን)?\\s*እምብርት",
  "በ?ዲፕሎማ..\\s*መ..ሪያ",
  "በ?(ደማቁ|ተወዳጁ|ጥንቱ|ዉቧ)\\s*(ከተማ)?",
  "በ?(ዘመነው\\s*(ደመቀው)?)\\s*ሰፈር",
  "በ?(ደጃፍዎ|ነፋሻዋማ?|ነፋሻማው?)",
  "(ነበር|ነባሩ)\\s*(ሰፈር)?",
  "የለማው?\\s*(ሰፈር|መንደር|አካባቢ)",
  # TODO: this needs improvement to not remove ቦታ that is part of a word
  "(የ?(?:ሚሆን|ሆ(ነ|ን)|ያ(ዘ|ዝ)|ቢዝነስ))?\\s*(የ?ቢዝነስ|ባዶ|ክፍት|ገራሚ|ወሳ(ኝ|ኚ)|ምርጥ|ልዩ)?\\s+ቦታው?",
  "^[ቦብበ](ታ|ተ)\\s*ው?",
  "\\s+(ዋጋ|አስቸኳይ|ይፍጠኑ|ቅናሽ|ድርድር|ያለው|ይ?ደው(ል|ሉ)|የሚገዛ|የሚከራይ|ብቻ|ክፍል|አድራሻ|በጣም|ቆንጆ|ምር+(ጥ|ጡ)|የ?(ድሮው?|አሁን))\\s+",
  "እዳ\\s*(የዘጋ|(ያ|አ)ለው|የሌለው|የለውም|የጨረሰ|የተከፋለ(ለት)?|ያለበት|የሌለበት)",
  "የ?ልማት\\s*ተነ(ሽ|ሺ)",
  "\\bነዉ\\b|\\bብ[ርሩ]\\b|ተፈልጎ",
  "((ድ|ዲ)ጅታል)?\\s*ካርታ\\s*(የያዘ|(አ|ያ)ለው)\\s*(ቤት)?",
  "(የለማው?|ምቹ|አሪፍ|ቆንጆ|የ?መኖ(ሪ|ር)ያ)\\s*(ሰፈር|መንደር|አካባቢ)",
  "ለ(ትርፍ|ትረፈ)\\s*(የ?ሚሆን)?\\s*(ቤት|ኮንዶምኒየም|ቪላ|አፓርትመንት)?",
  "የኢንቨስትመንት",
  "የ?ንግድ\\s*(ሱቅ|ቤት)",
  "(የ|ለ|ከ|በ)ንግድ\\s*(ቤ(ቶ|ት).?)?",
  "ለ(ንግድ|መኖ[ሪር]ያ?)ም?",
  "የ?(ንግድ|ሱቅ)\\s(ቤት|ቦታ)",
  "ለ(አፓርታማ|መጋዝን)",
  "ሰር(ቪ|ቪ|ብ|ቢ)(ሱ|ስ)\\s*(ቤት)?",
  "ቪላ\\s*ቤት",
  "አፓርትመንት",
  "ሱቆች|ቤቶች|ቪላዎች|አፓርትመንቶች",
  "ለቤት.",
  "^ኤል\\s+|\\s+ኤል\\s+|\\s+ኤል$",
  "የገበያ\\s*ማእከል",
  "ጀምሮ",
  "(አ?ስ?ገራሚ)?\\s*አቀማመጥ",
  "አዲስ\\s*የተሰራው?",
  "በ?ቆርቆሮ\\s*የታጠረው?|በ?ቆርቆሮ|የ?ታጠረው?",
  "በሽያጭ\\s*ላይ\\s*ነ[ንው]",
  "(ዘናጭ|የዘነጠ|ዝንጥ|ተመራጭ)",
  "(ቅንጡ|ፅድት|በደንብ)",
  "በ?ማስታወቂያ",
  "ማህተም",
  "ዘመናዊ",
  "እጅግ",
  ".?ጥራት",
  "ትል(ቅ|ቁ)",
  "(ት|ቲ)(ን|ኒ)ሽ",
  "በጣም",
  "(ወይም|ደግሞ)",
  "(በ|ከ|ለ|በ)ጥንታዊ(ትዋ|ት|ው)?",
  "ግንቦታው?",
  "እስላብ",
  "(ባለ)?\\s*እ(ጣ|ዳ)",
  "ያ[ገጋግ]ባ",
  "(ባ|በ)አ?ዲሱ",
  "የያዘው?",
  "(ዲ|ድ|ደ)(ጅ|ጂ)ታል",
  "የ?ስም\\s*ማዞሪያ",
  "ዙሪያ",
  ".መኖርያ",
  "^(በር|ቤት)$",
  "አማራ(ጪ|ጭ)ው?",
  "አሪ(ፉ|ፍ)",
  "አለ\\s*የተባለ",
  "ተፈላጊ",
  "ፖርቲሽን",
  "ፓር..ግ",
  "የ?ተቀየረለት",
  ".መጨረሻው?",
  ".መጀመሪያው?",
  "ንግድ\\s*ባንኩ",
  "ኮምፓውንድ",
  "በ?ኢምባሲ.ች",
  ".ተከበበው",
  "አለም\\s*አቀፍ",
  "ወደ\\s*ከተማ",
  "በ(ብ|ቡ)ዙ|በ?ብዛት",
  "(ከ|የ|በ|ለ)ሙሉ",
  "የሚያሳይ",
  "የቪው",
  "አማራጮች",
  "ያሉት",
  "በተለምዶ",
  "በሚለው|በሚጠራው",
  "\\+sከነ\\s+",
  "(ከነ)?\\s*?እቃዉ",
  "አስቸኳይ",
  "ያለቀ",
  "እድል",
  "ምርጥ|መርጢ|ሚረጢ|ሚርጥ",
  ".?(ዋ|ዎ)ናው?ን?",
  "(ኤል)?\\s*የተጣራ",
  "\\s+እን.ን\\s+",
  "ደስ\\s*አላ(ቹ|ችሁ)",
  "እንዲሁም",
  "አዋጭ",
  "ይዘን",
  "እንጠብቃቸዋለን",
  "ጥቂት",
  "በመጣው",
  "(ያ|ባ|ካ|ላ)ለው",
  "የገ[በባ]ሬ",
  "የልማት\\s*ተ.ሺ",
  ".?ኮሬው",
  "እ.ታው",
  "አከፋፈል",
  "አለ\\s*ከ?ሚባሉት",
  "ምቹ\\s*የ?ሚባሉት",
  "ሰፈሮች",
  "መምህራን\\s*ምሪት",
  "ማስረከቢያ",
  "package",
  ".ተንጣለለ",
  "ቀርተ(ውናል|ዋል)",
  "\\S?ከተማው",
  "ምርጫዎ?",
  "ለፍተው",
  "ጥረው|ግረው",
  "ያፈሩትን?",
  "ጥሪትዎን?",
  "በምን",
  "ማዋል",
  "አስበ(ዋል|ው)",
  "ለዚህማ?",
  "ጊዜ.ን?",
  "የሚመጥን",
  "አስተማማኝ",
  "የ?ሚያደርግ(ዎትን)?",
  "ትርፋማ",
  "እንዳያመልጥ(ዎ|ወ)ት?",
  "ደማቋ",
  "(ከ|ለ|በ|የ)?መብራቱ",
  ".?(ፎቆቹ|ፎቅ|ፎቁ)",
  "ጥን?ቅቅ",
  "[ከለበየ]ትራፊ[ክኩ]",
  ".?ባንክ\\s*አለበት",
  "የ?ባንክ\\s*አለው",
  "emigerm",
  "bota\\s*lay",
  "yewana",
  "g[ei]*l[ie]*bach?",
  "ኮ[ኑሙመንም]?[ፓፐፖ][ዋወው]ንድ",
  "ሙሉ\\s*.ቢ\\s*ቤት",
  "አቀማመጡ",
  "የ?ወጣ\\s*ቦታ",
  "ካሬ\\s*ሜትር",
  "ሼፕ",
  "ለሁለት",
  "መቆረጥ",
  "የሚችል",
  "teshagro|tesagro",
  "የ?ተ?ንጣለለው",
  "\\d*\\s*kare\\s*\\d+\\b",
  "[ውወ]ደ\\s*ታ[ቺች]",
  "ሲወርዱ",
  "ውድ\\s*ያላቸው",
  "መንገድ\\s*ዳ[ረር]",
  "bekegn",
  "bekul",
  "\\bbale\\b",
  "መኻል",
  "ጥሩ\\s*ይግዙ",
  "\\bcompound\\b"
)

rm_miscs = function(address) {
  rx_miscs = embrace_regex(rx_miscs, T)
  # rx_miscs = c(
  #   add_boundary(rx_miscs, boundary = "\\s"),
  #   paste0("^\\s", rx_miscs),
  #   paste0("\\s", rx_miscs, "$")
  # )

  address = remove_strings(address, rx_miscs)
  return(str_squish(address))
}

# Function to remove common address directions
# Define common patterns found in addresses
common_patterns = c(
  c(
    "(?:in|at)?\\s*the\\s*(middle|back|heart|front|hub|center|centre)\\s*(of)?",
    "(?:in|at)?\\s*(the)?\\s*(middle|back|heart|front|hub|center|centre)\\s*(of)?\\s*(the)?\\s*city",
    "(right)?\\s*next\\s*(to)?",
    "\\d+\\s*from\\s*the\\s*main\\s*road",
    "few\\s*meters?\\s*away\\s*from",
    "on\\s*the\\s*road\\s*(to|from)",
    "on\\s*the\\s*(side|way)",
    "side\\s*(road\\s*on)?",
    "inside\\s*(compound)?",
    "wede?\\s*w(e|i)s(e|i)?t\\s*g(e|i)?ba\\s*b(e|i)?ll?o",
    "closer?",
    "m(e|e)?ngede?",
    "side\\s*of",
    "up\\s*hill",
    "a(?:k|ch)?[aei]{0,2}b(a|e)b[ie]?",
    "(([jg]ere?ba)|behind)",
    "ar{0,2}ound\\s*(?:the)?",
    "[il]n\\s*front\\s*(of)?",
    "ne(a|e)r\\s*(to|of)?",
    "wered\\s*(b[ie]lo)?",
    "back\\s*(of|side)",
    "asph?alt\\s*(road)?",
    "(b\\s*/\\s*n|between)",
    "mehal[a-z]?(\\s*ketema)?",
    "mehall?e?",
    "(?:on|in|at)",
    "(?:adjacent|past|ategeb|wede|lay|wust|(?<!bah[ei]r\\s)dar|gar?|by|to|from|after|before|towards?|wanaw)",
    "finish(ing|ed)"
  ) |> add_boundary(),
  c(
    "(በ(ስተ)?)?\\s*(ጀርባ|ቀኝ|ግራ|ሰሜን|ደቡብ|ም(ስ|ሥ)ራቅ|ም(እ|ዕ)ራብ)",
    "(?:\\d+.?ኛ)?\\s*(ፍቅ|ፍሎር|ወለል)?\\s*ላይ",
    "(?:\\d+.?ኛ)?\\s*(ፍቅ|ፍሎር|ወለል)",
    "በ?ታች(ኛው)?",
    "አለፍ\\s*(ብሎ)?",
    "ትንሽ\\s*ገባ",
    "ገባ\\s*(ይላል|ያለ)",
    "(በ|የ|ከ)?ርቀት",
    "ይገኛ(ል|ን)|.?ሚገኝ|ይላል|ያለ",
    "ግልባ(ጭ|ጪ)",
    "ሳይደረስ",
    "መስመር\\s*(ዳር)?",
    "(ቦታ|ከታ)",
    ".(ዋ|ዎ)ናው?ን?",
    "ነ(ው|ወ)",
    "ጋ(ር|ራ)?",
    "(ወደ|ገባ|ወጣ|ርቀት|በኩል|ውስጥ|ወረድ|(?<!ባህር\\s)ዳር|ጎን|ጫፍ|ጥግ)",
    "ብሎ"
  ) |> (\(.x) c(
    add_boundary(.x, boundary = "\\s"),
    sprintf("^%s\\s+", .x),
    sprintf("\\s+%s$", .x)
  )
  )()
)

rm_common_address_patterns = function(address) {
  address = remove_strings(address, common_patterns)
  return(str_squish(address))
}


# Read address typo corrections from a CSV text
typos_mapping = read.csv(
  text = r'(
regex;replacement
\b([sc][aeu]?m{1,2}[iuea]{1,2}t{1,2}[a-z]?)\s*(\d+)?\b; semit \2
\b(samit|semi)\b; semit
summit|semit; semit
semit 72 (yeka|bole)? addis ababa; semit 72
\b(aye?[ty]|ha?yate?)\b; ayat
f[ei]?ye?l\s*bet; fiyel bet
^72\s*(area|condominium|sefer|akababi|site)?$; semit 72
semit fiyel (yeka|bole)? addis ababa; semit fiyel bet
\b(w[ae]sse[nm]|wa?sn)\b; wesen
\bs[ea]?f[eai]?r.*?\b; sefer
add?e?bab[ae](y|i); adebabay
kaliti; kality
akaky|aqaqi|acach?i; akaki
አካቂ|አቃኪ|አካኪ; አቃቂ
\bsh[ea]*g{1,2}[ea]r{1,2}\b; sheger
\byaka\b; yeka
\bj[aeo]m{1,2}o\b; jemo
\blaph?to\b; lafto
ledeta; lideta
\badd?i?ss?\s*ab[ae]b[ae]\b; addis ababa
\badd?i?ss?e?\b; addis
\b(oromia)?\W*finfinne\b; addis ababa
mar[i]?yam[n]?; mariam
[x]t[ae]fo; tafo
\bcoyy?e\b; koye
[ኮከ][የዬ]\s*[ፈፌ][ቼቸጨጬ]; ኮየ ፈጬ
koyy?e\s*f[a-z]{2}t?ch?e; koye feche
\bme?genag[a-z]?a\b; megenagna
\bgeb[a-z]?r[a-z]{0,2}l\b; gebrael
[ገግ][ብበቤቢ][ረራሬርሩ][ኤኢአ]?ል; ገብርኤል
[ገጉጊጋጌግጎ][ፈፉፊፋፊፍፎ]\s*ገብሬል; ጎፋ ገብርኤል
me?d[a-z]?h[a-z]?n[a-z]{0,2}l[a-z]?m; medhanialem
\bf[a-z]?r[a-z]{0,2}say\b; ferensay
\bs[a-z]?l[a-z]?ss?[iea]{1,2}\b; selassie
\bselk\b; silk
\bg[ea]?l[ae]ne?\b; gelan
\bmaxoria\b; mazoria
\bn/s/l\b; "nifas silk lafto"
\bn/s/?\b; "nifas silk"
\bnsl\b; nifas silk lafto
\bnfs\b; nifas silk lafto
^[ንነ](ፋስ)?[\s[:punct:]]*ስ(ልክ)?[\s[:punct:]]*[ለላ](ፍቶ)?$; ንፋስ ስልክ-ላፍቶ
^[ንነ](ፋስ)?[\s[:punct:]]*ስ(ልክ)?[\s[:punct:]]*[ለላ](ፍቶ)?\s+; ንፋስ ስልክ-ላፍቶ
\s+[ንነ](ፋስ)?[\s[:punct:]]*ስ(ልክ)?[\s[:punct:]]*[ለላ](ፍቶ)?$; ንፋስ ስልክ-ላፍቶ
\s+[ንነ](ፋስ)?[\s[:punct:]]*ስ(ልክ)?[\s[:punct:]]*[ለላ](ፍቶ)?\s+; ንፋስ ስልክ-ላፍቶ
\bg[eu]st\b; guest
ruw?anda|ro?u?nda|e?r(a|o|u)w(o|a)nda; rwanda
we?ye?ra; weyra
አ(ካ|ከ)(ባ|በ)ቢው?; አካባቢ
\bak[ae]?b[ae]b[iye]?\b; akababi
[ፔፖፓፒ]ያሳ; ፒያሳ
piazza; piassa
ሀያት; አያት
mechanisa; mekanisa
([ሰሴሳስ])ሚት|([ሰሳ])ምት; ሰሚት
አ[ርረሪ]ባ\s*ዘጠኝ; 49
ሰባ\s*ሁለት; 72
[ሴሰሲስ][\s[:punct:]]*ኤ?[\s[:punct:]]*[ሚምሜ][\s[:punct:]]*ሲ; ሲኤምሲ
[ከኮ]ን?[ዶደዴድ][ሚምመ](ን|ኔ|ነ|ኒ)የ?ም; ኮንዶሚኒየም
\bcondenem\b; condominium
co[nm]do(minium)?s?; condominium
(ኮ|ከ).*?ውን?ድ; ኮምፓውንድ
(ዳ|ደ|ዲ|ድ|ጂ)ያ?ስ(ፖ|ፐ|ፕ|በ|ቦ|ፎ)ራ; ዲያስፖራ
(ዳ|ደ|ድ)(መ|ም|ማ)(ና|ነ); ደመና
ቶፕ\s*ቢው; ቶፕ ቪው
ta*f*o*\s*ro(z|s)*et*a; tafo rosseta real estate
(ፊ|ፍ)..ት\s*(ስ|ሰ).ን; ፍሊንት ስቶን
መ(ድ|ደ|ዳ).*ለም; መድሀኒአለም
ፓውሎስ; ጳውሎስ
መከ[ኒን]ሳ; መካኒሳ
ስላስ; ሰላሴ
ቱሉ\s*..?ንቱ; ቱሉ ዲምቱ
አ[ለላል]ም\s*ባን?ክ; አለም ባንክ
d(i|e)?n.?b.*?ua,denberwa
\b(boel|bola|ble|bo.le)\b; bole
bithel; betel
biritish; british
\b(4kelo|4k)\b; 4 kilo
4 kg; 4 kilo
4\s*kill?o; 4 kilo
6\s*kill?o; 6 kilo
\byakk?a\b; yeka
\bcotebe\b; kotebe
(g|j)erm(e|a)n|germany; germen
መስከል; መስቀል
ka[sz]+anch?i[sz]?e?; kazanchis
ካዛንቺስ; ካዛንችስ
\babuare\b; aware
\bg[ieoy]+r[iey]?g[ieo]*s\b; giyorgis
ሳይታችን; ሳይት
[ሰሳ][ፍፋ][ሪርሩ]; ሰፈር
\s+በር\s*አካባቢ;
^ሰሚት\s*(አካባቢ|በር)$; ሰሚት
^mery$; meri
\bs(a|e)nt\b; saint
(ከ)?\s*አደባ+[ይዩ]; አደባባይ
\bu\.\s*s\.?\b; us
ኤምባሲ\s*ዎች\s*(መንደር)?;
ebass?i|e[nm].?bass?[iy]; embassy
[እኤኢይ][ንም]?[ባፓ]ሲ; ኤምባሲ
[we]nglzi; british
[እኢ]ን?ግ[ሊል]ዝ; ብሪቲሽ
english\s*embassy; british council
ብሪቲሽ\s*ኤምባሲ; ብሪቲሽ ካውንስል
ሆላንድ\s*ኤምባሲ; ኔዘርላንድስ ኤምባሲ
አፍሪካን?\s*ዩኒየን; african union
አፍሪካ\s*ዮኒየን; አፍሪካ ህብረት
au\s*(ቡልጋሪያ|bulgaria); african union
bulgaria.*(african?\s*union|au)\s*(area)?; african union
አያት\s*ማሪ; አያት መሪ
yeka\s*ab.do; yeka abado
\bgoro[uw]?\b; goro
meke?lakeya; military
እ?\s*[ሪር]ል\s*እ?ስ[ቴት]+; ሪል እስቴት
ሪያል\s*እስቴትስ?; ሪል እስቴት
real\s*e?state; real estate
ለቡ\s*መብራት; ለቡ መብራት
feri?s\s*bet; feres bet
(sefer|akababi|area|ሰፈር|አካባቢ); \1
ወሎ\s*ሰፈር; ወሎ ሰፈር
አለምአቀፍ; አለም አቀፍ
22\s*(ቦሌ|bole); 22 \1
(ቦሌ|bole)\s*22; \1 22
(\d+)\s*ጋር?; \1
.d.s\s*zemen;
\bbere\b; ber
ጋዜዎ|ጋዚቦ; ጋዜቦ
እግ.ያ.*?[ርራ]\s*አ?ብ|እግዚያራብ|እግዚአራም; እግዚአብሄር አብ
(\d+)\s*ሚ\s; \1 ሜ
ሀናማርያም; ሀና ማርያም
koyefichi?e.*?\b; koye feche
^ኩየ\s+|\s+ኩየ\s+$|\s+ኩየ\s+; ኮየ
ድንበሮ; ድንበሯ
[ሀሃ]ያ\s*አ[ረሩሬር]ት; 24
ብስረተ\s*ጋብሪኤል|ብስረተ\s*ጋብሪኤል|ብስራተ\s*ገብርር|ብስራተ\s*ገብርሬ; ብስራተ ገብርኤል
gal[ea]n(ani)?; gelan
መካንሳ; መካኒሳ
weiyra; weyra
gerjy; gerji
g[ei]w[eao]rg[ei]s; giyorgis
ህፃ(?!(ናት|ን))|ህንጣ; ህንፃ
\b(others?\s*(location|place|address(es)?)?)\b;
^\d*\s*ፕሮ.ክት?\s*\d*$;
\d+\s*\+\s*\d+;
^[ከበለተየ]?ወሰን\s*(አካባቢ)?$; ወሰን ሚካኤል
22\s*ማዞ[ርሪ]ያ; 22 ማዞሪያ አዲስ አበባ
^22\W*(diplomatic)?\W*(area|akababi|main\s*road)?\W*(addis\s*ababa)?$; Haya Hulet Area
(22|24)\s*አውራሪስ\s*(ሆቴል|hotel)?|አውራሪስ\s*(ሆቴል|hotel)?\s*(22|24); Awraris Hotel, Haya Hulet
^24\s*(area|akababi|sefer)?$; 24 addis ababa
g[uo]lag[uo]l; golagol
^bole\s*.l\d+$; Bole Medhanialem
shalla; shola
ሳርቤት; ሳር ቤት
ባቲካን; ቫቲካን
(ሀይሌ)?\s*ጋርመን?ት; ሀይሌ ጋርመንት
^.?ጋርመንት$; ሀይሌ ጋርመንት
hailegaremnt; haile garement
[በብቦባ][ላለሊሌ]\s*አ[ረርራ][ብባበ]ሳ; ቦሌ አራብሳ
^(.*)\s*(?:አካባቢ|በር)$; \1
ጉርድ\s*[ሾሸሽ][ላለሌ]; ጉርድ ሾላ
ሰሚት\s*ፔፕሲ\s*(ፋብሪካ)?; Semit PEPSI Factory
Semit Giy?org[ie]s|ሰሚት [ጊገ][ዮየ]ር[ገጊ]ስ; Semit St. George Church
ሰሚት ኖህ.*; Semit Noah Real Estate
ሰሚት [ብበ]ር.ኑ.*; Birhanu Hotel Semit
ሰሚት [ካከ]ም?ብሪጅ አካዳሚ; Semit Cambrige Academy
ሰሚት መድ.ኒ..?ለም; Semit Mekane Selam Medhanialem Church
ሰሚት ሰን\s*ራይዝ; Sunrise Real-Estate Semit
ሰሚት ፊጋ; Semit Figa
ፊጋ; ፊጋ የመኖሪያ መንደር
የረር ሆምስ; Yerer Homes
ባልደራስ ሲግናል; Balderas Signal
)',
  sep = ";"
)

# Function to correct common typos in addresses
fix_address_typos = function(address) {
  # Validate typo mapping
  if (!is.list(typos_mapping) || !all(names(typos_mapping) %in% c("regex", "replacement"))) {
    stop("Typo mapping must be a list with 'regex' and 'replacement' elements.", call. = FALSE)
  }
  for (i in seq_along(typos_mapping$regex)) {
    address = gsub(
      typos_mapping$regex[i],
      typos_mapping$replacement[i],
      address,
      ignore.case = TRUE,
      perl = TRUE
    )
  }
  str_squish(address)
}


## Addis Ababa + Ethiopia including short forms rxs ----
addis_ethio_re_en = sprintf(
  "(?:Ethiopia)?[,\\s]*(?:%1$s)?\\s*(%2$s)[,\\s]*(?:Ethiopia)?",
  r"{(?:in|at)?\s*(?:the)?\s*(center|heart|hub)\s*(?:of)?|central}",
  c("Add?iss?\\s*Abb?(a|e)?bb?a?", "A[\\s./-]*A[\\s./-]?") |>
    embrace_regex(T) |>
    combine_regex()
) |>
  add_boundary()

fmts = c(
  "በ?መ(ሀ|ሃ)ል\\s*(?:ከተማ)?\\s*%s",
  "በ?መ(ሀ|ሃ)ል\\s*%s\\s*(?:ከተማ)?",
  "%s"
)
aa_am_rx = c(
  "በ?(አ|እ)(ዲ|ድ|ዱ)ስ\\s*(አ|ኣ)[በባ]{2}", "በ?አ[\\s/.-]*አ", "\\sበ?አ\\s*አ\\s", "በ?አዲሳባ"
) |>
  embrace_regex(T) |>
  combine_regex()
addis_ethio_re_am = sprintf(
  "(?:ኢትዮጵያ)?[\\s,፤]*%s[\\s,፤]*(?:ኢትዮጵያ)?",
  vapply(fmts, \(fmt) sprintf(fmt, aa_am_rx), NA_character_) |>
    embrace_regex(T) |>
    combine_regex()
)
# Correct for Addis Ababa
fix_addis = function(address) {
  address = pgsub(combine_regex(addis_ethio_re_en), " Addis Ababa ", address, ignore.case = TRUE)
  address = pgsub(combine_regex(addis_ethio_re_am), " አዲስ አበባ ", address, ignore.case = TRUE)
  return(str_squish(address))
}


# Function to remove repeated words and phrases
# TODO Could not make it work with Amharic scripts coz "\b" does not work well with them.
remove_repetition = function(text) {
  patterns = c(
    r"{(?:\b(\b[a-z]+\b(?:[[:punct:]\s]+\b\w+\b)*)[[:punct\s]+\1\b)+}",
    r"{(?:\b(\b\d+\b(?:[[:punct:]\s]+\b[a-z]+\b)+)[[:punct:]\s]+\1\b)+}",
    r"{^(?:(\b\d+\b(?:[[:punct:]\s]+\b\d+\b)*)[[:punct:]\s]+\1)+$}"
  )

  remove_repetition_ = function(txt, patterns) {
    if (is.na(txt)) {
      return(txt)
    }
    modified_text = txt
    repeat {
      previous_text = modified_text
      for (pattern in patterns) {
        modified_text = gsub(pattern, "\\1", modified_text, perl = TRUE, ignore.case = TRUE)
      }
      if (previous_text == modified_text) {
        break
      }
    }
    return(modified_text)
  }

  if (length(text) > 1) {
    return(vapply(text, remove_repetition_, character(1), patterns))
  }
  text = remove_repetition_(text, patterns)
  return(str_squish(text))
}


# Function to remove amharic preposition "በ" from the beginning of the address
rm_preposition = function(text) {
  re = "^በ(?!(ሻሌ|ቅሎ|ር))|\\b(ከ|የ|ለ)\\b|^(ከ|የ|ለ)\\s+"
  text = sub("^በ\\s*", "በ", text, perl = TRUE)
  text = sub("\\s+በ\\s+", "", text, perl = TRUE)
  text = sub(re, "", text, perl = TRUE)
  return(str_squish(text))
}

# Function to remove spaces and punct around an isolated ( ), and spaces around commas
rm_leftovers = function(x) {
  pgsub("(?<=\\()([^\\w\\p{Script=Ethiopic})(])+?", "", x) |>
    pgsub("([^\\w\\p{Script=Ethiopic})(])+?(?=\\))", "", x = _) |>
    pgsub("([\\s,]*,[\\s,]*)", ", ", x = _) |>
    pgsub("\\s*,\\s*", ", ", x = _) |>
    str_squish()
}

# Function to clean addresses by applying the above removers
clean_address = function(address) {
  message("Cleaning addresses ... Please wait this may take a while.")
  # Standardize and fix typos
  cleaned_address = cleanText(address) |>
    normalize_text() |>
    fix_addis() |>
    fix_address_typos() # important to place it here coz it corrects some common typos for the next steps

  # Remove distractions
  cleaned_address = cleaned_address |>
    rm_type_patterns() |>
    rm_property_size() |>
    rm_descriptions() |>
    rm_features() |>
    rm_floor_story() |>
    rm_construction_stage() |>
    rm_installment_payment() |>
    rm_dist_direction_info() |>
    rm_common_address_patterns() |>
    rm_miscs() |>
    # gsub(other_syms, " ", x = _, perl = TRUE) |>
    remove_repetition() |>
    rm_preposition() |>
    rm_leftovers() |>
    str_squish()

  return(cleaned_address)
}


# Geez letters/numbers normalization
mapping_chars = list(
  list(
    main = c(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100),
    s = c("፩", "፪", "፫", "፬", "፭", "፮", "፯", "፰", "፱", "፲", "፳", "፴", "፵", "፶", "፷", "፸", "፹", "፺", "፻")
  ),
  list(
    main = c("ሀ", "ሁ", "ሂ", "ሃ", "ሄ", "ህ", "ሆ"),
    s = c("ሐ", "ሑ", "ሒ", "ሓ", "ሔ", "ሕ", "ሖ"),
    s1 = c("ኀ", "ኁ", "ኂ", "ኃ", "ኄ", "ኅ", "ኆ")
  ),
  list(
    main = c("ሰ", "ሱ", "ሲ", "ሳ", "ሴ", "ስ", "ሶ"),
    s = c("ሠ", "ሡ", "ሢ", "ሣ", "ሤ", "ሥ", "ሦ")
  ),
  list(
    main = c("አ", "ኡ", "ኢ", "ኣ", "ኤ", "እ", "ኦ"),
    s = c("ዐ", "ዑ", "ዒ", "ዓ", "ዔ", "ዕ", "ዖ")
  ),
  list(
    main = c("ፀ", "ፁ", "ፂ", "ፃ", "ፄ", "ፅ", "ፆ"),
    s = c("ጸ", "ጹ", "ጺ", "ጻ", "ጼ", "ጽ", "ጾ")
  ),
  list(
    main = c("ው", "አ", "የ", "ሀ"),
    s = c("ዉ", "ኣ", "ዬ", "ሃ")
  )
)

# a named vector of the mapping where the secondary chars are the names
# and the main ones are the values
mapping_chars_vec = lapply(mapping_chars, \(x) {
  secondary_chars = unlist(x[setdiff(names(x), "main")])
  setNames(rep(x$main, length(secondary_chars) / length(x$main)), secondary_chars)
}) |>
  unlist()

non_standard_chars = names(mapping_chars_vec) |> paste0(collapse = "|")

normalize_char = function(char) {
  # check if the input is a single non-na character
  if (is.na(char) || length(char) != 1 || nchar(char) != 1) {
    stop("`char` must be a single non-NA character.", call. = FALSE)
  }

  # Find the corresponding standard char
  standard_char = mapping_chars_vec[char]

  # Check if a match was found
  if (is.na(standard_char)) {
    warning(
      sprintf("No match for `%s`. The letter/character has no replacement. Returning the input asis.", char),
      call. = FALSE
    )
    return(char)
  }

  standard_char
}

normalize_text = function(text) {
  not_na = !is.na(text)
  text_not_na = text[not_na]
  # find the positions of nonstandard amharic chars
  match_idx = gregexpr(non_standard_chars, text_not_na) |> lapply(\(x) x[x > 0])
  # replace the nonstandard amharic chars with the standard ones
  for (i in seq_along(text_not_na)[lengths(match_idx) > 0]) {
    for (m in match_idx[[i]]) {
      substr(text_not_na[[i]], m, m) = normalize_char(substr(text_not_na[[i]], m, m))
    }
  }
  text[not_na] = text_not_na
  text
}
