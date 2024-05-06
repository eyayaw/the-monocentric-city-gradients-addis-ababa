import re
from typing import NamedTuple

import sys

sys.path.append("./script")
from helpers.helpers_cleaning import str_squish

CONFIG = {
    "types": "geocode",
    "components": {"country": "et", "administrative_area": "Addis Ababa"},
    "location": (9.01024, 38.76140),  # Meskel Square
    "radius": 15_000,
    "bounds": {"southwest": "8.5825,38.2951", "northeast": "9.0320,38.7760"},
    "region": "et",
    "language": "en-US",
}


class GeocodeError(Exception):
    """Exception raised for errors in the geocoding process."""

    pass


class NotValidAddressError(Exception):
    """Exception raised for invalid addresses."""

    pass


class AddressData(NamedTuple):
    """A pair of main and alternative addresses."""

    main: str
    alternative: str
    use_api: str
    ids: list[str]


def standardize_address(word: str) -> str:
    """Make it lowercase and removing non-word characters."""
    word = word.lower()
    word = re.sub(r"[^\w\s]", " ", word)
    return str_squish(word)


ADMIN_AREAS_1 = [
    "ethiopia;ኢትዮጵያ",
    "addis ababa;አዲስ አበባ",
    "adama|naz[ie]?ret;አዳማ|ናዝሬት",
    "oromia|finfinn?ee?;ኦሮሚያ|ፊንፊኔ",
]

ADMIN_AREAS_2 = [
    "bole;ቦሌ",
    "yeka;የካ",
    "kirkos;ቂርቆስ",
    "arada;አራዳ",
    "lideta;ልደታ",
    "nifas s(i|e)lk lafto;ንፋስ ስልክ ላፍቶ",
    "nifas s(i|e)lk;ንፋስ ስልክ",
    "akaki kalit(i|y);አቃቂ ቃሊቲ",
    "akaki;አቃቂ",
    "kolfe keranio;ቆልፈ ቀራንዮ",
    "gullele;ጉለሌ",
    "addis ketema;አዲስ ከተማ",
]

ADMIN_TERMS = [
    "sub city;ክፍለ ከተማ",
    "woreda|wereda;ወረዳ",
    "kebele;ቀበሌ",
]

NUMERIC_ADDRESSES = ["22", "24", "7", "18", "49", "71", "72", "41", "3", "140", "30"]

RE_NUMERIC_ADDRESSES = f'({"|".join(NUMERIC_ADDRESSES)})'

RE_LOCALITY_TERMS = r"(\b\d*\s*(area|bota|akababi|sefer|men[ei]?der|site|adebabay)\b|(አካባቢ|ቦታ|ሰፈር|መንደር|ሳይት|አደባባይ)\s*\d*)"

RE_OTHER_TERMS = r"(\b\d*\s*(condominium|apartments?|house|villa|bet|ber)\b|(ኮንዶሚኒየም|አፓርታማ|አፓርትመንት|ቤት|ቤቶች|ቪላ|በር)\s*\d*)"
#TODO: beklo bet, abc codominium will be stripped of these terms, so not idea.

RE_SEFER_ADDRESSES = r"((w[eo]ll?o|addis|w(o|e)[yi].?ra|geja)\s*sefer)|((ወይራ|አዲስ|ጌጃ|ወሎ)\s*ሰፈር)"
RE_BET_ADDRESSES = r"(\b(fere?s|be[qk][ei]?ll?o|fiyele?)\s*bet\b|(ፈረስ|በቅሎ|ፍየል)\s*ቤት)"
RE_CONDO_ADDRESSES = r"(\b((ayat|semit|ajamba|gelan|gotera|24|haya\s*arat|22|haya\s*hulet|kill?into|abado|mexico|arabsa|koye|jemm?o)\s*condominiums?)\b|(አያት|ሰሚት|አጃምባ|ገላን|ጎተራ|ሀያ\s*አራት|ሀያ\s*ሁለት|ቂሊንጦ|አባዶ|ሜክሲኮ|አራብሳ|ኮየ|ጀሞ)\s*ኮንዶሚኒየም)"

def construct_regex(terms: list[str]) -> str:
    """Constructs a regular expression from a list of semi-colon separated terms."""
    unique_words = set(word for item in terms for word in item.split(";"))
    regex = [text.replace(" ", "\\s*") for text in unique_words]
    return f'({"|".join(regex)})'


RE_ADMIN_AREAS_1 = construct_regex(ADMIN_AREAS_1)
RE_ADMIN_AREAS_1 = rf"(\b\d*\s*({RE_ADMIN_AREAS_1})\s*\d*\b)"

# RE_ADMIN_AREAS_2 = construct_regex(ADMIN_AREAS_2)

RE_ADMIN_TERMS = construct_regex(ADMIN_TERMS)
RE_ADMIN_TERMS = rf"(\b\d*\s*({RE_ADMIN_TERMS})\s*\d*\b)"

# RE_LOCALITY_TERMS_NUM = r"\d*\s*(" + RE_LOCALITY_TERMS + r")\s*\d*"
# RE_OTHER_TERMS_NUM = r"\d*\s*(" + RE_OTHER_TERMS + r")\s*\d*"

RE_NUMERIC_ADDRESSES_2 = rf"(\b({RE_NUMERIC_ADDRESSES})\s*(({RE_LOCALITY_TERMS})|({RE_OTHER_TERMS}))|(({RE_LOCALITY_TERMS})|({RE_OTHER_TERMS}))\s*({RE_NUMERIC_ADDRESSES})\b)"


def validate_address(address: str, strict=True) -> bool:
    """Validates an address. Returns False if the address is None, whitespace, or 'NA'."""

    if not address:
        return False

    address = address.strip().upper()

    is_proper = (
        not address.isspace() and not address.isdigit() and address not in ("NA", "NAN")
    )
    # Strict validation
    if not strict:
        return is_proper
    is_admin_1 = re.compile(RE_ADMIN_AREAS_1, re.I | re.U).fullmatch(address)
    # is_admin_2 = re.compile(RE_ADMIN_AREAS_2, re.I | re.U).fullmatch(address)
    is_other_terms = re.compile(RE_OTHER_TERMS, re.I | re.U).fullmatch(address)

    is_local_terms = re.compile(RE_LOCALITY_TERMS, re.I | re.U).fullmatch(address)
    is_numeric_address = re.compile(RE_NUMERIC_ADDRESSES, re.I | re.U).fullmatch(
        address
    )

    return (
        is_proper
        and not bool(is_admin_1)
        # and not bool(is_admin_2)
        and not bool(is_local_terms)
        and not bool(is_other_terms)
        or bool(is_numeric_address)
    )


def is_exception(address, pattern, exclusions_re):
    # The excluded terms will be considered if the pattern matches them
    # Pass terms/regex in exclusions
    match = re.search(pattern, address)
    if match:
        # It is an exception because it contains excluded terms
        if re.search(exclusions_re, address, re.U | re.I):
            return True

    return False  # Not an exception if it doesn't match the pattern or doesn't contain excluded terms



def tidy_address(address: str, max_iter=5) -> str:
    """Cleans up an address string by removing unwanted parts repeatedly, with corrected scope and definitions."""
    address = standardize_address(address)

    # Define all necessary patterns
    broads = rf"^(?:({RE_ADMIN_AREAS_1})|({RE_LOCALITY_TERMS})|({RE_OTHER_TERMS}))$"
    others = rf"((?:{RE_LOCALITY_TERMS})|(?:{RE_ADMIN_AREAS_1})|(?:{RE_OTHER_TERMS}))"
    isolated = r"(?:\s+[^0-9bnቁክህብ]\s+|^[^0-9bnቁክህብ]\s+|\s+[^0-9bnቁክህብ]$)"
    num_am = r"^(\d+\s*(ቁጥር|ቁ\.?)\s*\d+)"
    num_address = r"^\d+$"  # Pattern for any numeric address
    valid_num_address = rf"\b({RE_NUMERIC_ADDRESSES})\b"
    exceptions = rf"({RE_NUMERIC_ADDRESSES_2})|({RE_SEFER_ADDRESSES})|({RE_BET_ADDRESSES})|({RE_CONDO_ADDRESSES})"

    # Compile the main pattern excluding valid numeric addresses from the general removal process
    patterns = rf"(?:({others})|({broads})|({isolated})|({num_am}))"

    rx = re.compile(patterns, flags=re.I | re.U)
    mtext = address
    for _ in range(max_iter):
        prev_text = mtext
        # Check against valid numeric addresses first
        if re.fullmatch(valid_num_address, mtext, flags=re.I | re.U):
            break  # Retain addresses that match the valid numeric list
        if is_exception(mtext, patterns, exceptions):
            break

        mtext = rx.sub(" ", mtext).strip()  # Apply regex removal
        # Special handling for trimming numeric addresses not listed as valid
        if re.fullmatch(num_address, mtext):
            mtext = ""  # Trim if it's just a numeric address not in the valid list
        mtext = str_squish(mtext)
        if mtext == prev_text:
            break
    return mtext


def trim_words(text, side="right"):
    """Trim words one at a time from the left, right, or center."""
    if not text or not isinstance(text, str):
        raise TypeError("The second argument must be a string.")
    if side not in ["left", "right", "center"]:
        raise ValueError("The direction must be 'left', 'right', or 'center'.")

    words = text.split()
    word_count = len(words)
    trimmed = []

    if word_count == 0:
        return trimmed
    elif word_count < 3:
        return words

    for i in range(1, word_count):
        if side == "left":
            # Trim from the left
            trimmed.append(" ".join(words[i:]))
        if side == "right":
            # Trim from the right
            trimmed.append(" ".join(words[: word_count - i]))
        if side == "center":
            # Trim from both sides
            if i <= word_count // 2:
                trimmed.append(" ".join(words[i : word_count - i]))

    return trimmed
