import json
import os
import requests
import time

url = "https://ebuy.kavanatech.net/api/properties"

headers = {
    "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0.2 Safari/605.1.15",
}


def get_product_data(session, url):
    product_data = []
    next_page_url = url
    while next_page_url:
        try:
            response_json = session.get(next_page_url, headers=headers).json()
        except json.JSONDecodeError:
            break
        if "data" in response_json:
            data = response_json["data"]
            next_page_url = (
                response_json.get("meta", {})
                .get("pagination", {})
                .get("links", {})
                .get("next", None)
            )
            product_data.extend(data)
        time.sleep(0.5)
    else:
        print("No more pages.")
    return product_data


def main():
    session = requests.Session()
    product_data = get_product_data(session, url)
    timestamp = time.strftime("%Y-%m-%d")
    file_path = f"./data/housing/raw/ebuy/product-data_{timestamp}.json"
    os.makedirs(os.path.dirname(file_path), exist_ok=True)
    with open(file_path, "w") as f:
        json.dump(product_data, f, indent=2, ensure_ascii=False)

if __name__ == "__main__":
    main()