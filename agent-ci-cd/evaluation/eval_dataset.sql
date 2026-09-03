-- =============================================================================
-- Create evaluation dataset for Cortex Agent testing
-- Run against the target database (dev or prod)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS EVALUATION;

CREATE OR REPLACE TABLE EVALUATION.AGENT_EVAL_DATASET (
    question VARCHAR,
    expected_answer VARCHAR,
    expected_tool VARCHAR DEFAULT 'ANALYST_TOOL',
    category VARCHAR
);

INSERT INTO EVALUATION.AGENT_EVAL_DATASET (question, expected_answer, category) VALUES
-- Revenue questions
('What is the total revenue?', 'The total revenue is the sum of all order totals.', 'revenue'),
('What is the average order value?', 'The average order value (AOV) is calculated by dividing total revenue by total orders.', 'revenue'),
('Which product category generates the most revenue?', 'The query should group by product_category and sum order totals.', 'revenue'),

-- Customer questions
('How many customers do we have?', 'The total number of unique customers in the system.', 'customers'),
('Who are our top customers by number of orders?', 'Customers ranked by lifetime_orders descending.', 'customers'),
('Which state has the most customers?', 'Group customers by state and count.', 'customers'),

-- Order questions
('How many orders are in processing status?', 'Count of orders where order_status = processing.', 'orders'),
('What is the order completion rate?', 'Percentage of orders with status completed vs total orders.', 'orders'),
('What is the average number of items per order?', 'Average of total_quantity across all orders.', 'orders'),

-- Product questions
('What are our top selling products?', 'Products ranked by total_units_sold descending.', 'products'),
('How many product categories do we have?', 'Count of distinct product categories.', 'products'),
('Which products have never been ordered?', 'Products where total_units_sold = 0 or number_of_orders = 0.', 'products');
