with source as (
    select * from {{ ref('stg_ibrd__loan_snapshots') }}
)

, borrowers as (
    select 
        ( {{dbt_utils.generate_surrogate_key(['borrower', 'country']) }} )as borrower_id
        , borrower
        , country
        , end_of_period
        , sum(case when 
            (loan_status in ('Approved','Effective', 'Disbursing', 'Disbursing&Repaying', 'Repaying', 'Fully Disbursed')
                then 1 else 0 end)) as active_loans
        , sum(case when 
            (loan_status in ('Fully Cancelled','Fully Transferred', 'Terminated')
                then 1 else 0 end)) as closed_loans
        , sum(case when 
            (loan_status in ('Fully Repaid'))
                then 1 else 0 end) as repaid_loans
    from source
    group by borrower, country, end_of_period
)

, scd as (
    select 
        borrower_id
        , borrower
        , country
        , active_loans
        , closed_loans
        , repaid_loans
        , end_of_period
        , lead(end_of_period) over (partition by borrower_id order by end_of_period) as next_end_of_period
    from borrowers
    where borrower is not null and country is not null
)

, final as (
    select
        dbt_utils.generate_surrogate_key(['borrower_id', 'country', 'end_of_period']) as dim_borrower_id
        , borrower_id
        , borrower
        , country
        , active_loans
        , closed_loans
        , repaid_loans
        , end_of_period as valid_from
        , case 
            when next_end_of_period is null then '9999-12-31'::date 
            else dateadd(day, -1, next_end_of_period) 
          end as valid_to
        , case 
            when next_end_of_period is null then true 
            else false 
          end as is_current
    from scd
)

select * from final