with acceptance as (

    select * from DEEL.staging.stg_acceptance

),

chargeback as (

    select * from DEEL.staging.stg_chargeback

),

acceptance_with_fx as (

    select
        transaction_id,
        status,
        payment_provider,
        provider_external_ref,
        transaction_timestamp,
        transaction_status,
        is_cvv_provided,
        transaction_amount,
        card_country_code,
        currency_code,
        

    cast(get(parse_json(fx_rates_to_usd), currency_code) as decimal(10, 6))

 as fx_rate_usd_to_local

    from acceptance

),

joined as (

    select
        acceptance_with_fx.transaction_id,
        acceptance_with_fx.status,
        acceptance_with_fx.payment_provider,
        acceptance_with_fx.provider_external_ref,
        acceptance_with_fx.transaction_timestamp,
        acceptance_with_fx.transaction_status,
        acceptance_with_fx.is_cvv_provided,
        acceptance_with_fx.transaction_amount,
        acceptance_with_fx.card_country_code,
        acceptance_with_fx.currency_code,
        acceptance_with_fx.fx_rate_usd_to_local,
        1 / nullif(acceptance_with_fx.fx_rate_usd_to_local, 0) as fx_rate_local_to_usd,
        acceptance_with_fx.transaction_amount < 0 as transaction_anomoly,
        chargeback.chargeback_status,
        chargeback.is_chargeback

    from acceptance_with_fx
    left join chargeback
        on acceptance_with_fx.transaction_id = chargeback.transaction_id

)

select * from joined