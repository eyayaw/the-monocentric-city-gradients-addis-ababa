import json
import os
from pathlib import Path
import time
from bs4 import BeautifulSoup
import requests
import sys

from zenrows import ZenRowsClient

sys.path.append("./script/")
from helpers.helpers_io import read_json, write_json

BASE_URL = "https://ethiopiapropertycentre.com/addis-ababa"


def fetch_html_zenrows(client, url):
    try:
        response = client.get(url, timeout=15)
        response.raise_for_status()
    except requests.exceptions.RequestException as e:
        print(f"Error for {url}: {e}")
    else:
        return response.text


def fetch_html_scrapeninja(session, api_key, url, max_retries=5):
    rapidapi_url = "https://scrapeninja.p.rapidapi.com/scrape"

    headers = {
        "Content-Type": "application/json",
        "x-rapidapi-host": "scrapeninja.p.rapidapi.com",
        "x-rapidapi-key": api_key,
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
        response = session.post(rapidapi_url, json=payload, headers=headers)
        if response.status_code == 429:
            # Exponential backoff
            for attempt in range(max_retries):
                retry_after = int(response.headers.get("Retry-After", 1))
                time.sleep(retry_after)
                return fetch_html_scrapeninja(session, api_key, url)
        response.raise_for_status()
    except requests.exceptions.HTTPError as e:
        # print(response.text)
        raise Exception(f"ScrapeNinjaError: {e}")
    else:
        response_json = json.loads(response.text)
        return response_json["body"]


def get_page_links(html_content, base_page_url):
    # Parse page links from HTML
    soup = BeautifulSoup(html_content, "html.parser")
    pagination_selector = "div.wp-block.default.product-list-filters.light-gray.pPagination > ul > li > a:not([rel='next']):not([rel='prev'])"
    page_links = soup.select(pagination_selector)
    page_urls = []
    if page_links:
        last_page_link = page_links[-1].get("href")
        last_page_num = int(last_page_link.strip().split("page=")[-1])
        page_urls = [
            base_page_url,
            *[f"{base_page_url}?page={i}" for i in range(2, last_page_num + 1)],
        ]

    return page_urls


def get_product_links(html_content):
    # Parse product links from HTML
    product_link_selector = "div[itemscope] div.wp-block-body div.wp-block-content.clearfix.text-xs-left.text-sm-left > a"
    soup = BeautifulSoup(html_content, "html.parser")
    links = soup.select(product_link_selector)
    page_product_urls = [link["href"] for link in links]
    page_product_urls = [
        f"https://ethiopiapropertycentre.com{url}"
        for url in page_product_urls
        if "https://ethiopiapropertycentre.com" not in url
    ]
    return page_product_urls


def main():
    session = requests.Session()
    rapid_key = os.getenv("RAPID_API_KEY")
    # client = ZenRowsClient(os.getenv("ZENROWS_API_KEY"))
    dir_ = Path("./data/housing/raw/ethiopiapropertycentre/")
    path_urls = dir_ / "product_urls.json"
    urls = read_json(path_urls)
    urls = list(dict.fromkeys(urls))

    types = ["for-sale", "for-rent"]
    for type in types:
        # Get page links
        base_page_url = f"https://ethiopiapropertycentre.com/{type}/addis-abeba"

        # html_base_page = fetch_html_scrapeninja(session, rapid_key, base_page_url)
        html_base_page = fetch_html_zenrows(client, base_page_url)
        page_urls = get_page_links(html_base_page, base_page_url)

        # Get product links
        product_urls = []
        try:
            for page_url in page_urls:
                # html = fetch_html_scrapeninja(session, rapid_key, page_url)
                html = fetch_html_zenrows(client, page_url)
                page_product_urls = get_product_links(html)
                product_urls.extend(page_product_urls)
                # Stop if the last url is already in the list
                if page_product_urls[-1] in urls:
                    break
                time.sleep(0.1)
        except Exception as e:
            pass
        urls.extend(product_urls)
        urls = list(dict.fromkeys(urls))
        write_json(urls, path_urls)

    Path.mkdir(dir_ / "html", exist_ok=True)
    for url in urls:
        fname = (dir_ / "html" / Path(url).name).with_suffix(".html")
        if not fname.exists():
            print(f"Downloading {url} ...")
            # html = fetch_html_scrapeninja(session, rapid_key, url)
            html = fetch_html_zenrows(client, url)
            if html:
                with open(fname, "w") as f:
                    f.write(html)
            time.sleep(0.1)


if __name__ == "__main__":
    main()
