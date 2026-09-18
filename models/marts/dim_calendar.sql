-- One row per calendar month covering the full data range
with months as (
    select unnest(
        generate_series(date '2022-01-01', date '2025-06-01', interval '1 month')
    ) as calendar_month
)

select
    calendar_month::date as calendar_month,
    year(calendar_month) as calendar_year,
    month(calendar_month) as month_number,
    strftime(calendar_month::date, '%Y-%m') as month_label
from months