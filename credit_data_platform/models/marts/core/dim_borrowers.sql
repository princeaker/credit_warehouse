with source as (
    select * from {{ ref('int_loans_unioned') }}
)

, borrowers as (
    select 
        {{ dbt_utils.generate_surrogate_key(['borrower', 'country_code']) }} as borrower_id
        , borrower
        , country_code
    from source
)

select * from borrowers