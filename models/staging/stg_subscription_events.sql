with source as (

    select *
    from {{ ref('subscription_events') }}

),

deduped as (

    select *
    from source

    qualify row_number() over (
        partition by
            event_id,
            customer_id,
            event_date,
            event_type,
            plan_from,
            plan_to,
            cancellation_reason
        order by event_id
    ) = 1

),

cleaned as (

    select
        event_id,
        customer_id,
        {{ parse_flexible_date('event_date') }} as event_date,
        lower(trim(event_type)) as event_type,
        trim(plan_from) as plan_from,

        case
            when plan_to is null or trim(plan_to) = '' then null
            else trim(plan_to)
        end as plan_to,

        coalesce(
            nullif(trim(cancellation_reason), ''),
            'Unknown'
        ) as cancellation_reason

    from deduped

),

with_ranks as (

    select
        *,

        case lower(plan_from)
            when 'starter' then 1
            when 'growth' then 2
            when 'pro' then 3
            when 'enterprise' then 4
        end as plan_from_rank,

        case
            when plan_to is null then null
            else case lower(plan_to)
                when 'starter' then 1
                when 'growth' then 2
                when 'pro' then 3
                when 'enterprise' then 4
            end
        end as plan_to_rank

    from cleaned

)

select
    *,

    case
        when event_type = 'cancellation' then 'cancellation'
        when plan_to_rank is not null
             and plan_to_rank > plan_from_rank then 'upgrade'
        when plan_to_rank is not null
             and plan_to_rank < plan_from_rank then 'downgrade'
        else 'no_change'
    end as derived_direction,

    case
        when event_type = 'cancellation' then true
        else event_type =
            case
                when plan_to_rank is not null
                     and plan_to_rank > plan_from_rank then 'upgrade'
                when plan_to_rank is not null
                     and plan_to_rank < plan_from_rank then 'downgrade'
                else 'no_change'
            end
    end as event_type_matches_derived

from with_ranks