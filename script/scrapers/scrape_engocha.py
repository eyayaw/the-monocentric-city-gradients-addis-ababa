import os
import requests
import time
import json
from urllib.parse import quote, urljoin


BASE_URL = "https://engocha.com/api/v1/classifieds/"
headers = {
    "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0.2 Safari/605.1.15",
}


def get_real_estate_categories():
    params = {"sortby": "latest", "page": 1}
    response = requests.get(BASE_URL, headers=headers, params=params)
    if response.ok:
        data = response.json()
    else:
        print("Error fetching categories")
        return
    cats = data["categories"]
    real_estate_idx = next(
        (i for i, c in enumerate(cats) if "real estate" in c["CategoryName"].lower()), None
    )

    if real_estate_idx is not None:
        subcats = cats[real_estate_idx]["children"]
        return subcats
    else:
        print("Real Estate category not found")


def get_product_data(sub_cat_id, city="Addis Ababa"):
    quoted_path = quote(
        f"{sub_cat_id}-/condition_all/brand_all/city_{city}/minprice_zr/maxprice_in/currency_df?sortby=latest",
        safe="/?=&",
    )
    url = urljoin(BASE_URL, quoted_path)
    data_list = []

    while url is not None:
        response = requests.get(url, headers=headers).json()
        data = response.get("listings", {}).get("data", None)
        if data:
            data_list.extend(data)
        url = response.get("listings", {}).get("next_page_url", None)
        time.sleep(0.5)
    return data_list


def main():
    data_list = []
    cats = get_real_estate_categories()
    for cat in cats:
        data = get_product_data(cat["ChildCategoryID"])
        for d in data:
            d["PropertyType"] = cat["ChildCategoryName"]
        data_list.extend(data)
        time.sleep(0.5)

    timestamp = time.strftime("%Y-%m-%d")
    file_path = f"./data/housing/raw/engocha/engocha_real-estate_{timestamp}.json"
    os.makedirs(os.path.dirname(file_path), exist_ok=True)
    with open(file_path, "w") as f:
        json.dump(data_list, f, indent=2, ensure_ascii=False)
    with open(
        f"./data/housing/raw/engocha/engocha_real-estate-categories_{timestamp}.json",
        "w",
    ) as f:
        json.dump(cats, f, indent=2, ensure_ascii=False)


if __name__ == "__main__":
    main()
