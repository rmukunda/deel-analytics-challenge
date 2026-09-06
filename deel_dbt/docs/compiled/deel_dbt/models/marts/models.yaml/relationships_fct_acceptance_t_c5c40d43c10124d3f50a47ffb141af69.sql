
    
    

with child as (
    select transaction_date_key as from_field
    from DEEL.marts.fct_acceptance_transactions
    where transaction_date_key is not null
),

parent as (
    select date_day as to_field
    from DEEL.marts.dim_calendar
)

select
    from_field

from child
left join parent
    on child.from_field = parent.to_field

where parent.to_field is null


