library(fixest)
library(data.table)
source("./script/helpers/helpers.R")
source("./script/helpers/helpers_estimation.R")

# get and tidy fixed effects from a fixest object
tidy_fixeffs = function(model) {
  stopifnot(inherits(model, "fixest"))
  fixeffs = fixef(model)
  dep_var = all.vars(formula(model))[[1]]
  out = data.frame(names(fixeffs[[1]]), fixeffs[[1]])
  names(out) = c("id", dep_var)
  fixeff_vars = strsplit(names(fixeffs), "^", fixed = TRUE)[[1]]
  out[, fixeff_vars] = do.call("rbind", strsplit(out$id, "_"))
  out = out[, c(fixeff_vars, dep_var)]
  rownames(out) = NULL
  return(out)
}

# import data ----
data = fread(
  "./data/housing/processed/tidy/listings_cleaned_tidy__geocoded.csv",
  na.strings = ""
)

# cleaning ----
# Types I care about for now and have sufficient data points
listing_types = c(Rent = "for rent", Price = "for sale")
property_types = c(House = "house", Apartment = "apartment")

data = data[listing_type %in% listing_types & property_type %in% property_types, ]

## Create/transform vars ----
# Create year-month, year-quarter
data[, time := ym_date(as.Date(date_published))
][, quarter := paste0(year(time), "_q", quarter(time))]

data[, names(data) := type.convert(.SD, as.is = TRUE)] # fread my fail to auto detect types

# Call the dependent variable "value"
data[, value := price_adj_sqm][, ln_value := log(value)]
data = data[!is.infinite(ln_value), ]


# Fill NAs in numeric variables
incols = c("num_bedrooms", "num_bathrooms", "num_images")
data[, (incols) := lapply(.SD, \(x) fill_na_const(x, na.rm = TRUE)),
  .(listing_type, property_type),
  .SDcols = c(incols)
]

# Data prep
binary_vars = c("garden", "parking", "kitchen", "balcony", "elevator", "power")
data[, (binary_vars) := lapply(.SD, \(x) fifelse(is.na(x), "no", x)), .SDcols = binary_vars][, furnishing := fifelse(is.na(furnishing) | furnishing == "no", "unfurnished", furnishing)][, condition := fifelse(is.na(condition), "used", condition)]


# Estimate a hedonic model
construct_vars = function(dep_var, fixef_vars, num_vars, fac_vars) {
  vars_list = list(
    dep_var = dep_var,
    fixef_vars = fixef_vars,
    num_vars = num_vars,
    fac_vars = fac_vars
  )
  # vars_list$all_vars = c(fixef_vars, dep_var, num_vars, setdiff(fac_vars, fixef_vars))
  return(vars_list)
}

estimate_hedonic = function(data, vars_list, add_fml_terms = NULL) {
  get_vars = function(name) {
    if (!(name %in% names(vars_list))) {
      stop(sprintf("%s can't be found in the vars list.", name), call. = FALSE)
    }
    return(get(name, vars_list))
  }
  dep_var = get_vars("dep_var")
  num_vars = get_vars("num_vars")
  fixef_vars = get_vars("fixef_vars")
  fac_vars = get_vars("fac_vars")
  all_vars = c(fixef_vars, dep_var, num_vars, setdiff(fac_vars, fixef_vars))

  data[, (num_vars) := lapply(.SD, as.numeric), .SDcols = c(num_vars)]
  data[, (fac_vars) := lapply(.SD, as.factor), .SDcols = c(fac_vars)]


  # Estimation
  # construct model formula
  rhs = paste0(
    dep_var, " ~ ", paste(setdiff(all_vars, c(dep_var, fixef_vars)), collapse = " + ")
  )
  if (!is.null(add_fml_terms)) {
    rhs = paste0(rhs, " + ", paste0(add_fml_terms, collapse = " + "))
  }
  form = sprintf("%s | %s", rhs, paste(fixef_vars, collapse = "^")) |> as.formula()

  # Estimate the fixed effects model
  model = feols(form, data, combine.quick = FALSE)
  gc(verbose = FALSE)

  return(model)
}

tidy_output = function(model, data, include_all_vars = TRUE) {
  fixef_vars = all.vars(model$fml_all$fixef)
  mod_vars = all.vars(model$fml)
  dep_var = mod_vars[1]
  pred_var = paste0(dep_var, "_pred")

  fixeffs_df = tidy_fixeffs(model) # extract fixed effects

  predicted = predict(model, newdata = data)
  new_data = copy(data)
  new_data[, paste0(dep_var, "_pred") := predicted]

  if (!include_all_vars) {
    new_data = new_data[, c(fixef_vars, mod_vars, pred_var)]
  }
  setcolorder(new_data, fixef_vars)
  setcolorder(new_data, pred_var, after = dep_var)

  return(list(predicted = new_data, fixeffs = fixeffs_df))
}

# Run estimation ----
# Define required variables
dep_var = "ln_value"
fixef_vars = c("time", "subcity") # fixed-effects (individual, time, etc.)
num_vars = c("size_sqm", "num_bedrooms", "num_bathrooms", "num_images")
# factor variables
imputed_flag_vars = NULL # c("size_sqm_is_imputed", "is_lng_lat_sampled")
fac_vars = c(
  fixef_vars, "property_type", "furnishing", "condition",
  c("garden", "parking", "kitchen", "balcony", "elevator", "power"),
  imputed_flag_vars
)
additional_fml_terms = c("I(size_sqm^2)")


data_list = split(data, by = "listing_type") # split(data, by = c("listing_type", "property_type")
models = vector("list", length(data_list)) |> setNames(names(data_list))
outputs = models

out_dir = "./data/housing/processed/tidy/hedonic/"
dir.create(out_dir, showWarnings = FALSE)


for (sample in names(data_list)) {
  vars_list = construct_vars(
    dep_var = dep_var, fixef_vars = fixef_vars, num_vars = num_vars, fac_vars = fac_vars
  )
  # if (sample == "for sale") {
  #   vars_list$fac_vars = setdiff(vars_list$fac_vars, "pets")
  # }
  models[[sample]] = estimate_hedonic(data_list[[sample]], vars_list, additional_fml_terms)

  outputs[[sample]] = tidy_output(models[[sample]], data_list[[sample]])
}

hedonic = lapply(outputs, function(x) get("predicted", x)) |>
  rbindlist(use.names = TRUE, idcol = "listing_type")

hedonic_fe = lapply(outputs, function(x) get("fixeffs", x)) |>
  rbindlist(use.names = TRUE, idcol = "listing_type")

# write to disk
fwrite(hedonic, file.path(out_dir, "hedonic.csv"))
fwrite(hedonic_fe, file.path(out_dir, "hedonic_fixeffs.csv"))


notes = glue::glue("*Notes*: \\footnotesize The dependent variable is the logarithm of the property value in Birr per square meter of floorspace. The model includes {knitr::combine_words(fixef_vars)} fixed effects. It also controls for the usual structural characteristics of the property, condition, furnishing levels, and additional property amenities. Furthermore, the model accounts for the subcity in which the property is located to control for unobserved systematic differences across the subcities of Addis Ababa. The number of images is imputed for the provider Qefira. \nClustered ({paste(fixef_vars, collapse=', ')}) standard errors in parentheses. Significance levels: *** p < 0.01, ** p < 0.05, * p < 0.1.")
model_names = names(listing_types)[match(names(models), listing_types)]

rename_vars = function(x) {
  for (var in c(vars_list$fac_vars, vars_list$fixef_vars)) {
    x = gsub(paste0("(", var, ")(.)(\\w+?)"), paste0(tools::toTitleCase(var), " \\U\\2\\E\\3"), x, perl = TRUE)
  }
  return(gsub("\\s+", " ", x) |> trimws())
}

etable(
  c(models),
  file = file.path(out_dir, "hedonic_ouput.tex"),
  # title = "Hedonic Regression Results",
  # label = "tbl-hedonic-results",
  headers = names(listing_types)[match(names(models), listing_types)],
  order = c("%size_sqm.*", "%property.*type", "%num_.*"),
  postprocess.tex = \(x) rename_vars(x) |> fix_adjustbox_conflict(),
  depvar = FALSE,
  replace = TRUE,
  notes = notes,
  fontsize = "small",
  arraystretch = 0.8,
  adjustbox = TRUE,
  placement = ""
)
