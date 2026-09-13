{% macro parse_flexible_date(column) %}
    coalesce(
        try_strptime({{ column }}, '%Y-%m-%d')::date,    {# 2023-07-17 #}
        try_strptime({{ column }}, '%m/%d/%Y')::date,    {# 02/19/2022 #}
        try_strptime({{ column }}, '%d-%b-%Y')::date     {# 30-Apr-2024 #}
    )
{% endmacro %}