with source as (
    select * from {{ ref('orders') }}
),

staged as (
    select
        order_id,
        customer_id,
        order_date::date as order_date,
        status as order_status,
        shipping_address_city,
        shipping_address_state
    from source
)

select * from staged
