import re
from string import punctuation

from .regular_expressions import (
    AM_RE,
    AM_UNICODE,
    EMOJIES_RE,
    IRRELEVANT_RE,
    OTHER_SYMS_RE,
)


def check_instance(obj, type):
    """Check if `obj` is an instance of `type`."""
    if not isinstance(obj, type):
        raise TypeError(f"Input should be a {type}.")


def str_squish(text):
    return " ".join(text.split())


def remove_punct(text):
    """Removes punctuation from a string and replaces it with a single space."""
    check_instance(text, str)
    text = re.sub(r"[{}]".format(re.escape(punctuation)), " ", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def remove_html_stuff(text):
    TAG_RE = re.compile(r"<[^>]+?>")
    ENTITY_RE = re.compile(r"&[^;\s]+?;")
    text = TAG_RE.sub("", text)
    text = ENTITY_RE.sub("", text)
    return text


def clean_text(text):
    """Keep only Amharic and English characters, numbers, and some special characters, and replace the rest with a single space."""
    check_instance(text, str)
    # Remove html tags, entities
    # text = remove_html_stuff(text)
    text = IRRELEVANT_RE.sub(" ", text)
    return str_squish(text).strip()


def clean_text2(text: str) -> str:
    """Cleans the text by removing special characters, numbers, and spaces."""
    check_instance(text, str)
    # Remove phone numbers
    # text = PHONE_RE.sub(r" ", text)
    # Remove html tags
    text = text.replace("<p>", "").replace("</p>", "")
    # Remove html entities
    text = re.compile(r"&nbsp;").sub(r" ", text)
    # Remove emojies
    text = EMOJIES_RE.sub(r" ", text)
    # Remove other symbols
    text = OTHER_SYMS_RE.sub(r" ", text)
    return str_squish(text).strip()


def contains_amharic(text):
    """Check if a string contains Amharic script based on the Unicode range."""
    check_instance(text, str)
    return bool(re.search(AM_UNICODE, text))


def all_amharic(text):
    """Check if a string contains only Amharic script, after trimming spaces. Consider arabic numerals and punctuations as Amharic."""
    check_instance(text, str)
    return bool(re.fullmatch(AM_RE, text))


def all_ascii(text):
    """Check if a string contains only ascii characters."""
    check_instance(text, str)
    return bool(re.fullmatch(r"[\x00-\x7F]+", text))


def extract_en(text):
    """Extract the English part of a string."""
    check_instance(text, str)
    text = remove_punct(clean_text(text))
    regex_en = re.compile(
        r"[a-z0-9\s]+(?=[\u1200-\u137F])|(?=[\u1200-\u137F])[a-z0-9\s]+", re.IGNORECASE
    )


def classify_and_group(text):
    """Classify and group parts of an address string based on language detection of each part."""
    check_instance(text, str)
    text = remove_punct(clean_text(text))
    parts = text.split()
    english_parts = []
    amharic_parts = []
    for i, part in enumerate(parts):
        if part.isnumeric():
            # Check adjacency to decide the target group for the part
            if i > 0 and contains_amharic(parts[i - 1]):
                # Previous part is Amharic, so append the number to Amharic parts
                amharic_parts.append(part)
            elif i < len(parts) - 1 and contains_amharic(parts[i + 1]):
                # Next part is Amharic, so append the number to Amharic parts
                amharic_parts.append(part)
            else:
                # Default to English
                english_parts.append(part)
        else:
            # For non-numeric parts, append directly based on language detection
            if contains_amharic(part):
                amharic_parts.append(part)
            else:
                english_parts.append(part)
    return english_parts, amharic_parts


# def split_into_en_am(address, split=r"\s\|\s", sep=" | "):
#     """Split an address into English and Amharic parts. Reorders if amharic comes first and english part comes second. Handles single-language addresses."""
#     # Splitting the address using the pipe as a separator
#     parts = re.split(split, address)

#     # Classify and group parts
#     english_parts, amharic_parts = classify_and_group(parts)

#     # Joining the parts back together
#     english_address = sep.join(english_parts) if english_parts else address
#     amharic_address = sep.join(amharic_parts) if amharic_parts else address

#     return (english_address, amharic_address)


def extract_parts(text):
    """Extract the parts of a string that are likely to be English and Amharic."""
    check_instance(text, str)
    text = remove_punct(clean_text(text))
    punct = re.escape(punctuation)
    patt_am = re.compile(
        rf"([0-9{punct}\s]*?[\u1200-\u137F]+[0-9{punct}\s]*?)+",
        flags=re.UNICODE | re.MULTILINE,
    )
    matches = patt_am.finditer(text)
    if matches:
        text_am = []
        text_en = text
        for i, match in enumerate(matches, 1):
            if i == 2:
                print(f"Found more than one amharic part in '{text}'")
            text_am.append(match.group())
            # the amharic part removed from the (input) text makes the english part
            text_en = text_en.replace(match.group(), "", 1)
        # trim punct and spaces
        text_am = " ".join([t.strip(punct + " ") for t in text_am])
        text_en = text_en.strip(punct + " ")
        return text_en, text_am
    else:
        return text, text
