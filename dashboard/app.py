"""SaaS Subscription & Churn Analytics — Streamlit dashboard.

Reads directly from the DuckDB file produced by `dbt build`.
Run from the project root:  streamlit run dashboard/app.py
"""

from pathlib import Path

import duckdb
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import streamlit as st

# Database lives in the project root, no matter where streamlit is launched from
DB_PATH = str(Path(__file__).resolve().parent.parent / "saas_churn.duckdb")

st.set_page_config(page_title="SaaS Churn Analytics", layout="wide")

st.title("SaaS Subscription & Churn Analytics")
st.caption(
    "Built with dbt + DuckDB. Definitions: active month = monthly_logins > 0; "
    "plan-change direction derived from plan hierarchy, not source labels; "
    "MRR uses assumed plan pricing (see dim_plan)."
)


@st.cache_data(ttl=300)
def q(query: str) -> pd.DataFrame:
    """Run a read-only query against the dbt-built DuckDB warehouse."""
    con = duckdb.connect(DB_PATH, read_only=True)
    try:
        return con.execute(query).df()
    finally:
        con.close()


tab1, tab2, tab3, tab4 = st.tabs(
    ["Pre-churn signal", "Cohort retention", "MRR movement", "Churn risk"]
)

# --------------------------------------------------------------- TAB 1
with tab1:
    st.subheader("Usage indexed to 100 in the months before cancellation")
    st.markdown(
        "Average monthly logins of churned customers, indexed to each customer's "
        "own baseline (mean of months -4 to -6 before churn). Includes only "
        "customers with a non-zero baseline and no events recorded after their "
        "cancellation (misdated cancellations are excluded)."
    )
    df = q("""
        with churned as (
            select
                f.customer_id,
                f.monthly_logins,
                datediff('month', f.calendar_month, d.churn_date) as months_before_churn
            from fact_customer_month as f
            join dim_customer as d using (customer_id)
            where d.is_churned
              and d.n_events_after_churn = 0
              and datediff('month', f.calendar_month, d.churn_date) between 0 and 6
              and f.monthly_logins is not null
        ),
        base as (
            select customer_id, avg(monthly_logins) as base_logins
            from churned
            where months_before_churn between 4 and 6
            group by customer_id
            having avg(monthly_logins) > 0
        )
        select
            c.months_before_churn,
            count(distinct c.customer_id) as n_customers,
            round(avg(c.monthly_logins / b.base_logins) * 100, 1) as avg_indexed_logins
        from churned as c
        join base as b using (customer_id)
        group by c.months_before_churn
        order by c.months_before_churn
    """)
    st.metric("Churned customers in sample", int(df["n_customers"].max()))
    fig = px.line(df, x="months_before_churn", y="avg_indexed_logins", markers=True)
    fig.update_xaxes(title="Months before cancellation (0 = churn month)")
    fig.update_yaxes(title="Avg logins, indexed (100 = own baseline)", range=[0, 110])
    st.plotly_chart(fig, use_container_width=True)

# --------------------------------------------------------------- TAB 2
with tab2:
    st.subheader("Retention by signup cohort (quarterly)")
    ret = q("""
        with cust as (
            select
                customer_id,
                printf('%d-Q%d', year(signup_date), quarter(signup_date)) as cohort
            from dim_customer
        ),
        sizes as (
            select cohort, count(*) as cohort_size
            from cust
            group by 1
        ),
        activity as (
            select
                c.cohort,
                f.months_since_signup,
                f.customer_id,
                f.is_active
            from fact_customer_month f
            join cust c using (customer_id)
            where f.months_since_signup <= 12
        )
        select
            a.cohort,
            a.months_since_signup,
            s.cohort_size,
            count(distinct case when a.is_active then a.customer_id end) as active_customers,
            count(distinct case when a.is_active then a.customer_id end) * 1.0
                / s.cohort_size as retention_rate
        from activity a
        join sizes s using (cohort)
        group by 1, 2, 3
        order by 1, 2
    """)
    pivot  = ret.pivot(index="cohort", columns="months_since_signup", values="retention_rate")
    active = ret.pivot(index="cohort", columns="months_since_signup", values="active_customers")
    sizes  = ret.drop_duplicates("cohort").set_index("cohort")["cohort_size"]

    hovertext = [
        [
            f"{pivot.iloc[i, j]:.0%} active ({int(active.iloc[i, j])} of {int(sizes[pivot.index[i]])})"
            if pd.notna(pivot.iloc[i, j]) else "cohort not old enough yet"
            for j in range(pivot.shape[1])
        ]
        for i in range(pivot.shape[0])
    ]

    fig = px.imshow(
        pivot,
        color_continuous_scale="Blues",
        aspect="auto",
        zmin=0, zmax=1,
        labels=dict(x="Months since signup", y="Signup cohort", color="Retention"),
    )
    fig.update_traces(
        hovertext=hovertext,
        hovertemplate="%{y} + %{x}m<br>%{hovertext}<extra></extra>",
    )
    fig.update_layout(height=560)
    st.plotly_chart(fig, use_container_width=True)
    st.caption(
        "Quarterly cohorts pool ~25-40 customers per cell so the gradient is readable. "
        "Blank cells = cohort not old enough yet (normal censoring, not missing data). "
        "Active = monthly_logins > 0."
    )
# --------------------------------------------------------------- TAB 3
with tab3:
    st.subheader("Monthly MRR movement (assumed pricing)")
    mrr = q("""
        with movements as (
            -- 1) New business: each signup adds its initial plan's price
            select
                strftime('%Y-%m', d.signup_date) as month,
                'new' as movement,
                sum(p.assumed_monthly_price) as mrr_change
            from dim_customer d
            join dim_plan p on d.initial_plan = p.plan
            group by 1, 2

            union all

            -- 2) Expansion / contraction / churn from plan-change events
            select
                strftime('%Y-%m', event_date) as month,
                case derived_direction
                    when 'upgrade'      then 'expansion'
                    when 'downgrade'    then 'contraction'
                    when 'cancellation' then 'churn_loss'
                end as movement,
                sum(case derived_direction
                        when 'upgrade'      then greatest(mrr_delta, 0)
                        when 'downgrade'    then least(mrr_delta, 0)
                        when 'cancellation' then mrr_delta
                    end) as mrr_change
            from fact_subscription_event
            where not is_event_after_churn
              and derived_direction <> 'no_change'
            group by 1, 2
        )
        select month, movement, round(sum(mrr_change), 0) as mrr_change
        from movements
        group by 1, 2
        order by 1, 2
    """)

    order  = ['new', 'expansion', 'contraction', 'churn_loss']
    labels = {
        'new':          'New business',
        'expansion':    'Expansion (upgrades)',
        'contraction':  'Contraction (downgrades)',
        'churn_loss':   'Churned MRR',
    }
    colors = {
        'new':          '#1f77b4',
        'expansion':    '#2ca02c',
        'contraction':  '#ff7f0e',
        'churn_loss':   '#d62728',
    }

    pivot = mrr.pivot(index='month', columns='movement',
                      values='mrr_change').fillna(0)
    for col in order:                      # guarantee all 4 columns exist
        if col not in pivot.columns:
            pivot[col] = 0.0
    pivot = pivot[order]
    pivot['ending_mrr'] = pivot[order].sum(axis=1).cumsum()

    fig = go.Figure()
    for col in order:
        fig.add_trace(go.Bar(name=labels[col], x=pivot.index, y=pivot[col],
                             marker_color=colors[col]))
    fig.add_trace(go.Scatter(name='Ending MRR', x=pivot.index,
                             y=pivot['ending_mrr'], mode='lines',
                             yaxis='y2', line=dict(color='white', width=2)))
    fig.update_layout(
        barmode='stack',
        xaxis_title='Month',
        yaxis_title='MRR change ($/month)',
        yaxis2=dict(title='Ending MRR ($/month)', overlaying='y', side='right'),
        legend_title='Movement',
        height=520,
    )
    st.plotly_chart(fig, use_container_width=True)
    st.caption(
        "New business = signups x initial plan price; ending MRR (white line) is the "
        "cumulative sum of all four movements. Prices are assumptions (dim_plan), so "
        "treat dollar levels as illustrative - the *mix* of movements is the real signal."
    )
# --------------------------------------------------------------- TAB 4
with tab4:
    st.subheader("Active customers: health score vs usage trend")
    risk = q("""
        select
            customer_id,
            acquisition_channel,
            current_plan,
            risk_segment,
            latest_health_score,
            latest_logins_slope_3m,
            company_size_employees
        from dim_customer
        where not is_churned
          and latest_health_score is not null
    """)
    fig = px.scatter(
        risk,
        x="latest_logins_slope_3m",
        y="latest_health_score",
        color="risk_segment",
        size="company_size_employees",
        size_max=18,
        hover_data=["customer_id", "acquisition_channel", "current_plan"],
        labels={
            "latest_logins_slope_3m": "Usage trend (3-month slope of logins)",
            "latest_health_score": "Health score (0-100)",
        },
    )
    fig.add_vline(x=0, line_dash="dot", line_color="gray")
    fig.add_hline(y=50, line_dash="dot", line_color="gray")
    st.plotly_chart(fig, use_container_width=True)

    st.markdown("**Top 20 highest-risk active customers (lowest health score first)**")
    st.dataframe(
        risk[risk["risk_segment"] == "high_risk"]
        .sort_values("latest_health_score")
        .head(20),
        use_container_width=True,
        hide_index=True,
    )