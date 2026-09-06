with source as (

    select * from DEEL.raw.countries

),

renamed as (

    select
        country_id,
        country_code,
        country_name,
        currency_code

    from source

)

select * from renamed