import json
import os
import time
import re
import requests
from bs4 import BeautifulSoup


headers = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.110 Safari/537.36"
}


# for-rent, for-sale, etc
def get_property_status(session):
    url = "https://www.ethiopianproperties.com/property-search/"
    payload = {"location": "addis-ababa"}
    try:
        r = session.get(url, params=payload, headers=headers)
        soup = BeautifulSoup(r.content, "html.parser")
        status = soup.select('#select-status > option[value!=""]')
        status = [t.attrs.get("value") for t in status]
    except Exception as e:
        print(f"No property status found. Error: {e}")
        status = []
    return status


# residential, commercial, land, hotel, ...
def get_property_types(session):
    url = "https://www.ethiopianproperties.com/property-search/"
    payload = {"location": "addis-ababa"}
    try:
        r = session.get(url, params=payload, headers=headers)
        soup = BeautifulSoup(r.content, "html.parser")
        types = soup.select('#select-property-type > option[value!=""]')
        types = [t.attrs["value"] for t in types]
    except Exception as e:
        print(f"No property types found. Error: {e}")
        types = []
    return types


def get_property_links(session, property_type, property_status):
    url = "https://ethiopianproperties.com/property-search/"
    payload = {
        "location": "addis-ababa",
        "type": property_type,
        "status": property_status,
    }
    r = session.get(url, params=payload, headers=headers)
    soup = BeautifulSoup(r.text, "html.parser")

    selector = "#search-results section > div.list-container.clearfix article.property-item.clearfix > h4 > a[href]"
    print(f"Getting links for {property_type=}, and {property_status=} properties ...")
    # first page
    property_links = [link.attrs.get("href") for link in soup.select(selector)]
    # the rest of pages, if any
    page_num = 2
    while True:
        r = session.get(f"{url}/page/{page_num}/", params=payload, headers=headers)
        soup = BeautifulSoup(r.text, "html.parser")
        links = [link.attrs.get("href") for link in soup.select(selector)]
        if not links:
            print(f"Reached the last page: {page_num}.")
            break
        property_links.extend(links)
        if page_num % 10 == 0:
            print(f"Gathered property links on {page_num} pages.")
        page_num += 1
        time.sleep(0.1)
    return property_links


def extract_property_details(session, property_link):
    response = session.get(property_link, headers=headers)
    soup = BeautifulSoup(response.content, "html.parser")

    def _get_text(element, strip=True):
        try:
            return element.get_text(strip=strip)
        except AttributeError:
            return None

    # CSS Selectors
    TITLE = "body > div.page-head > div > div > h1 > span"
    ID = "#overview > article > div.wrap.clearfix > h4"
    STATUS = "#overview > article > div.wrap.clearfix > h5 > span.status-label"
    PRICE_AND_TYPE = "#overview > article > div.wrap.clearfix > h5 > span:nth-child(2)"
    CHARACTERISTICS = "#overview > article > div.property-meta.clearfix > span:has(svg)"
    DESCRIPTION = "#overview > article > div.content.clearfix > p"
    ADDITIONAL_DETAILS = "#overview > article > div.content.clearfix > ul > li"
    FEATURES = "#overview > article > div.features > ul > li > a[href]"
    IMAGES = "#property-carousel-two > ul.slides > li > img[src]"
    AGENT_NAME = "#overview > div.agent-detail.clearfix > div.left-box > h3"
    AGENT_ADDRESS = "#overview > div.agent-detail.clearfix > div.left-box > ul > li"
    # No pure selector for address, sometimes found in the title, url, or description
    # constructing from region and neighborhood/town
    ADDRESS = "body > div.page-head > div > div > div > nav > ul > li:not(:first-child) > a[href]"
    MAP_DATA = "#overview > div.map-wrap.clearfix > script"
    JSON_LD = "script[type='application/ld+json'].yoast-schema-graph"

    property_title = _get_text(soup.select_one(TITLE))
    property_id = _get_text(soup.select_one(ID)).split(": ")[-1]
    property_status = _get_text(soup.select_one(STATUS))

    try:
        price, property_type = _get_text(soup.select_one(PRICE_AND_TYPE)).split("- ")
    except ValueError:
        price, property_type = _get_text(soup.select_one(PRICE_AND_TYPE)), None

    characteristics = {}
    for res in soup.select(CHARACTERISTICS):
        try:
            value, key = _get_text(res).replace("\xa0", ";").split(";")
        except ValueError:
            value = _get_text(res).strip()
            key = "unknown or sqm"
        characteristics.update({key: value})

    description = "\n".join([_get_text(p) for p in soup.select(DESCRIPTION)])

    additional_details = [_get_text(p) for p in soup.select(ADDITIONAL_DETAILS)]
    additional_details = "; ".join(additional_details) if additional_details else None

    features = "; ".join([_get_text(f) for f in soup.select(FEATURES)])
    images = [img.attrs.get("src") for img in soup.select(IMAGES)]

    agent_details = {
        "agent-name": _get_text(soup.select_one(AGENT_NAME)),
        "agent-address": _get_text(soup.select_one(AGENT_ADDRESS)),
    }

    # parse property_map_data mainly for property address ----
    property_address_text = ", ".join([_get_text(a) for a in soup.select(ADDRESS)])
    property_map_data = _get_text(soup.select_one(MAP_DATA))

    try:
        json_data = re.search(
            r"var propertyMarkerInfo = (\{.*?\})", property_map_data
        ).group(1)
        data = json.loads(json_data)
        latitude, longitude = data.get("lat"), data.get("lang")
    except (TypeError, AttributeError):
        # print("No valid `property_map_data` found or JSON data not found in `property_map_data`.")
        latitude, longitude = None, None

    # parse JSON_LD_DATA for date_info ----
    json_ld_data = _get_text(soup.select_one(JSON_LD))
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
        "title": property_title,
        "price": price,
        **date_info,
        "address": property_address_text,
        "latitude": latitude,
        "longitude": longitude,
        **characteristics,
        "description": description,
        "additional_details": additional_details,
        "features": features,
        "images": images,
        **agent_details,
    }

    return details


def get_category_data(session, property_type, property_status):
    property_links = get_property_links(
        session, property_type=property_type, property_status=property_status
    )
    category_data = []
    print(f"Getting data for {len(property_links)} properties.")
    counter = 1
    for property_link in property_links:
        try:
            category_data.append(extract_property_details(session, property_link))
        except Exception as e:
            print(f"{property_link}: {e}")
        if counter % 25 == 0 or counter == len(property_links):
            print(f"Extracted data for {counter}/{len(property_links)} properties.")
        counter += 1
        time.sleep(0.1)
    return category_data


def main():
    session = requests.Session()
    property_types = ["any"] #get_property_types(session)
    property_statuses = ["any"] #get_property_status(session)
    timestamp = time.strftime("%Y_%m_%d")
    with open("./data/housing/raw/ethiopianproperties/any_any_2024_02_04.json", "r") as f:
        data = json.load(f)
    for status in property_statuses:
        for type in property_types:
            # category_data = get_category_data(
            #     session, property_type=type, property_status=status
            # )
            category_data = []
            urls = [d['property_url'] for d in data]
            for url in urls:
                try:
                    category_data.append(extract_property_details(session, url))
                except:
                    print(url)
                    continue
                time.sleep(1)
            file_path = f"data/housing/raw/ethiopianproperties/{status}_{type}_{timestamp}.json"
            os.makedirs(os.path.dirname(file_path), exist_ok=True)
            with open(file_path, "w") as f:
                json.dump(category_data, f, indent=2, ensure_ascii=False)
            print(f"Saved data for [{status}, {type}] to {file_path}")
            print("-" * 25)


if __name__ == "__main__":
    st = time.time()
    main()
    et = time.time()
    print(f"Total time: {et - st}")
