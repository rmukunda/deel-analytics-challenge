with spine as (

    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2018-01-01' as date)",
        end_date="cast('2028-01-01' as date)"
    ) }}

),

calendar as (

    select
        date_day,
        date_part('year', date_day) as year,
        date_part('month', date_day) as month,
        date_part('quarter', date_day) as quarter,
        date_part('week', date_day) as week_number,
        date_trunc('week', date_day)::date as week_start_date,
        dayname(date_day) as day_of_week,
        to_char(date_day, 'YYYY-MM') as year_month,
        date_part('year', date_day) || '-Q' || date_part('quarter', date_day) as year_quarter,
        date_part('year', date_day) || '-W' || lpad(date_part('week', date_day), 2, '0') as year_week_number

    from spine

)

select * from calendar
