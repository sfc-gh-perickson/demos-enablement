with source as (
    select * from {{ ref('products') }}
),

staged as (
    select
        product_id,
        product_name,
        category,
        subcategory,
        unit_price::decimal(10,2) as unit_price,
        created_at::timestamp as product_created_at
    from source
)

select * from staged
