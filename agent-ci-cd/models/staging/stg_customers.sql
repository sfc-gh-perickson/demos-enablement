with source as (
    select * from {{ ref('customers') }}
),

staged as (
    select
        customer_id,
        first_name,
        last_name,
        first_name || ' ' || last_name as full_name,
        email,
        city,
        state,
        country,
        created_at::timestamp as customer_created_at
    from source
)

select * from staged
