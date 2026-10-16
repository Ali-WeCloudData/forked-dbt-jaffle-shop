{% docs order_id %}
The unique identifier for an order. One order can contain many order items.

This description is defined once in a doc block and reused in several models via
`{{ doc('order_id') }}`, so the definition stays consistent across the project.
{% enddocs %}

{% docs order_item_id %}
The unique identifier for a single order item — one product within one order.
{% enddocs %}

{% docs customer_id %}
The unique identifier for a customer.
{% enddocs %}

{% docs product_id %}
The unique identifier for a product (its SKU).
{% enddocs %}

{% docs ordered_at %}
The timestamp an order was placed, truncated to the day.
{% enddocs %}
