import json
from pathlib import Path
import re
import pandas as pd
import sys

sys.path.append("./script/")
from property_schema import PROPERTY_SCHEMA
from helpers.helpers_io import write_to_csv, read_json



def escape_quotes(text):
    """
    Escape dobule quotes in a JSON string.
    """
    lines = text.splitlines()
    cleaned_lines = []
    for line in lines:
        parts = line.strip().split(": ")
        if len(parts) == 2:
            key, value = parts
            value = re.sub(r'^"', r".'.", value)
            value = re.sub(r'"([,\s]*)$', r".'.\1", value)
            value = value.replace('"', "'").replace(".'.", '"')
            cleaned_line = f"{key}: {value}"
        else:
            cleaned_line = line
        cleaned_lines.append(cleaned_line)

    text = "\n".join(cleaned_lines)

    return text


def parse_json(text):
    if isinstance(text, list) and len(text) == 1:
        text = text[0]
    if not isinstance(text, str):
        raise TypeError("Expecting a string.")
    elif not text.startswith("```json"):
        raise ValueError("Expecting a markdown code block with JSON.")

    clean = text.removeprefix("```json").removesuffix("```")
    try:
        return json.loads(clean)
    except json.JSONDecodeError:
        pass
    # Try manipulating the text
    try:
        # Remove comments
        clean = re.sub(r"(?<!https:)//\s+.*(?=\n)", "", clean)
        return json.loads(clean)
    except json.JSONDecodeError:
        pass  # Try other methods
    try:
        # Remove trailing commas
        clean = re.sub(r",(\s*(?=\}))", r"\1", clean)
        return json.loads(clean)
    except json.JSONDecodeError:
        pass
    try:
        # Escape quotes
        clean = escape_quotes(clean)
        return json.loads(clean)
    except json.JSONDecodeError as e:
        # Give up :(
        print(
            f"Error: Invalid JSON (just give up) for input <<{text[0:10]}...{text[-10:]}>>"
        )
        raise e


def get_list_keys(record: dict):
    """
    Get keys of values that have list of dicts in a dict.
    """
    if not isinstance(record, dict):
        raise TypeError("Expecting a dict.")
    list_keys = []
    for k, v in record.items():
        if isinstance(v, list) and len(v) > 0 and all(isinstance(vv, dict) for vv in v):
            list_keys.append(k)
    return list_keys


def expand_dict_on_list_values(record):
    """
    Expand a dict with values of list of dicts into multiple records.
    """
    list_keys = get_list_keys(record)
    if not list_keys:
        return record

    lengths = list({len(record[key]) for key in list_keys})
    if len(lengths) > 1:
        length = min(lengths)
        print(
            f"Warning: All fields to expand do not have lists of the same length. {lengths=}. Keeping the min {length}."
        )
    else:
        length = lengths[0]

    records = []
    for i in range(length):
        new_record = {k: v for k, v in record.items() if k not in list_keys}
        for key in list_keys:
            new_record[key] = record[key][i]
        records.append(new_record)

    return records


def tidy_attributes(json_path):
    """
    Tidy attributes json data extracted with gemini-pro.
    """
    data = read_json(json_path)
    d = []
    bad_keys = []
    for item in data:
        output = item.get("output")
        if not output or "error" in output:
            continue
        if isinstance(output, str):
            try:
                output = parse_json(output)
            except ValueError:
                print(f"Warning: Unexpected output @{item['id']}: {output}")
                bad_keys.append(item["id"])
                continue
        # Check if there are multiple records
        if isinstance(output, list):
            lo = len(output)
            if lo == 1:
                output = output[0]
                if isinstance(output, str):
                    try:
                        output = parse_json(output)
                    except ValueError:
                        print(f"Warning: Unexpected output @{item['id']}: {output}")
                        bad_keys.append(item["id"])
                        continue
                else:
                    # Check if there are a list of dicts for a key
                    # e.g. "price": [{'amount': 2000, 'currency': 'ETB'}, {'amount': 3000, 'currency': 'ETB'}]
                    list_keys = get_list_keys(output)
                    if list_keys:
                        expanded = expand_dict_on_list_values(output)
                        for i, expanded_i in enumerate(expanded):
                            nid = (
                                f"{item['id']}_expand_suffix_{str(i)}"
                                if i > 0
                                else item["id"]
                            )
                            d.append(
                                {
                                    "id": nid,
                                    **expanded_i,
                                    "input": item["input"],
                                }
                            )
                    else:
                        d.append({"id": item["id"], **output, "input": item["input"]})
            elif lo > 1:
                for i in range(lo):
                    nid = f"{item['id']}_multi_suffix_{str(i)}" if i > 0 else item["id"]
                    d.append({"id": nid, **output[i], "input": item["input"]})
        elif isinstance(output, dict):
            d.append({"id": item["id"], **output, "input": item["input"]})

    data_tidy = pd.json_normalize(d)

    def _join_list(x):
        if isinstance(x, list):
            return ";".join(str(element) for element in x)
        else:
            return x

    for var in data_tidy.columns:
        data_tidy[var] = data_tidy[var].apply(_join_list)

    return data_tidy


def filter_cols_by_NA_frac(df, threshold=0.95, include_list=None, verbose=True):
    """
    Drop columns in a DataFrame if the fraction of NA values >= `threshold`.
    `include_list`: List of columns to include regardless of their NA fraction.
    """
    # Check if df is None or empty
    if df is None or df.empty:
        raise ValueError("Input dataframe is None or empty.")

    # Validate threshold
    if not 0 <= threshold <= 1:
        raise ValueError("threshold must be a number between 0 and 1.")

    # Validate and process include_list
    if include_list is None:
        include_list = []
    elif isinstance(include_list, str):
        include_list = [include_list]
    elif not isinstance(include_list, list):
        raise TypeError("include_list must be a list or a string.")

    # Check if include_list contains valid columns
    for col in include_list:
        if col not in df.columns:
            print(f"Warning: Column '{col}' in include_list is not in the dataframe.")
            include_list.remove(col)

    include_set = set(include_list)

    # Calculate the fraction of NA values for all columns
    na_frac = df.isna().mean()

    # Determine columns to drop based on threshold and include_list
    drop_cols = [
        col
        for col in df.columns
        if col not in include_set and na_frac[col] >= threshold
    ]

    # Drop missing engulfed columns
    df = df.drop(drop_cols, axis=1)

    # Print verbose information
    if verbose:
        if drop_cols:
            print(f"Dropped columns: {drop_cols} that have NA fraction >= {threshold}.")
        if include_set:
            print(f"Included columns: {include_list}")

    return df


# Reorder columns
# Like data.table::setcolorder (without the inplace modification capability)
def set_col_order(df):
    # Patterns for the columns to be moved to the front
    patterns = [
        "id",
        "listing(.*type)?",
        "(property.*)?type",
        "price.*",
        "size.*",
        "address.*",
        "input",
        ".*rooms|features.*",
        ".*condition",
        "seller.*",
    ]

    # Construct main_vars from patterns
    main_vars = []
    for pattern in patterns:
        main_vars.extend([c for c in df.columns if re.match(pattern, c)])

    # Drop duplicates
    main_vars = list(dict.fromkeys(main_vars))  # `set` does not preserve order

    # Reorder columns
    order_cols = [c for c in main_vars if c in df.columns] + [
        c for c in df.columns if c not in main_vars
    ]

    return df.reindex(columns=order_cols)


# Import the schema
def load_schema(schema: str = PROPERTY_SCHEMA) -> dict:
    schema = json.loads(re.sub(r"//.*(?=\n)", "", schema))  # Remove comments
    return schema


def clean_and_prep_data(data_path: str, schema: dict, include_list: list):
    # Tidy the data
    data_extracted = tidy_attributes(data_path)

    # Drop 'all NA' columns upfront
    data_extracted = filter_cols_by_NA_frac(data_extracted, 0.99)

    # key vars + vars defined in the schema -> main_vars
    cols_main = ["id", "input"] + list(pd.json_normalize(schema).columns)
    cols_main = list(dict.fromkeys(cols_main))  # Remove duplicates

    # Drop vars not in the df
    cols_main = [c for c in cols_main if c in data_extracted.columns]
    # The main variables extracted by Gemini Pro
    data_extracted_main = data_extracted[cols_main]

    # Other variables extracted by Gemini Pro (relevant or otherwise) but are not explicitly defined in the schema.
    # These variables are kept in case they are useful for imputation of missing values or for other purposes.
    extra_cols = list(set(data_extracted.columns) - set(cols_main)) + [
        "id",
        "input",
    ]
    # Maybe useful for imputation of missing values or for other purposes
    data_extracted_extra = data_extracted[extra_cols]

    # Drop vars with high number of NA values,
    # keep the ones in include_list regardless
    data_extracted_main = filter_cols_by_NA_frac(
        data_extracted_main, include_list=include_list
    )
    data_extracted_main = set_col_order(data_extracted_main)

    return data_extracted_main, data_extracted_extra


def main():
    # Import data ----
    data_dir = Path("./data/housing/processed/structured/")
    data_paths = [
      "listings_cleaned__extracted_property_attributes__gemini.json",
    "loozap_cleaned__extracted_property_attributes__gemini.json",
       "ethiopianproperties_cleaned__extracted_property_attributes__gemini.json",
       "ethiopiapropertycentre_cleaned__extracted_property_attributes__gemini.json",
    ]
    data_paths = [data_dir / p for p in data_paths]

    schema = load_schema(PROPERTY_SCHEMA)

    # Keep them even with high number of NA values
    include_list = [
        "features.counts.units",
        "features.counts.floors",
        "location.floor",
        "additional.basement",
        "additional.furnishing",
        "additional.pets_allowed",
    ]

    for path in data_paths:
        print(f"Processing {path.name} ...")
        data_main, data_extra = clean_and_prep_data(path, schema, include_list)

        # Important ones
        write_to_csv(data_main, data_dir / "tidy" / (path.stem + "__tidy.csv"))

        # Extra
        write_to_csv(
            data_extra, data_dir / "tidy" / "extra" / (path.stem + "__extra.csv")
        )


if __name__ == "__main__":
    main()
