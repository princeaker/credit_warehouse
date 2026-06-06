# credit_data_platform

A financial data warehouse built on Snowflake, modeled with dbt, and provisioned end-to-end with Terraform. The platform ingests World Bank sovereign lending data and daily FX rates to enable credit risk analysis across developing countries and emerging market borrowers. This project focuses on dimensional modeling, data quality as a system, and consistency

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Data Sources                             │
│                                                                 │
│   World Bank IBRD/IDA         World Bank          FX Rate API   │
│   Statement of Loans          Country API           (daily)     │
│   (JSON via World Bank)        (REST/JSON)          (JSON)      │
└────────────┬────────────────────┬──────────────────┬────────────┘
             │                    │                  │
             ▼                    ▼                  ▼
┌────────────────────────────────────────────────────────────────┐
│                          AWS S3                                │
│                                                                │
│   IBRD & IDA Loans                     daily fx rates          │
│   (batch ingestion                     (daily via Lambda)      │
│    via Python script)                                          │
└────────────────────────────────┬───────────────────────────────┘
                                 │  Snowpipe (auto-ingest)
                                 ▼
┌────────────────────────────────────────────────────────────────┐
│                        Snowflake                               │
│                                                                │
│  RAW schema                                                    │
│  ├── ibrd_loans                                                │
│  ├── ida_loans                                                 │
│  └── fx_rates                                                  │
│                                                                │
│  STAGING schema              MARTS schema                      │
│  ├── stg_ibrd__loans         ├── dim_countries                 │
│  ├── stg_ida__loans          ├── dim_borrowers                 │
│  └── stg_fx__rates           ├── dim_loans                     │
│                              ├── dim_date                      │
│  INTERMEDIATE schema         ├── fact_loan_balances            │
│  └── int_loans_unioned       └── fact_fx_rates                 │
└────────────────────────────────────────────────────────────────┘
```

---

## Data Sources

World Bank IBRD/IDA Statement of Loans - Monthly loan-level snapshots from the World Bank's public lending portfolio — borrower, country, loan type, disbursements, outstanding balance, interest rate. The primary fact source.

Source: 
* IBRD: (https://finances.worldbank.org/Loans-and-Credits/IBRD-Statement-Of-Loans-Latest-Available-Snapshot/sfv5-tf7p) 
* IDA: (https://financesone.worldbank.org/ida-statement-of-credits-grants-and-guarantees-latest-available-snapshot/DS00001)

World Bank Country API - Country metadata including ISO codes, region classification, income level (Low / Lower-Middle / Upper-Middle / High), and lending type (IDA / IBRD / Blend). Used to build and enrich `dim_countries`.

Endpoint: `https://api.worldbank.org/v2/country?format=json`


Open Exchange Rates API - Monthly average exchange rates (local currency units per USD) for target countries. Fetched daily via AWS Lambda and EventBridge, landing JSON files in S3 for Snowpipe ingestion into `fact_fx_rates`.

The API is sourced from https://openexchangerates.org/

---

## Data Model

The warehouse follows a **Kimball-style star schema**. Analytical queries join fact tables to dimension tables via surrogate keys generated in dbt.

### Dimensions

| Table | Grain | Key Fields |
|---|---|---|
| `dim_countries` | One row per country | `country_key`, `iso2_code`, `iso3_code`, `region`, `income_level`, `lending_type` |
| `dim_borrowers` | One row per borrower entity | `borrower_key`, `borrower_name`, `borrower_type`, `country_key` |
| `dim_loans` | One row per loan | `loan_key`, `loan_number`, `product_line`, `interest_rate_type`, `currency`, `original_principal_usd` |
| `dim_date` | One row per calendar date | `date_key`, `date`, `year`, `month`, `quarter`, `fiscal_year` |

### Facts

| Table | Grain | Key Fields |
|---|---|---|
| `fact_loan_balances` | Monthly balance per loan | `loan_key`, `borrower_key`, `country_key`, `date_key`, `disbursed_amount`, `outstanding_balance`, `repaid_to_ibrd`, `due_to_ibrd` |
| `fact_fx_rates` | Monthly rate per country | `country_key`, `date_key`, `currency_code`, `lcu_per_usd` |

`fact_fx_rates` is kept as a separate fact table rather than a dimension attribute, since FX rates change frequently and joining at query time against a monthly grain preserves point-in-time accuracy for currency conversion.

---

## Repo Structure

```
credit_warehouse
 - credit_data_platform       # dbt project
 - lambda                     # FX ingestion Lambda function
 - scripts                    # One-time and batch ingestion and seed scripts
 - terraform                  # All infrastructure as code
 - pyproject.toml             # Python dependency management (uv)
```

---

## Infrastructure

All cloud resources are provisioned with Terraform. The stack includes:

**AWS**
- S3 buckets for raw data landing (IBRD loans, country metadata, FX rates)
- SQS queue for S3 event notifications consumed by Snowpipe
- Lambda function for daily FX ingestion, triggered by EventBridge cron rule
- IAM roles scoped to least-privilege for Lambda execution and Snowflake S3 access

**Snowflake**
- Dedicated warehouse, database, and three schemas (`RAW`, `STAGING`, `MARTS`)
- Snowpipe configured per source table with SQS auto-ingest
- Service account (`DBT_SVC`) using key-pair authentication for dbt connectivity
- Role-based access control separating ingestion, transformation, and read-only access

---

## dbt Layer

The transformation layer follows a three-tier architecture:

**Staging** — casts types, renames columns to a consistent convention, and generates surrogate keys.

**Intermediate** — Cross-source joins and unioning. `int_loans_unioned` combines IBRD and IDA loan records into a single conformed dataset before mart modeling.

**Marts** — Business-facing dimensions and facts. Surrogate keys are generated using `dbt_utils.generate_surrogate_key()`. Incremental models on fact tables use `uploaded_at` with a lookback window for late-arriving data.

---

## Setup

### Prerequisites
- Terraform >= 1.5
- Python >= 3.11 (managed via `uv`)
- Snowflake account
- AWS account with appropriate IAM permissions

### 1. Provision infrastructure
```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 2. Configure dbt
Set up your `profiles.yml` with Snowflake credentials. This project uses key-pair authentication:
```yaml
credit_data_platform:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: "{{ env_var('SNOWFLAKE_ACCOUNT') }}"
      user: DBT_SVC
      private_key_path: "{{ env_var('SNOWFLAKE_PRIVATE_KEY_PATH') }}"
      role: DBT_ROLE
      database: CREDIT_DATA_PLATFORM
      warehouse: CREDIT_DATA_PLATFORM_WH
      schema: dev
      threads: 4
```

### 3. Run ingestion scripts
```bash
# Install dependencies
uv sync

# Load IBRD/IDA loan data into S3
python scripts/upload_loan_snapshots.py

# Snowpipe picks up files automatically via SQS notification

# Create seed file for dim_countries dbt modell
python scripts/generate_countries_data.py

```

### 4. Run dbt
```bash
cd credit_data_platform
dbt deps
dbt build
```

---

## In Progress

- **Great Expectations suite** — Data quality checks at the `RAW` layer before dbt runs, with domain-informed expectations (e.g., disbursed amount ≤ original principal, FX rates within historically plausible bounds per currency)
- **dbt model documentation** — Column-level descriptions and lineage docs via `dbt docs generate`
- **Analysis notebook** — Jupyter notebook of analytical queries against the mart layer covering debt service burden by income level, currency depreciation exposure, and IDA vs. IBRD disbursement trends

---

## Tech Stack

| Layer | Tool |
|---|---|
| Warehouse | Snowflake |
| Transformation | dbt Core |
| Data Quality | Great Expectations |
| Ingestion (batch) | Python + boto3 |
| Ingestion (scheduled) | AWS Lambda + EventBridge |
| Auto-ingest | Snowpipe + SQS |
| Infrastructure | Terraform |
| Package Management | uv |