{{ config(severity='warn') }}

select
    u.customer_id,
    u.usage_month,
    c.signup_date
from {{ ref('stg_usage_events') }} u
join {{ ref('stg_customers') }} c using (customer_id)
where u.usage_month < date_trunc('month', c.signup_date)