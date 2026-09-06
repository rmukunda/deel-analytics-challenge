
    
    

select
    transaction_id as unique_field,
    count(*) as n_records

from DEEL.marts.fct_acceptance_transactions
where transaction_id is not null
group by transaction_id
having count(*) > 1


