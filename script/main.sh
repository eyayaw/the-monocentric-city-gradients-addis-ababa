# 1. scrape data
## Run script/scrapers/*.py

# 2. clean datasets
R -f ./script/clean_datasets.R

# 3. extract property attributes with gemini pro
python3 ./script/extract_property_attributes_gemini_async.py
python3 ./script/tidy_extracted_property_attributes_gemini.py

# 4. tidy datasets
R -f ./script/tidy_datasets.R

# 5. geocoding
# 5.1. clean property addresses
R -f ./script/clean_property_addresses.R
# 5.2. geocode property addresses
python3 ./script/geocode.py
python3 ./script/geocode_tidy.py
# 5.3. integrate geocoding
R -f ./script/integrate_geocoding.R

# 6. estimate hedonic prices
R -f ./script/hedonic_prices.R
