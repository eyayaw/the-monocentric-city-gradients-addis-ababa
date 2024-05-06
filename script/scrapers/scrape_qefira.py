import os
import time
import requests
from bs4 import BeautifulSoup
import json
from concurrent.futures import ThreadPoolExecutor, as_completed

headers = {"User-Agent": "Mozilla/5.0"}


def get_page_links(session, category_slug):
    url = f"https://www.qefira.com/{category_slug}/addis-ababa"
    response = session.get(url, headers=headers)
    soup = BeautifulSoup(response.content, "html.parser")

    # find the container of the pages
    pages_container = soup.select(
        "nav > ul.pagination > li.page-item:not(.page-item--next)"
    )
    try:
        total_pages = int(pages_container[-1].text)
    except IndexError:
        total_pages = 1
    pages_links = [url + f"?page={page}" for page in range(1, total_pages + 1)]
    print(f"Total {total_pages} page links retrieved, for category `{category_slug}`.")
    return pages_links


# scrape properties on each page
# get the list of advertised properties on each page
def get_product_links(session, page_link):
    response = session.get(page_link, headers=headers)
    soup = BeautifulSoup(response.content, "html.parser")
    product_list = soup.select(
        "div.listings-cards__list-item > div.listing-card.listing-card--tab > a[href].listing-card__inner"
    )
    product_links = [
        item.attrs["href"]
        for item in product_list
        if item.attrs["href"] not in ["#", "", None]
    ]
    return product_links


# def extract_product_json_script(soup):
#     scripts = soup.find_all('script', type='application/ld+json')
#     product_script = None
#     for script in scripts:
#         data = json.loads(script.text)
#         if isinstance(data, dict):
#             if data.get('@type') == 'Product':
#                 product_script = script
#                 break
#     return product_script


# get the json data from the script that holds json-ld data
def extract_data_from_json_link_data(soup: BeautifulSoup):
    # step: 1
    # filter for the script tag that holds json-ld data with @type of Product
    scripts = soup.find_all("script", type="application/ld+json")
    product_script = None
    for script in scripts:
        data = json.loads(script.text)
        if isinstance(data, dict):
            if data.get("@type") == "Product":
                product_script = script
                break
    # step: 2 --
    # the "description" field contains characteristics of the product in dl tag
    # the real "description" is contained in a p tag inside "description"

    if product_script is None:
        return None
    # parse the JSON-LD data from the script tag
    data = json.loads(product_script.text)

    # parse the HTML content in the description field
    soup = BeautifulSoup(data["description"], "html.parser")

    # find all the <dt> and <dd> tags
    dt_tags = soup.find_all("dt")
    dd_tags = soup.find_all("dd")

    parsed_data = {}
    # loop through the <dt> and <dd> tags and add the data to the dictionary
    for dt, dd in zip(dt_tags, dd_tags):
        key = dt.get_text()
        value = dd.get_text()

        # If the value is a list of amenities, split it into a list
        if key == "Amenities":
            value = "; ".join([li.get_text() for li in dd.find_all("li")])

        parsed_data[key] = value

    # adjust the description field, removing the parsed part
    data["description"] = "\n".join(
        [s.get_text(strip=True) for s in soup.find_all("p") if s is not None]
    )
    data["parsed_description"] = parsed_data

    # remove some unnecessary fields
    for key in ["@context", "@type"]:
        if key in data:
            del data[key]

    return data


#  get the data for each property
def get_product_data(session, property_url):
    response = session.get(property_url, headers=headers)
    soup = BeautifulSoup(response.content, "html.parser")
    # check whether the advert is not deleted
    try:
        message_text = (
            soup.select_one("div.message__content").get_text(strip=True).lower()
        )
        if message_text == "That Ad is no longer active".lower():
            print("The advert is no longer active.")
            return None
    except AttributeError:
        pass

    product_data = extract_data_from_json_link_data(soup)
    # address of the product is missing in the json-ld data
    address_container = soup.select_one("div.listing-item__address")
    try:
        sub_region = address_container.select_one(
            "span.listing-item__address-location"
        ).get_text(strip=True)
        region = address_container.select_one(
            "span.listing-item__address-region"
        ).get_text(strip=True)
        product_data["address"] = f"{sub_region}, {region}"
    except AttributeError:
        product_data["address"] = None

    return product_data


# def get_product_category_data(session, category_slug):
#     print(f"\nGetting data for category `{category_slug}` ...")
#     pages = get_page_links(session, category_slug)
#     product_urls = []
#     for page in pages:
#         product_urls.extend(get_product_links(session, page))

#     product_data = []
#     num_products = 0
#     for product_url in product_urls:
#         try:
#             product_data.append(get_product_data(session, product_url))
#         except Exception as e:
#             print(f"An error occurred: {e}")
#             pass
#         num_products += 1
#         if num_products % 10 == 0:
#             print(
#                 f"Processed {num_products} out of {len(product_urls)} total products."
#             )
#             time.sleep(0.1)

#     return product_data



def get_product_category_data(session, category_slug):
    print(f"\nGetting data for category {category_slug} ...")
    pages = get_page_links(session, category_slug)
    product_urls = []
    for page in pages:
        product_urls.extend(get_product_links(session, page))

    product_data = []
    with ThreadPoolExecutor(max_workers=8) as executor:
        future_to_url = {executor.submit(get_product_data, session, url): url for url in product_urls}
        for future in as_completed(future_to_url):
            url = future_to_url[future]
            try:
                data = future.result()
            except Exception as exc:
                print(f'{url} generated an exception: {exc}')
            else:
                product_data.append(data)
                time.sleep(1)
    return product_data



def save_category_data(category_data, category_slug, timestamp=None):
    if timestamp is None:
        timestamp = time.strftime("%Y_%m_%d")
    file_path = f"./data/housing/raw/qefira/{category_slug}_{timestamp}.json"
    os.makedirs(os.path.dirname(file_path), exist_ok=True)
    with open(file_path, "w") as f:
        json.dump(category_data, f, indent=2, ensure_ascii=False)
    print(f"Saved data for category `{category_slug}` under `{file_path}`.")


def get_category_slugs(session):
    response = session.get(
        "https://www.qefira.com/property-rentals-sales", headers=headers
    )
    soup = BeautifulSoup(response.content, "html.parser")
    slugs = [
        item.attrs["href"]
        for item in soup.select(
            "li#category-property-rentals-sales > ul.filter__category-list.filter__category-list--level-2 > li > h2 > a[href]"
        )
        if item.attrs["href"] not in ["#", "", None]
    ]
    slugs = [slug.split("/")[-1] for slug in slugs]
    return slugs


def main():
    session = requests.Session()
    # category_slugs = get_category_slugs(session)
    category_slugs = [
        "apartments-for-sale",
        "houses-for-sale",
        "apartments-for-rent",
        "houses-for-rent",
        "commercial-property-for-sale",
        "land-for-sale",
        "commercial-property-for-rent",
        "bedsitters-rooms-for-rent",
    ]
    for category_slug in category_slugs:
        category_data = get_product_category_data(session, category_slug)
        save_category_data(category_data, category_slug)
        time.sleep(1)


if __name__ == "__main__":
    main()

