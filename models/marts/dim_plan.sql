-- Plan hierarchy + ASSUMED monthly pricing. There is no revenue data in
-- the source, so prices are a documented modeling assumption (see README).
select 'Starter'    as plan, 1 as plan_rank, 29  as assumed_monthly_price
union all
select 'Growth',    2, 99
union all
select 'Pro',       3, 249
union all
select 'Enterprise', 4, 999