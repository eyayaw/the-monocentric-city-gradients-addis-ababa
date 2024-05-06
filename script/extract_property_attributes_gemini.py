import csv
import logging
import os
import platform
import subprocess
import time
import json
from tqdm import tqdm
import google.generativeai as genai

from create_prompt_gemini import PROMPT
from helpers.helpers_io import setup_logger, write_json


logger = logging.getLogger(__name__)
setup_logger(__name__, "./logs/gemini.log")


def reconnect_vpn():
    """
    Reconnects the VPN via the Hotspot Shield VPN's cli on Linux.

    Returns:
    bool: True if successful, False otherwise.
    """
    if platform.system() != "Linux":
        logger.error(
            f"The VPN CLI can't be used on {platform.system()}. Please reconnect manually via the GUI."
        )
        return False

    logger.info("Reconnecting VPN...")
    command = ["hotspotshield", "connect", "us"]

    try:
        stdout = subprocess.run(
            command, shell=False, check=True, capture_output=True, text=True
        )
        logger.info(f"VPN reconnected successfully: {stdout}")
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to reconnect VPN: {e.output}")
        return False


def configure_model(api_key, temperature=0, top_p=0.9, **kwargs):
    """
    Configures a Gemini Pro generative model with the given parameters.
    Returns:
        genai.GenerativeModel: The configured model.
    """
    # # If the API key is not provided, retrieve it from the environment variables
    # if api_key is None:
    #     if "GOOGLE_GEMINI_PRO_API_KEY" not in os.environ:
    #         raise ValueError(
    #             "API key not provided and environment variable GOOGLE_GEMINI_PRO_API_KEY not set."
    #         )

    #     api_key = os.environ["GOOGLE_GEMINI_PRO_API_KEY"]

    genai.configure(api_key=api_key)

    # Set up the model
    generation_config = {
        "temperature": temperature,
        "top_p": top_p,
        "top_k": 1,
        "max_output_tokens": 2048,
        **kwargs,
    }

    safety_settings = [
        {"category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},
        {
            "category": "HARM_CATEGORY_HATE_SPEECH",
            "threshold": "BLOCK_MEDIUM_AND_ABOVE",
        },
        {
            "category": "HARM_CATEGORY_SEXUALLY_EXPLICIT",
            "threshold": "BLOCK_MEDIUM_AND_ABOVE",
        },
        {
            "category": "HARM_CATEGORY_DANGEROUS_CONTENT",
            "threshold": "BLOCK_MEDIUM_AND_ABOVE",
        },
    ]

    model = genai.GenerativeModel(
        model_name="gemini-1.5-pro-latest",
        generation_config=generation_config,
        safety_settings=safety_settings,
    )

    return model


def get_finish_reason(response):
    """
    Extracts the finish reason from the model's response.

    Parameters:
    response (object): The response from the model.

    Returns:
    str: The finish reason or None if not found.
    """
    try:
        return response.candidates[0].finish_reason.name
    except AttributeError:
        logger.error("No finish_reason in response.")
        return None


def parse_response(response):
    """
    Parses the response from the model and returns the output as JSON.

    Parameters:
    response (object): The response from the model.

    Returns:
    dict: The parsed response.
    """

    def _parse_json(response_text):
        try:
            return json.loads(
                response_text.removeprefix("```json\n").removesuffix("```")
            )
        except json.JSONDecodeError:
            logger.exception(
                f"Failed to decode JSON in `parse_response` for {response_text}."
            )
            return response_text

    if not response.parts:
        finish_reason = get_finish_reason(response)
        if finish_reason == "MAX_TOKENS":
            logger.error("Max tokens reached in `parse_response`.")
            return error_output(text, "MAX_TOKENS")
        else:
            logger.error(
                f"Empty response in `parse_response`. Finish Reason: {finish_reason}"
            )
            return error_output(
                text, f"No parts in response. Finish Reason: {finish_reason}"
            )

    return _parse_json(response.text)


def error_output(text, error_message):
    """
    Helper function to generate error output.

    Parameters:
    error_message (str): The error message.

    Returns:
    dict: The text as input and the error as output.
    """
    return {"input": text, "output": {"error": error_message}}


def extract_attributes(model, text):
    """
    Extract attributes from the model's response.

    Parameters:
    model (object): The model.
    text (str): The input text.

    Returns:
    dict: The input text and extracted attributes.
    """
    text_clean = " ".join(text.split())
    prompt_parts = f'{PROMPT}\n**Input**: "{text_clean}"\n**Output**: '
    response = model.generate_content(prompt_parts)
    output = parse_response(response)
    if "error" in output and output["error"] == "MAX_TOKENS":
        raise Exception(output["error"])
    return {"input": text, "output": output}


def extract_attributes_with_retry(model, text, max_retries=4):
    """
    Extract attributes with retries on certain exceptions.

    Parameters:
    model (object): The model.
    text (str): The input text.
    max_retries (int): The maximum number of retries.

    Returns:
    dict: The input text and extracted attributes.
    """
    retry_delay = 1  # Start with 1 second
    max_token_retry = 0

    for attempt in range(max_retries):
        try:
            return extract_attributes(model, text)
        except Exception as e:
            err_str = str(e)
            if "400" in err_str:
                # FailedPrecondition: 400 User location is not supported for the API use.
                logger.error(f"FailedPrecondition: {err_str}.")
                reconnect_vpn()
                time.sleep(retry_delay)
            elif "429" in err_str:
                logger.error(
                    f"Rate limit exceeded: {err_str}. Retrying in {retry_delay}s."
                )
                time.sleep(retry_delay)
                retry_delay *= 2  # exponential backoff
            elif "MAX_TOKENS" in err_str:
                max_token_retry += 1
                if max_token_retry >= 1:  # retry only twice
                    logger.error("Max retries reached for MAX_TOKENS error.")
                    return error_output("Max retries reached for exception: MAX_TOKENS")
            elif "500" in err_str or "503" in err_str:
                logger.error(f"Service unavailable/Server error: {err_str}. Skipping.")
                return error_output(text, f"Server error: {err_str}")
            # Check if all retries are exhausted for any other errors
            elif attempt == max_retries - 1:
                logger.error("Max retries reached")
                return error_output(text, "Max retries reached")


def combine_text(row: dict[str, str]) -> str:
    title = row.get("title", "")
    description = row.get("description", "")
    combined_text = []

    if title:
        combined_text.append(f"Title: {title}")
    if description:
        combined_text.append(f"Description: {description}")
    return "\n".join(combined_text)


def load_property_texts(path: str) -> dict[str, list[str]]:
    try:
        with open(path, "r", encoding="utf-8") as file:
            reader = csv.DictReader(file)
            texts = {row["id"]: combine_text(row) for row in reader if "id" in row}
    except (FileNotFoundError, csv.Error):
        logger.exception(f"Failed to load property texts from {path}.")
        return {}
    else:
        unique_texts = list(set(texts.values()))
        # Create a reverse dictionary mapping text to keys
        text_to_keys = {text: [] for text in unique_texts}
        for key, text in texts.items():
            text_to_keys[text].append(key)
        return text_to_keys


if __name__ == "__main__":
    # Configure the model
    model = configure_model(os.environ.get("GOOGLE_GEMINI_PRO_API_KEY"))

    # Define the input and output paths
    data_dir = "./data/housing/processed/"
    path = f"{data_dir}/listings_cleaned.csv"
    base_name = os.path.splitext(os.path.basename(path))[0]
    out_filename = (
        f"{data_dir}/structured/{base_name}_extracted_property_attributes_gemini.json"
    )

    # Load the data
    text_to_keys = load_property_texts(path)

    results = []
    # Extract attributes for each unique text and map the results to the keys
    for i, text in enumerate(tqdm(text_to_keys.keys()), 1):
        extracted = extract_attributes_with_retry(model, text)
        for key in text_to_keys[text]:
            results.append({"id": key, **extracted})
        # Save the results, every 500 ads or at the end
        if i % 500 == 0 or i == len(text_to_keys.keys()):
            write_json(results, out_filename)
