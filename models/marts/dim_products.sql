-- Product dimension table. One row per product.

with

products as (

    select * from {{ ref('stg_products') }}

),

final as (

    select
        product_id,
        product_name,
        product_type,
        product_description,
        product_price,
        is_food_item,
        is_drink_item

    from products

)

select * from final
