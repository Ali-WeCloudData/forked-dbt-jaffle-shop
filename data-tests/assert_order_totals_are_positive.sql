-- Singular test: a single .sql file that returns the rows that FAIL the assertion.
-- If this query returns zero rows, the test passes. Here we assert that every
-- order in the orders fact table has a positive total.

select
    order_id,
    order_total
from {{ ref('fct_orders') }}
where order_total <= 0
