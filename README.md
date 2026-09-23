# SaaS Subscription & Churn Analytics

End-to-end analytics engineering project: intentionally messy CRM / billing /
usage exports → tested dbt models → star-schema marts in DuckDB → live dashboard.
Runs 100% locally — no warehouse, no credentials.

**[Live dashboard ↗](https://saas-churn-analytics-gfjm5kcix5hdybraxdrb38.streamlit.app/)** · **[Case study ↗](…)** · **[LinkedIn ↗](…)**

![Dashboard overview](docs/images/dashboard_overview.png)

## Key findings

- **The pre-churn signal is real:** <X>% of customers who cancelled had a
  negative 3-month login slope in their final month; <Y>% scored below 50 on
  the health score.
- **<S> silent churns** — accounts with 3+ months of zero usage but *no*
  cancellation record in the CRM (e.g. CUST-0227). The risk tab surfaces them.
- **The source system mislabels plan changes:** <M> of <K> upgrade/downgrade
  events (<P>%) contradict the actual plan movement, and <NO> are "changes"
  where the plan didn't change at all. Direction is derived, never trusted.
- **<D> events are dated after the customer's cancellation** — flagged and
  excluded from MRR, not silently dropped.

## The data

Synthetic but realistic (CRM export + billing events + usage logs), with
messiness injected on purpose so the cleaning layer is real work.

| File | Grain | Rows | Contents |
|---|---|---|---|
| `customers.csv` | 1 row / customer | 400 | signup, plan, channel, industry, size |
| `subscription_events.csv` | 1 row / plan change or cancellation | 660 (656 after dedupe) | upgrades, downgrades, cancellations + reason |
| `usage_events.csv` | 1 row / customer / month | ~12k | logins, active users, tickets |

| Issue found | Count | Handling |
|---|---|---|
| 3 date formats | all date columns | `parse_flexible_date()` macro |
| Exact duplicate rows | 4 | deduped in staging, counted first |
| Plan casing (`PRO` vs `Pro`) | <C> rows | normalized |
| Null `monthly_logins` | <G> rows | kept NULL + `is_login_gap` flag, never imputed silently |
| `event_type` contradicts plan move | <M> rows | `derived_direction` from plan hierarchy; disagreement measured in `dq_event_label_mismatches` |
| Events after cancellation | <D> rows | flagged `is_event_after_churn`, excluded from MRR |

## Architecture

`seeds → staging → intermediate → marts → dashboard`

![dbt lineage](docs/images/lineage.png)

| Layer | Models | Highlights |
|---|---|---|
| staging | 3 `stg_*` | parsing, dedupe, casing, derived direction |
| intermediate | `int_customer_lifecycle`, `int_customer_month_usage` | churn dates; health score + 3-month least-squares slope |
| marts | 3 dims, 2 facts, 1 agg | star schema, grains documented in dbt docs |
| dashboard | `dashboard/app.py` | 4 tabs, one business question each |

**Testing:** <T> tests — uniqueness, not-null, accepted values, referential
integrity, plus custom singular tests (no usage before signup; one row per
customer-month; events-vs-signup sanity).

## Key modeling decisions

1. **Never trust source labels** — direction derived from plan hierarchy
   (Starter < Growth < Pro < Enterprise); disagreement measured, not hidden.
2. **Health score is self-referential** — scored against each customer's own
   first-3-month baseline, so small accounts aren't structurally "unhealthy".
3. **"Active" = `monthly_logins > 0`** — zombie rows with `active_users = 1`
   and zero logins exist post-churn; using active_users would overstate retention.
4. **First cancellation is terminal** — later events flagged, not deleted.
5. **Revenue is an assumption, stated openly** — `dim_plan` carries assumed
   prices; all MRR figures inherit this and say so.
6. **Month spine for `fact_customer_month`** — gaps can't hide silently.

## Validation

Of <C> customers who cancelled, <X>% showed a negative 3-month login slope and
<Y>% a health score below 50 in their churn month. Reproduce via the query in
`analysis/validate_churn_signal.sql`.

## Dashboard

| Tab | Question it answers |
|---|---|
| Pre-churn signal | Does usage actually decline before cancellation? |
| Cohort retention | Which cohorts (and channels) retain best? |
| MRR movement | How much of growth/loss is new vs expansion vs churn? |
| Churn risk | Which customers should CS call this week? |

## How to run

```bash
git clone https://github.com/<you>/saas-churn-analytics.git
cd saas-churn-analytics
pip install dbt-duckdb streamlit duckdb plotly
dbt build        # seeds + models + tests
dbt docs serve   # lineage & model documentation
streamlit run dashboard/app.py