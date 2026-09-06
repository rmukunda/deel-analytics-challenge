with acceptance_chargeback as (

    select * from {{ ref('int_acceptance_chargeback') }}

),

country as (

    select * from {{ ref('dim_country') }}

),

joined as (

    select
        acceptance_chargeback.transaction_id,
        acceptance_chargeback.status,
        acceptance_chargeback.payment_provider,
        acceptance_chargeback.provider_external_ref,
        acceptance_chargeback.transaction_timestamp,
        cast(acceptance_chargeback.transaction_timestamp as date)
            as transaction_date_key,
        acceptance_chargeback.transaction_status,
        acceptance_chargeback.is_cvv_provided,
        acceptance_chargeback.transaction_amount,
        acceptance_chargeback.fx_rate_local_to_usd,
        country.country_id,
        acceptance_chargeback.transaction_anomoly,
        acceptance_chargeback.is_chargeback,
        acceptance_chargeback.transaction_amount
        * acceptance_chargeback.fx_rate_local_to_usd as transaction_amount_usd

    from acceptance_chargeback
    left join country
        on acceptance_chargeback.card_country_code = country.country_code

)

select * from joined
