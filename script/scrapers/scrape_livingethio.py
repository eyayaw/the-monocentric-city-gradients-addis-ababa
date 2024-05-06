import json
from pathlib import Path
import requests

headers = {
    "Accept": "application/json, text/plain, */*",
    "Referer": "https://livingethio.com/",
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36",
}


def get_product_data():
    url = "https://18.222.115.205.nip.io/api/properties/find/published"
    try:
        response = requests.get(url, headers=headers)
        response.raise_for_status
    except requests.exceptions as e:
        print(f"Some error occurred: {e}")
    else:
        return response.json()


def main():
    dir = Path("./data/housing/raw/livingethio/")
    dir.mkdir(parents=True, exist_ok=True)

    product_data = get_product_data()

    with open(dir / "livingethio.json", "w") as f:
        json.dump(product_data, f, indent=2, ensure_ascii=False)


if __name__ == "__main__":
    main()
