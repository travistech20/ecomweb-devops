-- Remove columns that will be handled by variants
ALTER TABLE products DROP COLUMN IF EXISTS price;
ALTER TABLE products DROP COLUMN IF EXISTS original_price;
ALTER TABLE products DROP COLUMN IF EXISTS inventory;
ALTER TABLE products DROP COLUMN IF EXISTS sold;
ALTER TABLE products DROP COLUMN IF EXISTS external_sku_id;

-- Remove promotion columns (can be handled at variant level if needed)
ALTER TABLE products DROP COLUMN IF EXISTS is_promotion;
ALTER TABLE products DROP COLUMN IF EXISTS promotion_price;
ALTER TABLE products DROP COLUMN IF EXISTS promotion_start_date;
ALTER TABLE products DROP COLUMN IF EXISTS promotion_end_date;

-- Remove category column (keep category_id)
ALTER TABLE products DROP COLUMN IF EXISTS category;