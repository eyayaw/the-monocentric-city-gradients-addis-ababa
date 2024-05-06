import asyncio
import logging
from pathlib import Path

from .helpers.helpers_io import read_json, write_json


from .extract_property_attributes_gemini import (
    configure_model,
    extract_attributes_with_retry,
    load_property_texts,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    filename="./logs/" + __file__ + ".log",
)


async def async_extract_attributes_with_retry(model, text, max_retries=4):
    loop = asyncio.get_running_loop()
    # Run the synchronous function in a ThreadPoolExecutor
    return await loop.run_in_executor(
        None, extract_attributes_with_retry, model, text, max_retries
    )


async def process_texts(
    texts, models, dump_interval=500, intermittent_prefix="intermittent_results"
):
    results = []
    tasks = []
    text_keys = list(texts.keys())  # Assuming texts is a dictionary

    for i, text in enumerate(text_keys):
        model = models[i % len(models)]
        # Directly associate each task with its text
        task = asyncio.create_task(async_extract_attributes_with_retry(model, text))
        # Store the task and its corresponding text together
        tasks.append((task, text))

        if (i + 1) % dump_interval == 0 or i == len(text_keys) - 1:
            # Wait for the current batch of tasks to complete
            for task, associated_text in tasks:
                completed_task = await task
                # use associated_text to accurately index into results
                if completed_task is not None:
                    for key in texts[associated_text]:
                        results.append({"id": key, **completed_task})
                else:
                    logging.error(f"Failed to extract attributes for {associated_text}")

            # Dump the results to a JSON file
            write_json(
                results,
                f"./data/housing/processed/structured/{intermittent_prefix}_{i // dump_interval}.json",
            )
            results = []  # Reset results after dumping
            tasks = []  # Clear tasks for the next batch


def get_api_keys():
    with open("./script/api_keys.txt", "r") as file:
        api_keys = file.read().splitlines()
        api_keys = [key.split("=")[1] for key in api_keys if key]  # Remove empty lines
    return api_keys


# Running the async process
if __name__ == "__main__":
    # Prepare models each configured with a different API key
    api_keys = get_api_keys()
    models = [configure_model(api_key=key) for key in api_keys]

    # Prepare texts
    data_dir = Path("./data/housing/processed")
    input_path = data_dir / "loozap_cleaned.csv"
    done_path = (
        data_dir
        / "structured"
        / f"{input_path.stem}_extracted_property_attributes_gemini.json"
    )

    texts = load_property_texts(input_path)
    try:
        done = read_json(done_path)
    except FileNotFoundError:
        done = {}
    texts = {text: keys for text, keys in texts.items() if keys[0] not in done}
    asyncio.run(process_texts(texts, models, intermittent_prefix=done_path.stem))
