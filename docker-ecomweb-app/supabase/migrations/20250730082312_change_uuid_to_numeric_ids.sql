-- Migration: Change UUID IDs to numeric types
-- Store ID => integer (4 bytes)
-- Category ID => integer (4 bytes) 
-- Product ID => bigint (8 bytes)
-- Order ID => bigint (8 bytes)
-- Customer ID => integer (4 bytes)

-- Step 1: Create sequences for auto-incrementing IDs
CREATE SEQUENCE IF NOT EXISTS stores_id_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS categories_id_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS products_id_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS orders_id_seq START WITH 1 INCREMENT BY 1;

-- Step 2: Create temporary tables with new ID types
CREATE TABLE stores_new (
    id INTEGER PRIMARY KEY DEFAULT nextval('stores_id_seq'),
    user_id UUID NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    subdomain TEXT,
    custom_domain TEXT,
    logo_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE TABLE categories_new (
    id INTEGER PRIMARY KEY DEFAULT nextval('categories_id_seq'),
    store_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    image_url TEXT,
    parent_id INTEGER,
    sort_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    external_cat_id TEXT
);

CREATE TABLE products_new (
    id BIGINT PRIMARY KEY DEFAULT nextval('products_id_seq'),
    store_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    price NUMERIC(10,2) NOT NULL,
    original_price NUMERIC(10,2),
    inventory INTEGER DEFAULT 0,
    sold INTEGER DEFAULT 0,
    status TEXT DEFAULT 'active'::text,
    category TEXT,
    images TEXT[],
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    category_id INTEGER,
    is_featured BOOLEAN DEFAULT false,
    is_promotion BOOLEAN DEFAULT false,
    promotion_price NUMERIC(10,2),
    promotion_start_date TIMESTAMP WITH TIME ZONE,
    promotion_end_date TIMESTAMP WITH TIME ZONE,
    external_sku_id TEXT
);

CREATE TABLE orders_new (
    id BIGINT PRIMARY KEY DEFAULT nextval('orders_id_seq'),
    order_number CHARACTER VARYING(50) NOT NULL,
    store_id INTEGER,
    user_id UUID,
    customer_name CHARACTER VARYING(255) NOT NULL,
    customer_email CHARACTER VARYING(255) NOT NULL,
    customer_phone CHARACTER VARYING(20),
    customer_avatar TEXT,
    status CHARACTER VARYING(20) DEFAULT 'pending'::character varying,
    payment_status CHARACTER VARYING(20) DEFAULT 'pending'::character varying,
    payment_method CHARACTER VARYING(20) DEFAULT 'cod'::character varying,
    subtotal NUMERIC(12,2) DEFAULT 0 NOT NULL,
    shipping_fee NUMERIC(12,2) DEFAULT 0 NOT NULL,
    tax NUMERIC(12,2) DEFAULT 0 NOT NULL,
    discount NUMERIC(12,2) DEFAULT 0 NOT NULL,
    total NUMERIC(12,2) DEFAULT 0 NOT NULL,
    shipping_street TEXT NOT NULL,
    shipping_city CHARACTER VARYING(100) NOT NULL,
    shipping_district CHARACTER VARYING(100),
    shipping_ward CHARACTER VARYING(100),
    shipping_postal_code CHARACTER VARYING(20),
    tracking_number CHARACTER VARYING(100),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    CONSTRAINT orders_payment_method_check CHECK ((payment_method::text = ANY ((ARRAY['cod'::character varying, 'banking'::character varying, 'e_wallet'::character varying, 'credit_card'::character varying])::text[]))),
    CONSTRAINT orders_payment_status_check CHECK ((payment_status::text = ANY ((ARRAY['pending'::character varying, 'paid'::character varying, 'failed'::character varying, 'refunded'::character varying])::text[]))),
    CONSTRAINT orders_status_check CHECK ((status::text = ANY ((ARRAY['pending'::character varying, 'confirmed'::character varying, 'processing'::character varying, 'shipped'::character varying, 'delivered'::character varying, 'cancelled'::character varying, 'refunded'::character varying])::text[])))
);

CREATE TABLE order_items_new (
    id BIGINT PRIMARY KEY DEFAULT nextval('products_id_seq'), -- Reuse products sequence for order items
    order_id BIGINT,
    product_id BIGINT,
    product_name CHARACTER VARYING(255) NOT NULL,
    product_image TEXT,
    quantity INTEGER DEFAULT 1 NOT NULL,
    price NUMERIC(12,2) NOT NULL,
    total NUMERIC(12,2) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE TABLE banners_new (
    id BIGINT PRIMARY KEY DEFAULT nextval('products_id_seq'), -- Reuse products sequence for banners
    store_id INTEGER NOT NULL,
    title TEXT NOT NULL,
    subtitle TEXT,
    image_url TEXT NOT NULL,
    link_url TEXT,
    button_text TEXT,
    position INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Step 3: Copy data from old tables to new tables
-- Note: We'll need to map UUIDs to sequential integers
-- This is a simplified approach - in production you'd want to preserve specific ID mappings

INSERT INTO stores_new (id, user_id, name, description, subdomain, custom_domain, logo_url, created_at, updated_at)
SELECT 
    ROW_NUMBER() OVER (ORDER BY created_at) as id,
    user_id,
    name,
    description,
    subdomain,
    custom_domain,
    logo_url,
    created_at,
    updated_at
FROM stores;

INSERT INTO categories_new (id, store_id, name, description, image_url, parent_id, sort_order, is_active, created_at, updated_at, external_cat_id)
SELECT 
    ROW_NUMBER() OVER (ORDER BY c.created_at) as id,
    s_new.id as store_id,
    c.name,
    c.description,
    c.image_url,
    parent_new.id as parent_id,
    c.sort_order,
    c.is_active,
    c.created_at,
    c.updated_at,
    c.external_cat_id
FROM categories c
JOIN stores s ON c.store_id = s.id
JOIN stores_new s_new ON s_new.user_id = s.user_id AND s_new.name = s.name
LEFT JOIN categories parent ON c.parent_id = parent.id
LEFT JOIN categories_new parent_new ON parent_new.name = parent.name AND parent_new.store_id = s_new.id;

INSERT INTO products_new (id, store_id, name, description, price, original_price, inventory, sold, status, category, images, created_at, updated_at, category_id, is_featured, is_promotion, promotion_price, promotion_start_date, promotion_end_date, external_sku_id)
SELECT 
    ROW_NUMBER() OVER (ORDER BY p.created_at) as id,
    s_new.id as store_id,
    p.name,
    p.description,
    p.price,
    p.original_price,
    p.inventory,
    p.sold,
    p.status,
    p.category,
    p.images,
    p.created_at,
    p.updated_at,
    c_new.id as category_id,
    p.is_featured,
    p.is_promotion,
    p.promotion_price,
    p.promotion_start_date,
    p.promotion_end_date,
    p.external_sku_id
FROM products p
JOIN stores s ON p.store_id = s.id
JOIN stores_new s_new ON s_new.user_id = s.user_id AND s_new.name = s.name
LEFT JOIN categories c ON p.category_id = c.id
LEFT JOIN categories_new c_new ON c_new.name = c.name AND c_new.store_id = s_new.id;

INSERT INTO orders_new (id, order_number, store_id, user_id, customer_name, customer_email, customer_phone, customer_avatar, status, payment_status, payment_method, subtotal, shipping_fee, tax, discount, total, shipping_street, shipping_city, shipping_district, shipping_ward, shipping_postal_code, tracking_number, notes, created_at, updated_at)
SELECT 
    ROW_NUMBER() OVER (ORDER BY o.created_at) as id,
    o.order_number,
    s_new.id as store_id,
    o.user_id,
    o.customer_name,
    o.customer_email,
    o.customer_phone,
    o.customer_avatar,
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
JOIN stores s ON o.store_id = s.id
JOIN stores_new s_new ON s_new.user_id = s.user_id AND s_new.name = s.name;

INSERT INTO order_items_new (id, order_id, product_id, product_name, product_image, quantity, price, total, created_at)
SELECT 
    ROW_NUMBER() OVER (ORDER BY oi.created_at) as id,
    o_new.id as order_id,
    p_new.id as product_id,
    oi.product_name,
    oi.product_image,
    oi.quantity,
    oi.price,
    oi.total,
    oi.created_at
FROM order_items oi
JOIN orders o ON oi.order_id = o.id
JOIN orders_new o_new ON o_new.order_number = o.order_number
JOIN products p ON oi.product_id = p.id
JOIN products_new p_new ON p_new.name = p.name;

INSERT INTO banners_new (id, store_id, title, subtitle, image_url, link_url, button_text, position, is_active, created_at, updated_at)
SELECT 
    ROW_NUMBER() OVER (ORDER BY b.created_at) as id,
    s_new.id as store_id,
    b.title,
    b.subtitle,
    b.image_url,
    b.link_url,
    b.button_text,
    b.position,
    b.is_active,
    b.created_at,
    b.updated_at
FROM banners b
JOIN stores s ON b.store_id = s.id
JOIN stores_new s_new ON s_new.user_id = s.user_id AND s_new.name = s.name;

-- Step 4: Drop old tables and rename new tables
DROP TABLE banners;
DROP TABLE order_items;
DROP TABLE orders;
DROP TABLE products;
DROP TABLE categories;
DROP TABLE stores;

ALTER TABLE stores_new RENAME TO stores;
ALTER TABLE categories_new RENAME TO categories;
ALTER TABLE products_new RENAME TO products;
ALTER TABLE orders_new RENAME TO orders;
ALTER TABLE order_items_new RENAME TO order_items;
ALTER TABLE banners_new RENAME TO banners;

-- Step 5: Add constraints and indexes
ALTER TABLE ONLY stores ADD CONSTRAINT stores_subdomain_key UNIQUE (subdomain);
ALTER TABLE ONLY categories ADD CONSTRAINT categories_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES categories(id) ON DELETE CASCADE;
ALTER TABLE ONLY categories ADD CONSTRAINT categories_store_id_fkey FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE;
ALTER TABLE ONLY order_items ADD CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE;
ALTER TABLE ONLY order_items ADD CONSTRAINT order_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE;
ALTER TABLE ONLY orders ADD CONSTRAINT orders_store_id_fkey FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE;
ALTER TABLE ONLY orders ADD CONSTRAINT orders_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE ONLY products ADD CONSTRAINT products_category_id_fkey FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL;
ALTER TABLE ONLY products ADD CONSTRAINT products_store_id_fkey FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE;
ALTER TABLE ONLY stores ADD CONSTRAINT stores_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- Indexes
CREATE INDEX idx_banners_active ON banners USING btree (is_active);
CREATE INDEX idx_banners_position ON banners USING btree (position);
CREATE INDEX idx_banners_store_id ON banners USING btree (store_id);
CREATE INDEX idx_categories_active ON categories USING btree (is_active);
CREATE INDEX idx_categories_external_cat_id ON categories USING btree (external_cat_id);
CREATE INDEX idx_categories_parent_id ON categories USING btree (parent_id);
CREATE INDEX idx_categories_store_external_cat ON categories USING btree (store_id, external_cat_id);
CREATE UNIQUE INDEX idx_categories_store_external_cat_unique ON categories USING btree (store_id, external_cat_id) WHERE (external_cat_id IS NOT NULL);
CREATE INDEX idx_categories_store_id ON categories USING btree (store_id);
CREATE INDEX idx_order_items_order_id ON order_items USING btree (order_id);
CREATE INDEX idx_order_items_product_id ON order_items USING btree (product_id);
CREATE INDEX idx_orders_created_at ON orders USING btree (created_at);
CREATE INDEX idx_orders_order_number ON orders USING btree (order_number);
CREATE INDEX idx_orders_payment_status ON orders USING btree (payment_status);
CREATE INDEX idx_orders_status ON orders USING btree (status);
CREATE INDEX idx_orders_store_id ON orders USING btree (store_id);
CREATE INDEX idx_orders_user_id ON orders USING btree (user_id);
CREATE INDEX idx_products_category_id ON products USING btree (category_id);
CREATE INDEX idx_products_external_sku_id ON products USING btree (external_sku_id);
CREATE INDEX idx_products_featured ON products USING btree (is_featured);
CREATE INDEX idx_products_promotion ON products USING btree (is_promotion);
CREATE INDEX idx_products_status ON products USING btree (status);
CREATE INDEX idx_products_store_external_sku ON products USING btree (store_id, external_sku_id);
CREATE INDEX idx_products_store_id ON products USING btree (store_id);
CREATE INDEX idx_stores_user_id ON stores USING btree (user_id);

-- Step 6: Update functions to use new ID types

DROP FUNCTION IF EXISTS lookup_guest_order(text, text);
DROP FUNCTION IF EXISTS lookup_guest_order_items(text, text);

CREATE OR REPLACE FUNCTION create_order_simple(order_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    new_order_id BIGINT;
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
        (order_data->>'store_id')::INTEGER,
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

CREATE OR REPLACE FUNCTION create_order_with_items(order_data jsonb, items_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    new_order_id BIGINT;
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
        (order_data->>'store_id')::INTEGER,
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
            (item->>'product_id')::BIGINT,
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

CREATE OR REPLACE FUNCTION lookup_guest_order(p_order_number text, p_customer_email text) RETURNS TABLE(id BIGINT, order_number text, store_id INTEGER, customer_name text, customer_email text, customer_phone text, status text, payment_status text, payment_method text, subtotal numeric, shipping_fee numeric, tax numeric, discount numeric, total numeric, shipping_street text, shipping_city text, shipping_district text, shipping_ward text, shipping_postal_code text, tracking_number text, notes text, created_at timestamp with time zone, updated_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
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

CREATE OR REPLACE FUNCTION lookup_guest_order_items(p_order_number text, p_customer_email text) RETURNS TABLE(id BIGINT, order_id BIGINT, product_id BIGINT, product_name text, product_image text, quantity integer, price numeric, total numeric, created_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
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

-- Step 7: Recreate triggers
CREATE OR REPLACE TRIGGER trigger_set_order_number BEFORE INSERT ON orders FOR EACH ROW EXECUTE FUNCTION set_order_number();
CREATE OR REPLACE TRIGGER trigger_update_orders_updated_at BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE OR REPLACE TRIGGER update_products_updated_at BEFORE UPDATE ON products FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE OR REPLACE TRIGGER update_stores_updated_at BEFORE UPDATE ON stores FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Step 8: Recreate RLS policies
ALTER TABLE banners ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE stores ENABLE ROW LEVEL SECURITY;

-- Recreate all the RLS policies (simplified version - you may need to adjust based on your specific requirements)
CREATE POLICY "Anyone can view active products" ON products FOR SELECT USING ((status = 'active'::text));
CREATE POLICY "Anyone can view stores" ON stores FOR SELECT USING (true);
CREATE POLICY "Public can view active banners" ON banners FOR SELECT USING ((is_active = true));
CREATE POLICY "Public can view active categories" ON categories FOR SELECT USING ((is_active = true));

-- Store owner policies
CREATE POLICY "Store owners can manage banners" ON banners USING ((store_id IN ( SELECT stores.id FROM stores WHERE (stores.user_id = auth.uid()))));
CREATE POLICY "Store owners can manage categories" ON categories USING ((store_id IN ( SELECT stores.id FROM stores WHERE (stores.user_id = auth.uid()))));
CREATE POLICY "Users can create products in own stores" ON products FOR INSERT WITH CHECK ((EXISTS ( SELECT 1 FROM stores WHERE ((stores.id = products.store_id) AND (stores.user_id = auth.uid())))));
CREATE POLICY "Users can create stores" ON stores FOR INSERT WITH CHECK ((auth.uid() = user_id));
CREATE POLICY "Users can delete own stores" ON stores FOR DELETE USING ((auth.uid() = user_id));
CREATE POLICY "Users can delete products for their stores" ON products FOR DELETE USING ((EXISTS ( SELECT 1 FROM stores WHERE ((stores.id = products.store_id) AND (stores.user_id = auth.uid())))));

-- Order policies
CREATE POLICY "guest_and_user_can_create_orders" ON orders FOR INSERT WITH CHECK (true);
CREATE POLICY "guest_and_user_can_create_order_items" ON order_items FOR INSERT WITH CHECK (true);
CREATE POLICY "authenticated_users_view_own_orders" ON orders FOR SELECT USING ((user_id = auth.uid()));
CREATE POLICY "authenticated_users_update_own_orders" ON orders FOR UPDATE USING ((user_id = auth.uid()));
CREATE POLICY "authenticated_users_delete_own_orders" ON orders FOR DELETE USING ((user_id = auth.uid()));
CREATE POLICY "authenticated_users_view_own_order_items" ON order_items FOR SELECT USING ((EXISTS ( SELECT 1 FROM orders WHERE ((orders.id = order_items.order_id) AND (orders.user_id = auth.uid())))));

-- Store owner order policies
CREATE POLICY "store_owners_view_store_orders" ON orders FOR SELECT USING ((EXISTS ( SELECT 1 FROM stores WHERE ((stores.id = orders.store_id) AND (stores.user_id = auth.uid())))));
CREATE POLICY "store_owners_update_store_orders" ON orders FOR UPDATE USING ((EXISTS ( SELECT 1 FROM stores WHERE ((stores.id = orders.store_id) AND (stores.user_id = auth.uid())))));
CREATE POLICY "store_owners_view_store_order_items" ON order_items FOR SELECT USING ((EXISTS ( SELECT 1 FROM (orders JOIN stores ON ((stores.id = orders.store_id))) WHERE ((orders.id = order_items.order_id) AND (stores.user_id = auth.uid())))));
CREATE POLICY "store_owners_update_store_order_items" ON order_items FOR UPDATE USING ((EXISTS ( SELECT 1 FROM (orders JOIN stores ON ((stores.id = orders.store_id))) WHERE ((orders.id = order_items.order_id) AND (stores.user_id = auth.uid())))));
CREATE POLICY "store_owners_delete_store_order_items" ON order_items FOR DELETE USING ((EXISTS ( SELECT 1 FROM (orders JOIN stores ON ((stores.id = orders.store_id))) WHERE ((orders.id = order_items.order_id) AND (stores.user_id = auth.uid())))));

-- Product policies
CREATE POLICY "Users can insert products for their stores" ON products FOR INSERT WITH CHECK ((EXISTS ( SELECT 1 FROM stores WHERE ((stores.id = products.store_id) AND (stores.user_id = auth.uid())))));
CREATE POLICY "Users can update products for their stores" ON products FOR UPDATE USING ((EXISTS ( SELECT 1 FROM stores WHERE ((stores.id = products.store_id) AND (stores.user_id = auth.uid())))));
CREATE POLICY "Users can view products from own stores" ON products FOR SELECT USING ((EXISTS ( SELECT 1 FROM stores WHERE ((stores.id = products.store_id) AND (stores.user_id = auth.uid())))));

-- Store policies
CREATE POLICY "Users can insert their own stores" ON stores FOR INSERT WITH CHECK ((auth.uid() = user_id));
CREATE POLICY "Users can update their own stores" ON stores FOR UPDATE USING ((auth.uid() = user_id));
CREATE POLICY "Users can view own stores" ON stores FOR SELECT USING ((auth.uid() = user_id));

-- Grant permissions
GRANT ALL ON TABLE banners TO anon, authenticated, service_role;
GRANT ALL ON TABLE categories TO anon, authenticated, service_role;
GRANT ALL ON TABLE order_items TO anon, authenticated, service_role;
GRANT ALL ON TABLE orders TO anon, authenticated, service_role;
GRANT ALL ON TABLE products TO anon, authenticated, service_role;
GRANT ALL ON TABLE stores TO anon, authenticated, service_role;

GRANT ALL ON FUNCTION create_order_simple(jsonb) TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION create_order_with_items(jsonb, jsonb) TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION lookup_guest_order(text, text) TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION lookup_guest_order_items(text, text) TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION generate_order_number() TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION set_order_number() TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION set_user_id() TO anon, authenticated, service_role;
GRANT ALL ON FUNCTION update_updated_at_column() TO anon, authenticated, service_role;

-- Grant sequence permissions
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
