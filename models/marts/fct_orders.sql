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
    -- On an incremental run, only process orders newer than what we've already loaded.
    -- (Teaching note: a production model would also handle late-arriving rows and the
    --  customer_order_number window below; we keep it simple here.)
    where ordered_at > (select coalesce(max(ordered_at), '1900-01-01') from {{ this }})
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
        sum(
            case
                when is_food_item then 1
                else 0
            end
        ) as count_food_items,
        sum(
            case
                when is_drink_item then 1
                else 0
            end
        ) as count_drink_items

    from order_items

    group by 1

),

compute_booleans as (

    select
        orders.*,

        order_items_summary.order_cost,
        order_items_summary.order_items_subtotal,
        order_items_summary.count_food_items,
        order_items_summary.count_drink_items,
        order_items_summary.count_order_items,
        order_items_summary.count_food_items > 0 as is_food_order,
        order_items_summary.count_drink_items > 0 as is_drink_order

    from orders

    left join
        order_items_summary
        on orders.order_id = order_items_summary.order_id

),

customer_order_count as (

    select
        *,

        row_number() over (
            partition by customer_id
            order by ordered_at asc
        ) as customer_order_number

    from compute_booleans

)

select * from customer_order_count
