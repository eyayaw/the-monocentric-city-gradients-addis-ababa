

<!-- README.md is generated by README.qmd. Please edit that file. -->

# Testing the gradient predictions of the monocentric city model in Addis Ababa

> [!NOTE]
>
> This repo contains replication code and data for the paper [Beze
> (2024)](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4803607).

## Requirements

- R 4.3.3

> The necessary R packages are listed in the `renv.lock` file. You can
> install them by running the following command in the R console:
>
> ``` r
> # renv::init() # to initialize renv on the project if you don't clone the repo
> renv::restore()
> ```

- Python 3.12

> The necessary Python packages are listed in the `requirements.txt`
> file. You can install them with [uv](https://github.com/astral-sh/uv):
>
> ``` bash
> uv pip install -r requirements.txt
> ```

- The order in which the scripts should be run is provided in
  [script/main.sh](./script/main.sh).

## Data

The data used in the analysis constitutes two main parts: real estate
data and building footprint data.

### Housing data

> [!IMPORTANT]
>
> ### Data availability
>
> The dataset has been published on Zenodo and can be accessed
> [here](https://zenodo.org/records/11205969).

<details>
<summary>
Variable description
</summary>

| var                            | description                                                                       | group                                            | remark                                                                                                                                                          |
|--------------------------------|-----------------------------------------------------------------------------------|--------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------|
| id                             | ID of the property (prepended with the provider name)                             |                                                  | The ID uniquely identifies properties; in the raw data, it may not have been, even within a provider.                                                           |
| listing_type                   | Listing type (for rent or sale etc.)                                              | listing and property types                       | Parsed if not provided                                                                                                                                          |
| property_type                  | Property type (house, apartment, etc.)                                            | listing and property types                       | Parsed if not provided                                                                                                                                          |
| price                          | Price of the property in local currency (Ethiopian Birr (ETB))                    | price                                            | Other currency units are converted to ETB                                                                                                                       |
| price_type                     | The type of price (fixed, negotiable, etc.)                                       | price                                            | Parsed if not provided                                                                                                                                          |
| price_adj                      | Price of the property adjusted for inflation                                      | price                                            |                                                                                                                                                                 |
| price_sqm                      | Price of the property per square meter                                            | price                                            |                                                                                                                                                                 |
| price_adj_sqm                  | Price of the property per square meter adjusted for inflation                     | price                                            |                                                                                                                                                                 |
| size_sqm                       | Floor area of the property in square meters                                       | size                                             | Imputed if not provided                                                                                                                                         |
| size_sqm_is_imputed            | Yes if the floor area of the property was imputed                                 | size                                             |                                                                                                                                                                 |
| plot_size                      | Lot size of the property in square meters                                         | size                                             |                                                                                                                                                                 |
| address                        | Address of the property (untouched as provided)                                   | address                                          |                                                                                                                                                                 |
| address_main                   | Address of the property (manually corrected or cleaned)                           | address                                          | The address of the property has been manually corrected or cleaned. Addresses for properties have been manually extracted from the description of the property. |
| address_alt                    | Address of the property (extracted with Gemini Pro)                               | address                                          | Equals to address_main if extraction failed or null                                                                                                             |
| unique_address_grp             | Address group counter                                                             | address                                          | This variable identifies properties with the same addresses.                                                                                                    |
| place_name                     | The name of the geocoded place, from the geocoding api,address                    | address                                          |                                                                                                                                                                 |
| place_id                       | The id of the geocoded place                                                      | address                                          |                                                                                                                                                                 |
| is_lng_lat_sampled             | Yes if lng,lat is sampled                                                         | address                                          | When the address is broad like Bole”                                                                                                                            |
| or even “Addis Ababa”          | a random lng                                                                      | lat sampled from the subcity or Addis polygons.” |                                                                                                                                                                 |
| subcity                        | The subcity name                                                                  | address                                          |                                                                                                                                                                 |
| lng                            | The longitude of the property location                                            | address                                          |                                                                                                                                                                 |
| lat                            | The latitude of the property location                                             | address                                          |                                                                                                                                                                 |
| date_published                 | The date the property was published on the website                                | time                                             |                                                                                                                                                                 |
| time                           | The month (formatted year-month-01) the property was published on the website     | time                                             |                                                                                                                                                                 |
| year                           | The year the property was published on the website                                | time                                             |                                                                                                                                                                 |
| quarter                        | The quarter the property was published on the website                             | time                                             |                                                                                                                                                                 |
| title                          | The title of the property ad                                                      | description                                      |                                                                                                                                                                 |
| description                    | The description of the property ad                                                | description                                      |                                                                                                                                                                 |
| num_bedrooms                   | The number of bedrooms in the property                                            | features                                         |                                                                                                                                                                 |
| num_bathrooms                  | The number of bathrooms in the property                                           | features                                         |                                                                                                                                                                 |
| num_images                     | The number of images in the property ad                                           | features                                         |                                                                                                                                                                 |
| features                       | A list of additional features of the property                                     | features                                         | A semi-colon separated list of features                                                                                                                         |
| condition                      | The condition of the property                                                     | features                                         |                                                                                                                                                                 |
| furnishing                     | The furnishing level of the property                                              | features                                         | E.g. fully furnished, semi-furnished, etc.                                                                                                                      |
| pets                           | Yes if pets are allowed in the property                                           | features                                         | Applicable to rentals. Parsed if not provided                                                                                                                   |
| floor                          | The floor location of the property                                                | features                                         | Applicable to apartments. It may refer to the number of floors in some cases.                                                                                   |
| garden                         | Yes if the property has a garden                                                  | features                                         | Parsed if not provided                                                                                                                                          |
| parking                        | Yes if the property has parking                                                   | features                                         | Parsed if not provided                                                                                                                                          |
| kitchen                        | Yes if the property has a kitchen                                                 | features                                         | Parsed if not provided                                                                                                                                          |
| elevator                       | Yes if the property has an elevator                                               | features                                         | Parsed if not provided                                                                                                                                          |
| balcony                        | Yes if the property has a balcony                                                 | features                                         | Parsed if not provided                                                                                                                                          |
| water                          | Yes if the property has water                                                     | features                                         | Parsed if not provided                                                                                                                                          |
| power                          | Yes if the property has power                                                     | features                                         | Parsed if not provided                                                                                                                                          |
| seller_address                 | The address of the seller mentioned in the ad                                     |                                                  |                                                                                                                                                                 |
| dist_meskel_square             | The distance from the property location to the CBD (Meskel Square) in km          | Distance to the CBD                              |                                                                                                                                                                 |
| dist_arat_kilo                 | The distance from the property location to the CBD (Arat Kilo) in km              | Distance to the CBD                              |                                                                                                                                                                 |
| dist_piassa                    | The distance from the property location to the CBD (Piassa) in km                 | Distance to the CBD                              |                                                                                                                                                                 |
| exchange_rate                  | Monthly Birr to USD exchange rates                                                |                                                  | Source: National Bank of Ethiopia                                                                                                                               |
| misclassified_or_outliers_flag | Yes if the property’s listing or type are thought to be misclassified or outlier. |                                                  |                                                                                                                                                                 |

</details>

If you want to reproduce the data using the scripts, you can follow the
steps below:

The primary dataset for the analysis is constructed from
[data/housing/processed/listings_cleaned.csv](data/housing/processed/listings_cleaned.csv),
a cleaned version of the scraped data from all providers. The raw data
is available in [data/housing/raw](data/housing/raw) for the providers
included in the analysis. Missing attributes in the dataset are imputed
using `gemini pro`, and the imputed data can be found in
[data/housing/processed/structured/tidy](data/housing/processed/structured/tidy/).
Finally, property addresses are geocoded using [Google Places
API](https://developers.google.com/maps/documentation/places/web-service)
and [OSM nominatim](https://nominatim.openstreetmap.org/ui/search.html).
The georeferenced data is available in
[data/housing/processed/tidy/listings_cleaned_tidy\_\_geocoded.csv](data/housing/processed/tidy/listings_cleaned_tidy__geocoded.csv).

> [!IMPORTANT]
>
> During web scraping, I tried to respect the `robots.txt` file of the
> website. See the contents in
> [data/housing/robots_txt](data/housing/robots_txt/).

<details>
<summary>
A list of real estate providers in Addis
</summary>

| name                                                                                                           | num_ads |
|----------------------------------------------------------------------------------------------------------------|---------|
| [Loozap Ethiopia](https://et.loozap.com/category/real-estate-house-apartment-and-land)                         | 75358   |
| [Cari Africa Homes](https://homes.et.cari.africa/)                                                             | 42612   |
| [AfroTie](https://play.google.com/store/apps/details?id=com.ewaywednesday.amoge.ewaywednesday&hl=en_US&gl=US)  | 30000   |
| [JIji](https://jiji.com.et/real-estate)                                                                        | 12272   |
| [Qefira](https://web.archive.org/web/20230530142104/https://www.qefira.com/property-rentals-sales/addis-ababa) | 8121    |
| [Ethiopia Property Centre](https://ethiopiapropertycentre.com/addis-ababa)                                     | 3649    |
| [Engocha](https://engocha.com/classifieds)                                                                     | 2059    |
| [Real Ethio](https://www.realethio.com/search-result-page/?location%5B%5D=addis-ababa)                         | 1585    |
| [Airbnb Addis Ababa](https://www.airbnb.com/s/Addis%20Ababa-Ababa--Ethiopia/homes?adults=)                     | 1000    |
| [EthiopianHome](https://www.ethiopianhome.com/city/addis_ababa-1/)                                             | 990     |
| [Ethiopian Properties](https://www.ethiopianproperties.com/property-type/residential/)                         | 880     |
| [Sarrbet](https://sarrbet.com/with-list-layout/)                                                               | 741     |
| [Ethiopia Realty](https://ethiopiarealty.com/search-results/?location%5B%5D=addis-ababa)                       | 717     |
| [Ermithe Ethiopia](https://ermitheethiopia.com/all-ads/listing-category/property/)                             | 645     |
| [LiveEthio](https://livingethio.com/site/property)                                                             | 625     |
| [ZeGebeya.com](https://zegebeya.com/properties/)                                                               | 560     |
| [Zerzir](https://zerzir.com/ads/real-estate/)                                                                  | 539     |
| [Real Addis](https://www.realaddis.com/property-search/)                                                       | 513     |
| [Beten](https://betenethiopia.com/)                                                                            | 495     |
| [Kemezor](https://et.kemezor.com/products?type=house&city=addis%20ababa)                                       | 434     |
| [HahuZon](https://hahuzon.com/listing-category/property-rentals-sales/)                                        | 400     |
| [Ethiobetoch](https://www.ethiobetoch.com/propertylisting)                                                     | 315     |
| [Verenda](https://www.verenda.et/)                                                                             | 285     |
| [Mondinion](https://www.mondinion.com/Real_Estate/country/Ethiopia/)                                           | 268     |
| [Yegna Home](https://yegnahome.com/search-result-page?propertyType=Apartment)                                  | 247     |
| [Expat](https://www.expat.com/en/housing/africa/ethiopia/addis-ababa/)                                         | 233     |
| [Keys to Addis](https://keystoaddis.com/search-results/?keyword=&location%5B%5D=addis-ababa)                   | 219     |
| [Ebuy](https://www.ebuy.et/properties?type=property)                                                           | 216     |
| [Addis Agents](https://rentinaddisagent.com/listing/)                                                          | 195     |
| [Rent in Addis Agent](https://www.addisagents.com/property-types/residential/)                                 | 175     |
| [Betoch](https://www.betoch.com/property/)                                                                     | 126     |
| [Sheger Home](https://shegerhome.com/)                                                                         | 120     |
| [Ethio Broker](https://www.ethiobroker.com/property/filter?is_rental=0)                                        | 105     |
| [Betbegara](https://www.betbegara.com/)                                                                        | 83      |
| [Addis Property Listings](https://addispropertylistings.com/all-properties)                                    | 76      |
| [Shega Home](https://shegahome.com/properties)                                                                 | 60      |
| [Realtor Ethiopia](https://realtor.com.et/store/)                                                              | 33      |
| [Addis Gojo](https://addisgojo.com)                                                                            | 32      |
| Notes: The number of ads is as of April 2024. Qefira shut down in June 2023.                                   |         |

</details>

### Building footprint datasets

The building variables are extracted from two sources:

- The German Aerospace Center ([DLR](https://www.dlr.de/en)): the World
  Settlement Footprint [(WSF)
  3D](https://geoservice.dlr.de/web/maps/eoc:wsf3d) and [WSF
  2019v1](https://download.geoservice.dlr.de/WSF2019/) datasets.
- [Open buildings](https://sites.research.google/open-buildings/) from
  Google.

## Citation

Please cite the paper or dataset for any use of the code or data in this
repository.

``` bibtex
@article{Beze_2024,
  title = {Testing the Gradient Predictions of the Monocentric City Model in Addis Ababa},
  ISSN = {1556-5068},
  url = {https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4803607},
  DOI = {10.2139/ssrn.4803607},
  journal = {SSRN Electronic Journal},
  publisher = {Elsevier BV},
  author = {Beze,  Eyayaw},
  year = {2024}
}
```

``` bibtex
@misc{Beze_2024_dataset,
  title = {Georeferenced real estate data for Addis Ababa},
  author = {Beze,  Eyayaw},
  year = {2024},
  doi = {10.5281/ZENODO.11205969},
  url = {https://zenodo.org/doi/10.5281/zenodo.11205969},
  publisher = {Zenodo},
  copyright = {Creative Commons Attribution 4.0 International}
}
```
