with source as (
    select * from {{ ref('world_bank_economies') }}
)

, final as (
    select
        ({{ dbt_utils.generate_surrogate_key(['economy']) }}) as country_id
        , economy as country
        , code as country_code
        , region
        , income_group
        , lending_category
    from source
)

select * from final
