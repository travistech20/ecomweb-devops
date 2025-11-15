-- Migration: Add Product Variants Schema
-- This migration adds support for product variants with flexible attribute combinations

-- Create sequences for new tables
CREATE SEQUENCE IF NOT EXISTS product_variants_id_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS variant_options_id_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS variant_option_values_id_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS product_variant_combinations_id_seq START WITH 1 INCREMENT BY 1;

-- 1. Product Variants Table
CREATE TABLE product_variants (
    id BIGINT PRIMARY KEY DEFAULT nextval('product_variants_id_seq'),
    product_id BIGINT NOT NULL,
    sku_id INTEGER NOT NULL,
    seller_sku TEXT,
    external_id TEXT,
    price NUMERIC(10,2) NOT NULL,
    inventory INTEGER DEFAULT 0,
    weight NUMERIC(8,2),
    dimensions JSONB, -- {length, width, height, unit}
    is_default BOOLEAN DEFAULT false,
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'out_of_stock')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    
    CONSTRAINT product_variants_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
    CONSTRAINT product_variants_sku_id_unique UNIQUE (sku_id)
);

-- 2. Variant Options Table
CREATE TABLE variant_options (
    id INTEGER PRIMARY KEY DEFAULT nextval('variant_options_id_seq'),
    store_id INTEGER NOT NULL,
    name TEXT NOT NULL, -- e.g., "Size", "Color", "Material"
    display_name TEXT NOT NULL, -- e.g., "Size", "Color", "Material"
    type TEXT DEFAULT 'text', -- 'text', 'color', 'image'
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    
    CONSTRAINT variant_options_store_id_fkey FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE
);

-- 3. Variant Option Values Table
CREATE TABLE variant_option_values (
    id INTEGER PRIMARY KEY DEFAULT nextval('variant_option_values_id_seq'),
    option_id INTEGER NOT NULL,
    value TEXT NOT NULL, -- e.g., "Red", "XL"
    display_value TEXT NOT NULL, -- e.g., "Red", "Extra Large"
    color_code TEXT, -- For color type options
    image_url TEXT, -- For image type options
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    
    CONSTRAINT variant_option_values_option_id_fkey FOREIGN KEY (option_id) REFERENCES variant_options(id) ON DELETE CASCADE
);

-- 4. Product Variant Combinations Table
CREATE TABLE product_variant_combinations (
    id BIGINT PRIMARY KEY DEFAULT nextval('product_variant_combinations_id_seq'),
    variant_id BIGINT NOT NULL,
    option_id INTEGER NOT NULL,
    option_value_id INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    
    CONSTRAINT product_variant_combinations_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES product_variants(id) ON DELETE CASCADE,
    CONSTRAINT product_variant_combinations_option_id_fkey FOREIGN KEY (option_id) REFERENCES variant_options(id) ON DELETE CASCADE,
    CONSTRAINT product_variant_combinations_option_value_id_fkey FOREIGN KEY (option_value_id) REFERENCES variant_option_values(id) ON DELETE CASCADE,
    CONSTRAINT product_variant_combinations_unique UNIQUE (variant_id, option_id)
);

-- 5. Update Products Table
ALTER TABLE products ADD COLUMN has_variants BOOLEAN DEFAULT false;
ALTER TABLE products ADD COLUMN min_price NUMERIC(10,2);
ALTER TABLE products ADD COLUMN max_price NUMERIC(10,2);

-- 6. Update Order Items Table
ALTER TABLE order_items ADD COLUMN variant_id BIGINT;
ALTER TABLE order_items ADD CONSTRAINT order_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES product_variants(id) ON DELETE SET NULL;

-- Create indexes for product_variants
CREATE INDEX idx_product_variants_product_id ON product_variants(product_id);
CREATE INDEX idx_product_variants_sku_id ON product_variants(sku_id);
CREATE INDEX idx_product_variants_seller_sku ON product_variants(seller_sku);
CREATE INDEX idx_product_variants_external_id ON product_variants(external_id);
CREATE INDEX idx_product_variants_is_default ON product_variants(is_default);
CREATE INDEX idx_product_variants_status ON product_variants(status);

-- Create indexes for variant_options
CREATE INDEX idx_variant_options_store_id ON variant_options(store_id);
CREATE INDEX idx_variant_options_sort_order ON variant_options(sort_order);

-- Create indexes for variant_option_values
CREATE INDEX idx_variant_option_values_option_id ON variant_option_values(option_id);
CREATE INDEX idx_variant_option_values_sort_order ON variant_option_values(sort_order);

-- Create indexes for product_variant_combinations
CREATE INDEX idx_product_variant_combinations_variant_id ON product_variant_combinations(variant_id);
CREATE INDEX idx_product_variant_combinations_option_id ON product_variant_combinations(option_id);
CREATE INDEX idx_product_variant_combinations_option_value_id ON product_variant_combinations(option_value_id);

-- Create indexes for updated tables
CREATE INDEX idx_products_has_variants ON products(has_variants);
CREATE INDEX idx_order_items_variant_id ON order_items(variant_id);

-- Create functions
CREATE OR REPLACE FUNCTION update_product_has_variants()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
        UPDATE products 
        SET has_variants = EXISTS(
            SELECT 1 FROM product_variants 
            WHERE product_id = NEW.product_id
        )
        WHERE id = NEW.product_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE products 
        SET has_variants = EXISTS(
            SELECT 1 FROM product_variants 
            WHERE product_id = OLD.product_id
        )
        WHERE id = OLD.product_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_product_price_range()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
        UPDATE products 
        SET 
            min_price = (SELECT MIN(price) FROM product_variants WHERE product_id = NEW.product_id AND status = 'active'),
            max_price = (SELECT MAX(price) FROM product_variants WHERE product_id = NEW.product_id AND status = 'active')
        WHERE id = NEW.product_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE products 
        SET 
            min_price = (SELECT MIN(price) FROM product_variants WHERE product_id = OLD.product_id AND status = 'active'),
            max_price = (SELECT MAX(price) FROM product_variants WHERE product_id = OLD.product_id AND status = 'active')
        WHERE id = OLD.product_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION ensure_one_default_variant()
RETURNS TRIGGER AS $$
BEGIN
    -- If this variant is being set as default, unset other defaults for this product
    IF NEW.is_default = true THEN
        UPDATE product_variants 
        SET is_default = false 
        WHERE product_id = NEW.product_id AND id != NEW.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers
CREATE TRIGGER trigger_update_product_has_variants
    AFTER INSERT OR UPDATE OR DELETE ON product_variants
    FOR EACH ROW EXECUTE FUNCTION update_product_has_variants();

CREATE TRIGGER trigger_update_product_price_range
    AFTER INSERT OR UPDATE OR DELETE ON product_variants
    FOR EACH ROW EXECUTE FUNCTION update_product_price_range();

CREATE TRIGGER trigger_ensure_one_default_variant
    BEFORE INSERT OR UPDATE ON product_variants
    FOR EACH ROW EXECUTE FUNCTION ensure_one_default_variant();

-- Enable RLS on new tables
ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE variant_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE variant_option_values ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_variant_combinations ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY "Anyone can view active product variants" ON product_variants FOR SELECT USING (status = 'active');
CREATE POLICY "Anyone can view variant options" ON variant_options FOR SELECT USING (true);
CREATE POLICY "Anyone can view variant option values" ON variant_option_values FOR SELECT USING (true);
CREATE POLICY "Anyone can view product variant combinations" ON product_variant_combinations FOR SELECT USING (true);

CREATE POLICY "Store owners can manage product variants" ON product_variants USING (
    product_id IN (SELECT id FROM products WHERE store_id IN (SELECT id FROM stores WHERE user_id = auth.uid()))
);
CREATE POLICY "Store owners can manage variant options" ON variant_options USING (
    store_id IN (SELECT id FROM stores WHERE user_id = auth.uid())
);
CREATE POLICY "Store owners can manage variant option values" ON variant_option_values USING (
    option_id IN (SELECT id FROM variant_options WHERE store_id IN (SELECT id FROM stores WHERE user_id = auth.uid()))
);
CREATE POLICY "Store owners can manage product variant combinations" ON product_variant_combinations USING (
    variant_id IN (SELECT id FROM product_variants WHERE product_id IN (SELECT id FROM products WHERE store_id IN (SELECT id FROM stores WHERE user_id = auth.uid())))
);

-- Grant permissions
GRANT ALL ON TABLE product_variants TO anon, authenticated, service_role;
GRANT ALL ON TABLE variant_options TO anon, authenticated, service_role;
GRANT ALL ON TABLE variant_option_values TO anon, authenticated, service_role;
GRANT ALL ON TABLE product_variant_combinations TO anon, authenticated, service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role; 