import time
import requests
from datetime import datetime
from script.helpers.helpers_io import write_json


def get_product_data():
    endpoint = "https://betenethiopia.com/api/properties"
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3"
    }
    params = {"page": 1}
    data_list = []
    delay = 0.5  # Initial delay
    max_delay = 60  # Don't wait more than a minute
    while True:
        try:
            response = requests.get(endpoint, headers=headers, params=params)
            response.raise_for_status()

            data = response.json().get("properties", [])
            # Add a timestamp to use it for calculating the date of publication, since the API does not provide the absolute time of publication
            # use universal time to avoid timezone issues
            retrieved_at = datetime.utcnow().isoformat()
            for i, d in enumerate(data):
                data[i]["retrieved_at"] = retrieved_at
            data_list.extend(data)
            print(f"Retrieved page {params['page']}.")

            params["page"] += 1
            delay = 0.5  # Reset delay
        except requests.exceptions.HTTPError as e:
            # Server Error, Too Many Requests
            if response.status_code == 429 or response.status_code == 500:
                print("Server Error or Rate limit reached. Waiting...")
                delay = min(delay * 2, max_delay)  # Increase delay
                if delay == max_delay:
                    print(
                        f"Max delay reached: {max_delay}s. Moving to the next page ..."
                    )
                    params["page"] += 1  # skip to the next page
                    delay = 0.5  # reset delay
                    continue
            elif response.status_code == 404:  # Not found
                print(
                    "404 Not Found. Page does not exist. We may have reached the last page."
                )
                break  # exits the loop when a 404 error is encountered
            else:
                print(f"Some error occured: {e}")
                break
        time.sleep(delay)
    return data_list


def main():
    data = get_product_data()
    write_json(data, "./data/housing/raw/beten/beten_data.json", overwrite=True)


if __name__ == "__main__":
    main()
