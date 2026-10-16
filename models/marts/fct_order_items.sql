-- Order item fact table: one enriched row per order item. Assembles the staging
-- order items with their product details and the per-product supply cost (from the
-- intermediate model). This is the layer that brings the pieces together.

with

order_items as (

    select * from {{ ref('stg_order_items') }}

),

orders as (

    select * from {{ ref('stg_orders') }}

),

products as (

    select * from {{ ref('stg_products') }}

),

supply_costs as (

    select * from {{ ref('int_supplies_cost_per_product') }}

),

joined as (

    select
        order_items.order_item_id,
        order_items.order_id,
        order_items.product_id,

        orders.ordered_at,

        products.product_name,
        products.product_price,
        products.is_food_item,
        products.is_drink_item,

        supply_costs.supply_cost

    from order_items

    left join orders on order_items.order_id = orders.order_id

    left join products on order_items.product_id = products.product_id

    left join supply_costs on order_items.product_id = supply_costs.product_id

)

select * from joined
