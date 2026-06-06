with fx_rates as (
    select 
        fx_rate_id
        , reported_date
        , base_currency
        , quote_currency
        , fx_rate
    from {{ ref('stg_oer__fx_rates') }}
)

select * from fx_rates

