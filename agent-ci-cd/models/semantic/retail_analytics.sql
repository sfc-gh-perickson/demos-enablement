{{ config(materialized='semantic_view') }}

TABLES(
    customers AS {{ ref('dim_customers') }},
    products AS {{ ref('dim_products') }},
    orders AS {{ ref('fct_orders') }}
)
RELATIONSHIPS(
    orders.customer_id REFERENCES customers.customer_id AS orders_to_customers,
    orders.order_id REFERENCES orders.order_id AS self_ref
)
FACTS(
    orders.order_total AS order_total COMMENT 'Total order amount after discounts',
    orders.total_quantity AS quantity COMMENT 'Total items in the order',
    orders.total_discount AS discount_amount COMMENT 'Total discount applied',
    orders.number_of_items AS line_item_count COMMENT 'Number of distinct line items',
    customers.lifetime_orders AS customer_lifetime_orders COMMENT 'Total orders by this customer',
    products.total_units_sold AS product_units_sold COMMENT 'Total units sold for this product',
    products.total_revenue AS product_total_revenue COMMENT 'Total revenue for this product'
)
DIMENSIONS(
    customers.customer_name AS customer_name VARCHAR COMMENT 'Full name of the customer' SYNONYMS ('customer', 'buyer', 'client name'),
    customers.email AS customer_email VARCHAR COMMENT 'Customer email address',
    customers.city AS customer_city VARCHAR COMMENT 'Customer city',
    customers.state AS customer_state VARCHAR COMMENT 'Customer state',
    products.product_name AS product_name VARCHAR COMMENT 'Name of the product' SYNONYMS ('product', 'item name'),
    products.category AS product_category VARCHAR COMMENT 'Product category' SYNONYMS ('category', 'department'),
    products.subcategory AS product_subcategory VARCHAR COMMENT 'Product subcategory',
    orders.order_date AS order_date DATE COMMENT 'Date the order was placed' SYNONYMS ('purchase date', 'transaction date'),
    orders.order_status AS order_status VARCHAR COMMENT 'Current order status' SYNONYMS ('status', 'order state')
)
METRICS(
    total_revenue AS SUM(orders.order_total) COMMENT 'Sum of all order totals' SYNONYMS ('revenue', 'sales', 'total sales'),
    average_order_value AS AVG(orders.order_total) COMMENT 'Average order amount' SYNONYMS ('AOV', 'avg order'),
    total_orders AS COUNT(orders.order_id) COMMENT 'Total number of orders' SYNONYMS ('order count', 'number of orders'),
    total_items_sold AS SUM(orders.total_quantity) COMMENT 'Total items sold across all orders',
    total_discounts AS SUM(orders.total_discount) COMMENT 'Total discounts given'
)
COMMENT = 'Retail analytics semantic view for customer orders, products, and revenue analysis'
