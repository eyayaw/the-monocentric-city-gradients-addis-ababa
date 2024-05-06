# plotting helper functions ----

gold = (1 + 5**0.5) / 2 # the golden ratio

# custom theme minimal
custom_theme_minimal = function(base_size = 11, base_family = "", ...) {
  theme_minimal(base_size = base_size, base_family = base_family, ...) +
    theme(
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(color = "gray80", linetype = "dotted"),
      panel.background = element_rect(fill = "white", color = "gray90"),
      plot.title.position = "plot",
      plot.caption.position = "plot",
      plot.title = element_text(face = "bold", size = rel(1.7), hjust = 0.5),
      plot.subtitle = element_text(size = rel(1.1)),
      plot.background = element_rect(fill = "white", color = NA),
      strip.background = element_blank(),
      strip.text = element_text(face = "bold"),
      text = element_text(color = "gray20"),
      axis.text = element_text(color = "gray30"),
      axis.line = element_line(color = "gray25"),
      axis.text.y = element_text(angle = 90)
    )
}


# saver with some defaults, aspect ratio = golden ratio
my_ggsave = function(filename, plot = ggplot2::last_plot(), width = 6, height = width / ((1 + 5**0.5) / 2), units = "in", ...) {
  message(sprintf("Saving %g x %g [%s] ...\n%s", width, height, units, filename))
  ggplot2::ggsave(filename, plot, width = width, height = height, units = units, ...)
}


get_label = function(x, math = FALSE) {
  switch(x,
    lnp = if (math) expression(italic(ln) ~ P) else "ln P",
    lnr = if (math) expression(italic(ln) ~ R) else "ln R",
    lnhpi = if (math) expression(italic(ln) ~ P) else "ln P",
    lnhri = if (math) expression(italic(ln) ~ R) else "ln R",
    x
  )
}


# maintain the same num bins for the log scale of the var as in level with
# a given bin width in the level of the var, 2km bins
binwidth_logscale = function(x, binwidth_level = 2) {
  rng = range(x, na.rm = TRUE)
  binwidth_level * diff(rng) / diff(exp(rng))
}



# legend position helper
# rescale a number to be in [0, 1]
trans = function(x, r) {
  if (r < 0 || r > 1) stop("r should be in [0,1]", call. = FALSE)
  min(x, na.rm = TRUE) + (max(x, na.rm = TRUE) - min(x, na.rm = TRUE)) * r
}
