with source as (
    select * from {{ ref('countries') }}
)

, final as (
    select
        ({{ dbt_utils.generate_surrogate_key(['iso2_code']) }}) as country_id
        , country
        , country_code as country_code_alpha_3
        , iso2_code as country_code
        , region
        , income_group
        , lending_type
        , currency
    from source
)

select * from final
