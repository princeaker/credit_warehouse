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

def main():
    client = boto3.client("s3")
    directory_path = Path("data/")
    
    files = os.listdir(directory_path)
    bucket_name = "cw-world-bank-data"

    for file in files:
        prefix = "loan-snapshots/" + file.split("_")[-1].split(".")[0]
        if key_exists(client, bucket_name, prefix + "/" + file):
            print(f"File '{file}' already exists in bucket '{bucket_name}' under prefix '{prefix}'. Skipping upload.")
        else:
            file_path = directory_path / file
            client.upload_file(file_path, bucket_name, prefix + "/" + file)


if __name__ == "__main__":
    main()
