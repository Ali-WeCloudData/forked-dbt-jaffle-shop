-- Intermediate model: re-grains orders to one row per customer before the
-- customers dimension consumes it. Materialized as ephemeral (see
-- dbt_project.yml), so it creates no object in the warehouse — dbt inlines it
-- as a CTE inside every model that ref()s it.

with orders as (

    select * from {{ ref('fct_orders') }}

),

customer_orders_summary as (

    select
        customer_id,

        count(distinct order_id) as count_lifetime_orders,
        count(distinct order_id) > 1 as is_repeat_buyer,
        min(ordered_at) as first_ordered_at,
        max(ordered_at) as last_ordered_at,
        sum(subtotal) as lifetime_spend_pretax,
        sum(tax_paid) as lifetime_tax_paid,
        sum(order_total) as lifetime_spend

    from orders

    group by 1

)

select * from customer_orders_summary
