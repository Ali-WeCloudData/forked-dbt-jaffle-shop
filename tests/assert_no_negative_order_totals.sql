-- Singular test: a single .sql file that returns the rows that FAIL the assertion.
-- If this query returns zero rows, the test passes. Here we assert that no order
-- has a negative total. (Zero totals are allowed, e.g. fully-discounted orders.)

select
    order_id,
    order_total
from {{ ref('fct_orders') }}
where order_total < 0
