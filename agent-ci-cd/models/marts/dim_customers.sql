with customers as (
    select * from {{ ref('stg_customers') }}
),

orders as (
    select * from {{ ref('stg_orders') }}
),

customer_orders as (
    select
        customer_id,
        min(order_date) as first_order_date,
        max(order_date) as most_recent_order_date,
        count(order_id) as number_of_orders
    from orders
    group by customer_id
)

select
    c.customer_id,
    c.full_name as customer_name,
    c.email,
    c.city,
    c.state,
    c.country,
    c.customer_created_at,
    co.first_order_date,
    co.most_recent_order_date,
    coalesce(co.number_of_orders, 0) as lifetime_orders
from customers c
left join customer_orders co on c.customer_id = co.customer_id
