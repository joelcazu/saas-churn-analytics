with source as (
    select * from {{ ref('usage_events') }}
)

select
    customer_id,
    (usage_month || '-01')::date as usage_month,   -- '2024-04' -> 2024-04-01
    monthly_logins,                                -- nulls kept as nulls on purpose
    monthly_logins is null as is_login_gap,        -- flags the tracking gaps
    active_users,
    support_tickets
from source