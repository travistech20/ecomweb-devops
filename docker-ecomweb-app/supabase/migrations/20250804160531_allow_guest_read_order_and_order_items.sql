-- Migration: Allow Guest and User Read Access to Orders and Order Items
-- This migration adds RLS policies to allow both guests and authenticated users to read orders and order items

-- Drop existing policies that restrict read access to authenticated users only
DROP POLICY IF EXISTS "authenticated_users_view_own_orders" ON orders;
DROP POLICY IF EXISTS "authenticated_users_view_own_order_items" ON order_items;

-- Create new policies that allow both guests and users to read orders
-- For authenticated users: they can read their own orders
CREATE POLICY "users_can_read_own_orders" ON orders 
FOR SELECT 
USING (
    auth.uid() IS NOT NULL AND user_id = auth.uid()
);

-- For guests and users: they can read orders by order_number and customer_email or phone
CREATE POLICY "guests_and_users_can_read_orders_by_number_and_email_or_phone" ON orders 
FOR SELECT 
USING (
    order_number IS NOT NULL AND (customer_email IS NOT NULL OR customer_phone IS NOT NULL)
);

-- Create new policies that allow both guests and users to read order items
-- For authenticated users: they can read order items from their own orders
CREATE POLICY "users_can_read_own_order_items" ON order_items 
FOR SELECT 
USING (
    auth.uid() IS NOT NULL AND 
    EXISTS (
        SELECT 1 FROM orders 
        WHERE orders.id = order_items.order_id 
        AND orders.user_id = auth.uid()
    )
);

-- For guests and users: they can read order items by order_number and customer_email or phone
CREATE POLICY "guests_and_users_can_read_order_items_by_number_and_email_or_phone" ON order_items 
FOR SELECT 
USING (
    EXISTS (
        SELECT 1 FROM orders 
        WHERE orders.id = order_items.order_id 
        AND orders.order_number IS NOT NULL 
        AND (orders.customer_email IS NOT NULL OR orders.customer_phone IS NOT NULL)
    )
);

-- Grant necessary permissions to anon and authenticated roles
GRANT SELECT ON orders TO anon, authenticated;
GRANT SELECT ON order_items TO anon, authenticated;
