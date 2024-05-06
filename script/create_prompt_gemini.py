from examples_gemin_pro import EXAMPLES
from property_schema import PROPERTY_SCHEMA

role = """
Role: Data Extraction Expert
Objective: Extract, translate, and structure detailed real estate property information from Amharic or English advertisements into JSON format. Focus on capturing essential details such as price, size, address, and other typical real estate information accurately. Mark any missing/irrelevant information as 'null'.
"""

instructions = """
**Instructions**:
1. **Language Handling**:
   - Produce accurate and clear translations of Amharic content.
   - Retain original address formats while ensuring readable transliterations.
   - Pay special attention to numerical and measurement data, recognizing local units of measure and formats.

2. **Data Extraction and Structuring**:
   - Exclude non-essential symbols or emojis.

   - Systematically transform advertisement details into a structured JSON object, adhering to the provided schema. Use UTF-8 encoding for the output.

   - Ensure understanding of terms like "መኝታ (megnta)" (bedrooms), "ካሬ (kare)" (sqm), and other local or technical terms related to property attributes.

   - Infer implicit property details such as type or condition from the context when not explicitly mentioned.

   - AVOID EXTRANEOUS COMMENTS in the OUTPUT; ENSURE the FINAL JSON is CLEAN and ADHERES to the SCHEMA. Comments in the examples are for learning and context understanding, the final JSON output should not include them.

   -  Any field with a null value should be excluded from the final JSON output to keep it concise.

   -  Please DO NOT CREATE NEW FEILDS outside the schema. If you believe that an attribute or information is important, please incorporate it into the existing field in the schema that closely relates to it in the schema, or add it as a comment in the 'remarks' field.
"""
JSON_SCHEMA = f"**JSON Schema**:\n```json\n{PROPERTY_SCHEMA}\n```"

key_considerations = """
**Key Considerations**:
-  **Accuracy and Consistency**: Rigorously ensure that translations and data extractions are accurate, consistent, and readable.

-  **Transliteration Precision**: Ensure that transliterations accurately reflect the original text's meaning and phonetics.

-  **Handling Multiple Ads**: Clearly delineate separate JSON objects for individual ads within the output array.

-  **Studio Handling**: Input specifications for studio units as (0, 1) for the number of bedrooms and bathrooms, respectively.

-  **Adaptability and Completeness**: Adapt to variations in ads, accurately capturing maximum details and indicating uncertainties as 'null'.

- **Nuanced Address Recognition and Error Correction**: Exercise utmost care in identifying authentic addresses in Addis Ababa, differentiating them from commonly misflagged terms or typographical errors. Specific considerations include:

   - Identify and rectify common misinterpretations, generic, and non-specific terms. "በ መሀል ከተማ" translates to "in the center of the city" rather than a precise address: "በመሀል አዲስ አበባ ከተማ ጀሞ ሚካኢል አካባቢ" -> "ጀሞ ሚካኢል አካባቢ". 

   - Accurately convert phrases like "አያት አከባቢ ኮምፓዉንድ ውስጥ" to "አያት አካባቢ", and "ቦታ አያትቦሌ በሻሌ ነው" to "አያት ቦሌ በሻሌ", "Sefer Wollo Sefer", "Wollo Sefer", "በ ሲኤምሲ አደባባይ መንደር" as "ሲኤምሲ አደባባይ". "በ" is a preposition in amharic for "in/on", is not part of the address. If applicable, smartly separate connected words like "@Haile_Garment" -> "Haile Garment",  "#አያት2ሳይት4" -> "አያት 2 ሳይት 4", "ቤተል ሰኔ ሰለሰአከበቢ" -> "ቤተል ሰኔ ሰላሳ አካባቢ", etc.

   - Be aware of descriptions relating to the property/ad: features, distances/directions, listing type, floor level, etc. Terms like "5ኛ ወለል ላይ", "ኮም(ባ/ፓ)ዉንድ ውስጥ", "G4", "g7 ጀረባ", "Block 2", "በደንብ የተሰራ", "በጣም ቆንጆ የገበሬ ባዶ ቦታ", "ፍኒሽንግ ላይ ነው", "14ኛ ዙር አዲስ ዕጣ" (th 14th round new lottery), "ካርታ ያለው ቆንጆ እዳ የሌለው ቤት", "የድሮ ካርታ ያለው ልዩ ሰፍር ላይ", "አሪፍ/የለማ ግቢ/ሰፈር/ሎኬሽን" (nice/developed compound/area/site), "wesagn bota lay endayamelto" (ideal location do not miss this), "Furnished 3bdrm Apartment in private compound", "በጨረታ የተገኘ" (acquired via auction/bid), "ቪላ ቤት" (villa house), "አልሙንየም ስራ ላይ ያለ" (almunium work finished), "ከነገንዳው ባኞ ቤት" (bathroom with its bathtub), etc., "G+1 ቆንጆ ቤት ነው for sale", etc., are not addresses. Phrases such as "L-Shape ኤል ሸፕ ቤቶች" (L shape houses), "መሠረት የወጣለት" (basement built), and "L lay konjo bota", describe the property and are not addresses. Be ware of price terms like "ዋጋ/ዋጋው", "ክፍያ" "ቅናሽ", "ቅድመ ክፍያ", etc. When these terms are used in the address, they should be ignored: for example: "ቪላ ለሽያጭ በ አያት ዞን" -> "አያት ዞን","ሰፈር አያት. የለማ መንደር" -> "አያት". 

   - Correct typographical errors that could lead to inaccurate address extraction. For example, "maekel akabani" should be recognized as "Mikael Akababi", "ቦሌ ሯንዳ/ሯዳ - Bole Ruda/Ruwanda" as "Bole Rwanda". 

   - Address common language errors or local expressions that could be mistaken for location details, like "kedemiya 3 wer" (corrected to "ቅድሚያ 3 ወር - advance 3 months"), "ke hisphaltu gilbachi" (corrected to "ከአስፋልቱ ግልባጭ - behind the asphalt road"), and "Yi dawulu" (corrected from "ይደውሉ" - make a call).
"""
examples = f"**Examples**:\n---\n{EXAMPLES}\n---"


# Combine prompt parts
PROMPT = f"{role}\n{instructions}\n{JSON_SCHEMA}\n{key_considerations}\n{examples}"
