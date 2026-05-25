with date_spine as (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2016-01-01' as date)",
        end_date="cast('2037-01-01' as date)"
    ) }}
)

, extracted_dates as (
    select 
        date_day as day
        , extract(year from date_day) as year
        , extract(quarter from date_day) as quarter
        , extract(month from date_day) as month
        , extract(week from date_day) as week_of_year
        , extract(dayofweek from date_day) as day_of_week
        , case when extract(dayofweek from date_day) in (0, 6) then true else false end as is_weekend
        , date_trunc('week', date_day) as week_start_date
        , last_day(date_day, 'week') as week_end_date
        , date_trunc('month', date_day) as month_start_date
        , last_day(date_day, 'month') as month_end_date
        , date_trunc('quarter', date_day) as quarter_start_date
        , last_day(date_day, 'quarter') as quarter_end_date
    from date_spine
)

, final as (
    select 
        day
        , year
        , quarter
        , month
        , case
            when month = 1 then 'January'
            when month = 2 then 'February'
            when month = 3 then 'March'
            when month = 4 then 'April'
            when month = 5 then 'May'
            when month = 6 then 'June'
            when month = 7 then 'July'
            when month = 8 then 'August'
            when month = 9 then 'September'
            when month = 10 then 'October'
            when month = 11 then 'November'
            when month = 12 then 'December'
            else null 
        end as month_name
        , week_of_year
        , day_of_week
        , case 
            when day_of_week = 0 then 'Sunday'
            when day_of_week = 1 then 'Monday'
            when day_of_week = 2 then 'Tuesday'
            when day_of_week = 3 then 'Wednesday'
            when day_of_week = 4 then 'Thursday'
            when day_of_week = 5 then 'Friday'
            when day_of_week = 6 then 'Saturday'
            else null 
          end as day_name
        , is_weekend
        , week_start_date
        , week_end_date
        , month_start_date
        , month_end_date
        , quarter_start_date
        , quarter_end_date
        
    from extracted_dates
)

select * from final