-- Intermediate model: rolls fluctuating supply costs up to one cost per product.
-- stg_supplies has many rows per product (costs change over time, each a new row);
-- this collapses them to a single supply_cost per product so a mart can join it 1:1.
-- Depends only on staging. Materialized as a view in the dev_intermediate schema.

select
    product_id,
    cast(sum(supply_cost) as numeric(16, 2)) as supply_cost
from {{ ref('stg_supplies') }}
group by 1
