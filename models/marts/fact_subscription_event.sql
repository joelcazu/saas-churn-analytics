-- Grain: one row per deduplicated subscription event
with events as (
    select * from {{ ref('stg_subscription_events') }}
),

lifecycle as (
    select * from {{ ref('int_customer_lifecycle') }}
)

select
    md5(ev.event_id) as event_key,
    md5(ev.customer_id) as customer_key,
    ev.event_id,
    ev.customer_id,
    ev.event_date,
    ev.event_type as event_type_raw,
    ev.derived_direction,
    not ev.event_type_matches_derived as is_mislabeled_source,
    ev.plan_from,
    ev.plan_to,
    pf.assumed_monthly_price as plan_from_price,
    pt.assumed_monthly_price as plan_to_price,
    coalesce(pt.assumed_monthly_price, 0) - pf.assumed_monthly_price as mrr_delta,
    ev.cancellation_reason,
    row_number() over (
        partition by ev.customer_id order by ev.event_date, ev.event_id
    ) as customer_event_seq,
    lc.churn_date is not null and ev.event_date > lc.churn_date as is_event_after_churn
from events ev
left join lifecycle lc on ev.customer_id = lc.customer_id
left join {{ ref('dim_plan') }} pf on ev.plan_from = pf.plan
left join {{ ref('dim_plan') }} pt on ev.plan_to = pt.plan