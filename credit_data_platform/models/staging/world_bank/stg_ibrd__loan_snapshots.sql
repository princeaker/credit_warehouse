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
        {{ dbt_utils.generate_surrogate_key(['loans:"loan_number"::varchar', 'snapshot_date']) }} as loan_snapshot_id
        , loans:"agreement_signing_date"::date as agreement_signing_date
        , loans:"board_approval_date"::date as board_approval_date
        , loans:"borrower"::varchar as borrower
        , loans:"borrowers_obligation"::decimal(12, 2) as borrowers_obligation_usd
        , loans:"cancelled_amount"::decimal(12, 2) as cancelled_amount_usd
        , loans:"closed_date_most_recent"::date as closed_date_most_recent
        , loans:"country"::varchar as country
        , loans:"country_code"::varchar as country_code
        , loans:"currency_of_commitment"::varchar as currency_of_commitment
        , loans:"disbursed_amount"::decimal(12, 2) as disbursed_amount_usd
        , loans:"due_3rd_party"::decimal(12, 2) as due_3rd_party_usd
        , loans:"due_to_ibrd"::decimal(12, 2) as due_to_ibrd_usd
        , loans:"effective_date_most_recent"::date as effective_date_most_recent
        , loans:"end_of_period"::date as end_of_period
        , loans:"exchange_adjustment"::decimal(12, 2) as exchange_adjustment_usd
        , loans:"first_repayment_date"::date as first_repayment_date
        , loans:"guarantor"::varchar as guarantor
        , loans:"guarantor_country_code"::varchar as guarantor_country_code
        , loans:"interest_rate"::decimal(4, 2) as interest_rate
        , loans:"last_disbursement_date"::date as last_disbursement_date
        , loans:"last_repayment_date"::date as last_repayment_date
        , loans:"loan_number"::varchar as loan_number
        , loans:"loan_status"::varchar as loan_status
        , loans:"loan_type"::varchar as loan_type
        , loans:"loans_held"::decimal(12, 2) as loans_held
        , loans:"original_principal_amount"::decimal(12, 2) as original_principal_amount_usd
        , loans:"project_id"::varchar as project_id
        , loans:"project_name"::varchar as project_name
        , loans:"region"::varchar as region
        , loans:"undisbursed_amount"::decimal(12, 2) as undisbursed_amount_usd
        , snapshot_date
        , uploaded_at
    from unpacked_loan_snapshots
)

select * from renamed