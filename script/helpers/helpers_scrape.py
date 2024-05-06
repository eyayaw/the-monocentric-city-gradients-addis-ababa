# Gets the text of a soup object (Tag) without raising an exception
def my_get_text(element, strip=True, default=""):
    try:
        return element.get_text(strip=strip)
    except AttributeError:
        if element:
            print(
                f"Element {element} is not a BeautifulSoup object or does not contain text."
            )
        return default
