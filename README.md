# SaaS Subscription & Churn Analytics

An end-to-end analytics engineering project: raw, intentionally messy
CRM/billing/usage exports → tested dbt models → star-schema marts →
live dashboard. Built with dbt-core, DuckDB, and Streamlit.

**Live dashboard:** [link]

## The data problem
- 3 source files, ~660 events, ~12k usage rows, 400 customers
- Known messiness found and handled:
  - 3 different date formats → single parser macro
  - 4 exact duplicate event rows → deduplicated
  - Inconsistent plan casing → normalized
  - **~N events where `event_type` contradicts the plan transition**
    (e.g. "upgrade" Growth→Starter) → direction derived from plan
    hierarchy instead of trusted
  - N events dated after a customer's cancellation → flagged, excluded from MRR

## Key modeling decisions
1. Never trust source labels — derive and measure disagreement
2. Health score compares each customer to *their own* first-3-month baseline
3. "Active" = monthly_logins > 0 (zombie accounts with 0 logins exist post-churn)
4. No revenue in source → plan pricing is an explicitly stated assumption

## Validation
Of customers who cancelled, X% had a negative 3-month usage slope and
Y% had a health score below 50 in their churn month.

## How to run
pip install dbt-duckdb streamlit duckdb plotly
dbt build
streamlit run dashboard/app.py