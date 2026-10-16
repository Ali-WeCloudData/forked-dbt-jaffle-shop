{{
    config(
        materialized='incremental',
        unique_key='order_id',
        incremental_strategy='merge'
    )
}}

with

orders as (

    select * from {{ ref('stg_orders') }}

    {% if is_incremental() %}
    -- Reprocess orders on/after the latest ordered_at already loaded. Using >= (not >)
    -- means orders placed later on the current boundary day aren't missed; the merge on
    -- order_id upserts them, so reprocessed rows are updated in place, never duplicated.
    where ordered_at >= (select max(ordered_at) from {{ this }})
    {% endif %}

),

order_items as (

    select * from {{ ref('fct_order_items') }}

),

order_items_summary as (

    select
        order_id,

        sum(supply_cost) as order_cost,
        sum(product_price) as order_items_subtotal,
        count(order_item_id) as count_order_items,
        sum(case when is_food_item then 1 else 0 end) as count_food_items,
        sum(case when is_drink_item then 1 else 0 end) as count_drink_items

    from order_items

    group by 1

),

final as (

    select
        orders.order_id,
        orders.customer_id,
        orders.subtotal,
        orders.tax_paid,
        orders.order_total,
        orders.ordered_at,

        order_items_summary.order_cost,
        order_items_summary.order_items_subtotal,
        order_items_summary.count_order_items,
        order_items_summary.count_food_items,
        order_items_summary.count_drink_items,
        order_items_summary.count_food_items > 0 as is_food_order,
        order_items_summary.count_drink_items > 0 as is_drink_order

    from orders

    left join order_items_summary
        on orders.order_id = order_items_summary.order_id

)

select * from final
