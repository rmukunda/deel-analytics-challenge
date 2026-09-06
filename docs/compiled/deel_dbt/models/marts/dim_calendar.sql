with spine as (

    





with rawdata as (

    

    

    with p as (
        select 0 as generated_number union all select 1
    ), unioned as (

    select

    
    p0.generated_number * power(2, 0)
     + 
    
    p1.generated_number * power(2, 1)
     + 
    
    p2.generated_number * power(2, 2)
     + 
    
    p3.generated_number * power(2, 3)
     + 
    
    p4.generated_number * power(2, 4)
     + 
    
    p5.generated_number * power(2, 5)
     + 
    
    p6.generated_number * power(2, 6)
     + 
    
    p7.generated_number * power(2, 7)
     + 
    
    p8.generated_number * power(2, 8)
     + 
    
    p9.generated_number * power(2, 9)
     + 
    
    p10.generated_number * power(2, 10)
     + 
    
    p11.generated_number * power(2, 11)
    
    
    + 1
    as generated_number

    from

    
    p as p0
     cross join 
    
    p as p1
     cross join 
    
    p as p2
     cross join 
    
    p as p3
     cross join 
    
    p as p4
     cross join 
    
    p as p5
     cross join 
    
    p as p6
     cross join 
    
    p as p7
     cross join 
    
    p as p8
     cross join 
    
    p as p9
     cross join 
    
    p as p10
     cross join 
    
    p as p11
    
    

    )

    select *
    from unioned
    where generated_number <= 3652
    order by generated_number



),

all_periods as (

    select (
        

    dateadd(
        day,
        row_number() over (order by generated_number) - 1,
        cast('2018-01-01' as date)
        )


    ) as date_day
    from rawdata

),

filtered as (

    select *
    from all_periods
    where date_day <= cast('2028-01-01' as date)

)

select * from filtered



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