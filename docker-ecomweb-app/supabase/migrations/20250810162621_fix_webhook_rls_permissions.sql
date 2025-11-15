-- Fix RLS permissions for webhook user setup
-- The issue: Database triggers don't have auth context, so RLS policies block operations

-- Solution 1: Create a privileged function that bypasses RLS for system operations
CREATE OR REPLACE FUNCTION init_user_defaults(
    user_id UUID,
    user_name TEXT DEFAULT '',
    user_email TEXT DEFAULT '',
    store_name TEXT DEFAULT '',
    store_subdomain TEXT DEFAULT '',
    store_description TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER -- This runs with the privileges of the function owner
AS $$
DECLARE
    new_profile record;
    new_store record;
    result_json JSONB;
BEGIN
    -- Insert profile (bypasses RLS because of SECURITY DEFINER)
    INSERT INTO public.profiles (id, name, email)
    VALUES (init_user_defaults.user_id, init_user_defaults.user_name, init_user_defaults.user_email)
    ON CONFLICT (id) DO UPDATE SET
        name = EXCLUDED.name,
        email = EXCLUDED.email,
        updated_at = NOW()
    RETURNING * INTO new_profile;
    
    -- Check if user already has a store
    IF NOT EXISTS (SELECT 1 FROM public.stores s WHERE s.user_id = init_user_defaults.user_id) THEN
        -- Create default store (bypasses RLS because of SECURITY DEFINER)
        INSERT INTO public.stores (
            user_id,
            name,
            subdomain,
            description
        ) VALUES (
            init_user_defaults.user_id,
            COALESCE(init_user_defaults.store_name, 'Cửa hàng của tôi'),
            COALESCE(init_user_defaults.store_subdomain, 'store-' || init_user_defaults.user_id::text),
            COALESCE(init_user_defaults.store_description, 'Cửa hàng mặc định được tạo tự động')
        )
        RETURNING * INTO new_store;
    ELSE
        -- Get existing store
        SELECT * INTO new_store FROM public.stores s WHERE s.user_id = init_user_defaults.user_id LIMIT 1;
    END IF;
    
    -- Return result as JSON
    result_json := jsonb_build_object(
        'profile', row_to_json(new_profile),
        'store', row_to_json(new_store),
        'error', null
    );
    
    RETURN result_json;
    
EXCEPTION WHEN OTHERS THEN
    -- Return error information
    result_json := jsonb_build_object(
        'profile', null,
        'store', null,
        'error', jsonb_build_object(
            'message', SQLERRM,
            'detail', SQLSTATE
        )
    );
    
    RETURN result_json;
END;
$$;

-- Solution 2: Add a system policy for webhook operations
-- This allows the service role to insert profiles for any user
CREATE POLICY "System can insert profiles" ON "public"."profiles" 
FOR INSERT 
TO service_role 
WITH CHECK (true);

CREATE POLICY "System can insert stores" ON "public"."stores" 
FOR INSERT 
TO service_role 
WITH CHECK (true);

-- Update the webhook API endpoint to use the new system function
-- (This will be handled in the Next.js code, not in the database)

-- Update the handle_new_user trigger function to call Next.js webhook only
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY definer
SET search_path = public
AS $$
DECLARE
    webhook_url text;
    webhook_secret text;
    payload json;
    http_response record;
BEGIN
    -- Get webhook configuration from the app_config table
    webhook_url := get_config('webhook_url');
    webhook_secret := get_config('webhook_secret');
    
    -- If no webhook URL is configured, skip the webhook call
    IF webhook_url IS NULL OR webhook_url = '' THEN
        RAISE LOG 'No webhook URL configured, skipping user setup webhook';
        RETURN NEW;
    END IF;
    
    -- Construct the payload for the webhook
    payload := json_build_object(
        'type', 'INSERT',
        'table', 'users',
        'record', json_build_object(
            'id', NEW.id,
            'email', NEW.email,
            'created_at', NEW.created_at,
            'updated_at', NEW.updated_at,
            'raw_user_meta_data', NEW.raw_user_meta_data,
            'raw_app_meta_data', NEW.raw_app_meta_data,
            'is_super_admin', NEW.is_super_admin,
            'role', NEW.role
        ),
        'schema', 'auth'
    );
    
    -- Make HTTP request to webhook endpoint
    BEGIN
        -- Use http extension to make the webhook call with custom headers
        SELECT status, content, content_type
        INTO http_response
        FROM extensions.http((
            'POST',
            webhook_url,
            ARRAY[
                extensions.http_header('Content-Type', 'application/json'),
                extensions.http_header('Authorization', 'Bearer ' || COALESCE(webhook_secret, ''))
            ],
            'application/json',
            payload::text
        ));
        
        -- Log the response
        RAISE LOG 'Webhook response: status=%, content=%', 
            http_response.status, 
            http_response.content;
            
        -- Log webhook failures but don't attempt fallback
        IF http_response.status < 200 OR http_response.status >= 300 THEN
            RAISE LOG 'Webhook failed with status %: %', 
                http_response.status, 
                http_response.content;
        END IF;
        
    EXCEPTION WHEN OTHERS THEN
        -- Log the error but don't attempt fallback
        RAISE LOG 'Failed to call user setup webhook: %', SQLERRM;
    END;
    
    RETURN NEW;
END;
$$;

-- Grant necessary permissions to the new function
GRANT EXECUTE ON FUNCTION init_user_defaults(UUID, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION init_user_defaults(UUID, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon;

-- Add comments
COMMENT ON FUNCTION init_user_defaults(UUID, TEXT, TEXT, TEXT, TEXT, TEXT) IS 'System function to initialize user defaults (profile and store), bypassing RLS for webhook operations';
COMMENT ON POLICY "System can insert profiles" ON "public"."profiles" IS 'Allows service role to insert profiles for webhook operations';
COMMENT ON POLICY "System can insert stores" ON "public"."stores" IS 'Allows service role to insert stores for webhook operations';
