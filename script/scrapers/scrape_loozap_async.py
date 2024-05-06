import asyncio
import os
import time
import requests
import logging
from bs4 import BeautifulSoup
from ..helpers.helpers_scrape import my_get_text
from ..helpers.helpers_io import read_json, write_json


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(message)s",
    filename="./logs/scrapers/loozap.log",
    filemode="a",
)


# Constants
BASE_URL = "https://et.loozap.com/category/real-estate-house-apartment-and-land"
LINK_SELECTOR = "#postsList > .item-list .items-details h5.add-title > a[href]"
LAST_PAGE_SELECTOR = (
    "#wrapper nav > ul.pagination[role='navigation'] > li:nth-last-child(2)> a"
)
TIMEOUT = 15  # Loozap's server is quite slow, a longer timeout is needed


# Fetch all links from a single page
async def fetch_page_links(page_url, selector=LINK_SELECTOR):
    try:
        response = await asyncio.to_thread(requests.get, page_url, timeout=TIMEOUT)
        response.raise_for_status()
    except requests.exceptions.HTTPError as e:
        logging.error(f"HTTP Error: {e}")
        raise e
    soup = BeautifulSoup(response.content, "html.parser")
    links = soup.select(selector)
    links = [link.get("href") for link in links]
    if not links:
        logging.info(f"No links found on page: {page_url}")
        return []
    return links


# Fetch all links across all pages
async def get_links(
    base_url=BASE_URL,
    last_page_selector=LAST_PAGE_SELECTOR,
    link_selector=LINK_SELECTOR,
):
    try:
        resp = requests.get(base_url, timeout=TIMEOUT)
        resp.raise_for_status()
    except requests.exceptions.HTTPError as e:
        logging.error(f"HTTP Error: {e}")
        raise e
    soup = BeautifulSoup(resp.content, "html.parser")
    # get total pages
    last_page = soup.select_one(last_page_selector).get_text()
    last_page = int(last_page)

    print(f"Total pages: {last_page}")
    tasks = []
    for page in range(1, last_page + 1):
        page_url = f"{base_url}?{page=}"
        task = asyncio.create_task(fetch_page_links(page_url, link_selector))
        tasks.append(task)
    links_list = await asyncio.gather(*tasks)
    return [link for links in links_list for link in links]


# Asynchronously fetch property details using requests in a separate thread
async def get_details(url):
    details = {"url": url}
    try:
        # Using asyncio.to_thread to run the blocking operation in a separate thread
        response = await asyncio.to_thread(requests.get, url, timeout=TIMEOUT)
        response.raise_for_status()
    except requests.RequestException as e:
        logging.error(f"Request Exception for {url} - {e}")
        return details
    else:
        # Save the content to a file for debugging
        basename = os.path.basename(url)
        basename = basename + ".html" if not basename.endswith(".html") else basename
        filename = f"./data/housing/raw/loozap/html/{basename}"
        if not os.path.exists(filename):
            with open(filename, "w") as f:
                f.write(response.text)

    soup = BeautifulSoup(response.text, "html.parser")
    # Most details are within the main content container
    content_selector = (
        "#wrapper > div.main-container div > div.page-content.col-thin-right > div"
    )
    content = soup.select_one(content_selector)
    if not content:
        logging.error("Content container not found.")
        return details

    # Define selectors scoped within the base content
    breadcrumb_selector = "nav > ol.breadcrumb > li.breadcrumb-item:nth-child(4) > a" # contains listing type
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


# Manage fetching all details
async def fetch_all_details(urls):
    tasks = []
    for url in urls:
        # Schedule get_details to run in a separate thread for each URL
        task = asyncio.create_task(get_details(url))
        tasks.append(task)
    details = await asyncio.gather(*tasks)
    return details


# Main async function to run the scraper in chunks
async def main(chunk_size=2500):
    data_dir = "./data/housing/raw/loozap"
    links_filepath = f"{data_dir}/loozap_links.json"
    data_filepath = f"{data_dir}/loozap_data_new.json"

    # Fetch links
    # s = time.time()
    # print("Starting to fetch links...")
    # urls = await get_links()
    # write_to_json(urls, links_filepath)
    # e = time.time()
    # print(f"Time taken to fetch links: {e - s:.2f} seconds")
    urls = read_json(links_filepath)
    # Fetch details
    # urls = read_from_json(links_filepath)
    delay = 5  # Optional delay between chunks

    data = read_json(data_filepath)
    scraped = [item["url"] for item in data]
    urls = list(set(urls) - set(scraped))
    # Create chunks of URLs
    chunks = [
        urls[i : i + chunk_size] for i in range(0, len(urls), chunk_size)
    ]
    s = time.time()
    print(f"Total links to scrape: {len(urls)}")
    print("Starting to fetch details ...")
    for chunk_index, chunk in enumerate(chunks, start=1):
        tasks = [get_details(url) for url in chunk]
        details = await asyncio.gather(*tasks)
        write_json(details, f"{os.path.splitext(data_filepath)[0]}_{chunk_index:0>2}.json", overwrite=True)
        print(f"Completed and saved chunk {chunk_index}.")
        await asyncio.sleep(delay)
    e = time.time()
    print(f"Time taken to fetch details: {e - s:.2f} seconds")


if __name__ == "__main__":
    asyncio.run(main())
