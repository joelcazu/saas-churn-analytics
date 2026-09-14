{{ config(severity='warn') }}

-- Events shouldn't happen before the customer signed up.
-- severity='warn' because if rows appear, that's a real data
-- quality finding to discuss in the writeup, not a build-breaker.
select
    e.event_id,
    e.customer_id,
    e.event_date,
    c.signup_date
from {{ ref('stg_subscription_events') }} e
join {{ ref('stg_customers') }} c using (customer_id)
where e.event_date < c.signup_date