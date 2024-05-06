import json
import os
import time
import undetected_chromedriver as uc
from selenium.webdriver.common.by import By
from selenium.common.exceptions import NoSuchElementException


def get_page_links(driver, url):
    # get page links
    driver.get(url)
    driver.implicitly_wait(30)
    pagination_selector = "div.wp-block.default.product-list-filters.light-gray.pPagination > ul > li > a:not([rel='next']):not([rel='prev'])[href]"
    page_links = driver.find_elements(By.CSS_SELECTOR, value=pagination_selector)
    if page_links:
        last_page_link = page_links[-1].get_attribute("href")
        last_page_num = int(last_page_link.strip().split("page=")[-1])
        base_page_url = url
        page_urls = [
            base_page_url,
            *[f"{base_page_url}?page={i}" for i in range(2, last_page_num + 1)],
        ]
    else:
        page_urls = [url]

    return page_urls


def get_product_links(driver, page_urls):
    # get product links on each page
    product_link_selector = "div[itemscope] div.wp-block-body div.wp-block-content.clearfix.text-xs-left.text-sm-left > a[href]"
    product_links = []
    counter = 1
    for page_url in page_urls:
        driver.get(page_url)
        driver.implicitly_wait(30)
        try:
            links = driver.find_elements(By.CSS_SELECTOR, value=product_link_selector)
            product_links.extend([link.get_attribute("href") for link in links])
        except TimeoutError:
            print("TimeoutError.")
            continue
        if counter % 5 == 0:
            print(f"Extracted product links on {counter}/{len(page_urls)} pages.")
        counter += 1
        time.sleep(0.5)

    return product_links


# get product details ----
def get_element_text(driver, css_selector, default=None):
    try:
        return driver.find_element(By.CSS_SELECTOR, css_selector).text.strip()
    except NoSuchElementException:
        return default


def get_product_details(driver, product_url):
    # CSS Selectors
    CONTAINER = "body > div.body-wrap > div:nth-child(4)"
    PAGE_TITLE = f"{CONTAINER} > div.pg-opt div.col-md-12 > h1.page-title"
    CONTENT_TITLE = (
        f"{CONTAINER} > section div.col-md-8 div.col-sm-8.f15.property-details > h4"
    )
    ADDRESS = f"{CONTAINER} > section div.col-md-8 div.col-sm-8.f15.property-details > address"
    PRICE_CURRENCY = f"{CONTAINER} > section div.col-md-8 div.col-sm-4 > span.pull-right.property-details-price[itemprop=offers] > span.price[itemprop=priceCurrency]"
    PRICE = f"{CONTAINER} > section div.col-md-8 div.col-sm-4 > span.pull-right.property-details-price[itemprop=offers] > span.price[itemprop=price]"
    ADDITIONAL_PROPERTY = f"{CONTAINER} > section div.col-md-8 div.col-md-12 > div.product-info ul.aux-info > li[itemprop=additionalProperty]"
    PROPERTY_DESCRIPTION = "#tab-1 > div.tab-body > p[itemprop=description]"
    PROPERTY_DETAILS = "#tab-1 > div.tab-body > table > tbody > tr > td"

    driver.get(product_url)
    driver.implicitly_wait(30)

    page_title = get_element_text(driver, PAGE_TITLE)
    content_title = get_element_text(driver, CONTENT_TITLE)
    address = get_element_text(driver, ADDRESS)
    price_currency = get_element_text(driver, PRICE_CURRENCY)
    price = get_element_text(driver, PRICE)

    additional_property_data = {}
    additional_property = driver.find_elements(By.CSS_SELECTOR, ADDITIONAL_PROPERTY)
    for li in additional_property:
        name = get_element_text(li, "span[itemprop=name]")
        value = get_element_text(li, "span[itemprop=value]")
        if name:
            additional_property_data[name] = value

    property_description = get_element_text(driver, PROPERTY_DESCRIPTION)

    property_details_data = {}
    property_details = driver.find_elements(By.CSS_SELECTOR, PROPERTY_DETAILS)
    for td in property_details:
        name = get_element_text(td, "strong").replace(":", "").strip()
        value = td.text.replace(name, "").replace(":", "").strip()
        if name:
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
    # install the Chromium browser (the driver comes with it)
    options = uc.ChromeOptions()
    options.add_argument("--auto-open-devtools-for-tabs")
    driver = uc.Chrome(
        executable_path="/opt/homebrew/bin/chromedriver",
        browser_executable_path="/Applications//Google Chrome for Testing.app//Contents/MacOS/Google Chrome for Testing",
        use_subprocess=True,
        headless=False,
        options=options,
    )

    types = ["for-sale", "for-rent"]
    timestamp = time.strftime("%Y-%m-%d")
    for type in types:
        url = f"https://ethiopiapropertycentre.com/{type}/addis-abeba"
        page_links = get_page_links(driver, url)
        product_links = get_product_links(driver, page_links)
        # with open(f'ethio-prop-centre_f{type}_product-links.json', 'r') as f:
        #     product_links = json.load(f)
        product_details_list = []
        counter = 1
        for product_link in product_links:
            product_details = get_product_details(driver, product_link)
            product_details_list.append(product_details)
            if counter % 25 == 0:
                print(f"Retrieved details of {counter}/{len(product_links)} products.")
            counter += 1
            time.sleep(1)

        file_path = f"./data/housing/raw/ethiopiapropertycentre/{type}_selenium_{timestamp}.json"
        os.makedirs(os.path.dirname(file_path), exist_ok=True)
        with open(file_path, "w") as f:
            json.dump(product_details_list, f, indent=2, ensure_ascii=False)
            print(f"Saved {len(product_details_list)} records to {file_path} .")

    driver.quit


if __name__ == "__main__":
    main()
    print("---------- All done! ----------")
