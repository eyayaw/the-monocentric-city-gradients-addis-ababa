import sys
import re
import requests
import pandas as pd
from bs4 import BeautifulSoup


def fetch_page(url):
    try:
        response = requests.get(url)
        response.raise_for_status()
        return response
    except requests.exceptions.RequestException as e:
        print(e)
        sys.exit(1)


def parse_table(response):
    """Parse HTML to extract table header and data."""
    try:
        soup = BeautifulSoup(response.text, "html.parser")
        table = soup.select_one("div.table-expand > table.table tbody")

        data = []
        for tr in table.find_all("tr"):
            td = tr.find_all("td")
            row = [i.text for i in td]
            data.append(row)

        header = [th.text.lower().replace(" ", "_") for th in table.find_previous_sibling("thead").find_all("th")]
        data = [header] + data
        return data
    except Exception as e:
        print(f"Error during HTML parsing: {e}")
        sys.exit(1)


def get_salaries():
    url = "https://worldsalaries.com/average-salary-in-adis-abeba/ethiopia/"
    response = fetch_page(url)
    data = parse_table(response)
    title = BeautifulSoup(response.text, "html.parser").title.text
    file_path = title.replace(" ", "_").replace(",_", "_").lower()
    data = pd.DataFrame(data[1:], columns=data[0])
    data.salary = data.salary.str.replace(" ETB", "").str.replace(",", "").astype(int)
    return data, file_path


if __name__ == "__main__":
    salaries, file_path = get_salaries()
    salaries.to_csv(f"./data/{file_path}.csv", index=False)
