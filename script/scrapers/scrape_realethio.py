import json
from pathlib import Path
import time
import requests
from bs4 import BeautifulSoup
from tqdm import tqdm



headers = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.110 Safari/537.36"
}


def get_links():
    base_url = "https://www.realethio.com/search-result-page/"
    product_links = []
    page = 1

    while True:
        url = f"{base_url}/page/{page}/?location%5B%5D=addis-ababa"
        try:
            response = requests.get(url, headers=headers)
            response.raise_for_status()
        except requests.exceptions.HTTPError as err:
            print(err)
            break
        else:
            soup = BeautifulSoup(response.content, "html.parser")
            listings = soup.select(
                ".listing-view.grid-view.card-deck  .item-wrap  h2.item-title > a[href]"
            )
            if not listings:
                break
            product_links.extend([listing["href"] for listing in listings])
            page += 1
            time.sleep(0.5)
    return product_links


def get_product_details(product_link):
    try:
        response = requests.get(product_link, headers=headers)
        response.raise_for_status()
        soup = BeautifulSoup(response.content, "html.parser")
    except requests.exceptions.HTTPError as err:
        print(f'Error: for {product_link} - {err}')
        return
    # selectors
    title_selector = "#main-wrap > section.content-wrap.property-wrap.property-detail-v3 > div.page-title-wrap > div > div.d-flex.align-items-center.property-title-price-wrap > div > h1"

    price_selector = "#main-wrap > section.content-wrap.property-wrap.property-detail-v3 > div.page-title-wrap > div > div.d-flex.align-items-center.property-title-price-wrap > ul > li"

    listing_type_selector = "#main-wrap > section.content-wrap.property-wrap.property-detail-v3 > div.page-title-wrap > div > div.property-labels-wrap > a"

    address_sector = "#main-wrap > section.content-wrap.property-wrap.property-detail-v3 > div.page-title-wrap > div > address"

    lng_lat_selector = "#houzez-single-property-map-js-extra"

    description_selector = "#property-description-wrap > div > div.block-content-wrap"

    details_selector = (
        "#property-detail-wrap > div > div.block-content-wrap > div > ul > li"
    )

    features_selector = (
        "#property-features-wrap > div > div.block-content-wrap > ul > li"
    )

    images_selector = '#property-gallery-js a[href] > img[src]'

    product_details = {
        "title": _get_text(soup.select_one(title_selector)),
        "price": _get_text(soup.select_one(price_selector)),
        "listing_type": _get_text(soup.select_one(listing_type_selector)),
        "address": _get_text(soup.select_one(address_sector)),
        "description": _get_text(soup.select_one(description_selector)),
        "features": "; ".join(
            [_get_text(feature) for feature in soup.select(features_selector)]
        ),
        "images": [image.get('src', None) for image in soup.select(images_selector)],
    }

    for detail in soup.select(details_selector):
        key = _get_text(detail.strong).replace(":", "")
        value = _get_text(detail.span)
        if key:
            product_details[key] = value

    # date from ld+json
    ld_json = json.loads(
        _get_text(soup.select_one("script[type='application/ld+json'].yoast-schema-graph"))
    )
    if ld_json:
        product_details["date_published"] = ld_json["@graph"][0]["datePublished"]
        product_details["date_modified"] = ld_json["@graph"][0]["dateModified"]
        product_details["author"] = ld_json["@graph"][0]["author"]["name"]

    # get lng and lat from script
    lng_lat = json.loads(
        soup.select_one(lng_lat_selector)
        .text.strip()
        .split("var houzez_single_property_map = ", 1)[1]
        .split(";\nvar houzez_map_options = ")[0]
    )
    product_details["lng"] = lng_lat["lng"]
    product_details["lat"] = lng_lat["lat"]
    product_details["url"] = product_link

    return product_details

def _get_text(element):
        try:
            return element.get_text().strip()
        except AttributeError:
            return None

def main():
    product_links = get_links()
    product_data = []
    for product_link in tqdm(product_links):
        product_data.append(get_product_details(product_link))
        time.sleep(0.5) 
    dir = Path("./data/housing/raw/realethio")
    dir.mkdir(parents=True, exist_ok=True)
    
    with open(dir/"realethio_data.json", "w") as f:
        json.dump(product_data, f, indent=2, ensure_ascii=False)


if __name__ == "__main__":
    main()