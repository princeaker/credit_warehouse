with source as (

    select jsontext:"snapshot_date"::date as snapshot_date
        , jsontext:"uploaded_at"::date as uploaded_at
        , jsontext:"loans" as loans_payload
    from {{ source('world_bank', 'snowpipe_loan_snapshots') }}

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
        {{ dbt_utils.surrogate_key(['loan_number', 'snapshot_date']) }} as loan_snapshot_id
        , loans:"agreement_signing_date"::date as agreement_signing_date
        , loans:"board_approval_date"::date as board_approval_date
        , loans:"borrower" as borrower
        , loans:"borrowers_obligation"::decimal(12, 2) as borrowers_obligation_usd
        , loans:"cancelled_amount"::decimal(12, 2) as cancelled_amount_usd
        , loans:"closed_date_most_recent"::date as closed_date_most_recent
        , loans:"country" as country
        , loans:"country_code" as country_code
        , loans:"currency_of_commitment" as currency_of_commitment
        , loans:"disbursed_amount"::decimal(12, 2) as disbursed_amount_usd
        , loans:"due_3rd_party"::decimal(12, 2) as due_3rd_party_usd
        , loans:"due_to_ibrd"::decimal(12, 2) as due_to_ibrd_usd
        , loans:"effective_date_most_recent"::date as effective_date_most_recent
        , loans:"end_of_period"::date as end_of_period
        , loans:"exchange_adjustment"::decimal(12, 2) as exchange_adjustment_usd
        , loans:"first_repayment_date"::date as first_repayment_date
        , loans:"guarantor" as guarantor
        , loans:"guarantor_country_code" as guarantor_country_code
        , loans:"interest_rate"::decimal(4, 2) as interest_rate
        , loans:"last_disbursement_date"::date as last_disbursement_date
        , loans:"last_repayment_date"::date as last_repayment_date
        , loans:"loan_number" as loan_number
        , loans:"loan_status" as loan_status
        , loans:"loan_type" as loan_type
        , loans:"loans_held"::decimal(12, 2) as loans_held
        , loans:"original_principal_amount"::decimal(12, 2) as original_principal_amount_usd
        , loans:"project_id" as project_id
        , loans:"project_name" as project_name
        , loans:"region" as region
        , loans:"undisbursed_amount"::decimal(12, 2) as undisbursed_amount_usd
        , snapshot_date
        , uploaded_at
    from unpacked_loan_snapshots
)

select * from renamed