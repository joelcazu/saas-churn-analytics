with lifecycle as (
    select * from {{ ref('int_customer_lifecycle') }}
),

latest_usage as (
    select
        customer_id,
        usage_month as latest_usage_month,
        health_score as latest_health_score,
        logins_slope_3m as latest_logins_slope_3m
    from {{ ref('int_customer_month_usage') }}
    qualify row_number() over (
        partition by customer_id order by usage_month desc
    ) = 1
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
    case
        when lc.is_churned then 'churned'
        when lu.latest_health_score < 40 and lu.latest_logins_slope_3m < 0 then 'high_risk'
        when lu.latest_health_score < 60 or lu.latest_logins_slope_3m < 0 then 'watch'
        else 'healthy'
    end as risk_segment
from lifecycle lc
left join latest_usage lu on lc.customer_id = lu.customer_id