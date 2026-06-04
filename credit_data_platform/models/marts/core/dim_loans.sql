with loans as (
    select * from {{ ref('int_loans_unioned') }}
)

, renamed as (
    select 
        {{ dbt_utils.generate_surrogate_key(['loan_number']) }} as loan_id
        , {{ dbt_utils.generate_surrogate_key(['borrower', 'country_code']) }} as borrower_id
        , loan_number
        , agreement_signing_date
        , board_approval_date
        , original_principal_amount_usd
        , cancelled_amount_usd
        , closed_date_most_recent
        , currency_of_commitment
        , effective_date_most_recent
        , exchange_adjustment_usd
        , first_repayment_date
        , guarantor
        , guarantor_country_code
        , interest_rate
        , last_disbursement_date
        , last_repayment_date
        , loan_status
        , loan_type
        , project_id
        , project_name
    from loans
)

select * from renamed