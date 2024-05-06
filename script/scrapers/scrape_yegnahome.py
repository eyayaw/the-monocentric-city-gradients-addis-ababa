import json
import os
import time
import requests

url = "https://yegnahome.com/api/properties"

query_string = {
    "nearLat": "8.9806034",
    "nearLng": "38.7577605",
    "diameter": "9437.500661096128",
    "pageNo": 1,
    "size": 25,
    "hotelSearchTerm": "",
}

headers = {
    "accept": "application/json, text/plain, */*",
    "accept-language": "en-US,en;q=0.9",
    "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36",
}


def get_properties(session, url):
    properties = []
    while True:
        response = session.get(url, params=query_string, headers=headers)
        data = response.json()
        if not data["properties"]:
            break
        query_string["pageNo"] += 1
        properties.extend(data["properties"])
        time.sleep(2)

    return properties


def main():
    session = requests.Session()
    properties = get_properties(session, url)
    timestamp = time.strftime("%Y-%m-%d")
    file_path = f"./data/housing/raw/yegnahome/product-data_{timestamp}.json"
    os.makedirs(os.path.dirname(file_path), exist_ok=True)

    with open(file_path, "w") as f:
        json.dump(properties, f, indent=2, ensure_ascii=False)


if __name__ == "__main__":
    main()
