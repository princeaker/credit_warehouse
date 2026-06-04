with ibrd_loan_snapshots as (

    select *
    from {{ ref('stg_ibrd__loan_snapshots') }}

),

ida_loan_snapshots as (

    select *
    from {{ ref('stg_ida__loan_snapshots') }}

)

, unioned_loans as (
    select 
        loan_snapshot_id
        , agreement_signing_date
        , board_approval_date
        , borrower
        , borrowers_obligation_usd
        , cancelled_amount_usd
        , closed_date_most_recent
        , country
        , country_code
        , currency_of_commitment
        , disbursed_amount_usd
        , undisbursed_amount_usd
        , due_3rd_party_usd
        , due_to_ibrd_usd as due_to_bank_usd --- aligning IDA and IBRD fields for union compatibility.
        , effective_date_most_recent
        , end_of_period
        , exchange_adjustment_usd
        , first_repayment_date
        , guarantor
        , guarantor_country_code
        , interest_rate
        , last_disbursement_date
        , last_repayment_date
        , loan_number
        , loan_status
        , loan_type
        , loans_held_usd
        , original_principal_amount_usd
        , project_id
        , project_name
        , region
        , repaid_3rd_party_usd
        , repaid_to_ibrd_usd as repaid_to_bank_usd 
        , 'IBRD' as source_system
    from ibrd_loan_snapshots
    where loan_type not in ('GURB', 'GURF') -- guarantees are not loans and thus should be excluded

    union all

    select
        loan_snapshot_id
        , agreement_signing_date
        , board_approval_date
        , borrower
        , borrowers_obligation_usd
        , cancelled_amount_usd
        , closed_date_most_recent
        , country
        , country_code
        , currency_of_commitment
        , disbursed_amount_usd
        , undisbursed_amount_usd
        , due_3rd_party_usd
        , due_to_ida_usd as due_to_bank_usd --- aligning IDA and IBRD fields for union compatibility.
        , effective_date_most_recent
        , end_of_period
        , exchange_adjustment_usd
        , first_repayment_date
        , guarantor
        , guarantor_country_code
        , interest_rate
        , last_disbursement_date
        , last_repayment_date
        , credit_number as loan_number --- aligning IDA and IBRD fields for union compatibility.
        , credit_status as loan_status --- aligning IDA and IBRD fields for union compatibility.
        , credit_type as loan_type --- aligning IDA and IBRD fields for union compatibility.
        , credits_held_usd as loans_held_usd --- aligning IDA and IBRD fields for union compatibility.
        , original_principal_amount_usd
        , project_id
        , project_name
        , region
        , repaid_3rd_party_usd
        , repaid_to_ida_usd as repaid_to_bank_usd --- aligning IDA and IBRD fields for union compatibility.
        , 'IDA' as source_system
    from ida_loan_snapshots
    where loan_type not in ('IDAB', 'IDAG', 'IDAD','IDAH','IDAE') -- guarantees and grants are not loans and thus should be excluded   
) 

, leading_period as (
    select 
        *,
        lead(end_of_period) over (partition by loan_number order by end_of_period) as next_end_of_period
    from unioned_loans
)

, renamed as (
    select
        loan_snapshot_id
        , agreement_signing_date
        , board_approval_date
        , borrower
        , borrowers_obligation_usd
        , cancelled_amount_usd
        , closed_date_most_recent
        , country
        , country_code
        , currency_of_commitment
        , disbursed_amount_usd
        , due_3rd_party_usd
        , due_to_bank_usd
        , effective_date_most_recent
        , exchange_adjustment_usd
        , first_repayment_date
        , guarantor
        , guarantor_country_code
        , interest_rate
        , last_disbursement_date
        , last_repayment_date
        , loan_number
        , loan_status
        , loan_type
        , loans_held_usd 
        , original_principal_amount_usd
        , project_id
        , project_name
        , region
        , repaid_3rd_party_usd
        , repaid_to_bank_usd 
        , source_system 
        , end_of_period
        , end_of_period as valid_from
        , case 
            when next_end_of_period is null then '9999-12-31'::date 
            else dateadd(day, -1, next_end_of_period) 
          end as valid_to
        , case 
            when next_end_of_period is null then true 
            else false 
          end as is_current
    from leading_period
)

select * from renamed

