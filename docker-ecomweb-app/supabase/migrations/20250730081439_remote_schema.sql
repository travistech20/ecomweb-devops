

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."create_order_simple"("order_data" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    new_order_id UUID;
    order_number_generated TEXT;
    result_order JSONB;
BEGIN
    -- Insert the order and get the generated ID and order number
    INSERT INTO orders (
        store_id,
        user_id,
        customer_name,
        customer_email,
        customer_phone,
        customer_avatar,
        subtotal,
        shipping_fee,
        tax,
        discount,
        total,
        shipping_street,
        shipping_city,
        shipping_district,
        shipping_ward,
        shipping_postal_code,
        payment_method,
        notes,
        status,
        payment_status
    ) VALUES (
        (order_data->>'store_id')::UUID,
        auth.uid(),
        order_data->>'customer_name',
        order_data->>'customer_email',
        order_data->>'customer_phone',
        order_data->>'customer_avatar',
        (order_data->>'subtotal')::DECIMAL,
        (order_data->>'shipping_fee')::DECIMAL,
        (order_data->>'tax')::DECIMAL,
        (order_data->>'discount')::DECIMAL,
        (order_data->>'total')::DECIMAL,
        order_data->>'shipping_street',
        order_data->>'shipping_city',
        order_data->>'shipping_district',
        order_data->>'shipping_ward',
        order_data->>'shipping_postal_code',
        order_data->>'payment_method',
        order_data->>'notes',
        'pending',
        'pending'
    ) 
    RETURNING id, order_number INTO new_order_id, order_number_generated;

    -- Build result object
    result_order := jsonb_build_object(
        'id', new_order_id,
        'order_number', order_number_generated,
        'store_id', order_data->>'store_id',
        'user_id', auth.uid(),
        'customer_name', order_data->>'customer_name',
        'customer_email', order_data->>'customer_email',
        'customer_phone', order_data->>'customer_phone',
        'customer_avatar', order_data->>'customer_avatar',
        'status', 'pending',
        'payment_status', 'pending',
        'payment_method', order_data->>'payment_method',
        'subtotal', (order_data->>'subtotal')::DECIMAL,
        'shipping_fee', (order_data->>'shipping_fee')::DECIMAL,
        'tax', (order_data->>'tax')::DECIMAL,
        'discount', (order_data->>'discount')::DECIMAL,
        'total', (order_data->>'total')::DECIMAL,
        'shipping_street', order_data->>'shipping_street',
        'shipping_city', order_data->>'shipping_city',
        'shipping_district', order_data->>'shipping_district',
        'shipping_ward', order_data->>'shipping_ward',
        'shipping_postal_code', order_data->>'shipping_postal_code',
        'tracking_number', NULL,
        'notes', order_data->>'notes',
        'created_at', NOW(),
        'updated_at', NOW()
    );

    RETURN result_order;
END;
$$;


ALTER FUNCTION "public"."create_order_simple"("order_data" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_order_with_items"("order_data" "jsonb", "items_data" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    new_order_id UUID;
    order_number_generated TEXT;
    result_order JSONB;
    item JSONB;
BEGIN
    -- Insert the order and get the generated ID and order number
    INSERT INTO orders (
        store_id,
        user_id,
        customer_name,
        customer_email,
        customer_phone,
        customer_avatar,
        subtotal,
        shipping_fee,
        tax,
        discount,
        total,
        shipping_street,
        shipping_city,
        shipping_district,
        shipping_ward,
        shipping_postal_code,
        payment_method,
        notes,
        status,
        payment_status
    ) VALUES (
        (order_data->>'store_id')::UUID,
        auth.uid(), -- This will be NULL for guests, which is fine
        order_data->>'customer_name',
        order_data->>'customer_email',
        order_data->>'customer_phone',
        order_data->>'customer_avatar',
        (order_data->>'subtotal')::DECIMAL,
        (order_data->>'shipping_fee')::DECIMAL,
        (order_data->>'tax')::DECIMAL,
        (order_data->>'discount')::DECIMAL,
        (order_data->>'total')::DECIMAL,
        order_data->>'shipping_street',
        order_data->>'shipping_city',
        order_data->>'shipping_district',
        order_data->>'shipping_ward',
        order_data->>'shipping_postal_code',
        order_data->>'payment_method',
        order_data->>'notes',
        'pending',
        'pending'
    ) 
    RETURNING id, order_number INTO new_order_id, order_number_generated;

    -- Insert order items
    FOR item IN SELECT * FROM jsonb_array_elements(items_data)
    LOOP
        INSERT INTO order_items (
            order_id,
            product_id,
            product_name,
            product_image,
            quantity,
            price,
            total
        ) VALUES (
            new_order_id,
            (item->>'product_id')::UUID,
            item->>'product_name',
            item->>'product_image',
            (item->>'quantity')::INTEGER,
            (item->>'price')::DECIMAL,
            (item->>'total')::DECIMAL
        );
    END LOOP;

    -- Build result object
    result_order := jsonb_build_object(
        'id', new_order_id,
        'order_number', order_number_generated,
        'store_id', order_data->>'store_id',
        'user_id', auth.uid(),
        'customer_name', order_data->>'customer_name',
        'customer_email', order_data->>'customer_email',
        'customer_phone', order_data->>'customer_phone',
        'customer_avatar', order_data->>'customer_avatar',
        'status', 'pending',
        'payment_status', 'pending',
        'payment_method', order_data->>'payment_method',
        'subtotal', (order_data->>'subtotal')::DECIMAL,
        'shipping_fee', (order_data->>'shipping_fee')::DECIMAL,
        'tax', (order_data->>'tax')::DECIMAL,
        'discount', (order_data->>'discount')::DECIMAL,
        'total', (order_data->>'total')::DECIMAL,
        'shipping_street', order_data->>'shipping_street',
        'shipping_city', order_data->>'shipping_city',
        'shipping_district', order_data->>'shipping_district',
        'shipping_ward', order_data->>'shipping_ward',
        'shipping_postal_code', order_data->>'shipping_postal_code',
        'tracking_number', NULL,
        'notes', order_data->>'notes',
        'created_at', NOW(),
        'updated_at', NOW()
    );

    RETURN result_order;
EXCEPTION
    WHEN OTHERS THEN
        -- If anything goes wrong, the transaction will be rolled back
        RAISE EXCEPTION 'Failed to create order: %', SQLERRM;
END;
$$;


ALTER FUNCTION "public"."create_order_with_items"("order_data" "jsonb", "items_data" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_order_number"() RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    year_part TEXT;
    sequence_part TEXT;
    order_number TEXT;
BEGIN
    year_part := EXTRACT(YEAR FROM NOW())::TEXT;
    
    -- Get next sequence number for this year
    SELECT LPAD((COUNT(*) + 1)::TEXT, 6, '0') INTO sequence_part
    FROM orders 
    WHERE EXTRACT(YEAR FROM created_at) = EXTRACT(YEAR FROM NOW());
    
    order_number := 'ORD-' || year_part || '-' || sequence_part;
    
    RETURN order_number;
END;
$$;


ALTER FUNCTION "public"."generate_order_number"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."lookup_guest_order"("p_order_number" "text", "p_customer_email" "text") RETURNS TABLE("id" "uuid", "order_number" "text", "store_id" "uuid", "customer_name" "text", "customer_email" "text", "customer_phone" "text", "status" "text", "payment_status" "text", "payment_method" "text", "subtotal" numeric, "shipping_fee" numeric, "tax" numeric, "discount" numeric, "total" numeric, "shipping_street" "text", "shipping_city" "text", "shipping_district" "text", "shipping_ward" "text", "shipping_postal_code" "text", "tracking_number" "text", "notes" "text", "created_at" timestamp with time zone, "updated_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
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
$$;


ALTER FUNCTION "public"."lookup_guest_order"("p_order_number" "text", "p_customer_email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."lookup_guest_order_items"("p_order_number" "text", "p_customer_email" "text") RETURNS TABLE("id" "uuid", "order_id" "uuid", "product_id" "uuid", "product_name" "text", "product_image" "text", "quantity" integer, "price" numeric, "total" numeric, "created_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        oi.id,
        oi.order_id,
        oi.product_id,
        oi.product_name,
        oi.product_image,
        oi.quantity,
        oi.price,
        oi.total,
        oi.created_at
    FROM order_items oi
    JOIN orders o ON o.id = oi.order_id
    WHERE o.order_number = p_order_number 
    AND LOWER(o.customer_email) = LOWER(p_customer_email);
END;
$$;


ALTER FUNCTION "public"."lookup_guest_order_items"("p_order_number" "text", "p_customer_email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_order_number"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF NEW.order_number IS NULL OR NEW.order_number = '' THEN
        NEW.order_number := generate_order_number();
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."set_order_number"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_user_id"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  IF NEW.user_id IS NULL THEN
    NEW.user_id := auth.uid();
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."set_user_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."banners" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "store_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "subtitle" "text",
    "image_url" "text" NOT NULL,
    "link_url" "text",
    "button_text" "text",
    "position" integer DEFAULT 0,
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."banners" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."categories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "store_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "image_url" "text",
    "parent_id" "uuid",
    "sort_order" integer DEFAULT 0,
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "external_cat_id" "text"
);


ALTER TABLE "public"."categories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."order_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid",
    "product_id" "uuid",
    "product_name" character varying(255) NOT NULL,
    "product_image" "text",
    "quantity" integer DEFAULT 1 NOT NULL,
    "price" numeric(12,2) NOT NULL,
    "total" numeric(12,2) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."order_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_number" character varying(50) NOT NULL,
    "store_id" "uuid",
    "user_id" "uuid",
    "customer_name" character varying(255) NOT NULL,
    "customer_email" character varying(255) NOT NULL,
    "customer_phone" character varying(20),
    "customer_avatar" "text",
    "status" character varying(20) DEFAULT 'pending'::character varying,
    "payment_status" character varying(20) DEFAULT 'pending'::character varying,
    "payment_method" character varying(20) DEFAULT 'cod'::character varying,
    "subtotal" numeric(12,2) DEFAULT 0 NOT NULL,
    "shipping_fee" numeric(12,2) DEFAULT 0 NOT NULL,
    "tax" numeric(12,2) DEFAULT 0 NOT NULL,
    "discount" numeric(12,2) DEFAULT 0 NOT NULL,
    "total" numeric(12,2) DEFAULT 0 NOT NULL,
    "shipping_street" "text" NOT NULL,
    "shipping_city" character varying(100) NOT NULL,
    "shipping_district" character varying(100),
    "shipping_ward" character varying(100),
    "shipping_postal_code" character varying(20),
    "tracking_number" character varying(100),
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "orders_payment_method_check" CHECK ((("payment_method")::"text" = ANY ((ARRAY['cod'::character varying, 'banking'::character varying, 'e_wallet'::character varying, 'credit_card'::character varying])::"text"[]))),
    CONSTRAINT "orders_payment_status_check" CHECK ((("payment_status")::"text" = ANY ((ARRAY['pending'::character varying, 'paid'::character varying, 'failed'::character varying, 'refunded'::character varying])::"text"[]))),
    CONSTRAINT "orders_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['pending'::character varying, 'confirmed'::character varying, 'processing'::character varying, 'shipped'::character varying, 'delivered'::character varying, 'cancelled'::character varying, 'refunded'::character varying])::"text"[])))
);


ALTER TABLE "public"."orders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."products" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "store_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "price" numeric(10,2) NOT NULL,
    "original_price" numeric(10,2),
    "inventory" integer DEFAULT 0,
    "sold" integer DEFAULT 0,
    "status" "text" DEFAULT 'active'::"text",
    "category" "text",
    "images" "text"[],
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "category_id" "uuid",
    "is_featured" boolean DEFAULT false,
    "is_promotion" boolean DEFAULT false,
    "promotion_price" numeric(10,2),
    "promotion_start_date" timestamp with time zone,
    "promotion_end_date" timestamp with time zone,
    "external_sku_id" "text"
);


ALTER TABLE "public"."products" OWNER TO "postgres";


COMMENT ON COLUMN "public"."products"."external_sku_id" IS 'Unique identifier from external source (e.g., TikTok SKU ID) used during product import to maintain reference to original product';



CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "name" "text",
    "email" "text",
    "avatar_url" "text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."stores" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "subdomain" "text",
    "custom_domain" "text",
    "logo_url" "text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."stores" OWNER TO "postgres";


ALTER TABLE ONLY "public"."banners"
    ADD CONSTRAINT "banners_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_order_number_key" UNIQUE ("order_number");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."stores"
    ADD CONSTRAINT "stores_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."stores"
    ADD CONSTRAINT "stores_subdomain_key" UNIQUE ("subdomain");



CREATE INDEX "idx_banners_active" ON "public"."banners" USING "btree" ("is_active");



CREATE INDEX "idx_banners_position" ON "public"."banners" USING "btree" ("position");



CREATE INDEX "idx_banners_store_id" ON "public"."banners" USING "btree" ("store_id");



CREATE INDEX "idx_categories_active" ON "public"."categories" USING "btree" ("is_active");



CREATE INDEX "idx_categories_external_cat_id" ON "public"."categories" USING "btree" ("external_cat_id");



CREATE INDEX "idx_categories_parent_id" ON "public"."categories" USING "btree" ("parent_id");



CREATE INDEX "idx_categories_store_external_cat" ON "public"."categories" USING "btree" ("store_id", "external_cat_id");



CREATE UNIQUE INDEX "idx_categories_store_external_cat_unique" ON "public"."categories" USING "btree" ("store_id", "external_cat_id") WHERE ("external_cat_id" IS NOT NULL);



CREATE INDEX "idx_categories_store_id" ON "public"."categories" USING "btree" ("store_id");



CREATE INDEX "idx_order_items_order_id" ON "public"."order_items" USING "btree" ("order_id");



CREATE INDEX "idx_order_items_product_id" ON "public"."order_items" USING "btree" ("product_id");



CREATE INDEX "idx_orders_created_at" ON "public"."orders" USING "btree" ("created_at");



CREATE INDEX "idx_orders_order_number" ON "public"."orders" USING "btree" ("order_number");



CREATE INDEX "idx_orders_payment_status" ON "public"."orders" USING "btree" ("payment_status");



CREATE INDEX "idx_orders_status" ON "public"."orders" USING "btree" ("status");



CREATE INDEX "idx_orders_store_id" ON "public"."orders" USING "btree" ("store_id");



CREATE INDEX "idx_orders_user_id" ON "public"."orders" USING "btree" ("user_id");



CREATE INDEX "idx_products_category_id" ON "public"."products" USING "btree" ("category_id");



CREATE INDEX "idx_products_external_sku_id" ON "public"."products" USING "btree" ("external_sku_id");



CREATE INDEX "idx_products_featured" ON "public"."products" USING "btree" ("is_featured");



CREATE INDEX "idx_products_promotion" ON "public"."products" USING "btree" ("is_promotion");



CREATE INDEX "idx_products_status" ON "public"."products" USING "btree" ("status");



CREATE INDEX "idx_products_store_external_sku" ON "public"."products" USING "btree" ("store_id", "external_sku_id");



CREATE INDEX "idx_products_store_id" ON "public"."products" USING "btree" ("store_id");



CREATE INDEX "idx_profiles_id" ON "public"."profiles" USING "btree" ("id");



CREATE INDEX "idx_stores_user_id" ON "public"."stores" USING "btree" ("user_id");



CREATE OR REPLACE TRIGGER "trigger_set_order_number" BEFORE INSERT ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "public"."set_order_number"();



CREATE OR REPLACE TRIGGER "trigger_update_orders_updated_at" BEFORE UPDATE ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_products_updated_at" BEFORE UPDATE ON "public"."products" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_profiles_updated_at" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_stores_updated_at" BEFORE UPDATE ON "public"."stores" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



ALTER TABLE ONLY "public"."banners"
    ADD CONSTRAINT "banners_store_id_fkey" FOREIGN KEY ("store_id") REFERENCES "public"."stores"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "public"."categories"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_store_id_fkey" FOREIGN KEY ("store_id") REFERENCES "public"."stores"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_store_id_fkey" FOREIGN KEY ("store_id") REFERENCES "public"."stores"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_store_id_fkey" FOREIGN KEY ("store_id") REFERENCES "public"."stores"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."stores"
    ADD CONSTRAINT "stores_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Anyone can view active products" ON "public"."products" FOR SELECT USING (("status" = 'active'::"text"));



CREATE POLICY "Anyone can view stores" ON "public"."stores" FOR SELECT USING (true);



CREATE POLICY "Public can view active banners" ON "public"."banners" FOR SELECT USING (("is_active" = true));



CREATE POLICY "Public can view active categories" ON "public"."categories" FOR SELECT USING (("is_active" = true));



CREATE POLICY "Store owners can manage banners" ON "public"."banners" USING (("store_id" IN ( SELECT "stores"."id"
   FROM "public"."stores"
  WHERE ("stores"."user_id" = "auth"."uid"()))));



CREATE POLICY "Store owners can manage categories" ON "public"."categories" USING (("store_id" IN ( SELECT "stores"."id"
   FROM "public"."stores"
  WHERE ("stores"."user_id" = "auth"."uid"()))));



CREATE POLICY "Users can create products in own stores" ON "public"."products" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."stores"
  WHERE (("stores"."id" = "products"."store_id") AND ("stores"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can create stores" ON "public"."stores" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete own stores" ON "public"."stores" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete products for their stores" ON "public"."products" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."stores"
  WHERE (("stores"."id" = "products"."store_id") AND ("stores"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can delete products in own stores" ON "public"."products" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."stores"
  WHERE (("stores"."id" = "products"."store_id") AND ("stores"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can delete their own stores" ON "public"."stores" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can insert own profile" ON "public"."profiles" FOR INSERT WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "Users can insert products for their stores" ON "public"."products" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."stores"
  WHERE (("stores"."id" = "products"."store_id") AND ("stores"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can insert their own stores" ON "public"."stores" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update own profile" ON "public"."profiles" FOR UPDATE USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can update own stores" ON "public"."stores" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update products for their stores" ON "public"."products" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."stores"
  WHERE (("stores"."id" = "products"."store_id") AND ("stores"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can update products in own stores" ON "public"."products" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."stores"
  WHERE (("stores"."id" = "products"."store_id") AND ("stores"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can update their own stores" ON "public"."stores" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view own profile" ON "public"."profiles" FOR SELECT USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can view own stores" ON "public"."stores" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view products from own stores" ON "public"."products" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."stores"
  WHERE (("stores"."id" = "products"."store_id") AND ("stores"."user_id" = "auth"."uid"())))));



CREATE POLICY "authenticated_users_delete_own_orders" ON "public"."orders" FOR DELETE USING (("user_id" = "auth"."uid"()));



CREATE POLICY "authenticated_users_update_own_orders" ON "public"."orders" FOR UPDATE USING (("user_id" = "auth"."uid"()));



CREATE POLICY "authenticated_users_view_own_order_items" ON "public"."order_items" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."orders"
  WHERE (("orders"."id" = "order_items"."order_id") AND ("orders"."user_id" = "auth"."uid"())))));



CREATE POLICY "authenticated_users_view_own_orders" ON "public"."orders" FOR SELECT USING (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."banners" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."categories" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "guest_and_user_can_create_order_items" ON "public"."order_items" FOR INSERT WITH CHECK (true);



CREATE POLICY "guest_and_user_can_create_orders" ON "public"."orders" FOR INSERT WITH CHECK (true);



ALTER TABLE "public"."order_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."orders" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."products" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "store_owners_delete_store_order_items" ON "public"."order_items" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM ("public"."orders"
     JOIN "public"."stores" ON (("stores"."id" = "orders"."store_id")))
  WHERE (("orders"."id" = "order_items"."order_id") AND ("stores"."user_id" = "auth"."uid"())))));



CREATE POLICY "store_owners_update_store_order_items" ON "public"."order_items" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM ("public"."orders"
     JOIN "public"."stores" ON (("stores"."id" = "orders"."store_id")))
  WHERE (("orders"."id" = "order_items"."order_id") AND ("stores"."user_id" = "auth"."uid"())))));



CREATE POLICY "store_owners_update_store_orders" ON "public"."orders" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."stores"
  WHERE (("stores"."id" = "orders"."store_id") AND ("stores"."user_id" = "auth"."uid"())))));



CREATE POLICY "store_owners_view_store_order_items" ON "public"."order_items" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM ("public"."orders"
     JOIN "public"."stores" ON (("stores"."id" = "orders"."store_id")))
  WHERE (("orders"."id" = "order_items"."order_id") AND ("stores"."user_id" = "auth"."uid"())))));



CREATE POLICY "store_owners_view_store_orders" ON "public"."orders" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."stores"
  WHERE (("stores"."id" = "orders"."store_id") AND ("stores"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."stores" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

























































































































































GRANT ALL ON FUNCTION "public"."create_order_simple"("order_data" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."create_order_simple"("order_data" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_order_simple"("order_data" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_order_with_items"("order_data" "jsonb", "items_data" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."create_order_with_items"("order_data" "jsonb", "items_data" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_order_with_items"("order_data" "jsonb", "items_data" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_order_number"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_order_number"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_order_number"() TO "service_role";



GRANT ALL ON FUNCTION "public"."lookup_guest_order"("p_order_number" "text", "p_customer_email" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."lookup_guest_order"("p_order_number" "text", "p_customer_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."lookup_guest_order"("p_order_number" "text", "p_customer_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."lookup_guest_order_items"("p_order_number" "text", "p_customer_email" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."lookup_guest_order_items"("p_order_number" "text", "p_customer_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."lookup_guest_order_items"("p_order_number" "text", "p_customer_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_order_number"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_order_number"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_order_number"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_user_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_user_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_user_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "service_role";


















GRANT ALL ON TABLE "public"."banners" TO "anon";
GRANT ALL ON TABLE "public"."banners" TO "authenticated";
GRANT ALL ON TABLE "public"."banners" TO "service_role";



GRANT ALL ON TABLE "public"."categories" TO "anon";
GRANT ALL ON TABLE "public"."categories" TO "authenticated";
GRANT ALL ON TABLE "public"."categories" TO "service_role";



GRANT ALL ON TABLE "public"."order_items" TO "anon";
GRANT ALL ON TABLE "public"."order_items" TO "authenticated";
GRANT ALL ON TABLE "public"."order_items" TO "service_role";



GRANT ALL ON TABLE "public"."orders" TO "anon";
GRANT ALL ON TABLE "public"."orders" TO "authenticated";
GRANT ALL ON TABLE "public"."orders" TO "service_role";



GRANT ALL ON TABLE "public"."products" TO "anon";
GRANT ALL ON TABLE "public"."products" TO "authenticated";
GRANT ALL ON TABLE "public"."products" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."stores" TO "anon";
GRANT ALL ON TABLE "public"."stores" TO "authenticated";
GRANT ALL ON TABLE "public"."stores" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";






























RESET ALL;
