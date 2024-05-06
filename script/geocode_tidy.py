import glob
import sys
from pathlib import Path
import pandas as pd


sys.path.append("script")
from helpers.helpers_io import read_json, write_json, extract_file_number


# Read in the geocoding data
def load_geocoding_results(dir, pattern):
    file_list = glob.glob(pattern, root_dir=dir)
    file_list.sort(key=extract_file_number)
    addresses = pd.read_csv(
        "./data/geodata/geocode/property_addresses__unique.csv",
        usecols=["address_main", "address_alt"],
    )
    addresses = (
        addresses[["address_main", "address_alt"]].to_records(index=False).tolist()
    )
    data_list = []
    for file in file_list:
        data = read_json(Path(dir) / file)
        # n = len(data)
        # # data = [item for item in data if item and item.get("results")]
        # data_relevant = []
        # for item in data:
        #     try:
        #         if (item["address_main"], item["address_alt"]) in addresses:
        #             data_relevant.append(item)
        #     except KeyError:
        #         print(
        #             f"Skipping {item} in {file} because it does not have address_main and address_alt keys."
        #         )
        #         continue
        # data = data_relevant
        # if len(data) < n:
        #     if len(data) / n < 0.85:
        #         # Guard against overwriting the data accidentally
        #         sys.exit(
        #             "There is something off, this much overwriting may not be intended. Review the data and try again"
        #         )
        #     write_json(data, Path(dir) / file, overwrite=True)
        dataOk = []
        for _, d in enumerate(data):
            if not d:
                continue
            d["file"] = Path(file).name
            dataOk.append(d)
        data_list.extend(dataOk)
    return data_list


def pluck_info(result: dict) -> dict:
    """Extract important attributes from the geocoding results.
    Uses 'address_components' and 'osm_id' keys to disambiguate between Google Maps and OpenStreetMap results."""
    if not isinstance(result, dict):
        raise TypeError("result must be a dict.")
    if "address_components" in result:  # from gmaps
        # NB: formatted_address can be too broad for some addresses, do not take it as the definite name of the place.
        # Use the place_id for further details about the place.
        # Example: gmaps geocoding returns formatted_address 'Bole, Addis Ababa, Ethiopia' for address 'semit fiyel bet addis ababa'
        # You can use the place_id 'ChIJnUKOBY6aSxYROrGznRQrKiI' or the plus_code '2V53+V2 Addis Ababa'.
        return {
            "place_name": result["formatted_address"],
            "place_id": result["place_id"],
            "lat": result["geometry"]["location"]["lat"],
            "lng": result["geometry"]["location"]["lng"],
            "plus_code": result.get("plus_code", {}).get("global_code", ""),
        }
    elif "osm_id" in result:  # from osm-nominatim
        return {
            "place_name": result.get("name", result["display_name"]),
            "place_id": result["place_id"],
            "lat": result["lat"],
            "lng": result["lon"],
        }
    else:
        raise ValueError("Result must contain either 'address_components' or 'osm_id'")


def tidy_geocoding_results(data: list[dict]) -> list[dict]:
    """
    Transforms a list of geocoding results into a tidier format.
    """
    data_tidy = []
    for i, item in enumerate(data):
        if not item:
            continue
        results = item["results"]
        if not results:
            continue
        other_info = {
            k: v for k, v in item.items() if k not in ["results", "ids", "suggestion"]
        }

        # Flatten the suggestion object
        if "suggestion" in item:
            suggestion = item.get("suggestion", {})
            if suggestion:
                for k, v in suggestion.items():
                    if not v:
                        continue
                    # geometry is one level deep
                    if isinstance(v, dict):
                        for k2, v2 in v.items():
                            other_info[f"suggestion_{k}_{k2}"] = v2
                    else:
                        other_info[f"suggestion_{k}"] = v
            # item.pop("suggestion")

        for j, id_ in enumerate(item["ids"]):
            # If the `results` contains muliple addresses, cycle through each and distribute them across IDs to add uniqueness. This bets on the proximity of the addresses returned, which is mostly true for both gmaps and OSM results. In the latter, the number of returned addresses are controlled by `limit`.
            # result = results[j % len(results)]
            result = results[0]
            info = pluck_info(result)
            dataTidy = {"id": id_, "unique_address_grp": i, **info, **other_info}
            data_tidy.append(dataTidy)
    return data_tidy


def main():
    dir = "./data/geodata/geocode/intermittents/"
    patterns = [
        "search/geocoding_results__search__*.json",
        "autocomplete/geocoding_results__autocomplete__*.json",
    ]
    fmt = "./data/geodata/geocode/geocoded_{0}__{1}.{2}"
    for pattern in patterns:
        data = load_geocoding_results(dir, pattern)
        write_json(
            data, fmt.format("results", Path(pattern).parent, "json"), overwrite=True
        )
        # remove those whose geocoding did not succeed
        data_tidy = [item for item in data if "results" in item and item["results"]]
        data_tidy = tidy_geocoding_results(data_tidy)
        write_json(
            data_tidy,
            fmt.format("addresses", Path(pattern).parent, "json"),
            overwrite=True,
        )
        data_tidy = pd.DataFrame(data_tidy)
        data_tidy.to_csv(
            fmt.format("addresses", Path(pattern).parent, "csv"), index=False
        )


if __name__ == "__main__":
    main()
