import logging.handlers
import os
import glob
import json


def ensure_dir_exists(filepath):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    return filepath


def read_json(filepath: str, verbose: bool = False):
    try:
        with open(filepath, "r") as f:
            data = json.load(f)
        if verbose:
            print(f"Data has been read from {filepath}.")
        return data
    except FileNotFoundError:
        raise FileNotFoundError(f"File not found: {filepath}")
    except json.JSONDecodeError:
        raise json.JSONDecodeError(f"Error reading from {filepath}.")


def write_json(data, filepath, overwrite=False, verbose: bool = True):
    ensure_dir_exists(filepath)
    try:
        if not overwrite and os.path.exists(filepath):
            raise FileExistsError(f"File already exists: {filepath}")
        with open(filepath, "w") as f:
            if not data:
                if os.path.exists(filepath):
                    print(f"No data to write to {filepath}.")
                    return filepath
            json.dump(data, f, indent=2, ensure_ascii=False)
        if verbose:
            print(
                f"Writing [#records: {len(data)}] to {filepath}."
            )
        return filepath
    except Exception as e:
        raise Exception(f"Error writing data to {filepath}: {e}")


def update_json(file_path, new_data, file_size_limit=500e6):
    # file_size_limit is in bytes, 500e6 bytes is approximately 500MB
    # Load existing data
    if os.path.exists(file_path) and os.path.getsize(file_path) <= file_size_limit:
        existing_data = read_json(file_path)
    else:
        existing_data = {}

    # Update existing data with new data
    existing_data.update(new_data)

    # If file size exceeds limit, append suffix to filename
    if os.path.getsize(file_path) > file_size_limit:
        base, ext = os.path.splitext(file_path)
        suffix = 1
        while os.path.exists(f"{base}_part-{suffix}{ext}"):
            suffix += 1
        file_path = f"{base}_part-{suffix}{ext}"
        print(
            f"File size exceeded {file_size_limit} bytes, appending suffix to {file_path}."
        )

    # Write updated data back to file
    write_json(existing_data, file_path, overwrite=True)
    print(f"Appended new entries to an existing file={file_path}.")

    return file_path


# Write to CSV ----
def write_to_csv(df, path):
    """
    A wrapper to write a pandas DataFrame to a CSV file with index=False.
    Returns: Path to the file if successful, None otherwise.
    """
    try:
        ensure_dir_exists(path)
        df.to_csv(path, index=False)
        print(f"Data successfully written to {path}")
        return path
    except Exception as e:
        print(f"An unexpected error occurred {path=}: {e=}")


def setup_logger(
    name,
    file,
    level=logging.INFO,
    formatter="%(asctime)s : %(name)s: %(levelname)s : %(message)s",
    console_level=logging.WARNING,
):
    logger = logging.getLogger(name)

    # Prevent adding duplicate handlers
    if logger.hasHandlers():
        logger.handlers.clear()

    formatter = logging.Formatter(formatter)

    fileHandler = logging.handlers.RotatingFileHandler(
        file, maxBytes=10 * 1024 * 1024, backupCount=10
    )
    fileHandler.setFormatter(formatter)

    streamHandler = logging.StreamHandler()
    streamHandler.setFormatter(formatter)
    streamHandler.setLevel(console_level)

    logger.setLevel(level)
    logger.addHandler(fileHandler)
    logger.addHandler(streamHandler)

    # Prevent log messages from being passed to the handlers of higher-level (ancestor) loggers
    logger.propagate = False


# Read multiple JSON files into a single list
def list_files(dir_, pattern, *args, **kwargs):
    pattern = os.path.join(dir_, pattern)
    return glob.glob(pattern, *args, **kwargs)


def read_json_files(files):
    if not files:
        return []
    if isinstance(files, str):
        files = [files]
    data = []
    for file in files:
        data.extend(read_json(file))
    return data

def extract_file_number(file_name, split="__"):
    """Extract the number from a file name."""
    return int(file_name.rsplit(split, 1)[1].split(".")[0])
