



select
    1
from DEEL.staging.stg_acceptance

where not(transaction_amount >= 0)

