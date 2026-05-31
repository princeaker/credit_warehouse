import datetime
import json
import os
import re
from pathlib import Path

import boto3
from botocore.exceptions import ClientError



def key_exists(s3_client, bucket, key):
    """Check if file already exists in S3 bucket."""
    try:
        s3_client.head_object(Bucket=bucket, Key=key)
        print(f"Key '{key}' exists in bucket '{bucket}'.")
        return True
    except ClientError:
        print(f"Key '{key}' does not exist in bucket '{bucket}'.")
        return False
    
def add_metadata(filepath, snapshot_date):
    """the snapshots do not contain metadata about the date of the snapshot 
    or when the data was uploaded to s3. This will be helpful when working with the 
    time series data in snowflake."""
    print (f"Adding metadata to snapshot '{filepath}' with snapshot date '{snapshot_date}'...")
    with open(filepath, "r") as f:
            payload = json.load(f)
    upload_date = datetime.datetime.now(tz=datetime.UTC).strftime("%Y-%m-%d") # Get current date in UTC
         
    return {
            "snapshot_date": snapshot_date,
            "uploaded_at": upload_date,
            "loans": payload
        }


def upload_snapshot_to_s3(files_to_upload: list[str] = None):
    """ Uploads the ibrd loan snapshot to s3. The snapshot is stored in the data/ directory and is named 
    in the format "loan_snapshot_YYYY-MM-DD.json". 
    The snapshot is uploaded to the "cw-world-bank-data" bucket under the "loan-snapshots/YYYY-MM-DD/" prefix. 
    If a file with the same name already exists in the bucket, the upload is skipped."""
    directory_path = Path("data/")

    client = boto3.client("s3")

    bucket_name = "cw-world-bank-data"

    if files_to_upload:
        files = files_to_upload if isinstance(files_to_upload, list) else [files_to_upload]
    else:
        files = os.listdir(directory_path)

    for file in files:
        file_path = directory_path / file
        snapshot_date_str = file.split("_")[-1].split(".")[0] # Extract date from filename
        date_obj = datetime.datetime.strptime(snapshot_date_str, "%m-%d-%Y")
        snapshot_date = date_obj.strftime("%Y-%m-%d")
        payload = add_metadata(file_path, snapshot_date)
        # Use the snapshot date as part of the S3 key to organize the files by date
        if "ida" in file.lower():
            prefix = "loan-snapshots/ida/" + snapshot_date
        elif "ibrd" in file.lower():
            prefix = "loan-snapshots/ibrd/" + snapshot_date
        else:
            pass

        if key_exists(client, bucket_name, prefix + "/" + file):
            print("Skipping upload.")
        else:
            client.put_object(Bucket=bucket_name, Key=prefix + "/" + file, Body=json.dumps(payload))



def main():
    upload_snapshot_to_s3()
    

if __name__ == "__main__":
    main()
