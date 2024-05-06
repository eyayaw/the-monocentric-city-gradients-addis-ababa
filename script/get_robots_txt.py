import requests
from urllib.parse import urlparse
import os


def get_robots_txt(url):
    path = urlparse(url).scheme + "://" + urlparse(url).netloc + "/robots.txt"
    try:
        req = requests.get(path, timeout=5)
        return req.text
    except requests.exceptions.RequestException as e:
        print(e)
        return None


urls = [
    "https://realethio.com",
    "https://jiji.com.et",
    "https://zegebeya.com",
    "https://betenethiopia.com/",
    "https://ethiopiapropertycentre.com/",
    "https://ethiopianproperties.com/",
    "https://et.loozap.com/",
    "https://engocha.com/",
    "https://qefira.com/",
    "https://livingethio.com/",
]

for url in urls:
    try:
        txt = get_robots_txt(url)
    except Exception as e:
        print(e)
        txt = None
    if not txt:
        continue
    file_path = f"./data/housing/robots_txt/{urlparse(url).netloc}_robots.txt"
    if not os.path.exists(file_path):
        with open(file_path, "w") as f:
            f.write(txt)
