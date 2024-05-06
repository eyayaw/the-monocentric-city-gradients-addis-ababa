import re
from script.helpers.helpers_cleaning import all_amharic, all_ascii, remove_punct, str_squish


def split_place_name(place_name):
    """
    Splits a place name into English and Amharic parts.

    Args:
    place_name (str): The place name to split.

    Returns:
    str: The original place name, the English part, and the Amharic part.
    If any part is missing or is a number, it is replaced with None.
    """

    if not place_name or not isinstance(place_name, str):
        return place_name, None, None

    # Pre-processing
    place_name = remove_punct(place_name)
    place_name = str_squish(place_name)

    # Detect the language of the input string
    lang = detect_lang(place_name)
    if lang == "All English":
        return place_name, place_name, None
    elif lang == "All Amharic":
        return place_name, None, place_name

    # Define regular expressions
    if lang == "English":
        ENGLISH_REGEX = re.compile(r"^[a-z0-9\s]+", re.IGNORECASE)
        AMHARIC_REGEX = re.compile(r"[\u1200-\u137F\s0-9]+$")
    elif lang == "Amharic":
        ENGLISH_REGEX = re.compile(r"[a-z0-9\s]+$", re.IGNORECASE)
        AMHARIC_REGEX = re.compile(r"^[\u1200-\u137F\s0-9]+")
    else:
        return place_name, None, None

    # Split the input string into English and Amharic parts
    english_part = extract_part(place_name, ENGLISH_REGEX)
    amharic_part = extract_part(place_name, AMHARIC_REGEX)

    if not english_part or not amharic_part:
        return place_name, english_part, amharic_part

    english_part, amharic_part = adjust_parts(english_part, amharic_part)

    return place_name, english_part, amharic_part


def extract_part(place_name, regex):
    """Extracts a part of the place name using the provided regular expression."""
    try:
        part = " ".join(regex.findall(place_name)).strip()
        part = str_squish(part)
        return None if not part or part.isdigit() else part
    except re.error:
        return None


def adjust_parts(english_part, amharic_part):
    """Adjusts the English and Amharic parts based on certain conditions."""
    english_splits = english_part.split()
    amharic_splits = amharic_part.split()
    if len(english_splits) < 2 or len(amharic_splits) < 2:
        return english_part, amharic_part

    en_start, en_pen, en_end = (
        english_splits[0].strip(),
        english_splits[-2].strip(),
        english_splits[-1].strip(),
    )

    am_start, am_2nd, am_end = (
        amharic_splits[0].strip(),
        amharic_splits[1].strip(),
        amharic_splits[-1].strip(),
    )

    # Case 1: 02 Condominium Lamberet 02 ኮንዶሚኒየም ላምበረት
    if en_start == en_end == am_start and am_start != am_end:
        english_part = " ".join(english_splits[1:])
    # Case 2: 02 Condominium Lamberet ኮንዶሚኒየም ላምበረት 02
    # The regexes match the parts properly.
    # Case 3: Condominium Lamberet 02 ኮንዶሚኒየም ላምበረት 02
    elif am_start == am_end == en_end and en_end != am_start:
        amharic_part = " ".join(amharic_splits[1:])
    # Case 4: Condominium Lamberet 02 02 ኮንዶሚኒየም ላምበረት
    elif en_pen == en_end == am_start == am_2nd:
        english_part = " ".join(english_splits[0:-1])
        amharic_part = " ".join(amharic_splits[1:])
    else:
        # Handle when a non-am word(+num) is important for the amharic part
        if en_start == en_end or en_pen == en_end:
            if not re.match(
                en_end, amharic_part, re.IGNORECASE
            ):  # at the start of the amharic part
                # TODO: check if there are cases where re.search should be used to match the whole amharic part

                # e.g.: 11D BAR AND RESTAURANT 11D ስጋ ቤት ባር እና ሬስቶራንት
                # 11D should go to the amharic part, the amharic regex will miss it because of "D"
                amharic_part = en_end + " " + amharic_part
            elif not re.search(en_end, " ".join(amharic_splits[1:]), re.IGNORECASE):
                print(
                    f"Warning: Struggling where to put {en_end} which is not found in {amharic_part}."
                )
            english_part = " ".join(english_splits[0:-1])

    return english_part, amharic_part


def detect_lang(place_name):
    """Detect the language of the place name."""
    try:
        if all_ascii(place_name):
            return "All English"
        elif all_amharic(place_name):
            return "All Amharic"
    except TypeError:
        return None
    if re.search(r"^[0-9]*\s*[\u1200-\u137F]+", place_name):
        return "Amharic"
    elif re.search(r"^[0-9]*\s*[a-z]+", place_name, re.IGNORECASE):
        return "English"
    return None
