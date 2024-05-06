import json
import os
import time
import requests
from bs4 import BeautifulSoup
from urllib.parse import urljoin


def send_to_scrapeninja(session, url):
    rapidapi_url = "https://scrapeninja.p.rapidapi.com/scrape"

    headers = {
        "Content-Type": "application/json",
        "x-rapidapi-host": "scrapeninja.p.rapidapi.com",
        "x-rapidapi-key": os.getenv("RAPIDAPI_KEY"),
    }

    payload = {
        "url": url,
        "headers": ["X-Header: some-random-header"],
        "retryNum": 2,
        "geo": "default",
        "followRedirects": 0,
        "timeout": 8,
        "textNotExpected": ["random-captcha-text-which-might-appear"],
        "statusNotExpected": [403, 502],
    }

    try:
        response = session.request("POST", rapidapi_url, json=payload, headers=headers)
        response.raise_for_status()
    except requests.exceptions.HTTPError as e:
        print(response.text)
        raise Exception(f"ScrapeNinjaError: {e}")
    else:
        response_json = json.loads(response.text)
        return response_json


def get_product_links_on_page(session, page_url):
    # get product links on a page
    product_link_selector = "div[itemscope] div.wp-block-body div.wp-block-content.clearfix.text-xs-left.text-sm-left > a[href]"
    try:
        response_json = send_to_scrapeninja(session, page_url)
        soup = BeautifulSoup(response_json["body"], "html.parser")
    except Exception as e:
        print(e)
        return []
    else:
        product_links = soup.select(product_link_selector)
        product_links = [
            urljoin(page_url, link.attrs.get("href")) for link in product_links
        ]
        time.sleep(0.5)

    return product_links


def get_product_links(session, url):
    main_url = url
    product_links = []
    page_num = 1
    while True:
        try:
            new_product_links = get_product_links_on_page(session, url)
            if not new_product_links:
                break
            product_links.extend(new_product_links)
            page_num += 1
            url = main_url + f"?page={page_num}" if page_num > 1 else main_url
            if page_num % 5 == 0:
                print(f"Product urls scraped on {page_num} pages.")
        except Exception as e:
            print(f"Error occurred: {e}. Could not scrape product urls")
            break
    return product_links


def get_element_text(soup, css_selector, default=None):
    try:
        return soup.select_one(css_selector).text.strip()
    except Exception:
        return default


def get_product_details(session, product_url):
    # CSS Selectors, simplified (see scrape-ethiopiapropertycentre.py for long ones)
    PAGE_TITLE = "h1.page-title"
    CONTENT_TITLE = "div.property-details > h4"
    ADDRESS = "div.property-details > address"
    PRICE_CURRENCY = "span.property-details-price > span.price[itemprop=priceCurrency]"
    PRICE = "span.property-details-price > span.price[itemprop=price]"
    ADDITIONAL_PROPERTY = "ul.aux-info > li[itemprop=additionalProperty]"
    PROPERTY_DESCRIPTION = "p[itemprop=description]"
    PROPERTY_DETAILS = "table > tbody > tr > td"

    try:
        resp_json = send_to_scrapeninja(session, product_url)
        soup = BeautifulSoup(resp_json["body"], "html.parser")
    except Exception as e:
        print(f"No product details found for {product_url}. Error: {e}.")
        return None

    page_title = get_element_text(soup, PAGE_TITLE)
    content_title = get_element_text(soup, CONTENT_TITLE)
    address = get_element_text(soup, ADDRESS)
    price_currency = get_element_text(soup, PRICE_CURRENCY)
    price = get_element_text(soup, PRICE)

    additional_property_data = {}
    additional_property = soup.select(ADDITIONAL_PROPERTY)
    for li in additional_property:
        name = get_element_text(li, "span[itemprop=name]")
        value = get_element_text(li, "span[itemprop=value]")
        if name and value:  # add this check to avoid empty keys/values in dictionary
            additional_property_data[name] = value

    property_description = get_element_text(soup, PROPERTY_DESCRIPTION)

    property_details_data = {}
    property_details = soup.select(PROPERTY_DETAILS)
    for td in property_details:
        name = get_element_text(td, "strong").replace(":", "").strip()
        value = td.text.replace(name, "").replace(":", "").strip()
        if name and value:  # add this check to avoid empty keys/values in dictionary
            property_details_data[name] = value

    product_details = {
        "page_title": page_title,
        "content_title": content_title,
        "address": address,
        "price_currency": price_currency,
        "price": price,
        **additional_property_data,
        "property_description": property_description,
        **property_details_data,
        "product_url": product_url,
    }

    return product_details


def main():
    session = requests.Session()
    types = ["for-sale", "for-rent"]
    timestamp = time.strftime("%Y-%m-%d")
    for type in types:
        url = f"https://ethiopiapropertycentre.com/{type}/addis-abeba"
        product_links = get_product_links(session, url)
        # with open(f'ethio-prop-centre_{type}_product-links.json') as f:
        #     product_links = json.load(f)
        product_details_list = []
        counter = 1
        for product_link in product_links:
            product_details = get_product_details(session, product_link)
            product_details_list.append(product_details)
            if counter % 25 == 0:
                print(f"Retrieved details of {counter}/{len(product_links)} products.")
            counter += 1
            time.sleep(2)

        file_path = (
            f"./data/housing/raw/ethiopiapropertycentre/{type}_{timestamp}.json"
        )
        os.makedirs(os.path.dirname(file_path), exist_ok=True)
        if product_details_list:
            with open(file_path, "w") as f:
                json.dump(product_details_list, f, indent=2, ensure_ascii=False)
                print(f"Saved {len(product_details_list)} records to {file_path}.")


if __name__ == "__main__":
    main()
    print("---------- All done! ----------")
