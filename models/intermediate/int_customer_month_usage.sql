with usage as (
    select * from {{ ref('stg_usage_events') }}
),

lifecycle as (
    select * from {{ ref('int_customer_lifecycle') }}
),

joined as (
    select
        u.customer_id,
        u.usage_month,
        datediff('month', date_trunc('month', lc.signup_date), u.usage_month) as months_since_signup,
        u.monthly_logins,
        u.active_users,
        u.support_tickets,
        u.is_login_gap,
        lc.churn_date,
        lc.is_churned,
        u.usage_month = date_trunc('month', lc.churn_date) as is_churn_month,
        lc.churn_date is not null
            and u.usage_month > date_trunc('month', lc.churn_date) as is_post_churn
    from usage u
    join lifecycle lc on u.customer_id = lc.customer_id
),

-- Each customer's OWN early baseline (months 1-3 after signup).
-- Comparing customers to themselves avoids penalizing naturally small accounts.
baseline as (
    select
        customer_id,
        nullif(avg(monthly_logins), 0) as baseline_logins,
        nullif(avg(active_users), 0) as baseline_users
    from joined
    where months_since_signup between 1 and 3
      and monthly_logins is not null
    group by customer_id
),

-- Sums needed for a least-squares slope over the trailing 3 months
with_sums as (
    select
        j.*,
        count(j.monthly_logins) over w as n_window,
        sum(j.months_since_signup * j.monthly_logins) over w as sum_xy,
        sum(j.months_since_signup) over w as sum_x,
        sum(j.monthly_logins) over w as sum_y,
        sum(j.months_since_signup * j.months_since_signup) over w as sum_xx
    from joined j
    window w as (
        partition by j.customer_id
        order by j.usage_month
        rows between 2 preceding and current row
    )
)

select
    s.customer_id,
    s.usage_month,
    s.months_since_signup,
    s.monthly_logins,
    s.active_users,
    s.support_tickets,
    s.is_login_gap,
    s.churn_date,
    s.is_churned,
    s.is_churn_month,
    s.is_post_churn,
    b.baseline_logins,
    -- Trend slope of logins over trailing <= 3 months (negative = declining)
    case
        when s.n_window >= 2
             and (s.n_window * s.sum_xx - s.sum_x * s.sum_x) <> 0
        then (s.n_window * s.sum_xy - s.sum_x * s.sum_y)
             / (s.n_window * s.sum_xx - s.sum_x * s.sum_x)
    end as logins_slope_3m,
    -- Health score (0-100): 50% login engagement, 30% seat retention,
    -- 20% support burden. Weights documented in the README.
    case
        when b.baseline_logins is null
             or b.baseline_users is null
             or s.monthly_logins is null then null
        else round(100 * (
            0.5 * least(greatest(s.monthly_logins / b.baseline_logins, 0), 1)
          + 0.3 * least(greatest(s.active_users::double / b.baseline_users, 0), 1)
          + 0.2 * greatest(1.0 - 0.2 * (s.support_tickets * 1.0 / nullif(s.active_users, 0)), 0)
        ), 1)
    end as health_score
from with_sums s
left join baseline b on s.customer_id = b.customer_id