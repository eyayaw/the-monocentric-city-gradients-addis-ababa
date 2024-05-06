import json
import logging
import os
import re
import requests
import time
from bs4 import BeautifulSoup

logging.basicConfig(filename="./script/scrapers/beten.log", level=logging.DEBUG)


# apartment, land, villa, etc?
def get_property_categories():
    resp = requests.get("https://betenethiopia.com/properties")
    soup = BeautifulSoup(resp.text, "html.parser")
    property_cats = soup.select(
        'select#ptype[name="property_category"] > option[value]'
    )
    return {opt.text.strip(): opt.attrs.get("value") for opt in property_cats}


# for rent or sale?
def get_property_types():
    resp = requests.get("https://betenethiopia.com/properties")
    soup = BeautifulSoup(resp.text, "html.parser")
    property_types = soup.select("select#propertytype > option[value]")
    return {opt.text.strip(): opt.attrs.get("value") for opt in property_types}


def get_property_page_links(session, property_category_id, property_type_id):
    """Fetches URLs of all properties across pages for a specific property category and type."""
    url = "https://betenethiopia.com/advance/search"
    params = {
        "city": "1",
        "property_category": str(property_category_id),
        "property_type": str(property_type_id),
    }

    try:
        response = session.get(url, params=params)
        response.raise_for_status()
    except requests.exceptions.HTTPError as e:
        print(f"HTTP error occurred: {e}")
        return None
    except requests.exceptions.RequestException as e:
        print(f"Requests Error occurred: {e}")
        return None

    soup = BeautifulSoup(response.text, "html.parser")
    pagination_selector = "nav > ul.pagination > li.page-item > a.page-link:not([rel='next']):not([rel='prev'])[href]"
    pages = soup.select(pagination_selector)

    if pages:
        last_page_num = int(pages[-1].text.strip())
        base_page_url = response.url
        page_urls = [f"{base_page_url}&page={i}" for i in range(1, last_page_num + 1)]
    else:
        page_urls = [response.url]

    # find product URLs on each page
    property_urls = []
    # make the english page load with localization
    with session as s:
        s.get("https://betenethiopia.com/localization/en")
        print(
            f"Getting property urls from {property_category_id=} and {property_type_id=}, across {len(page_urls)} pages ..."
        )
        for page_url in page_urls:
            response = s.get(page_url)
            soup = BeautifulSoup(response.text, "html.parser")
            property_selector = "div.row.justify-content-center div.property-listing.list_view > a[href]"
            products = soup.select(property_selector)
            for product in products:
                property_url = product["href"]
                property_urls.append(property_url)
        print(
            f"Extracted {len(property_urls)} property urls for {property_category_id=}, {property_type_id=}."
        )

    return property_urls


def get_property_details(session, property_url):
    try:
        response = session.get(property_url, timeout=15)
        response.raise_for_status()
        soup = BeautifulSoup(response.text, "html.parser")
    except requests.exceptions.HTTPError as e:
        print(f"HTTP error occurred: {e} for {property_url}.")
        return None
    except requests.exceptions.RequestException as e:
        print(f"Requests Error occurred: {e} for {property_url}.")
        return None

    # extract property details
    property_details = {}

    # about property
    title = soup.select_one("div.property_block_wrap div.block-body > p").text.strip()
    property_details["title"] = title

    property_type = soup.select_one(
        "div.property_info_detail_wrap.mb-4 > div > div > h5"
    ).text.strip()
    property_details["property_type"] = property_type

    property_address = soup.select_one(
        "div.property_info_detail_wrap.mb-4 > div > div > span"
    ).text.strip()
    property_details["property_address"] = property_address

    property_code = soup.select_one(
        "div.property_info_detail_wrap.mb-4 > div > div > strng"
    ).text.strip()
    property_details["property_id"] = property_code.split(":")[-1].strip()

    price = soup.select_one("div.side-booking-header h3.price").text.strip()
    price_off = soup.select_one(
        "div.side-booking-header h3.price > span.offs"
    ).text.strip()
    property_details["price"] = price.rsplit(price_off, 1)[0].strip()
    property_details["price_off"] = price_off

    # extract property features
    features = soup.select("#floor-option div.floor_listeo > ul > li")
    for feature in features:
        feature = feature.text.strip().split(":")
        if len(feature) != 2:
            print(f"A feature has no key or value. {feature}")
        property_details[feature[0]] = feature[1].strip()

    # extract property amenities
    amenities = soup.select(
        "div.property_block_wrap div.block-body > ul.avl-features > li"
    )
    property_details["amenities"] = "; ".join(
        [amenity.text.strip() for amenity in amenities]
    )

    # extract property publication date
    main_img = soup.select_one("div.gg_single_part.left > img#imageid[src]")
    if main_img:
        main_img_url = main_img.get("src", "")
        match = re.search(r"(\d{4}-\d{2}-\d{2})", main_img_url)
        if match:
            publication_date = match.group(1)
        else:
            logging.warning(
                f"Publication date not found in the image url: {main_img_url} for product={property_url}."
            )
    else:
        logging.warning(f"Main image not found for {property_url}.")
        publication_date = None

    property_details["publication_date"] = publication_date

    property_details["url"] = property_url

    return property_details


def get_data_category_type(session, category_id, type_id):
    product_urls = get_property_page_links(
        session, property_category_id=category_id, property_type_id=type_id
    )
    print(
        f"Getting details of {len(product_urls)} properties: {category_id=}, {type_id=}"
    )
    property_details = []
    counter = 1
    for url in product_urls:
        details = get_property_details(session, url)
        if details is not None:
            property_details.append(details)
        if counter % 10 == 0:
            print(f"Retrieved {counter}/{len(product_urls)} of properties.")
        counter += 1
        time.sleep(0.01)
    return property_details


def main():
    session = requests.Session()
    property_cats = get_property_categories()
    property_types = get_property_types()
    timestamp = time.strftime("%Y-%m-%d")

    for cat_name, cat_id in property_cats.items():
        for type_name, type_id in property_types.items():
            property_details = get_data_category_type(session, cat_id, type_id)
            file_path = f'./data/housing/raw/beten/{cat_name.lower().replace(" ", "-")}_{type_name.lower()}_{timestamp}.json'
            os.makedirs(os.path.dirname(file_path), exist_ok=True)
            with open(file_path, "w") as f:
                json.dump(property_details, f, indent=2, ensure_ascii=False)
            print(f"Saved {file_path}.")
            time.sleep(0.1)


if __name__ == "__main__":
    main()
