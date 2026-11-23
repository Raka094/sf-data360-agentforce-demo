"""
Generate synthetic sample data for the demo.

Creates three CSV files in ../data:
  - crm_accounts.csv   -> loaded into Salesforce CRM (Account object)
  - erp_customers.csv  -> uploaded to Data Cloud (same companies, slightly different names = identity resolution test)
  - orders.csv         -> uploaded to Data Cloud (order history from the "ERP")

All data is fake. Order dates are relative to TODAY, so re-run this script
before you upload if the files are more than a few weeks old.

Usage:
    python scripts/generate_sample_data.py            # 40 accounts, seed 42
    python scripts/generate_sample_data.py --accounts 60 --seed 7
"""
import argparse
import csv
import random
from datetime import date, timedelta
from pathlib import Path

CITIES = [("Frankfurt", "DE"), ("Munich", "DE"), ("Hamburg", "DE"), ("Berlin", "DE"),
          ("Vienna", "AT"), ("Zurich", "CH"), ("Cologne", "DE"), ("Stuttgart", "DE")]
PREFIX = ["Alpen", "Rhein", "Nord", "Sued", "Main", "Elbe", "Donau", "Bavaria", "Hansa",
          "Taunus", "Isar", "Spree", "Neckar", "Mosel", "Harz", "Eifel", "Allgaeu", "Ruhr",
          "Weser", "Saar"]
CORE = ["Reifen", "Auto", "Fleet", "Logistik", "Motors", "Tyre", "Service", "Mobility"]
LEGAL = ["GmbH", "AG", "GmbH & Co. KG"]
INDUSTRY = ["Automotive", "Transportation", "Retail", "Manufacturing"]
CATEGORIES = ["Passenger Tyres", "Truck Tyres", "Two-Wheel", "Services"]

# Behaviour profiles drive whether an account "looks at risk"
PROFILES = ["healthy"] * 6 + ["declining"] * 2 + ["gone_quiet"] * 2  # ~40% risky by design


def name_variant(name: str, rng: random.Random) -> str:
    """Make the ERP name slightly different from the CRM name (realistic messy data)."""
    variants = [
        name.upper(),
        name.replace("GmbH & Co. KG", "GmbH&Co KG"),
        name.replace(" GmbH", "").replace(" AG", ""),
        name.replace("ue", "ü") if "ue" in name else name + " ",
        name.replace("Reifen", "Reifen-Handel"),
    ]
    return rng.choice(variants).strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--accounts", type=int, default=40)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    rng = random.Random(args.seed)
    today = date.today()
    out = Path(__file__).resolve().parent.parent / "data"
    out.mkdir(exist_ok=True)

    accounts, used = [], set()
    while len(accounts) < args.accounts:
        base = f"{rng.choice(PREFIX)} {rng.choice(CORE)}"
        if base in used:
            continue
        used.add(base)
        idx = len(accounts) + 1
        city, country = rng.choice(CITIES)
        slug = base.lower().replace(" ", "-")
        accounts.append({
            "account_number": f"ACC-{idx:04d}",
            "name": f"{base} {rng.choice(LEGAL)}",
            "website": f"https://www.{slug}.example",
            "phone": f"+49 69 {rng.randint(1000000, 9999999)}",
            "city": city,
            "country": country,
            "industry": rng.choice(INDUSTRY),
            "erp_id": f"ERP-{100000 + idx}",
            "profile": rng.choice(PROFILES),
            "base": rng.uniform(1500, 4000) * rng.choice([1, 1, 2, 3, 5]),  # typical order value
        })

    # 1) CRM accounts (columns = Salesforce Account field API names, for sf data import bulk)
    with open(out / "crm_accounts.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["Name", "AccountNumber", "Website", "Phone", "BillingCity", "BillingCountryCode", "Industry"])
        for a in accounts:
            w.writerow([a["name"], a["account_number"], a["website"], a["phone"], a["city"], a["country"], a["industry"]])

    # 2) ERP customer master (messy names, same website/phone)
    with open(out / "erp_customers.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["erp_customer_id", "customer_name", "website", "phone", "city", "country", "crm_account_number"])
        for a in accounts:
            w.writerow([a["erp_id"], name_variant(a["name"], rng), a["website"], a["phone"], a["city"], a["country"], a["account_number"]])

    # 3) Orders over the last 18 months
    order_rows, n = [], 0
    start = today - timedelta(days=540)
    for a in accounts:
        d = start + timedelta(days=rng.randint(0, 20))
        while d <= today:
            age = (today - d).days
            amount = a["base"] * rng.uniform(0.85, 1.15)
            skip = False
            if a["profile"] == "gone_quiet" and age < rng.randint(75, 140):
                skip = True                      # stopped ordering recently
            if a["profile"] == "declining" and age < 90:
                amount *= rng.uniform(0.15, 0.35)  # still orders, but much smaller
            if not skip:
                n += 1
                order_rows.append([f"SO-{n:06d}", a["erp_id"], d.isoformat(), round(amount, 2),
                                   rng.choice(CATEGORIES), "EUR"])
            d += timedelta(days=rng.randint(10, 21))

    with open(out / "orders.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["order_id", "erp_customer_id", "order_date", "amount", "product_category", "currency"])
        w.writerows(order_rows)

    # Answer key so you can check the agent's output against ground truth
    with open(out / "_answer_key.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["account_number", "name", "erp_customer_id", "designed_profile"])
        for a in accounts:
            w.writerow([a["account_number"], a["name"], a["erp_id"], a["profile"]])

    risky = sum(1 for a in accounts if a["profile"] != "healthy")
    print(f"Wrote {len(accounts)} accounts, {len(order_rows)} orders to {out} (designed at-risk: {risky}).")


if __name__ == "__main__":
    main()
