-- Fix foreign key constraint issue for profiles table
-- The issue can occur when the database trigger calls init_user_defaults during user creation
-- and the foreign key constraint fails when trying to insert the profile

-- Solution 1: Make the foreign key constraint deferrable
-- This allows the constraint check to be deferred until the end of the transaction
ALTER TABLE public.profiles 
DROP CONSTRAINT IF EXISTS profiles_id_fkey;

ALTER TABLE public.profiles 
ADD CONSTRAINT profiles_id_fkey 
FOREIGN KEY (id) REFERENCES auth.users(id) 
ON DELETE CASCADE 
DEFERRABLE INITIALLY DEFERRED;

-- Solution 2: Add a retry mechanism to the init_user_defaults function
-- This will help handle any remaining timing issues
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

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION init_user_defaults(UUID, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION init_user_defaults(UUID, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon;
