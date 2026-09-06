
    
    

with all_values as (

    select
        transaction_status as value_field,
        count(*) as n_records

    from DEEL.staging.stg_acceptance
    group by transaction_status

)

select *
from all_values
where value_field not in (
    'ACCEPTED','DECLINED'
)


