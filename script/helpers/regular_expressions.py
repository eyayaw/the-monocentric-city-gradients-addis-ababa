import re
from string import punctuation

EMOJIES_RE = re.compile(
    r"["
    "\U0001F600-\U0001F64F"  # emoticons
    "\U0001F300-\U0001F5FF"  # symbols & pictographs
    "\U0001F680-\U0001F6FF"  # transport & map symbols
    "\U0001F1E0-\U0001F1FF"  # flags (iOS)
    "\U00002500-\U00002BEF"  # chinese char
    "\U00002702-\U000027B0"
    "\U00002702-\U000027B0"
    "\U000024C2-\U0001F251"
    "\U0001f926-\U0001f937"
    "\U00010000-\U0010ffff"
    "\u2640-\u2642"
    "\u2600-\u2B55"
    "\u200d"
    "\u23cf"
    "\u23e9"
    "\u231a"
    "\ufe0f"
    "\u3030"
    "]+",
    re.UNICODE | re.MULTILINE,
)

OTHER_SYMS_RE = re.compile(
    r"[%s]{2,}" % (punctuation),
    re.MULTILINE,
)
PHONE_RE = re.compile(
    r"(((\+|00)251)|(0))"  # eth area code
    "\d{9}",  # 9 digits
    re.MULTILINE,
)
# Define a pattern that matches Amharic characters, arabic numerals, spaces, and punctuation
AM_UNICODE = r"\u1200-\u137F"  # Amharic unicode range
AM_PAT = rf"[{AM_UNICODE}0-9\s{re.escape(punctuation)}]+"
AM_RE = re.compile(AM_PAT, re.UNICODE)

# pattern for irrelevant characters
IRRELEVANT_PAT = r"[^a-zA-Z0-9\u1200-\u137F\s%s]" % re.escape("%#._+,/():|*@?$&-")
IRRELEVANT_RE = re.compile(IRRELEVANT_PAT, re.IGNORECASE | re.UNICODE)
