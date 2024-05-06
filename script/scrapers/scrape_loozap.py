import logging
import os
import time
import requests
from bs4 import BeautifulSoup
from tqdm import tqdm
from script.helpers.helpers_scrape import my_get_text
from script.helpers.helpers_io import (
    read_json,
    setup_logger,
    write_json,
)

logger = logging.getLogger(__name__)
setup_logger(__name__, "./logs/scrapers/loozap.log")


# Constants
BASE_URL = "https://et.loozap.com/category/real-estate-house-apartment-and-land"
LINK_SELECTOR = "#postsList > .item-list .items-details h5.add-title > a[href]"
LAST_PAGE_SELECTOR = (
    "#wrapper nav > ul.pagination[role='navigation'] > li:nth-last-child(2)> a"
)
TIMEOUT = 60


class HTMLText:
    def __init__(self, url, text):
        self.url = url
        self.text = text

    def __repr__(self):
        return f"HTMLText(url={self.url})"

    def __str__(self):
        return f"HTMLText(url={self.url})"


# Fetch all links from a single page
def fetch_page_links(session, page_url, selector=LINK_SELECTOR):
    try:
        resp = session.get(page_url, timeout=TIMEOUT)
        resp.raise_for_status()
    except requests.exceptions.HTTPError as e:
        logging.error(f"HTTP Error: {e}")
        raise e
    soup = BeautifulSoup(resp.content, "html.parser")
    links = soup.select(selector)
    links = [link.get("href") for link in links]
    if not links:
        logging.info(f"No links found on page: {page_url}")
        return []
    return links


# Fetch all links across all pages
def get_links(
    session,
    base_url=BASE_URL,
    last_page_selector=LAST_PAGE_SELECTOR,
    link_selector=LINK_SELECTOR,
):
    try:
        resp = session.get(base_url, timeout=TIMEOUT)
        resp.raise_for_status()
    except requests.exceptions.HTTPError as e:
        logging.error(f"HTTP Error: {e}")
        raise e
    soup = BeautifulSoup(resp.content, "html.parser")
    # get total pages
    last_page = soup.select_one(last_page_selector).get_text()
    last_page = int(last_page)

    links_list = []
    print(f"Total pages: {last_page}")
    for page in tqdm(range(1, last_page + 1)):
        page_url = f"{base_url}?{page=}"
        links = fetch_page_links(session, page_url, link_selector)
        links_list.extend(links)
        time.sleep(1)
    return links_list


def get_html_text(session, url):
    try:
        response = session.get(url, timeout=TIMEOUT)
        response.raise_for_status()
    except requests.RequestException as e:
        logging.error(f"Error: {e}")
        raise e
    # Save the content to a file for debugging
    basename = os.path.basename(url)
    basename = basename + ".html" if not basename.endswith(".html") else basename
    filename = f"./data/housing/raw/loozap/html/{basename}"
    if not os.path.exists(filename):
        with open(filename, "wb") as f:
            f.write(response.content)
    return HTMLText(url, response.text)


def get_html_from_file(filename):
    with open(filename, "r") as f:
        html = f.read()
    return HTMLText(os.path.basename(filename), html)


# Fetch property details for a product
def get_details(html_text):
    if not html_text:
        logging.error("No response object provided.")
        return {}
    details = {"url": html_text.url}
    soup = BeautifulSoup(html_text.text, "html.parser")

    # Most details are within the main content container
    content_selector = (
        "#wrapper > div.main-container div > div.page-content.col-thin-right > div"
    )
    content = soup.select_one(content_selector)
    if not content:
        logging.error("Content container not found.")
        return details

    # Define selectors scoped within the base content
    breadcrumb_selector = "nav > ol.breadcrumb > li.breadcrumb-item:nth-child(4) > a"  # contains listing type
    title_selector = "h1 > strong"
    date_selector = "span.info-row > span.date > span[data-bs-content]"
    reference_number_selector = "span.info-row > span.category.float-md-end"
    image_urls_selector = "div.gallery-container div.bxslider-pager a > img"
    description_selector = ".col-12.detail-line-content"
    additional_details_selector = ".row.bg-light.rounded"
    tags_selector = ".row .col-12 > span.d-inline-block.border > a"
    loc_price_selector = (
        "#item-details div.items-details-info div.row .col-md-6.col-sm-6.col-6"
    )
    # Seller info selectors
    seller_info_base = (
        "div.page-sidebar-right > aside > div.card-user-info.sidebar-card"
    )
    seller_info_selectors = {
        "name": f"{seller_info_base} > div.block-cell.user > div.cell-content > span.name",
        "phone": f"{seller_info_base} > div.card-content a.btn-success[href*='https://wa.me']",
        "rating": f"{seller_info_base} > div.block-cell.user > div.cell-content span.rating-label",
    }

    details["listing_type"] = my_get_text(soup.select_one(breadcrumb_selector))
    # Extracting details within the content
    details["title"] = my_get_text(content.select_one(title_selector))
    date_published = content.select_one(date_selector)
    if date_published:
        details["date_published"] = date_published.attrs.get("data-bs-content", "")
    reference_number = content.select_one(reference_number_selector)
    if reference_number:
        details["reference_number"] = (
            my_get_text(reference_number).split(":", maxsplit=1)[-1].strip()
        )

    # Image URLs
    details["image_urls"] = [
        img.get("src") for img in content.select(image_urls_selector) if img.get("src")
    ]

    # Price and Location
    for row in content.select(loc_price_selector):
        key = my_get_text(row.select_one("h4 > span:nth-of-type(1)"))
        value = my_get_text(row.select_one("h4 > span:nth-of-type(2)"))
        if key:
            details[key] = value

    # Description
    description_element = content.select_one(description_selector)
    # Extract and clean the text
    if description_element:
        desc_content = str(description_element)
        # Replace <br> and <br/> with \n before processing
        desc_content = desc_content.replace("<br/>", "\n").replace("<br>", "\n")
        desc_soup = BeautifulSoup(desc_content, "html.parser")
        description = my_get_text(desc_soup).replace("Description", "").strip()
    details["description"] = description

    # Additional Details
    additional_details = {}
    for detail in content.select(additional_details_selector):
        key = my_get_text(detail.select_one(".col-6.fw-bolder"))
        value = my_get_text(detail.select_one(".col-6.text-sm-end.text-start"))
        if key:
            additional_details[key] = value
    details["additional_details"] = additional_details
    # Rating, reviews
    ratings = content.select_one("div.reviews-widget.ratings span.rating-label")
    reviews = content.select_one("#item-reviews-tab > h4")
    if ratings:
        details["additional_details"]["ratings"] = my_get_text(ratings)
    if reviews:
        details["additional_details"]["reviews"] = my_get_text(reviews)

    # Tags
    tags = [
        my_get_text(tag)
        for tag in content.select(tags_selector)
        if my_get_text(tag).lower() != "etc"
    ]
    details["features"] = "; ".join(tags)

    # Seller Info within the sidebar (not scoped within main content selector)
    sidebar = soup.select_one("#wrapper > div.main-container div.page-sidebar-right")
    if sidebar:
        seller = {}
        for key, selector in seller_info_selectors.items():
            element = sidebar.select_one(selector)
            if key != "phone":
                seller[key] = my_get_text(element)
                continue
            phone_href = element.get("href", "") if element else ""
            seller[key] = (
                phone_href.rsplit("?")[0].split("wa.me/")[-1] if phone_href else ""
            )
        details["seller"] = seller

    return details


if __name__ == "__main__":
    session = requests.Session()
    filepath_links = "./data/housing/raw/loozap/loozap_links.json"
    filepath_data = "./data/housing/raw/loozap/loozap_data_new.json"
    intermittents_dir = "./data/housing/raw/loozap/intermittents"

    # Fetch links
    # urls = get_links(session)
    # write_to_json(urls, filepath_links)
    urls = read_json(filepath_links)

    # Fetch details
    # data = read_json(filepath_data)
    # scraped = [item["url"] for item in data]
    # urls = list(set(urls) - set(scraped))
    data = []
    dump_freq = 1000  # 250
    dump_counter = 1
    for i, url in enumerate(tqdm(urls), start=1):
        try:
            # html_text = get_html_text(session, url)
            html_file = os.path.join(
                "./data/housing/raw/loozap/html", os.path.basename(url)
            )
            html_text = get_html_from_file(html_file)
            details = get_details(html_text)
            details["url"] = url
            data.append(details)
        except Exception as e:
            logging.info(f"Error: {e}")
            continue
        if i % dump_freq == 0 or i == len(urls):
            filename = f"{intermittents_dir}/intermittents_{dump_counter:0>2}.json"
            write_json(data, filename, overwrite=True)
            dump_counter += 1
            data = []
        # time.sleep(0.01)
