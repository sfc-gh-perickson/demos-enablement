with source as (
    select * from {{ ref('order_items') }}
),

staged as (
    select
        order_item_id,
        order_id,
        product_id,
        quantity,
        unit_price::decimal(10,2) as unit_price,
        discount_amount::decimal(10,2) as discount_amount,
        (quantity * unit_price::decimal(10,2)) - discount_amount::decimal(10,2) as line_total
    from source
)

select * from staged
