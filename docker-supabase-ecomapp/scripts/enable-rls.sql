-- ============================================
-- Enable RLS for All Tables in Public Schema
-- ============================================
-- This SQL script enables Row Level Security (RLS) for all tables
-- in the public schema and provides utility queries for managing RLS
--
-- USAGE:
--   psql -U postgres -d your_database -f enable-rls.sql
--   or via Docker:
--   docker exec supabase-db psql -U postgres -d postgres -f /path/to/enable-rls.sql

-- Display current RLS status before making changes
\echo '═══════════════════════════════════════════════════════'
\echo 'Current RLS Status'
\echo '═══════════════════════════════════════════════════════'

SELECT
    schemaname,
    tablename,
    CASE
        WHEN rowsecurity THEN '✓ ENABLED'
        ELSE '✗ DISABLED'
    END as rls_status,
    CASE
        WHEN rowsecurity THEN
            (SELECT COUNT(*)
             FROM pg_policies
             WHERE schemaname = 'public'
             AND tablename = t.tablename)
        ELSE 0
    END as policy_count
FROM pg_tables t
JOIN pg_class c ON c.relname = t.tablename
WHERE t.schemaname = 'public'
ORDER BY tablename;

\echo ''
\echo '═══════════════════════════════════════════════════════'
\echo 'Enabling RLS for all tables...'
\echo '═══════════════════════════════════════════════════════'

-- Generate and execute ALTER TABLE statements for all tables
DO $$
DECLARE
    table_record RECORD;
    enabled_count INTEGER := 0;
    already_enabled_count INTEGER := 0;
    total_count INTEGER := 0;
BEGIN
    -- Loop through all tables in public schema
    FOR table_record IN
        SELECT
            t.tablename,
            c.relrowsecurity as rls_enabled
        FROM pg_tables t
        JOIN pg_class c ON c.relname = t.tablename AND c.relnamespace = 'public'::regnamespace
        WHERE t.schemaname = 'public'
        ORDER BY t.tablename
    LOOP
        total_count := total_count + 1;

        IF table_record.rls_enabled THEN
            RAISE NOTICE '  → % - Already enabled', table_record.tablename;
            already_enabled_count := already_enabled_count + 1;
        ELSE
            -- Enable RLS on the table
            EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_record.tablename);
            RAISE NOTICE '  → % - ✓ Enabled', table_record.tablename;
            enabled_count := enabled_count + 1;
        END IF;
    END LOOP;

    -- Summary
    RAISE NOTICE '';
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    RAISE NOTICE 'Summary';
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    RAISE NOTICE 'Total tables: %', total_count;
    RAISE NOTICE 'Newly enabled: %', enabled_count;
    RAISE NOTICE 'Already enabled: %', already_enabled_count;
END $$;

\echo ''
\echo '═══════════════════════════════════════════════════════'
\echo 'Final RLS Status'
\echo '═══════════════════════════════════════════════════════'

-- Display final status with policy counts
SELECT
    schemaname,
    tablename,
    CASE
        WHEN rowsecurity THEN '✓ ENABLED'
        ELSE '✗ DISABLED'
    END as rls_status,
    (SELECT COUNT(*)
     FROM pg_policies
     WHERE schemaname = 'public'
     AND tablename = t.tablename) as policy_count,
    CASE
        WHEN rowsecurity AND
             (SELECT COUNT(*) FROM pg_policies
              WHERE schemaname = 'public' AND tablename = t.tablename) = 0
        THEN '⚠️  NO POLICIES!'
        ELSE '✓'
    END as policies_status
FROM pg_tables t
JOIN pg_class c ON c.relname = t.tablename
WHERE t.schemaname = 'public'
ORDER BY tablename;

-- Summary statistics
\echo ''
\echo '═══════════════════════════════════════════════════════'
\echo 'Statistics'
\echo '═══════════════════════════════════════════════════════'

SELECT
    COUNT(*) as total_tables,
    SUM(CASE WHEN rowsecurity THEN 1 ELSE 0 END) as rls_enabled,
    SUM(CASE WHEN NOT rowsecurity THEN 1 ELSE 0 END) as rls_disabled,
    (SELECT COUNT(DISTINCT tablename) FROM pg_policies WHERE schemaname = 'public') as tables_with_policies
FROM pg_tables t
JOIN pg_class c ON c.relname = t.tablename
WHERE t.schemaname = 'public';

\echo ''
\echo '═══════════════════════════════════════════════════════'
\echo 'Warning'
\echo '═══════════════════════════════════════════════════════'
\echo '⚠️  RLS is now enabled, but tables without policies are LOCKED!'
\echo 'No one can access tables without appropriate RLS policies.'
\echo ''
\echo 'Next steps:'
\echo '  1. Create RLS policies for each table'
\echo '  2. Consider using FORCE ROW LEVEL SECURITY for table owners'
\echo '  3. Test policies with different user roles'
\echo ''
\echo 'Example policy creation:'
\echo '  -- Allow public read access'
\echo '  CREATE POLICY "public_read" ON products'
\echo '    FOR SELECT USING (true);'
\echo ''
\echo '  -- Allow authenticated users to insert their own records'
\echo '  CREATE POLICY "user_insert" ON products'
\echo '    FOR INSERT TO authenticated'
\echo '    WITH CHECK (auth.uid() = user_id);'
\echo ''
\echo '  -- Force RLS even for table owners'
\echo '  ALTER TABLE products FORCE ROW LEVEL SECURITY;'
\echo '═══════════════════════════════════════════════════════'
