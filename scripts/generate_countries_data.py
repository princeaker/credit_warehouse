import json
import os

from country_config import COUNTRY_CURRENCIES

import pandas as pd
import pycountry
import requests
import snowflake.connector
from dotenv import load_dotenv




# load_dotenv()  # Load environment variables from .env file

# conn_params = {
#     "user": os.getenv("SNOWFLAKE_USER"),
#     "account": os.getenv("SNOWFLAKE_ACCOUNT"),
#     "authenticator": "SNOWFLAKE_JWT",
#     "private_key_file": os.getenv("SNOWFLAKE_PRIVATE_KEY_PATH"),
#     "warehouse": "CREDIT_DATA_PLATFORM_WH",
#     "database": "CREDIT_DATA_PLATFORM",
#     "schema": "dev"
# }

# ctx = snowflake.connector.connect(
#     **conn_params
# )
# cs = ctx.cursor()
# try:
#     cs.execute("SELECT distinct country, lower(country_code) as country_code from dev.stg_ibrd__loan_snapshots;")
#     country_list = cs.fetchall()

# finally:
#     cs.close()
# ctx.close()

def main():
    page = 1
    endpoint = "https://api.worldbank.org/v2/country?format=json"
    response = requests.get(endpoint, params={"page": page})
    page_total = response.json()[0]["pages"]
    country_dataset = []

    while page <= page_total:
        
        country_list = response.json()[1]
        for country in country_list:
            print(f"Processing country: {country['name']} ({country['id']})")
            record = {"country": country["name"]
            , "country_code": country["id"]
            , "iso2_code": country["iso2Code"]
            , "region": country["region"]["value"]
            , "income_group": country["incomeLevel"]["value"]
            , "lending_type": country["lendingType"]["value"]}
            
            try:
                country_obj = pycountry.countries.get(alpha_2=record["iso2_code"])
                if country_obj is None:
                    print(f"Country code {record['iso2_code']} not found in pycountry, skipping currency lookup")
                    continue
                print(f"Found country in pycountry: {country_obj}")
                if record["region"] == "Aggregates":
                    record["currency"] = None
                else:
                    record["currency"] = get_currency(record["iso2_code"])
            except KeyError:
                print("Invalid country code, skipping pycountry lookup")
            
            country_dataset.append(record)
        page += 1
        response = requests.get(endpoint, params={"page": page})

    pd.DataFrame(country_dataset).to_csv("countries.csv", index=False)


def get_currency(iso2_code):
   country = pycountry.countries.get(alpha_2=iso2_code)
   """There are a few exceptions where the currency code does not match the country code, so we need to handle those cases separately."""
   if iso2_code in COUNTRY_CURRENCIES:
       return COUNTRY_CURRENCIES[iso2_code]
   else: 
       return pycountry.currencies.get(numeric=country.numeric).alpha_3
       
if __name__ == "__main__":
    main()
    