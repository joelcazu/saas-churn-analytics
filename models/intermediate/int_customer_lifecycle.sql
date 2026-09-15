with customers as (
    select * from {{ ref('stg_customers') }}
),

events as (
    select * from {{ ref('stg_subscription_events') }}
),

-- Policy: a customer's FIRST cancellation is treated as the terminal one.
churn as (
    select
        customer_id,
        min(event_date) as churn_date,
        min_by(cancellation_reason, event_date) as churn_reason
    from events
    where event_type = 'cancellation'
    group by customer_id
),

last_plan_change as (
    select customer_id, plan_to as current_plan
    from events
    where derived_direction in ('upgrade', 'downgrade')
      and plan_to is not null
    qualify row_number() over (
        partition by customer_id
        order by event_date desc, event_id desc
    ) = 1
),

-- Counts events dated AFTER the cancellation (a known data quality issue
-- in the source; we measure it instead of hiding it)
post_churn as (
    select e.customer_id, count(*) as n_events_after_churn
    from events e
    join churn c on e.customer_id = c.customer_id
    where e.event_date > c.churn_date
    group by 1
)

select
    cu.customer_id,
    cu.signup_date,
    cu.initial_plan,
    cu.acquisition_channel,
    cu.industry,
    cu.company_size_employees,
    coalesce(lp.current_plan, cu.initial_plan) as current_plan,
    c.churn_date,
    c.churn_reason,
    c.churn_date is not null as is_churned,
    datediff('month', cu.signup_date, coalesce(c.churn_date, current_date)) as lifetime_months,
    coalesce(p.n_events_after_churn, 0) as n_events_after_churn
from customers cu
left join churn c on cu.customer_id = c.customer_id
left join last_plan_change lp on cu.customer_id = lp.customer_id
left join post_churn p on cu.customer_id = p.customer_id