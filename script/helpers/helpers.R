# helpers ----
file_stem = function(path) {
  tools::file_path_sans_ext(basename(path))
}


list_files <- function(dir, pattern, ...) {
  files = dir(path = dir, pattern = pattern, full.names = TRUE, ...)
  setNames(files, basename(files))
}


ensure_dir <- function(filepath) {
  dir.create(dirname(filepath), showWarnings = FALSE, recursive = TRUE)
  filepath
}


vsprintf = Vectorize(sprintf, c("fmt"), USE.NAMES = FALSE)


# enable perl ----
psub = function(pattern, replacement, x, ...) {
  sub(pattern, replacement, x, ..., perl = T)
}

pgsub = function(pattern, replacement, x, ...) {
  gsub(pattern, replacement, x, ..., perl = T)
}

pgrepl = function(pattern, x, ...) {
  grepl(pattern, x, ..., perl = T)
}

pgrep = function(pattern, x, ...) {
  grep(pattern, x, ..., perl = T)
}

# deal with character(0) et.al ----
zero_len = function(x) {
  if (length(x) == 0) TRUE else FALSE
}

zero_len_2na = function(x) {
  ifelse(zero_len(x), NA, x)
}


# deal with strings ----

# Like `stringr::str_squish`: remove leading, trailing, and repeated whitespace.
str_squish = function(text) {
  trimws(gsub("\\s+", " ", text), "both")
}


clean_names = function(nms) {
  nms |>
    tolower() |>
    gsub(pattern = "[[:punct:][:space:]]", replacement = "_", perl = TRUE) |>
    gsub(pattern = "_{2,}", replacement = "_", perl = TRUE) |>
    gsub(pattern = "((^_)|(_$))+", replacement = "")
}

str_escape = function(x) {
  if (!is.character(x) || length(x) != 1L) {
    stop("`x` must be a len(1) character string.", call. = FALSE)
  }
  escaped = if (nchar(x) > 1L)
    paste0(paste0("\\", strsplit(x, "", fixed = TRUE)[[1]]), collapse = "")
  else if (nchar(x) == 1L)
    paste0("\\", x)

  return(escaped)
}

# Remove any punctuation from text
remove_punct = function(text, exclude = NULL) {
  punct_set = strsplit("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~", "", fixed = TRUE)[[1]]

  if (!is.null(exclude)) {
    if (!is.character(exclude) || length(exclude) != 1L) {
      stop("`exclude` must be a single character string.", call. = FALSE)
    }

    if (nchar(exclude) > 1L) {
      exclude = strsplit(exclude, "", fixed = TRUE)[[1]]
    }

    if (any(!(exclude %in% punct_set))) {
      warning("`exclude` contains characters not in the punctuation set, will be ignored.", call. = FALSE)
    }

    punct_set = setdiff(punct_set, exclude)
  }

  regex_pattern = paste0("[", paste0(paste0("\\", punct_set), collapse = ""), "]")
  cleaned_text = gsub(regex_pattern, "", text, perl = TRUE)

  return(cleaned_text)
}

# Remove any punctuation from text
remove_punctuation = function(text, exclude = NULL) {
  if (!is.character(exclude) || length(exclude) != 1L) {
    stop("`exclude` must be a string.", call. = FALSE)
  }
  # ASCII codes for all punctuation: https://ascii-code.com/
  punct_codes = c(33:47, 58:64, 91:96, 123:126)
  if (!is.null(exclude)) {
    exclude = utf8ToInt(exclude)
    punct_codes = setdiff(punct_codes, exclude)
  }
  # ]\^- may need to be escaped for PCRE and TRE complains about {}
  punctuation = intToUtf8(punct_codes)
  regex = sprintf(r"([%s])", str_escape(punctuation))
  text = gsub(regex, "", text, perl = TRUE)
  return(text)
}


clean_text = function(text) {
  # pattern for irrelevant characters
  regex = r"([^[:punct:][:alnum:][:space:]\p{Ethiopic}])"
  text = gsub(regex, " ", text, perl = TRUE)
  return(str_squish(text))
}


# A verbose parse number broadcasts whether multiple entries can be parsed for a value that is clearly separated by a delimiter. For example, "1;2;3".
parse_number2 = function(x, split = ";", fixed = TRUE, verbose = TRUE) {
  if (is.numeric(x)) {
    warning("Numeric vector cannot be parsed, returning the original input.", call. = FALSE)
    return(x)
  }
  x_parsed = readr::parse_number(x)
  if (isFALSE(verbose)) {
    return(x_parsed)
  }
  problematics = lengths(strsplit(x, split, fixed = fixed)) > 1
  if (!any(problematics)) {
    return(x_parsed)
  }
  message(
    "Multiple values could be parsed if splitted at`", split, "`for some entries. See the attr(x, 'problematic') for details.")
  prob_attr = sprintf("%s -> %s", x[problematics], x_parsed[problematics])
  x_parsed = structure(x_parsed, problematic = prob_attr)
  return(x_parsed)
}


ym_date = function(date) {
  if (!inherits(date, "Date")) {
    stop("`date` must be of a Date class.", call. = FALSE)
  }
  return(as.Date(format(date, format = "%Y-%m-01")))
}

is_outlier = function(x, times=1.5, na.rm = FALSE) {
  iqr = IQR(x, na.rm = na.rm)
  qrts = quantile(x, probs = c(.25, .75), na.rm = na.rm)
  x < (qrts[1] - times * iqr) | x > (qrts[2] + times * iqr)
}



fill_na_const = function(x, fill_fun = median, ...) {
  fill_value = fill_fun(x, ...)
  filled = data.table::nafill(x, type = "const", fill = fill_value)
  return(filled)
}



na_stats = function(x, na_strings = c("")) {
  stats =list(
    N = length(x),
    N_NA = sum(is.na(x) | x %in% na_strings))
    stats$Pct_NA = 100 * stats$N_NA / stats$N
  stats
}
