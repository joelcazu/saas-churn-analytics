with source as (
    select * from {{ ref('customers') }}
)

select
    customer_id,
    {{ parse_flexible_date('signup_date') }} as signup_date,
    signup_date as signup_date_raw,          -- kept so anyone can audit the parsing
    trim(initial_plan) as initial_plan,
    trim(acquisition_channel) as acquisition_channel,
    trim(industry) as industry,
    company_size_employees
from source
