with orders as (
    select * from {{ ref('stg_orders') }}
),

order_items as (
    select * from {{ ref('stg_order_items') }}
),

order_totals as (
    select
        order_id,
        sum(quantity) as total_quantity,
        sum(line_total) as order_total,
        sum(discount_amount) as total_discount,
        count(order_item_id) as number_of_items
    from order_items
    group by order_id
)

select
    o.order_id,
    o.customer_id,
    o.order_date,
    o.order_status,
    o.shipping_address_city,
    o.shipping_address_state,
    coalesce(ot.total_quantity, 0) as total_quantity,
    coalesce(ot.order_total, 0) as order_total,
    coalesce(ot.total_discount, 0) as total_discount,
    coalesce(ot.number_of_items, 0) as number_of_items
from orders o
left join order_totals ot on o.order_id = ot.order_id
