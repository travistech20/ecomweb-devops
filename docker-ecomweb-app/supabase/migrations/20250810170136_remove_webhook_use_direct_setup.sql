-- Remove webhook dependency and use direct database function calls
-- This simplifies the user setup process by eliminating the HTTP call

-- Update the trigger to call init_user_defaults directly instead of using webhook/queue
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY definer
SET search_path = public
AS $$
DECLARE
    user_name TEXT;
    store_name TEXT;
    store_subdomain TEXT;
    store_description TEXT;
    setup_result JSONB;
    original_subdomain TEXT;
    counter INTEGER := 1;
    subdomain_exists BOOLEAN := TRUE;
BEGIN
    -- Prepare user data
    user_name := COALESCE(NEW.raw_user_meta_data->>'name', NEW.email, 'Người dùng');
    store_name := 'Cửa hàng của ' || user_name;
    
    -- Generate store subdomain with Vietnamese character normalization
    store_subdomain := lower(user_name);
    
    -- Normalize Vietnamese characters using nested replace() calls
    store_subdomain := replace(store_subdomain, 'à', 'a');
    store_subdomain := replace(store_subdomain, 'á', 'a');
    store_subdomain := replace(store_subdomain, 'ả', 'a');
    store_subdomain := replace(store_subdomain, 'ã', 'a');
    store_subdomain := replace(store_subdomain, 'ạ', 'a');
    store_subdomain := replace(store_subdomain, 'ă', 'a');
    store_subdomain := replace(store_subdomain, 'ằ', 'a');
    store_subdomain := replace(store_subdomain, 'ắ', 'a');
    store_subdomain := replace(store_subdomain, 'ẳ', 'a');
    store_subdomain := replace(store_subdomain, 'ẵ', 'a');
    store_subdomain := replace(store_subdomain, 'ặ', 'a');
    store_subdomain := replace(store_subdomain, 'â', 'a');
    store_subdomain := replace(store_subdomain, 'ầ', 'a');
    store_subdomain := replace(store_subdomain, 'ấ', 'a');
    store_subdomain := replace(store_subdomain, 'ẩ', 'a');
    store_subdomain := replace(store_subdomain, 'ẫ', 'a');
    store_subdomain := replace(store_subdomain, 'ậ', 'a');
    store_subdomain := replace(store_subdomain, 'è', 'e');
    store_subdomain := replace(store_subdomain, 'é', 'e');
    store_subdomain := replace(store_subdomain, 'ẻ', 'e');
    store_subdomain := replace(store_subdomain, 'ẽ', 'e');
    store_subdomain := replace(store_subdomain, 'ẹ', 'e');
    store_subdomain := replace(store_subdomain, 'ê', 'e');
    store_subdomain := replace(store_subdomain, 'ề', 'e');
    store_subdomain := replace(store_subdomain, 'ế', 'e');
    store_subdomain := replace(store_subdomain, 'ể', 'e');
    store_subdomain := replace(store_subdomain, 'ễ', 'e');
    store_subdomain := replace(store_subdomain, 'ệ', 'e');
    store_subdomain := replace(store_subdomain, 'ì', 'i');
    store_subdomain := replace(store_subdomain, 'í', 'i');
    store_subdomain := replace(store_subdomain, 'ỉ', 'i');
    store_subdomain := replace(store_subdomain, 'ĩ', 'i');
    store_subdomain := replace(store_subdomain, 'ị', 'i');
    store_subdomain := replace(store_subdomain, 'ò', 'o');
    store_subdomain := replace(store_subdomain, 'ó', 'o');
    store_subdomain := replace(store_subdomain, 'ỏ', 'o');
    store_subdomain := replace(store_subdomain, 'õ', 'o');
    store_subdomain := replace(store_subdomain, 'ọ', 'o');
    store_subdomain := replace(store_subdomain, 'ô', 'o');
    store_subdomain := replace(store_subdomain, 'ồ', 'o');
    store_subdomain := replace(store_subdomain, 'ố', 'o');
    store_subdomain := replace(store_subdomain, 'ổ', 'o');
    store_subdomain := replace(store_subdomain, 'ỗ', 'o');
    store_subdomain := replace(store_subdomain, 'ộ', 'o');
    store_subdomain := replace(store_subdomain, 'ơ', 'o');
    store_subdomain := replace(store_subdomain, 'ờ', 'o');
    store_subdomain := replace(store_subdomain, 'ớ', 'o');
    store_subdomain := replace(store_subdomain, 'ở', 'o');
    store_subdomain := replace(store_subdomain, 'ỡ', 'o');
    store_subdomain := replace(store_subdomain, 'ợ', 'o');
    store_subdomain := replace(store_subdomain, 'ù', 'u');
    store_subdomain := replace(store_subdomain, 'ú', 'u');
    store_subdomain := replace(store_subdomain, 'ủ', 'u');
    store_subdomain := replace(store_subdomain, 'ũ', 'u');
    store_subdomain := replace(store_subdomain, 'ụ', 'u');
    store_subdomain := replace(store_subdomain, 'ư', 'u');
    store_subdomain := replace(store_subdomain, 'ừ', 'u');
    store_subdomain := replace(store_subdomain, 'ứ', 'u');
    store_subdomain := replace(store_subdomain, 'ử', 'u');
    store_subdomain := replace(store_subdomain, 'ữ', 'u');
    store_subdomain := replace(store_subdomain, 'ự', 'u');
    store_subdomain := replace(store_subdomain, 'ỳ', 'y');
    store_subdomain := replace(store_subdomain, 'ý', 'y');
    store_subdomain := replace(store_subdomain, 'ỷ', 'y');
    store_subdomain := replace(store_subdomain, 'ỹ', 'y');
    store_subdomain := replace(store_subdomain, 'ỵ', 'y');
    store_subdomain := replace(store_subdomain, 'đ', 'd');
    
    -- Remove non-alphanumeric characters and clean up
    store_subdomain := regexp_replace(store_subdomain, '[^a-z0-9]', '-', 'g');
    store_subdomain := regexp_replace(store_subdomain, '-+', '-', 'g');
    store_subdomain := regexp_replace(store_subdomain, '^-|-$', '', 'g');
    store_subdomain := substring(store_subdomain from 1 for 20);
    
        -- Fallback if subdomain is empty
    IF store_subdomain = '' OR store_subdomain IS NULL THEN
        store_subdomain := 'store-' || substring(NEW.id::text from 1 for 8);
    END IF;

    -- Ensure subdomain uniqueness by checking for collisions
    original_subdomain := store_subdomain;
    counter := 1;
    subdomain_exists := TRUE;
    
    -- Check if subdomain already exists and find a unique one
    WHILE subdomain_exists LOOP
        SELECT EXISTS(
            SELECT 1 FROM public.stores 
            WHERE subdomain = store_subdomain
        ) INTO subdomain_exists;
        
        IF subdomain_exists THEN
            -- Append counter to make it unique
            store_subdomain := original_subdomain || '-' || counter::text;
            counter := counter + 1;
            
            -- Ensure it doesn't exceed length limit
            IF length(store_subdomain) > 20 THEN
                store_subdomain := substring(original_subdomain from 1 for (20 - length(counter::text) - 1)) || '-' || counter::text;
            END IF;
        END IF;
    END LOOP;

    store_description := 'Cửa hàng mặc định được tạo tự động';

    -- Call init_user_defaults directly (no webhook needed)
    BEGIN
        SELECT init_user_defaults(
            NEW.id,
            user_name,
            NEW.email,
            store_name,
            store_subdomain,
            store_description
        ) INTO setup_result;

        -- Log the result
        IF setup_result->>'error' IS NULL THEN
            RAISE LOG 'Successfully set up user: % (Profile: %, Store: %)', 
                NEW.email,
                setup_result->'profile'->>'id',
                setup_result->'store'->>'id';
        ELSE
            RAISE LOG 'Failed to setup user %: %', 
                NEW.email, 
                setup_result->'error'->>'message';
        END IF;

    EXCEPTION WHEN OTHERS THEN
        -- Log any errors but don't fail the user creation
        RAISE LOG 'Exception during user setup for %: %', NEW.email, SQLERRM;
    END;

    RETURN NEW;
END;
$$;

-- Add unique constraint on subdomain to ensure no duplicates
ALTER TABLE public.stores ADD CONSTRAINT stores_subdomain_unique UNIQUE (subdomain);

-- Update init_user_defaults function to also handle subdomain uniqueness
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
SECURITY DEFINER
AS $$
DECLARE
    new_profile record;
    new_store record;
    result_json JSONB;
    retry_count INTEGER := 0;
    max_retries INTEGER := 3;
    user_exists BOOLEAN := FALSE;
    original_subdomain TEXT;
    counter INTEGER := 1;
    subdomain_exists BOOLEAN := TRUE;
BEGIN
    -- First, check if the user exists in auth.users with retry logic
    WHILE retry_count < max_retries LOOP
        SELECT EXISTS(SELECT 1 FROM auth.users WHERE id = init_user_defaults.user_id) INTO user_exists;
        
        IF user_exists THEN
            EXIT; -- User found, proceed
        END IF;
        
        -- User not found, wait a bit and retry
        retry_count := retry_count + 1;
        IF retry_count < max_retries THEN
            PERFORM pg_sleep(0.1); -- Wait 100ms
        END IF;
    END LOOP;
    
    -- If user still doesn't exist after retries, return error
    IF NOT user_exists THEN
        result_json := jsonb_build_object(
            'profile', null,
            'store', null,
            'error', jsonb_build_object(
                'message', 'User not found in auth.users after retries',
                'detail', 'FK_CONSTRAINT_ERROR'
            )
        );
        RETURN result_json;
    END IF;

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
        -- Ensure subdomain uniqueness
        original_subdomain := COALESCE(init_user_defaults.store_subdomain, 'store-' || init_user_defaults.user_id::text);
        store_subdomain := original_subdomain;
        
        -- Check for subdomain collisions and find unique one
        WHILE subdomain_exists LOOP
            SELECT EXISTS(
                SELECT 1 FROM public.stores 
                WHERE subdomain = store_subdomain
            ) INTO subdomain_exists;
            
            IF subdomain_exists THEN
                -- Append counter to make it unique
                store_subdomain := original_subdomain || '-' || counter::text;
                counter := counter + 1;
                
                -- Ensure it doesn't exceed reasonable length
                IF length(store_subdomain) > 30 THEN
                    store_subdomain := substring(original_subdomain from 1 for (30 - length(counter::text) - 1)) || '-' || counter::text;
                END IF;
            END IF;
        END LOOP;
        
        -- Create default store (bypasses RLS because of SECURITY DEFINER)
        INSERT INTO public.stores (
            user_id,
            name,
            subdomain,
            description
        ) VALUES (
            init_user_defaults.user_id,
            COALESCE(init_user_defaults.store_name, 'Cửa hàng của tôi'),
            store_subdomain,
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

-- Clean up: Remove webhook configuration from app_config since we don't need it anymore
DELETE FROM public.app_config WHERE key IN ('webhook_url', 'webhook_secret');

-- Optional: Add a comment to document the simplified approach
COMMENT ON FUNCTION handle_new_user() IS 'Automatically creates user profile and default store on user registration. No webhook required - calls init_user_defaults directly.';

COMMENT ON FUNCTION init_user_defaults(UUID, TEXT, TEXT, TEXT, TEXT, TEXT) IS 'Creates user profile and default store. Used by handle_new_user trigger and can be called manually for setup.';
