import time
import requests
import sys

sys.path.append("script")
from helpers.helpers_io import list_files, write_json, read_json


headers = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0.2 Safari/605.1.15",
}


def get_advert_info(advert):
    """Helper function to get relevant advert info"""
    return {key: advert[key] for key in ["guid", "url", "user_phone"] if key in advert}


def request_with_backoff(session, url, max_retries=5, **kwargs):
    """Make an HTTP request with exponential backoff."""
    for attempt in range(max_retries):
        try:
            response = session.get(url, **kwargs)
            response.raise_for_status()
            return response
        except requests.exceptions.HTTPError as e:
            if e.response.status_code in [429, 500, 502, 503, 504]:
                sleep_time = 2 ** attempt
                time.sleep(sleep_time)
            else:
                raise
        except requests.exceptions.RequestException:
            time.sleep(1)
    raise requests.exceptions.RequestException(f"Failed after {max_retries} retries.")

def get_listings(session, category_slug):
    """
    Get a list of ads of a category scattered across pages.
    session: requests.Session object for making HTTP requests.
    category_slug: String representing category slug to be scraped.
    Returns the guid, url, and user's phone number.
    The last one is hidden in advert's main page.
    """
    endpoint = "https://jiji.com.et/api_web/v1/listing"
    params = {
        "slug": category_slug,
        "init_page": "true",
        "webp": "true",
        "lsmid": "1685041575972",
    }

    response = request_with_backoff(session, endpoint, params=params, headers=headers)

    data = response.json()
    if "adverts_list" not in data:
        print(f"No ads found for category: {category_slug}")
        print("Returned object: ", data)
        return
    adverts_list = data.get("adverts_list")
    total_pages = adverts_list.get("total_pages")
    count = adverts_list.get("count")
    adverts = adverts_list.get("adverts")
    adverts_info = [get_advert_info(advert) for advert in adverts]
    next_page = data.get("next_url")

    print(f"In {category_slug}, Num ads={count}, Num pages={total_pages}.")
    current_page = 1
    while next_page and current_page <= total_pages:
        try:
            response = request_with_backoff(session, next_page, headers=headers)
        except requests.RequestException as e:
            print(f"Failed to get page {current_page} of {total_pages}: {e}")
            continue
        else:
            data = response.json()
            adverts = data.get("adverts_list").get("adverts")
            adverts_info.extend([get_advert_info(advert) for advert in adverts])
            next_page = data.get("next_url")
            current_page += 1
            if current_page % 50 == 0:
                print(f"Page {current_page} of {total_pages} scraped.")
            time.sleep(0.1)
    print(f"Got {len(adverts_info)} ads from {category_slug}.")
    timestamp = time.strftime("%Y-%m-%d")
    write_json(
        adverts_info,
        f"./data/housing/raw/jiji/intermittents/pages/{category_slug}_adverts_{timestamp}.json",
    )
    return adverts_info


def get_advert_details(session, advert_guid):
    """Get details of an advert"""
    if advert_guid is None:
        return dict(advert=None, seller=None)
    endpoint_advert = f"https://jiji.com.et/api_web/v1/item/{advert_guid}"
    response = request_with_backoff(session, endpoint_advert, headers=headers)
    if response.status_code == 200:
        response_data = response.json()
        advert_details = {
            "advert": response_data["advert"],
            "seller": response_data["seller"],
        }
        return advert_details
    return None


# Scrape only the ads that are not already scraped
def get_scraped_urls(file_path):
    data = read_json(file_path)
    guids = [advert.get("guid") for advert in data]
    return guids


def scrape_data(session, category_slug):
    """Scrape ads from a given category."""
    adverts = get_listings(session, category_slug)
    # adverts = read_json(f"./data/housing/raw/jiji/intermittents/pages/{category_slug}_adverts_2024-03-08.json")
    if not adverts:
        print(f"No ads scraped from {category_slug}")
        return
    adverts = [advert for advert in adverts if advert]
    # iterate over urls of ads in category
    advert_details = []
    advert_counter = 0
    for i, advert in enumerate(adverts, 1):
        guid = advert.get("guid")
        user_phone = advert.get("user_phone")
        if guid:
            details = get_advert_details(session, guid)
            if details:
                details.get("seller")["phone"] = user_phone
                advert_details.append(details)
            time.sleep(0.1)
            advert_counter += 1
            if advert_counter % 100 == 0 or i == len(adverts):
                write_json(
                    advert_details,
                    f"./data/housing/raw/jiji/intermittents/data/{category_slug}_details_{advert_counter:0>2}.json",
                )
                advert_details = []
        else:
            print("No guid found for an advert, scraping so skipped.")
    print(f"Scraped {advert_counter} ads from {category_slug}.")
    return advert_details


# Recombine the intermittents and save it
def save_data(category_slug, timestamp):
    file_paths = list_files(
        "./data/housing/raw/jiji/intermittents/data/", 
        f"{category_slug}_*.json"
    )
    adverts = []
    for file_path in file_paths:
        chunk = read_json(file_path)
        adverts.extend(chunk)
    write_json(
        adverts,
        f"./data/housing/raw/jiji/{category_slug}_{timestamp}.json",
    )
    print(f"Recombined {len(adverts)} ads from {category_slug}.")


def get_category_slugs():
    # get the property category slugs
    from selenium import webdriver
    from selenium.webdriver.common.by import By

    driver = webdriver.Firefox()
    driver.get("https://jiji.com.et/real-estate")

    # the button is shown only when the window is maximized
    driver.maximize_window()

    try:
        driver.implicitly_wait(10)
        element = driver.find_element(
            By.CSS_SELECTOR,
            value=".b-categories-section-list__show_all-wrapper.h-pointer",
        )
        element.click()

        slugs = [
            link.get_attribute("href")
            for link in driver.find_elements(
                By.CSS_SELECTOR, value=".b-categories-section-list__list > li > a"
            )
        ]
        slugs = [slug.split("/")[-1] for slug in slugs]

    finally:
        driver.quit()
    return slugs


def main():
    # category_slugs = get_category_slugs()
    category_slugs = [
        # "new-builds",
        # "houses-apartments-for-rent",
        "houses-apartments-for-sale",
        # "land-and-plots-for-rent",
        # "land-and-plots-for-sale",
        # "commercial-property-for-rent",
        # "commercial-properties",
        # "event-centers-and-venues",
        # "temporary-and-vacation-rentals",
    ]
    timestamp = time.strftime("%Y-%m-%d")
    session = requests.Session()

    for category_slug in category_slugs:
        scrape_data(session, category_slug)
        save_data(category_slug, timestamp)


if __name__ == "__main__":
    main()
