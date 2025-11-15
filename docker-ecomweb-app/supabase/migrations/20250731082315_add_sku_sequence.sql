-- Migration: Add SKU sequence for product variants
-- This migration adds a sequence for automatic SKU ID generation

-- Create sequence for SKU IDs starting from 1000 to avoid conflicts with existing data
CREATE SEQUENCE IF NOT EXISTS product_variants_sku_id_seq START WITH 1000 INCREMENT BY 1;

-- Update product_variants table to use sequence as default for sku_id
ALTER TABLE product_variants 
ALTER COLUMN sku_id SET DEFAULT nextval('product_variants_sku_id_seq');

-- Grant permissions
ALTER SEQUENCE product_variants_sku_id_seq OWNER TO postgres;

-- Add comment for documentation
COMMENT ON SEQUENCE product_variants_sku_id_seq IS 'Auto-incrementing sequence for product variant SKU IDs';