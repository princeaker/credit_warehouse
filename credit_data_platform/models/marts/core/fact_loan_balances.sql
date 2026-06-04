with unioned_loans as (

    select * from {{ ref('int_loans_unioned') }}

)

, monthly_loan_balances as (

    select
        loan_snapshot_id as loan_date_id
        , {{ dbt_utils.generate_surrogate_key(['loan_number']) }} as loan_id
        , {{ dbt_utils.generate_surrogate_key(['borrower', 'country_code']) }} as borrower_id
        , {{ dbt_utils.generate_surrogate_key(['country_code']) }} as country_id
        , end_of_period as balance_date
        , borrowers_obligation_usd
        , interest_rate
        , cancelled_amount_usd
        , disbursed_amount_usd
        , undisbursed_amount_usd
        , loans_held_usd 
        , due_3rd_party_usd
        , due_to_bank_usd
        , exchange_adjustment_usd
        , loan_status
        , repaid_3rd_party_usd
        , repaid_to_bank_usd 
        , source_system 
        , is_current
    from unioned_loans
    
)

select * from monthly_loan_balances
