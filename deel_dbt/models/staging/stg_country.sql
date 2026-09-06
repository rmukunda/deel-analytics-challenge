with source as (

    select * from {{ ref('countries') }}

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
