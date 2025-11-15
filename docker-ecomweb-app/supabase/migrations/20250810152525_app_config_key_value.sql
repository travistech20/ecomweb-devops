-- Create app_config table with key-value structure
-- This replaces the environment-based webhook_config table

-- Drop the old webhook_config table and related functions

-- Create new app_config table
CREATE TABLE IF NOT EXISTS public.app_config (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key TEXT NOT NULL UNIQUE,
    value TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

-- Only allow service role to read/write app config
CREATE POLICY "Service role can manage app config" ON public.app_config
    FOR ALL USING (auth.role() = 'service_role');

-- Insert default webhook configuration
INSERT INTO public.app_config (key, value)
VALUES 
    ('webhook_url', 'http://host.docker.internal:3000/api/auth/webhook'),
    ('webhook_secret', 'dev-webhook-secret-change-me')
ON CONFLICT (key) DO NOTHING;

-- Function to get configuration value by key
CREATE OR REPLACE FUNCTION get_config(config_key TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY definer
AS $$
DECLARE
    config_value TEXT;
BEGIN
    SELECT value INTO config_value
    FROM public.app_config
    WHERE key = config_key;
    
    RETURN config_value;
END;
$$;

-- Function to set configuration value
CREATE OR REPLACE FUNCTION set_config(config_key TEXT, config_value TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY definer
AS $$
BEGIN
    INSERT INTO public.app_config (key, value)
    VALUES (config_key, config_value)
    ON CONFLICT (key) DO UPDATE SET
        value = EXCLUDED.value,
        updated_at = NOW();
        
    RAISE NOTICE 'Configuration updated: % = %', config_key, config_value;
END;
$$;

-- Function to get all webhook configuration
CREATE OR REPLACE FUNCTION get_webhook_config()
RETURNS TABLE (
    webhook_url TEXT,
    webhook_secret TEXT
)
LANGUAGE plpgsql
SECURITY definer
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        get_config('webhook_url') as webhook_url,
        get_config('webhook_secret') as webhook_secret;
END;
$$;

-- Update the handle_new_user function to use the new app_config table
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
            
        -- If webhook fails, log the error but don't fail the user creation
        IF http_response.status < 200 OR http_response.status >= 300 THEN
            RAISE LOG 'Webhook failed with status %: %', 
                http_response.status, 
                http_response.content;
        END IF;
        
    EXCEPTION WHEN OTHERS THEN
        -- Log the error but don't fail the user creation
        RAISE LOG 'Failed to call user setup webhook: %', SQLERRM;
    END;
    
    RETURN NEW;
END;
$$;

-- Update the trigger (it should still exist from previous migration)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION handle_new_user();

-- Grant necessary permissions
GRANT SELECT ON public.app_config TO authenticated;

-- Helper function to view all configuration
CREATE OR REPLACE FUNCTION get_all_config()
RETURNS TABLE (
    key TEXT,
    value TEXT,
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY definer
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ac.key,
        ac.value,
        ac.created_at,
        ac.updated_at
    FROM public.app_config ac
    ORDER BY ac.key;
END;
$$;

-- Add comments
COMMENT ON TABLE public.app_config IS 'Key-value configuration table for application settings';
COMMENT ON FUNCTION get_config(TEXT) IS 'Get configuration value by key';
COMMENT ON FUNCTION set_config(TEXT, TEXT) IS 'Set configuration key-value pair';
COMMENT ON FUNCTION get_webhook_config() IS 'Get webhook-specific configuration';
COMMENT ON FUNCTION get_all_config() IS 'Get all configuration key-value pairs';
