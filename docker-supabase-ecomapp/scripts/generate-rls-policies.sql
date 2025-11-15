-- ============================================
-- RLS Policy Templates - Secure by Default
-- ============================================
-- SECURITY PRINCIPLE: Deny All by Default
-- By enabling RLS without creating policies, ALL access is denied by default.
-- This script provides templates for granting specific, minimal permissions.
--
-- IMPORTANT: After enabling RLS, tables are LOCKED until you create policies.
-- Only grant the minimum permissions necessary for your application.

-- ═══════════════════════════════════════════════════════
-- Pattern 1: Service Role Only (Maximum Security)
-- ═══════════════════════════════════════════════════════
-- Use for: Sensitive tables that should only be accessed by backend services
-- By default, anon and authenticated roles CANNOT access these tables
-- Only service_role (your backend) can access

-- Example: Audit logs, system tables
/*
-- Enable RLS (this blocks everyone except service_role)
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- Force RLS even for table owners
ALTER TABLE audit_logs FORCE ROW LEVEL SECURITY;

-- NO POLICIES NEEDED - Service role bypasses RLS by default
-- Result: Only your backend API can access this table
*/

-- ═══════════════════════════════════════════════════════
-- Pattern 2: Backend-Mediated Access Only
-- ═══════════════════════════════════════════════════════
-- Use for: Tables that users should NEVER directly access
-- All operations must go through your backend API

-- Example: Orders, payments, sensitive user data
/*
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders FORCE ROW LEVEL SECURITY;

-- NO POLICIES for anon or authenticated
-- All access must be through backend API with service_role
*/

-- Example: Payment information
/*
ALTER TABLE payment_methods ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_methods FORCE ROW LEVEL SECURITY;

-- NO POLICIES - Backend only
*/

-- ═══════════════════════════════════════════════════════
-- Pattern 3: Read-Only Public Data (Minimal Access)
-- ═══════════════════════════════════════════════════════
-- Use for: Public catalog data that anyone can read
-- But ONLY backend can modify

-- Example: Products (public can read, backend controls writes)
/*
-- Enable RLS
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE products FORCE ROW LEVEL SECURITY;

-- Allow anon/authenticated to ONLY read active products
CREATE POLICY "public_read_active_products_only"
ON products
FOR SELECT
TO anon, authenticated
USING (
  deleted_at IS NULL
  AND is_published = true
);

-- NO INSERT, UPDATE, DELETE policies
-- Backend service_role handles all modifications
*/

-- ═══════════════════════════════════════════════════════
-- Pattern 4: Strict User Isolation (Users See Only Their Data)
-- ═══════════════════════════════════════════════════════
-- Use for: Personal user data with strict isolation
-- Users can ONLY see and manage their own data

-- Example: User profiles
/*
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_profiles FORCE ROW LEVEL SECURITY;

-- Read: Users can ONLY read their own profile
CREATE POLICY "users_read_own_profile_only"
ON user_profiles
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Update: Users can ONLY update their own profile
CREATE POLICY "users_update_own_profile_only"
ON user_profiles
FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- NO INSERT policy - Backend creates profiles
-- NO DELETE policy - Backend handles deletion
-- NO access for anon role
*/

-- Example: Shopping carts
/*
ALTER TABLE carts ENABLE ROW LEVEL SECURITY;
ALTER TABLE carts FORCE ROW LEVEL SECURITY;

-- Users ONLY see their own cart
CREATE POLICY "users_own_cart_only"
ON carts
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Users can ONLY update their own cart
CREATE POLICY "users_update_own_cart_only"
ON carts
FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Backend handles cart creation/deletion via service_role
-- NO policies for INSERT/DELETE from users
*/

-- ═══════════════════════════════════════════════════════
-- Pattern 5: Strict Multi-Tenancy (Store Isolation)
-- ═══════════════════════════════════════════════════════
-- Use for: Multi-tenant SaaS where data MUST be isolated by store
-- Users can ONLY access data from stores they belong to

-- Example: Store products
/*
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE products FORCE ROW LEVEL SECURITY;

-- Helper: Check if user belongs to store
CREATE OR REPLACE FUNCTION user_belongs_to_store(check_store_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM store_members
    WHERE user_id = auth.uid()
    AND store_id = check_store_id
    AND deleted_at IS NULL
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Read: ONLY store members can read products from their stores
CREATE POLICY "store_members_read_own_store_products_only"
ON products
FOR SELECT
TO authenticated
USING (user_belongs_to_store(store_id));

-- Update: ONLY store admins/owners can update
CREATE POLICY "store_admins_update_products_only"
ON products
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM store_members
    WHERE user_id = auth.uid()
    AND store_id = products.store_id
    AND role IN ('owner', 'admin')
    AND deleted_at IS NULL
  )
);

-- NO INSERT/DELETE for regular users
-- Backend handles via service_role
-- NO access for anon
*/

-- ═══════════════════════════════════════════════════════
-- Pattern 6: Role-Based Restrictions (Strict RBAC)
-- ═══════════════════════════════════════════════════════
-- Use for: Data with different access levels per role
-- Each role gets MINIMUM necessary permissions

-- Example: Store settings
/*
ALTER TABLE store_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE store_settings FORCE ROW LEVEL SECURITY;

-- Read: ONLY store members
CREATE POLICY "members_read_own_store_settings_only"
ON store_settings
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM store_members
    WHERE user_id = auth.uid()
    AND store_id = store_settings.store_id
    AND deleted_at IS NULL
  )
);

-- Update: ONLY owners can modify settings
CREATE POLICY "owners_update_settings_only"
ON store_settings
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM store_members
    WHERE user_id = auth.uid()
    AND store_id = store_settings.store_id
    AND role = 'owner'
    AND deleted_at IS NULL
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM store_members
    WHERE user_id = auth.uid()
    AND store_id = store_settings.store_id
    AND role = 'owner'
    AND deleted_at IS NULL
  )
);

-- NO INSERT/DELETE from users
-- NO access for anon or non-members
*/

-- ═══════════════════════════════════════════════════════
-- Pattern 7: Conditional Access (Business Logic Protection)
-- ═══════════════════════════════════════════════════════
-- Use for: Data with specific business rules

-- Example: Reviews (ONLY for purchased products)
/*
ALTER TABLE product_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_reviews FORCE ROW LEVEL SECURITY;

-- Read: Public can read approved reviews only
CREATE POLICY "public_read_approved_reviews_only"
ON product_reviews
FOR SELECT
TO anon, authenticated
USING (
  is_approved = true
  AND deleted_at IS NULL
);

-- Insert: ONLY users who purchased the product
CREATE POLICY "purchasers_insert_review_only"
ON product_reviews
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() = user_id
  AND EXISTS (
    SELECT 1
    FROM order_items oi
    JOIN orders o ON o.id = oi.order_id
    WHERE o.user_id = auth.uid()
    AND oi.product_id = product_reviews.product_id
    AND o.status = 'completed'
  )
);

-- Update: Users ONLY update their own unprocessed reviews
CREATE POLICY "users_update_own_pending_reviews_only"
ON product_reviews
FOR UPDATE
TO authenticated
USING (
  auth.uid() = user_id
  AND is_approved IS NULL
)
WITH CHECK (
  auth.uid() = user_id
);

-- NO DELETE for users
-- Backend handles approval/rejection
*/

-- ═══════════════════════════════════════════════════════
-- Pattern 8: Time-Restricted Access
-- ═══════════════════════════════════════════════════════
-- Use for: Scheduled content that's only visible during certain times

-- Example: Promotions
/*
ALTER TABLE promotions ENABLE ROW LEVEL SECURITY;
ALTER TABLE promotions FORCE ROW LEVEL SECURITY;

-- Public: ONLY active, current promotions
CREATE POLICY "public_read_active_promotions_only"
ON promotions
FOR SELECT
TO anon, authenticated
USING (
  is_active = true
  AND deleted_at IS NULL
  AND NOW() >= start_date
  AND (end_date IS NULL OR NOW() <= end_date)
);

-- Store members: See all promotions from their stores
CREATE POLICY "store_members_read_all_store_promotions"
ON promotions
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM store_members
    WHERE user_id = auth.uid()
    AND store_id = promotions.store_id
    AND deleted_at IS NULL
  )
);

-- NO INSERT/UPDATE/DELETE for users
*/

-- ═══════════════════════════════════════════════════════
-- Complete Application Example: E-commerce Platform
-- ═══════════════════════════════════════════════════════
-- A complete setup for a secure e-commerce application

/*
-- 1. Stores: Public read, backend manages
ALTER TABLE stores ENABLE ROW LEVEL SECURITY;
ALTER TABLE stores FORCE ROW LEVEL SECURITY;

CREATE POLICY "public_read_active_stores_only"
ON stores FOR SELECT TO anon, authenticated
USING (deleted_at IS NULL AND is_active = true);

-- 2. Store Members: ONLY see their own memberships
ALTER TABLE store_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE store_members FORCE ROW LEVEL SECURITY;

CREATE POLICY "users_read_own_memberships_only"
ON store_members FOR SELECT TO authenticated
USING (auth.uid() = user_id);

-- 3. Products: Public read active, members manage
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE products FORCE ROW LEVEL SECURITY;

CREATE POLICY "public_read_published_products_only"
ON products FOR SELECT TO anon, authenticated
USING (deleted_at IS NULL AND is_published = true);

CREATE POLICY "store_admins_update_products_only"
ON products FOR UPDATE TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM store_members
    WHERE user_id = auth.uid()
    AND store_id = products.store_id
    AND role IN ('owner', 'admin')
  )
);

-- 4. Orders: Backend only
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders FORCE ROW LEVEL SECURITY;
-- NO policies - service_role only

-- 5. Customers: Users see only their own data
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers FORCE ROW LEVEL SECURITY;

CREATE POLICY "users_read_own_customer_only"
ON customers FOR SELECT TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "users_update_own_customer_only"
ON customers FOR UPDATE TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- 6. Customer Addresses: Strict user isolation
ALTER TABLE customer_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_addresses FORCE ROW LEVEL SECURITY;

CREATE POLICY "users_manage_own_addresses_only"
ON customer_addresses FOR ALL TO authenticated
USING (
  customer_id IN (
    SELECT id FROM customers WHERE user_id = auth.uid()
  )
)
WITH CHECK (
  customer_id IN (
    SELECT id FROM customers WHERE user_id = auth.uid()
  )
);

-- 7. Payment Methods: Backend only
ALTER TABLE payment_methods ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_methods FORCE ROW LEVEL SECURITY;
-- NO policies - sensitive data, service_role only
*/

-- ═══════════════════════════════════════════════════════
-- Utility: Verify RLS Security
-- ═══════════════════════════════════════════════════════

-- Check tables with RLS but NO policies (completely locked)
/*
SELECT
  t.tablename,
  'LOCKED - No access allowed' as status
FROM pg_tables t
JOIN pg_class c ON c.relname = t.tablename
WHERE t.schemaname = 'public'
AND c.relrowsecurity = true
AND NOT EXISTS (
  SELECT 1 FROM pg_policies p
  WHERE p.schemaname = 'public'
  AND p.tablename = t.tablename
)
ORDER BY t.tablename;
*/

-- Check tables WITHOUT RLS (potential security risk)
/*
SELECT
  t.tablename,
  'WARNING - RLS not enabled' as security_status
FROM pg_tables t
JOIN pg_class c ON c.relname = t.tablename
WHERE t.schemaname = 'public'
AND c.relrowsecurity = false
ORDER BY t.tablename;
*/

-- List all policies by table
/*
SELECT
  tablename,
  policyname,
  CASE cmd
    WHEN 'SELECT' THEN 'READ'
    WHEN 'INSERT' THEN 'INSERT'
    WHEN 'UPDATE' THEN 'UPDATE'
    WHEN 'DELETE' THEN 'DELETE'
    ELSE cmd
  END as operation,
  CASE
    WHEN 'anon' = ANY(string_to_array(roles, ',')) THEN 'Allows Anonymous'
    WHEN 'authenticated' = ANY(string_to_array(roles, ',')) THEN 'Allows Authenticated'
    ELSE 'Restricted'
  END as access_level
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, cmd, policyname;
*/

-- ═══════════════════════════════════════════════════════
-- Security Checklist
-- ═══════════════════════════════════════════════════════
/*
✓ All tables have RLS enabled
✓ All tables have FORCE RLS enabled
✓ Sensitive tables have NO policies (backend only)
✓ Public tables allow ONLY read access
✓ User data tables enforce strict user_id checks
✓ Multi-tenant tables enforce store_id isolation
✓ No UPDATE/DELETE policies for end users on critical tables
✓ All policies use WITH CHECK clause for INSERT/UPDATE
✓ Service role is used for all backend operations
✓ Policies tested with different user contexts
*/
