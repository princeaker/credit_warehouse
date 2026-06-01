with source as (
    select * from {{ ref('countries') }}
)

, final as (
    select
        ({{ dbt_utils.generate_surrogate_key(['country']) }}) as country_id
        , country
        , country_code
        , iso2_code
        , region
        , income_group
        , lending_type
        , currency
    from source
)

select * from final
