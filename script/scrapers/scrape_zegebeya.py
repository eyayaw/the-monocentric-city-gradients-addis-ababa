import os
import re
import time
import requests
from bs4 import BeautifulSoup
import json


def get_property_types(session, url):
    r = session.get(url)
    soup = BeautifulSoup(r.content, "html.parser")
    # types = soup.select("#property_types_widget-2 > ul > li a[href]")
    # only the broad groups: commercial and residential
    types = soup.select("#property_types_widget-2 > ul > li > a[href]")
    types = [t.attrs["href"] for t in types]
    keys = [t.strip("/").rsplit("/")[-1] for t in types]
    return dict(zip(keys, types))


def get_property_links(session, property_type):
    url = f"https://www.zegebeya.com/property-type/{property_type}/"

    links = []
    page = 1

    while True:
        print(f"Scraping page {page}...")

        try:
            r = session.get(url + "/page/" + str(page))
            soup = BeautifulSoup(r.content, "html.parser")
            r.raise_for_status()
        except requests.HTTPError:
            if r.status_code == 404:
                print("Looks like we've reached the end of pages.")
                break
        else:
            page_links = soup.select(
                "#properties-listing div.rh-ultra-page-content div.rh-ultra-list-box > div.rh-ultra-list-card div.rh-ultra-list-card-detail div.rh-ultra-title-address > h3 > a[href]"
            )
            links.extend([l.attrs["href"] for l in page_links])
            page += 1

    return links


def extract_property_details(session, property_link):
    response = session.get(property_link)
    soup = BeautifulSoup(response.content, "html.parser")

    PROPERTY_CONTENT_SELECTOR = "div.rh-ultra-property-content"

    PROPERTY_STATUS_SELECTOR = "div.rh-ultra-content-container div > div.rh-ultra-property-tags.rh-property-title"
    PROPERTY_ID_SELECTOR = (
        "div.rh-ultra-overview-box > div.rh-property-id > span:last-child"
    )
    CHARACTERISTICS_SELECTOR = (
        "div.rh_ultra_prop_card_meta_wrap > .rh_ultra_prop_card__meta"
    )
    DESCRIPTION_SELECTOR = "div.rh-content-wrapper p"
    FEATURES_SELECTOR = "ul.rh_property__features > li.rh_property__feature a[href]"
    AGENT_NAME_SELECTOR = "div.rh-ultra-property-agent-info h3 > a"
    AGENT_CONTACTS_SELECTOR = (
        "div.rh-ultra-property-agent-info div.rh-property-agent-info-sidebar"
    )
    ADDRESS_SELECTOR = (
        "div.rh-ultra-content-container div.page-head-inner p.rh-ultra-property-address"
    )
    NUM_IMAGES_SELECTOR = "div.rh-ultra-property-carousel.rh-ultra-horizontal-carousel-trigger[data-count]"
    MAP_DATA_SELECTOR = "script#property-open-street-map-js-extra"
    JSON_LD_SELECTOR = "script[type='application/ld+json'].yoast-schema-graph"

    def _get_text(element):
        try:
            return element.get_text().strip()
        except AttributeError:
            return None

    property_content = soup.select_one(PROPERTY_CONTENT_SELECTOR)
    property_id = _get_text(property_content.select_one(PROPERTY_ID_SELECTOR))
    property_status = _get_text(soup.select_one(PROPERTY_STATUS_SELECTOR)).replace(
        "\n", ","
    )

    characteristics = {}
    for res in property_content.select(CHARACTERISTICS_SELECTOR):
        key = _get_text(res.select_one("span.rh-ultra-meta-label"))
        value = _get_text(res.select_one("span.figure"))
        unit = _get_text(res.select_one("span.label"))
        if unit:
            value = value + "_" + unit
        characteristics.update({key: value})

    description = "\n".join(
        [_get_text(p) for p in property_content.select(DESCRIPTION_SELECTOR)]
    )

    features = "; ".join(
        [_get_text(f) for f in property_content.select(FEATURES_SELECTOR)]
    )

    agent_details = {
        "agent-name": _get_text(property_content.select_one(AGENT_NAME_SELECTOR)),
        "contacts-list": _get_text(
            property_content.select_one(AGENT_CONTACTS_SELECTOR)
        ),
    }

    images_div = soup.select_one(NUM_IMAGES_SELECTOR)
    num_images = images_div.attrs.get("data-count", 0) if images_div else 0

    # parse property_map_data mainly for property address ----
    property_address_text = _get_text(soup.select_one(ADDRESS_SELECTOR))
    property_map_data = _get_text(soup.select_one(MAP_DATA_SELECTOR))

    match = re.search(r"var propertyMapData = (\{.*\});", property_map_data)
    if not match:
        raise ValueError("JSON data not found in `property_map_data`.")

    json_data = match.group(1)
    data = json.loads(json_data)

    title = data.get("title")
    property_type = BeautifulSoup(data.get("propertyType", ""), "html.parser").text
    price = data.get("price")
    latitude = data.get("lat")
    longitude = data.get("lng")

    # parse JSON_LD_DATA for date_info ----
    json_ld_data = _get_text(soup.select_one(JSON_LD_SELECTOR))
    json_ld_data = json.loads(json_ld_data)["@graph"][0]
    date_info = {
        "date_published": json_ld_data.get("datePublished"),
        "date_modified": json_ld_data.get("dateModified"),
    }

    details = {
        "property_id": property_id,
        "property_url": property_link,
        "property_type": property_type,
        "property_status": property_status,
        "title": title,
        "price": price,
        **date_info,
        "address": property_address_text,
        "latitude": latitude,
        "longitude": longitude,
        **characteristics,
        "description": description,
        "features": features,
        "num_images": num_images,
        **agent_details,
    }

    return details


def get_category_data(session, property_type):
    print(f"Getting data for `{property_type}` properties.")
    property_urls = get_property_links(session, property_type)
    category_data = []
    print(f"Getting data for {len(property_urls)} properties.")
    counter = 1
    for property_url in property_urls:
        try:
            category_data.append(extract_property_details(session, property_url))
        except Exception as e:
            print(f"Error while scraping {property_url}: {e}")
        if counter % 25 == 0:
            print(f"Extracted data for {counter}/{len(property_urls)} properties.")
        counter += 1
        time.sleep(0.1)
    return category_data


def main():
    session = requests.Session()
    url = "https://zegebeya.com/properties-search/"
    types = get_property_types(session, url)
    timestamp = time.strftime("%Y-%m-%d")
    for type in types.keys():
        file_path = f"data/housing/raw/zegebeya/{type}_{timestamp}.json"
        category_data = get_category_data(session, type)
        os.makedirs(os.path.dirname(file_path), exist_ok=True)
        with open(file_path, "w") as f:
            json.dump(category_data, f, indent=2, ensure_ascii=False)
        print(f"Saved data for `{type}` to {file_path}")
        print("-" * 25)


if __name__ == "__main__":
    st = time.time()
    main()
    et = time.time()
    print(f"Total time: {et - st}")
