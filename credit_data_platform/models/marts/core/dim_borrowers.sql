with source as (
    select * from {{ ref('int_loans_unioned') }}
)

, borrowers as (
    select 
        {{ dbt_utils.generate_surrogate_key(['borrower', 'country']) }} as borrower_id
        , borrower
        , country
        , country_code
        , region
    from source
)

select * from borrowers