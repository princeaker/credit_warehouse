{{config(
    materialized='incremental',
    unique_key='fx_rate_id')
}}

with source as (
    select 
        jsontext:"uploaded_at" as uploaded_at
        , jsontext:"data":"base" as base_currency
        , jsontext:"data":"rates" as fx_rates_payload
        , to_timestamp(jsontext:"data":"timestamp") as reported_at
        from {{ source('oer_fx_rates', 'snowpipe_fx_rates') }}

    {% if is_incremental() %}
        where jsontext:"uploaded_at"::timestamp > (select dateadd('day', -3, max(jsontext:"uploaded_at"::timestamp)) from {{ this }})
    {% endif %}
)

, unpacked_fx_rates as (
    select
        
        uploaded_at::timestamp as uploaded_at
        , base_currency::varchar(3) as base_currency
        , flattened.key as quote_currency
        , flattened.value::decimal(16, 8) as fx_rate
        , reported_at
        , reported_at::date as reported_date
    from source,
    lateral flatten (input => fx_rates_payload) as flattened
)

, final as (
    select 
        {{ dbt_utils.generate_surrogate_key(['base_currency', 'quote_currency', 'reported_date']) }} as fx_rate_id
        , *

    from unpacked_fx_rates
)

select * from final