with products as (
    select * from {{ ref('stg_products') }}
),

order_items as (
    select * from {{ ref('stg_order_items') }}
),

product_stats as (
    select
        product_id,
        sum(quantity) as total_units_sold,
        sum(line_total) as total_revenue,
        count(distinct order_id) as number_of_orders
    from order_items
    group by product_id
)

select
    p.product_id,
    p.product_name,
    p.category,
    p.subcategory,
    p.unit_price,
    p.product_created_at,
    coalesce(ps.total_units_sold, 0) as total_units_sold,
    coalesce(ps.total_revenue, 0) as total_revenue,
    coalesce(ps.number_of_orders, 0) as number_of_orders
from products p
left join product_stats ps on p.product_id = ps.product_id
