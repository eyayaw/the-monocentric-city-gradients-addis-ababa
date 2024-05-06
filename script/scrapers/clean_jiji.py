import json
import pandas as pd
from pathlib import Path


# simplify the attrs only keeping name and value of each attr, and unit if not none
def simplify_attrs(attrs: list[dict]) -> dict:
    simplified_attrs = {}
    for attr in attrs:
        name = attr["name"].lower().replace(" ", "_")
        unit = attr["unit"] if attr["unit"] else ""
        var_name = "_".join([name, unit]) if unit else name
        value = attr["value"]
        if isinstance(value, list):
            value = "; ".join(value)
        elif isinstance(value, dict):
            value = "; ".join(f"{k}: {v}" for k, v in value.items())
        if var_name in simplified_attrs:
            suffix = len(simplified_attrs)
            print(
                f"Warning: {var_name} already exists, renaming to {var_name}_{suffix}"
            )
            var_name = f"{var_name}_{suffix}"
        simplified_attrs[var_name] = value
    return simplified_attrs


def tidy_price(price: dict, prefix: str = "price"):
    price_tidy = [(f"{prefix}_{k}", v) for k, v in price.items()]
    price_tidy.append((f"{prefix}_currency", price.get("title").split()[0]))
    return dict(price_tidy)


# simplify the attrs, and price
def tidy_data(adverts_data: list[dict]) -> list[dict]:
    simplified = []
    irrelevant_keys = [
        "abuse_reported",
        "sold_reported",
        "admin_info",
        "available_tops_count",
        "badge_info",
        "can_make_an_offer",
        "can_view_contacts",
        "create_advert_like_this_url",
        "status",
        "date",
        "employer_took_cv",
        "is_active",
        "is_closed",
        "is_cv",
        "is_declined",
        "is_fav",
        "is_job",
        "is_on_moderation",
        "is_sent_cv",
        "make_an_offer_auth_url",
        "message_url",
        "similar_ads_href",
        "status_color",
        "title_labels",
        "stores",
        "video",
        "fb_view_content_data",
        "images",
        "images_data",
        "icon_attributes",
        "labels_data",
        "safety_tips",
        "safety_tips_title",
        "services_info",
        "shared_data",
    ]
    for item in adverts_data:
        advert = item["advert"]
        seller = item["seller"]
        if advert.get("attrs") is not None:
            attrs = advert["attrs"] = simplify_attrs(advert["attrs"])
            del advert["attrs"]
            advert = {**advert, **attrs}
        else:
            print("The advert does not have a attrs info.")
        if advert.get("price") is not None:
            price = advert["price"] = tidy_price(advert["price"])
            del advert["price"]
            advert = {**advert, **price}
        else:
            print("The advert does not have a price info.")
        advert = {k: v for k, v in advert.items() if k not in irrelevant_keys}
        seller = {
            "seller_name": seller.get("name"),
            "seller_phone": seller.get("phone"),
        }

        simplified.append({**advert, **seller})
    return simplified


def read_tidy_write(file_path, out_dir: str = None):
    if out_dir is None:
        out_dir = "./data/housing/processed/jiji/"
        Path(out_dir).mkdir(parents=True, exist_ok=True)
    try:
        with open(file_path, "r") as f:
            advert_details = json.load(f)
    except Exception as e:
        print(e)
    else:
        simplified = tidy_data(advert_details)
        simplified = pd.DataFrame(simplified)
        simplified.to_csv(Path(out_dir) / (file_path.stem + ".csv"), index=False)


def main():
    file_paths = Path("./data/housing/raw/jiji/").glob("*-*-*.json")

    for file_path in file_paths:
        read_tidy_write(file_path)


if __name__ == "__main__":
    main()
