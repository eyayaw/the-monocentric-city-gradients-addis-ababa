# fix adjustbox conflict with pandoc default global Gin options
fix_adjustbox_conflict = function(x) {
  p = r"(\\begin\{adjustbox\}\{.*?\})"
  pos = grep(p, x)
  if (length(pos) > 0) {
    x[pos] = r"(\begin{adjustbox}{width=\textwidth,totalheight=\textheight,keepaspectratio})"
  }
  return(x)
}

## fixest global options
# define a dictionary and set it globally
# define also notes, not just variable names
# The function 'dsb()' is like 'glue()'
FIXEST_DICT = c(
  "(Intercept)" = "Constant",
  ln_value = "$\\ln Price$",
  ln_value_pred = "$\\ln Price$",
  dist = "$\\text{dist}$",
  ln_dist = "$\\ln \\text{dist}$",
  ln_dist_meskel_square = "$\\ln \\text{dist}$",
  ln_dist_4_kilo = "$\\ln \\text{dist (4 Kilo)}$",
  ln_dist_piassa = "$\\ln \\text{dist (Piassa)}$",
  property_typehouse = "Property type House",
  property_typeapartment = "Property type Apartment",
  size_sqm = "Floorspace ($m^2$)",
  "I(size_sqm^2)" = "Floorspace squared",
  num_bathrooms = "Num. Bathrooms",
  num_bedrooms = "Num. Bedrooms",
  num_images = "Num. Images in the ad",
  lemikura = "Lemi Kura",
  kolfekeranio = "Kolfe Keranio",
  akakikality = "Akaki Kality",
  "Full sample" = "Pooled",
  "FE" = "Fixed Effects"
)

fixest::setFixest_dict(FIXEST_DICT)

# default style of the table
my_style_tex = fixest::style.tex(
  main = "aer",
  signif.code = c("***" = 0.01, "**" = 0.05, "*" = 0.1),
  tpt = TRUE,
  notes.intro = "\\textit{Notes:} "
)

fixest::setFixest_etable(style.tex = my_style_tex, page.width = "a4")
