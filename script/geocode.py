import csv
import logging
import time
from typing import Generator
import requests
from functools import lru_cache

from tqdm import tqdm
from helpers.helpers_geocoding import (
    AddressData,
    GeocodeError,
    NotValidAddressError,
    standardize_address,
    trim_words,
    validate_address,
    tidy_address,
)
from helpers.helpers_io import read_json, setup_logger, write_json

setup_logger(__name__, "./logs/geocoding.log", console_level=50)
logger = logging.getLogger(__name__)


@lru_cache(128 * 3)
def geocode_gmaps(api_key, address):
    endpoint = "https://maps.googleapis.com/maps/api/geocode/json"
    params = {
        "key": api_key,
        "address": address,
        "bounds": "rectangle:8.7825,38.5951|9.2320,38.9760",
        "components": "country:et|administrative_area:Addis+Ababa",
        "region": "et",
        "language": "en-US",
    }

    try:
        response = requests.get(endpoint, params=params)
        response.raise_for_status()
    except requests.exceptions.RequestException as e:
        logger.exception("Failed to make geocode API call for address: {address}")
        raise GeocodeError(f"API Error: {e}")
    else:
        return response.json()["results"]


@lru_cache(128 * 3)
def autocomplete_gmaps(api_key, address, types=None):
    endpoint = "https://maps.googleapis.com/maps/api/place/autocomplete/json"
    params = {
        "key": api_key,
        "input": address,
        "types": types,  #'geocode' #'point_of_interest|establishment'
        "components": "country:et",
        "locationrestriction": "rectangle:8.7825,38.5951|9.2320,38.9760",
        "strictbounds": "true",
        "language": "en-US",
    }

    try:
        response = requests.get(endpoint, params=params)
        response.raise_for_status()
    except requests.exceptions.RequestException as e:
        logger.exception("Failed to make autocomplete API call for address: {address}")
        raise GeocodeError(f"API Error: {e}")
    else:
        return response.json()


@lru_cache(128 * 3)
def search_gmaps(api_key, address):
    endpoint = "https://maps.googleapis.com/maps/api/place/findplacefromtext/json"
    params = {
        "key": api_key,
        "input": address,
        "inputtype": "textquery",
        "fields": "formatted_address,name,geometry,plus_code",
        "locationbias": "rectangle:8.7825,38.5951|9.2320,38.9760",
        "language": "en-US",
    }

    try:
        response = requests.get(endpoint, params=params)
        response.raise_for_status()
    except requests.exceptions.RequestException as e:
        logger.exception("Failed to make gmaps search API call for address: {address}")
        raise GeocodeError(f"API Error: {e}")
    else:
        return response.json()


@lru_cache
def geocode_nominatim(address, limit=5):
    endpoint = "https://nominatim.openstreetmap.org/search"
    params = {
        "q": address,
        "format": "json",
        "addressdetails": "1",
        "namedetails": "1",
        "countrycodes": "ET",
        "limit": limit,
        "viewbox": "38.5951,8.7825,38.9760,9.2320",
        "bounded": "1",
        "layer": "address,poi,railway,natural,manmade",
        "accept-language": "en-US",
        "email": "etb@tuta.com",
    }

    try:
        response = requests.get(endpoint, params=params)
        response.raise_for_status()
    except requests.exceptions.RequestException as e:
        logger.exception(
            f"Failed to make Nominatim geocode API call for address: '{address}'. Error: {e}"
        )
        raise GeocodeError(f"API error: {e}")
    else:
        return response.json()


def extract_suggestion(result, key):
    if key not in ["description", "formatted_address"]:
        raise ValueError(f"{key} must be either 'description' or 'formatted_address'")

    if not result:
        return {}

    first = result[0]
    suggested_address = first.get(key)
    if suggested_address:
        return {
            "suggested_address": suggested_address,
            "geometry": first.get("geometry", {}).get("location"),
            "name": first.get("name"),
            "place_id": first.get("place_id"),
            "plus_code": first.get("plus_code", {}).get("global_code"),
        }
    return {}


def get_suggestion_gmaps(api_key, address, api_name):
    if api_name not in ["autocomplete", "search"]:
        raise ValueError(f"{api_name} must be either 'autocomplete' or 'search'")

    apis = {
        "autocomplete": {
            "function": autocomplete_gmaps,
            "key1": "predictions",
            "key2": "description",
        },
        "search": {
            "function": search_gmaps,
            "key1": "candidates",
            "key2": "formatted_address",
        },
    }

    try:
        result = apis[api_name]["function"](api_key, address)
        suggestion = extract_suggestion(
            result[apis[api_name]["key1"]], apis[api_name]["key2"]
        )
        if suggestion:
            logger.info(
                f"Suggestion found via the gmaps {api_name} api. ['{address}', '{suggestion['suggested_address']}']"
            )
            return suggestion
    except GeocodeError as e:
        logger.exception(
            f"Error getting suggestion for address: '{address}' using Google Maps {api_name} API, {e}"
        )

    return {}


def geocode_gmaps_robust(
    api_key, api_key2, address: str, api, allowed_num_words=2
) -> dict:
    if not validate_address(address):
        raise NotValidAddressError(f"Invalid address: '{address}'")

    clean_address = standardize_address(address)
    suggestion = get_suggestion_gmaps(api_key, clean_address, api)
    suggested_address = suggestion.get("suggested_address")
    if suggested_address:
        try:
            # Attempt geocoding with suggested address
            results = geocode_gmaps(api_key2, suggested_address)
            if results:
                logger.info(
                    f"gmaps geocoding succeeded for '{address}' with suggestion '{suggested_address}' via api '{api}'"
                )
                return {
                    "address": address,
                    "results": results,
                    "suggestion": suggestion,
                }

        except GeocodeError as e:
            logger.error(f"gmaps geocoding failed for address '{address}', due to {e}")
            return {}

    # Try to trim the address and search for each trimmed part.
    if len(clean_address.split()) < allowed_num_words:
        logger.warning(
            f"gmaps geocoding failed for '{address}' and trimming won't be attempted b/c it is too short"
        )
        return {"address": address, "results": []}

    for side in ["right", "left", "center"]:
        choices = trim_words(clean_address, side)
        logger.debug(f"Trimming from the '{side}' side ...: {choices}")

        for choice in choices:
            choice = tidy_address(choice)
            if not validate_address(choice) or len(choice.split()) < allowed_num_words:
                continue
            suggestion = get_suggestion_gmaps(api_key, choice, api)
            suggested_address = suggestion.get("suggested_address")
            if suggested_address:
                # Attempt geocoding with suggested trimmed address
                try:
                    results = geocode_gmaps(api_key2, suggested_address)
                    if results:
                        logger.info(
                            f"gmaps geocoding succeeded for '{address}' with {side}-trimming '{choice}' leading to suggestion '{suggested_address}' via api '{api}'"
                        )
                        return {
                            "address": address,
                            "results": results,
                            "suggestion": suggestion,
                            "trimmed_address": choice,
                        }
                except GeocodeError as e:
                    logger.error(
                        f"gmaps geocoding failed for address '{address}', due to {e}"
                    )
                    return {}

        time.sleep(0.1)
    logger.warning(f"All gmaps geocoding attempts failed for '{address}'")
    return {"address": address, "results": []}


def geocode_nominatim_robust(address: str, allowed_num_words=2) -> dict:
    if not validate_address(address):
        raise NotValidAddressError(f"Invalid address: '{address}'")

    clean_address = standardize_address(address)

    try:
        results = geocode_nominatim(clean_address)
        if results:
            return {"address": address, "results": results}
    except GeocodeError as e:
        logger.error(f"Nominatim geocoding failed for address '{address}', due to {e}")
        return {}

    # Try to trim the address and search for each trimmed part.
    if len(clean_address.split()) < allowed_num_words:
        logger.info(f"Address too short, trimming won't be attempted for '{address}'")
        return {"address": address, "results": []}
    for side in ["right", "left", "center"]:
        # logger.debug(f"Trimming from the '{side}' side ...")
        choices = trim_words(clean_address, side)
        for choice in choices:
            choice = tidy_address(choice)
            if not validate_address(choice) or len(choice.split()) < allowed_num_words:
                continue
            try:
                results = geocode_nominatim(choice)
                if results:
                    logger.info(
                        f"Nominatim geocoding succeeded for '{address}' with {side}-trimming '{choice}'"
                    )
                    return {
                        "address": address,
                        "trimmed_address": choice,
                        "results": results,
                    }
            except GeocodeError as e:
                logger.error(
                    f"Nominatim geocoding failed for address '{address}', due to {e}"
                )
                return {}

        time.sleep(0.1)
    logger.warning(f"All Nominatim geocoding attempts failed for '{address}'")
    return {"address": address, "results": []}


def _create_result_dict(
    address_data, results, source, suggestion=None, trimmed_address=None
):
    return {
        "address_main": address_data.main,
        "address_alt": address_data.alternative,
        "ids": address_data.ids,
        "results": results,
        "source": source,
        "suggestion": suggestion,
        "trimmed_address": trimmed_address,
    }


def geocode_address(
    api_key, api_key2, address_data: AddressData, api, allowed_num_words=2
) -> dict:
    if not validate_address(address_data.main):
        logger.error(
            f'Invalid address "{address_data.main}", alt address "{address_data.alternative}" not used.'
        )
        return _create_result_dict(address_data, [], None)
    if address_data.use_api not in ["search", "autocomplete"]:
        raise TypeError(f'use_api should be one of {["search", "autocomplete"]}')
    for address in dict.fromkeys([address_data.main, address_data.alternative]):
        if not validate_address(address):
            break
        try:
            # # TODO: add more exceptions to the is_exception and play with min num of words an address must have to be trimmed for tems in locality terms.
            # if len(address.split()) < 4:
            #     address = tidy_trimmed(address)
            if len(address.split()) > 5:
                # nominatim not reliable for addresses like 22 sefer
                results = geocode_nominatim(address)
                if results:
                    return _create_result_dict(
                        address_data, results, "geocode_nominatim"
                    )
            if all(word.strip().isdigit() for word in tidy_address(address).split()):
                logger.error(f"Only digit address found: '{address}'")
                continue
            results = geocode_gmaps_robust(
                api_key, api_key2, address, api, allowed_num_words
            )
            if results["results"]:
                return _create_result_dict(
                    address_data,
                    results["results"],
                    f"gmaps_geocode_robust[{api}]",
                    results.get("suggestion"),
                    results.get("trimmed_address"),
                )
        except GeocodeError:
            logger.error(f"API Error: {address_data.main}, {address_data.alternative}")
            return {}
        except NotValidAddressError:
            break

    logger.error(
        f"gmaps geocoding failed for '{address_data.main}' and '{address_data.alternative}'"
    )
    return _create_result_dict(address_data, [], None)


def geocode_addresses(api_keys, api_keys2, addresses, api, dump_interval=250):
    results = []
    dump_counter = 0  # Initialize a counter for dumps

    for i, address_data in enumerate(tqdm(addresses), start=1):
        api_key = api_keys[i % len(api_keys)]
        api_key2 = api_keys2[i % len(api_keys2)]
        try:
            result = geocode_address(api_key, api_key2, address_data, api)
            results.append(result)
        except (GeocodeError, NotValidAddressError):
            continue

        # Check if it's time to dump results to a file
        if i % dump_interval == 0 or i == len(addresses):
            dump_counter += 1  # Increment dump counter
            filename = f"./data/geodata/geocode/intermittents/geocoding_results__{api}__{dump_counter:0>2}.json"
            write_json(results, filename)
            results = []  # Reset results after dumping

        time.sleep(0.5)


def load_addresses(file_path) -> Generator:
    csv.field_size_limit(1000_000)
    with open(file_path, "r") as file:
        csv_reader = csv.DictReader(file)
        for row in csv_reader:
            ids = [id_.strip() for id_ in row["ids"].split(",")]
            yield AddressData(
                row["address_main"],
                row["address_alt"],
                row["use_api"],
                ids,
            )


def get_api_keys() -> dict:
    api_keys = read_json("./script/.gmaps_api_keys.json")
    return api_keys


if __name__ == "__main__":
    api_keys = list(get_api_keys()["autocomplete"].values())
    api_keys2 = list(get_api_keys()["geocode"].values())
    addresses = load_addresses("./data/geodata/geocode/property_addresses__unique.csv")
    
    API_NAME = "search"
    file = f"./data/geodata/geocode/geocoded_results__{API_NAME}.json"
    geocoded = read_json(file)
    already_geocoded = [(d["address_main"], d["address_alt"]) for d in geocoded]
    not_geocoded = []
    for address in addresses:
        if (address.main, address.alternative) not in already_geocoded:
            not_geocoded.append(address)
    # addresses = [d for d in addresses if (d.main, d.alternative) not in already_geocoded]
    geocode_addresses(api_keys, api_keys2, not_geocoded, API_NAME, dump_interval=100)
