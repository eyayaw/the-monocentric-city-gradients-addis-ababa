# Constants for regular expressions
emojies = c(
  "\U0001F600-\U0001F64F",
  "\U0001F300-\U0001F5FF",
  "\U0001F680-\U0001F6FF",
  "\U0001F1E0-\U0001F1FF",
  "\U00002500-\U00002BEF",
  "\U00002702-\U000027B0",
  "\U00002702-\U000027B0",
  "\U000024C2-\U0001F251",
  "\U0001f926-\U0001f937",
  "\U00010000-\U0010ffff",
  "\u2640-\u2642",
  "\u2600-\u2B55",
  "\u200d",
  "\u23cf",
  "\u23e9",
  "\u231a",
  "\ufe0f",
  "\u3030",
  "\u1363" # Amharic comma
)
phone_num_regex = r"[(((\+|00)?251)?(?<sup>[\/. -]*))((0?9)\g<sup>([0-9]\g<sup>){8}|((?:11|22)\g<sup>([0-9]\g<sup>){7}))]"
other_syms = "[^0-9a-zA-Z|+/%._,()'\"\\p{Script=Ethiopic}\\s-]"
# Use this vector in perl-compatible regexes, TRE complains about {}
punctuation = sprintf(r'([%s])', "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~") # r"([[:punct:]])"
punctuation_exceptions = "+.|/" # trim_punct(exclude=*) does not remove these
amharic_nums = "(?:አንድ|ሁለት|ሶስት|አራት|አምስት|ስድስት|ሰባት|ስምንት|ዘጠኝ|አስር)"
