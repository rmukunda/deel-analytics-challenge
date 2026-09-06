with source as (

    select * from {{ ref('chargeback_report') }}

),

renamed as (

    select
        external_ref as transaction_id,
        status as chargeback_status,
        source as payment_provider,
        chargeback as is_chargeback

    from source

)

select * from renamed
