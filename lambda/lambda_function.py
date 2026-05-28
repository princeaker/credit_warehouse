import boto3
import json
import datetime
import logging
import os
import urllib.request

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger()

sm = boto3.client('secretsmanager')
s3 = boto3.client('s3')


def get_app_id(secret_name):
    """Fetch the Open Exchange Rates App ID from AWS Secrets Manager."""
    try:
        get_secret_value_response = sm.get_secret_value(SecretId=secret_name)
        secret = get_secret_value_response['SecretString']
        secret_dict = json.loads(secret)
        return secret_dict['app_id']
    except Exception as e:
        logger.error("Error retrieving secret from Secrets Manager: %s", e)
        raise

def lambda_handler(event, context):
    """Lambda function to fetch exchange rates from Open Exchange Rates API."""
    # Fetch the Open Exchange Rates App ID from Secrets Manager
    oer_app_id = get_app_id(os.getenv('APP_ID_SECRET_ARN'))

    # Fetch exchange rates from Open Exchange Rates API
    endpoint = f"https://openexchangerates.org/api/latest.json?app_id={oer_app_id}&base=USD"
    with urllib.request.urlopen(endpoint) as response:
        if response.status != 200:
            logger.error("Failed to fetch exchange rates: HTTP %s", response.status)
            raise Exception(f"Failed to fetch exchange rates: HTTP {response.status}")
        data = json.load(response)
        
    current_date_obj = datetime.datetime.now(tz=datetime.UTC)
    # Get the current date in UTC to use as part of the S3 key for organizing the files by date.
    current_date = current_date_obj.strftime("%Y-%m-%d")

    # Get the current date and time in UTC to include in the metadata of the JSON object.
    current_datetime = current_date_obj.strftime("%Y-%m-%d %H:%M:%S")

    # Add metadata to the JSON object, including the date and time of the upload.
    json_object = {
        "uploaded_at": current_datetime,
        "data": data
    }

    s3.put_object(
            Bucket='cw-world-bank-data',
            Key=f"fx-rates/{current_date}/fx_rates_{current_date_obj.strftime('%Y-%m-%d_%H-%M-%S')}.json",
            Body=json.dumps(json_object)
        )
