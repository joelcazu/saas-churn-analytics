-- Grain: one row per signup cohort x months since signup
with customers as (
    select * from {{ ref('dim_customer') }}
),

activity as (
    select customer_id, months_since_signup, is_active
    from {{ ref('fact_customer_month') }}
),

cohort_sizes as (
    select signup_month, count(*) as cohort_size
    from customers
    group by 1
)

select
    c.signup_month as cohort_month,
    a.months_since_signup,
    cs.cohort_size,
    count(distinct a.customer_id) as active_customers,
    round(count(distinct a.customer_id) * 1.0 / cs.cohort_size, 3) as retention_rate
from activity a
join customers c on a.customer_id = c.customer_id
join cohort_sizes cs on c.signup_month = cs.signup_month
where a.is_active
group by 1, 2, 3