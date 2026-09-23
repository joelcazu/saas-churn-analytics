with lifecycle as (
    select * from {{ ref('int_customer_lifecycle') }}
),

usage as (
    select * from {{ ref('int_customer_month_usage') }}
),

latest_usage as (
    select
        customer_id,
        usage_month as latest_usage_month,
        health_score as latest_health_score,
        logins_slope_3m as latest_logins_slope_3m
    from usage
    qualify row_number() over (
        partition by customer_id order by usage_month desc
    ) = 1
),

last_active as (
    select customer_id, max(usage_month) as last_active_month
    from usage
    where monthly_logins > 0
    group by customer_id
),

as_of as (
    select max(usage_month) as as_of_month from usage
)

select
    md5(lc.customer_id) as customer_key,
    lc.customer_id,
    lc.signup_date,
    date_trunc('month', lc.signup_date)::date as signup_month,
    lc.initial_plan,
    lc.acquisition_channel,
    lc.industry,
    lc.company_size_employees,
    lc.current_plan,
    lc.is_churned,
    lc.churn_date,
    lc.churn_reason,
    lc.lifetime_months,
    lc.n_events_after_churn,
    lu.latest_health_score,
    lu.latest_logins_slope_3m,
    la.last_active_month,
    datediff('month', la.last_active_month, a.as_of_month) as months_since_last_active,
    case
        when lc.is_churned then 'churned'
        when lu.latest_health_score < 60 then 'high_risk'          -- already collapsed
        when lu.latest_health_score < 80
          or lu.latest_logins_slope_3m < -1.0 then 'watch'          -- declining now
        else 'healthy'
    end as risk_segment
from lifecycle lc
left join latest_usage lu on lc.customer_id = lu.customer_id
left join last_active la on lc.customer_id = la.customer_id
cross join as_of a