import os
from bs4 import BeautifulSoup
from script.helpers.helpers_io import list_files, write_json
from script.helpers.helpers_scrape import my_get_text


def get_product_details(filepath):
    # Load the HTML content from a file
    try:
        with open(filepath, "r", encoding="utf-8") as file:
            html_content = file.read()
    except FileNotFoundError:
        print(f"File not found: {filepath}")
        return None

    # Create a BeautifulSoup object
    soup = BeautifulSoup(html_content, "html.parser")

    # Define a dictionary to hold the extracted information
    product_data = {"file_path": os.path.basename(filepath)}

    try:
        product_data["product_url"] = soup.select_one("link[rel=canonical]").get("href")
    except AttributeError:
        product_data["product_url"] = os.path.basename(filepath)
    product_data["page_title"] = my_get_text(
        soup.select_one(".container h1.page-title")
    )
    product_data["content_title"] = my_get_text(
        soup.select_one(".container .property-details h4.content-title")
    )
    product_data["address"] = my_get_text(
        soup.select_one(".container .property-details address")
    )

    # Price info container
    price_container = soup.select_one(
        ".container .property-details-price[itemprop='offers']"
    )
    price_details = {}
    if price_container:
        # Extracting the price info
        currency_amount = price_container.select("span.price")
        price_currency = my_get_text(currency_amount[0])
        price = my_get_text(currency_amount[1])
        price_unit = price_container.select_one("span.period").text.strip()
        price_naira_equiv = my_get_text(price_container.select_one("span.naira-equiv"))
        price_details["price"] = price
        price_details["price_currency"] = price_currency
        price_details["price_unit"] = price_unit
        price_details["price_naira_equiv"] = price_naira_equiv

    product_details = {}
    pd_soup = soup.select("#tab-1 > div.tab-body > table > tbody > tr > td")
    for td in pd_soup:
        text = my_get_text(td)
        if ":" in text:
            name, value = text.split(":")
            if name:
                product_details[name] = value
        else:
            if text:
                product_details[text] = text

    product_description = my_get_text(
        soup.select_one('#tab-1 .tab-body p[itemprop="description"]')
    )
    # Number of images
    image_urls = [img.get("data-src") for img in soup.select("ul#imageGallery > li")]

    # Seller info
    seller_details = {}
    try:
        phone_number = soup.select_one("#fullPhoneNumbers").get("value")
        seller_details["phone_number"] = phone_number
    except AttributeError:
        pass
    try:
        seller_name = my_get_text(soup.select_one(".panel-body p > a > strong"))
        map_icon = soup.select_one(".sidebar .panel-body i.fa-map-marker")
        seller_address = (
            map_icon.find_next_sibling(string=True).strip() if map_icon else ""
        )

        seller_details["seller_name"] = seller_name
        seller_details["seller_address"] = seller_address
    except IndexError:
        pass

    product_data = {
        **product_data,
        **price_details,
        **product_details,
        "description": product_description,
        "image_urls": image_urls,
        **seller_details,
    }
    return product_data


def main():
    html_files= list_files("data/housing/raw/ethiopiapropertycentre/html", "*.html")
    data = []
    for html_file in html_files:
        product_data = get_product_details(html_file)
        if product_data:
            data.append(product_data)
    datapath = "data/housing/raw/ethiopiapropertycentre/product_data_from_file.json"
    write_json(data, datapath)


if __name__ == "__main__":
    main()
