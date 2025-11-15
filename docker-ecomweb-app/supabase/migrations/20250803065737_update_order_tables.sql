-- Drop function create_order_with_items if it exists
DROP FUNCTION IF EXISTS create_order_with_items;

-- Drop existing order number related functions and triggers
DROP TRIGGER IF EXISTS trigger_set_order_number ON orders;
DROP FUNCTION IF EXISTS set_order_number();
DROP FUNCTION IF EXISTS generate_order_number();

-- Step 1: Change order_number from VARCHAR to BIGINT
-- First, we need to handle existing data by creating a temporary column
ALTER TABLE orders ADD COLUMN order_number_new BIGINT;

-- Update existing records with sequential numbers per store
WITH numbered_orders AS (
  SELECT 
    id,
    ROW_NUMBER() OVER (PARTITION BY store_id ORDER BY created_at) as new_order_number
  FROM orders
)
UPDATE orders 
SET order_number_new = numbered_orders.new_order_number
FROM numbered_orders 
WHERE orders.id = numbered_orders.id;

-- Drop the old column and rename the new one
ALTER TABLE orders DROP COLUMN order_number;
ALTER TABLE orders RENAME COLUMN order_number_new TO order_number;

-- Add constraints
ALTER TABLE orders ALTER COLUMN order_number SET NOT NULL;
ALTER TABLE orders ADD CONSTRAINT orders_store_order_number_unique UNIQUE (store_id, order_number);

-- Step 2: Create sequence for order numbers per store
CREATE SEQUENCE IF NOT EXISTS order_number_sequence;

-- Step 3: Create function to generate unique order number per store
CREATE OR REPLACE FUNCTION generate_order_number_per_store(store_id_param INTEGER) 
RETURNS BIGINT AS $$
DECLARE
    next_number BIGINT;
BEGIN
    -- Get the next order number for this specific store
    SELECT COALESCE(MAX(order_number), 0) + 1 
    INTO next_number
    FROM orders 
    WHERE store_id = store_id_param;
    
    RETURN next_number;
END;
$$ LANGUAGE plpgsql;

-- Step 4: Create trigger function to set order number
CREATE OR REPLACE FUNCTION set_order_number_per_store() 
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.order_number IS NULL THEN
        NEW.order_number := generate_order_number_per_store(NEW.store_id);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Step 5: Create trigger
CREATE TRIGGER trigger_set_order_number_per_store 
    BEFORE INSERT ON orders 
    FOR EACH ROW 
    EXECUTE FUNCTION set_order_number_per_store();

-- Step 6: Update lookup functions to work with numeric order_number
CREATE OR REPLACE FUNCTION lookup_guest_order(p_order_number BIGINT, p_customer_email TEXT) 
RETURNS TABLE(
    id BIGINT, 
    order_number BIGINT, 
    store_id INTEGER, 
    customer_name TEXT, 
    customer_email TEXT, 
    customer_phone TEXT, 
    status TEXT, 
    payment_status TEXT, 
    payment_method TEXT, 
    subtotal NUMERIC, 
    shipping_fee NUMERIC, 
    tax NUMERIC, 
    discount NUMERIC, 
    total NUMERIC, 
    shipping_street TEXT, 
    shipping_city TEXT, 
    shipping_district TEXT, 
    shipping_ward TEXT, 
    shipping_postal_code TEXT, 
    tracking_number TEXT, 
    notes TEXT, 
    created_at TIMESTAMP WITH TIME ZONE, 
    updated_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        o.id,
        o.order_number,
        o.store_id,
        o.customer_name,
        o.customer_email,
        o.customer_phone,
        o.status,
        o.payment_status,
        o.payment_method,
        o.subtotal,
        o.shipping_fee,
        o.tax,
        o.discount,
        o.total,
        o.shipping_street,
        o.shipping_city,
        o.shipping_district,
        o.shipping_ward,
        o.shipping_postal_code,
        o.tracking_number,
        o.notes,
        o.created_at,
        o.updated_at
    FROM orders o
    WHERE o.order_number = p_order_number 
    AND LOWER(o.customer_email) = LOWER(p_customer_email);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION lookup_guest_order_items(p_order_number BIGINT, p_customer_email TEXT) 
RETURNS TABLE(
    id BIGINT, 
    order_id BIGINT, 
    product_id BIGINT, 
    product_name TEXT, 
    product_image TEXT, 
    variant_id BIGINT,
    variant_name TEXT,
    quantity INTEGER, 
    price NUMERIC, 
    total NUMERIC, 
    created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        oi.id,
        oi.order_id,
        oi.product_id,
        oi.product_name,
        oi.product_image,
        oi.variant_id,
        oi.variant_name,
        oi.quantity,
        oi.price,
        oi.total,
        oi.created_at
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.id
    WHERE o.order_number = p_order_number 
    AND LOWER(o.customer_email) = LOWER(p_customer_email);
END;
$$ LANGUAGE plpgsql;

-- Step 7: Grant permissions
GRANT ALL ON FUNCTION generate_order_number_per_store(INTEGER) TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION set_order_number_per_store() TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION lookup_guest_order(BIGINT, TEXT) TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION lookup_guest_order_items(BIGINT, TEXT) TO anon, authenticated, service_role;
GRANT USAGE ON SEQUENCE order_number_sequence TO anon, authenticated, service_role;

