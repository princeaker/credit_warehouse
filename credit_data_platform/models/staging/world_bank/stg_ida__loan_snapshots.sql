{{config(
    materialized='incremental',
    unique_key='loan_snapshot_id')
}}

with source as (

    select jsontext:"snapshot_date"::date as snapshot_date
        , jsontext:"uploaded_at"::date as uploaded_at
        , jsontext:"loans" as loans_payload
    from {{ source('world_bank', 'snowpipe_ida_loan_snapshots') }}

    {% if is_incremental() %}
        where jsontext:"uploaded_at"::date > (select dateadd('day', -30, max(uploaded_at::date)) from {{ this }})
    {% endif %}
),

unpacked_loan_snapshots as (

    select snapshot_date
        , uploaded_at
        , flattened.value as loans
    from source,
    lateral flatten (input => loans_payload) as flattened
)

, renamed as (
    select
        {{ dbt_utils.generate_surrogate_key(['loans:"credit_number"::varchar', 'snapshot_date']) }} as loan_snapshot_id
        , loans:"agreement_signing_date"::date as agreement_signing_date
        , loans:"board_approval_date"::date as board_approval_date
        , loans:"borrower"::varchar as borrower
        , loans:"borrowers_obligation_us_"::decimal(12, 2) as borrowers_obligation_usd
        , loans:"cancelled_amount_us_"::decimal(12, 2) as cancelled_amount_usd
        , loans:"closed_date_most_recent"::date as closed_date_most_recent
        , loans:"country"::varchar as country
        , loans:"country_code"::varchar as country_code
        , loans:"currency_of_commitment"::varchar as currency_of_commitment
        , loans:"disbursed_amount_us_"::decimal(12, 2) as disbursed_amount_usd
        , loans:"due_3rd_party_us_"::decimal(12, 2) as due_3rd_party_usd
        , loans:"due_to_ida_us_"::decimal(12, 2) as due_to_ida_usd
        , loans:"effective_date_most_recent"::date as effective_date_most_recent
        , loans:"end_of_period"::date as end_of_period
        , loans:"exchange_adjustment_us_"::decimal(12, 2) as exchange_adjustment_usd
        , loans:"first_repayment_date"::date as first_repayment_date
        , loans:"guarantor"::varchar as guarantor
        , loans:"guarantor_country_code"::varchar as guarantor_country_code
        , loans:"interest_rate"::decimal(4, 2) as interest_rate
        , loans:"last_disbursement_date"::date as last_disbursement_date
        , loans:"last_repayment_date"::date as last_repayment_date
        , loans:"credit_number"::varchar as credit_number
        , loans:"credit_status"::varchar as credit_status
        , left(loans:"credit_number", 4)::varchar as credit_type
        , loans:"credits_held_us_"::decimal(12, 2) as credits_held_usd
        , loans:"original_principal_amount_us_"::decimal(12, 2) as original_principal_amount_usd
        , loans:"project_id"::varchar as project_id
        , loans:"project_name"::varchar as project_name
        , loans:"region"::varchar as region
        , loans:"repaid_3rd_party_us_"::decimal(12, 2) as repaid_3rd_party_usd
        , loans:"repaid_to_ida_us_"::decimal(12, 2) as repaid_to_ida_usd
        , loans:"service_charge_rate"::decimal(4, 2) as service_charge_rate
        , loans:"sold_3rd_party_us_"::decimal(12, 2) as sold_3rd_party_usd
        , loans:"undisbursed_amount_us_"::decimal(12, 2) as undisbursed_amount_usd
        , snapshot_date
        , uploaded_at
    from unpacked_loan_snapshots
)

select * from renamed