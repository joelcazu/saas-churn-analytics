import duckdb
import pandas as pd
import plotly.express as px
import streamlit as st

DB_PATH = "saas_churn.duckdb"   # ← adjust if your dbt file has another name

st.set_page_config(page_title="SaaS Churn Analytics", layout="wide")
st.title("SaaS Subscription & Churn Analytics")
st.caption("Built with dbt + DuckDB. Definitions: active = monthly_logins > 0; "
           "direction derived from plan hierarchy, not source labels.")

@st.cache_data
def q(query):
    with duckdb.connect(DB_PATH, read_only=True) as con:
        return con.execute(query).df()

tab1, tab2, tab3, tab4 = st.tabs(
    ["Pre-churn signal", "Cohort retention", "MRR movement", "Churn risk"]
)

# ---- 1. Pre-churn usage collapse ------------------------------------------
with tab1:
    st.subheader("Usage indexed to 100 six months before churn")
    df = q("""
        with churned as (
            select f.customer_id, f.monthly_logins,
                   datediff('month', f.calendar_month, d.churn_date) as months_before_churn
            from fact_customer_month f
            join dim_customer d using (customer_id)
            where d.is_churned
              and datediff('month', f.calendar_month, d.churn_date) between 0 and 6
              and f.monthly_logins is not null
        ),
        indexed as (
            select *,
                   first_value(monthly_logins) over (
                       partition by customer_id
                       order by months_before_churn desc
                   ) as base_logins
            from churned
        )
        select months_before_churn,
               round(avg(monthly_logins / nullif(base_logins, 0)) * 100, 1) as avg_indexed_logins
        from indexed
        group by 1
        order by 1 desc
    """)
    fig = px.line(df, x="months_before_churn", y="avg_indexed_logins", markers=True)
    fig.update_xaxes(title="Months before cancellation (6 = six months prior)")
    fig.update_yaxes(title="Avg logins, indexed (100 = month -6 level)")
    st.plotly_chart(fig, use_container_width=True)

# ---- 2. Cohort retention heatmap ------------------------------------------
with tab2:
    st.subheader("Retention by signup cohort")
    ret = q("""
        select strftime(cohort_month, '%Y-%m') as cohort, months_since_signup, retention_rate
        from agg_cohort_retention
        where months_since_signup <= 12
    """)
    pivot = ret.pivot(index="cohort", columns="months_since_signup", values="retention_rate")
    fig = px.imshow(pivot, color_continuous_scale="Blues", aspect="auto",
                    labels=dict(x="Months since signup", y="Cohort", color="Retention"))
    st.plotly_chart(fig, use_container_width=True)

# ---- 3. MRR movement --------------------------------------------------------
with tab3:
    st.subheader("Monthly MRR movement (assumed pricing)")
    df = q("""
        select strftime(event_date, '%Y-%m') as month,
               sum(case when derived_direction = 'upgrade' then greatest(mrr_delta, 0) else 0 end) as expansion,
               sum(case when derived_direction = 'downgrade' then mrr_delta else 0 end) as contraction,
               sum(case when derived_direction = 'cancellation' then mrr_delta else 0 end) as churn_loss
        from fact_subscription_event
        where not is_event_after_churn
        group by 1
        order by 1
    """)
    fig = px.bar(df, x="month", y=["expansion", "contraction", "churn_loss"],
                 barmode="group")
    st.plotly_chart(fig, use_container_width=True)

# ---- 4. Risk quadrant ---------------------------------------------------------
with tab4:
    st.subheader("Active customers: health score vs usage trend")
    df = q("""
        select customer_id, acquisition_channel, risk_segment,
               latest_health_score, latest_logins_slope_3m, company_size_employees
        from dim_customer
        where not is_churned and latest_health_score is not null
    """)
    fig = px.scatter(df, x="latest_logins_slope_3m", y="latest_health_score",
                     color="risk_segment", hover_data=["customer_id", "acquisition_channel"],
                     labels={"latest_logins_slope_3m": "Usage slope (3-mo trend)",
                             "latest_health_score": "Health score"})
    st.plotly_chart(fig, use_container_width=True)
    st.dataframe(
        df[df.risk_segment == "high_risk"]
        .sort_values("latest_health_score")
        .head(20),
        use_container_width=True,
    )