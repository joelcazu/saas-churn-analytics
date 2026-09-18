-- Grain: one row per customer per calendar month, from signup month
-- through the earlier of churn month or last observed usage month.
with lifecycle as (
    select * from {{ ref('int_customer_lifecycle') }}
),

usage as (
    select * from {{ ref('int_customer_month_usage') }}
),

calendar as (
    select * from {{ ref('dim_calendar') }}
),

last_seen as (
    select customer_id, max(usage_month) as last_observed_month
    from usage
    group by 1
),

spine as (
    select lc.customer_id, cal.calendar_month
    from lifecycle lc
    join last_seen ls on lc.customer_id = ls.customer_id
    join calendar cal
      on cal.calendar_month >= date_trunc('month', lc.signup_date)::date
     and cal.calendar_month <= least(
            ls.last_observed_month,
            coalesce(lc.churn_date, ls.last_observed_month)
        )
)

select
    md5(sp.customer_id || '|' || sp.calendar_month::varchar) as customer_month_key,
    md5(sp.customer_id) as customer_key,
    sp.customer_id,
    sp.calendar_month,
    u.months_since_signup,
    u.monthly_logins,
    u.active_users,
    u.support_tickets,
    u.is_login_gap,
    u.health_score,
    u.logins_slope_3m,
    coalesce(u.monthly_logins, 0) > 0 as is_active,   -- definition documented in README
    u.is_churn_month,
    u.is_post_churn
from spine sp
left join usage u
    on sp.customer_id = u.customer_id
   and u.usage_month = sp.calendar_month