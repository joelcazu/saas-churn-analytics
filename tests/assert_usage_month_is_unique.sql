-- A customer should never have two rows for the same month
select
    customer_id,
    usage_month,
    count(*) as n_rows
from {{ ref('stg_usage_events') }}
group by 1, 2
having count(*) > 1