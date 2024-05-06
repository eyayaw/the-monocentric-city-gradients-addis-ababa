# Constants
min_price_etb = 1000
max_price_USD = 1e6 # higher price doesn't make sense for hard currency price
max_per_sqm_price_etb = 200000

max_rent_etb = 150000
max_rent_usd = 5000 # also min_rent_etb
min_sale_etb = 500000
max_sale_etb = 0.5e9

min_size_sqm = 5
min_size_sqm2 = 10
max_size_sqm = 750
min_sale_etb_building = 1e6

SIZE_SQM_FILL_VALUE = 145 # based on the data: property_data[, median(size_sqm, na.rm = T)]
valid_currencies = c("etb", "usd", "euro", "gbp")
valid_periods = c(day = "per day", week = "per week", month = "per month", year = "per year")


# https://www.numbeo.com/property-investment/in/Addis-Ababa
# https://github.com/eyayaw/cleaning-RWI-GEO-RED?tab=readme-ov-file#features
# ABRS (2020) for germany
## All in ETB per sqm
sale_ll = 2500
sale_ul = 150000

rent_ll = 25
rent_ul = 500 # about 70k per month for median size 140 sqm

size_ll = 25
size_ul = 500
