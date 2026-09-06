with source as (

    select * from DEEL.raw.acceptance_transactions

),

renamed as (

    select
        external_ref as transaction_id,
        status,
        source as payment_provider,
        ref as provider_external_ref,
        date_time as transaction_timestamp,
        state as transaction_status,
        cvv_provided as is_cvv_provided,
        amount as transaction_amount,
        country as card_country_code,
        currency as currency_code,
        rates as fx_rates_to_usd

    from source

)

select * from renamed