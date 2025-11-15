-- Migration: Simplify Variant Options Structure
-- This migration removes the type and display_name columns from variant_options and ensures variant_option_values
-- always have both value and optional image_url

-- 1. Remove the type column from variant_options table
ALTER TABLE variant_options DROP COLUMN IF EXISTS type;

-- 2. Remove the display_name column from variant_options table
ALTER TABLE variant_options DROP COLUMN IF EXISTS display_name;

-- 3. Make value NOT NULL since it's always required
ALTER TABLE variant_option_values ALTER COLUMN value SET NOT NULL;

-- 4. Make image_url NOT NULL with default empty string since it's always required
ALTER TABLE variant_option_values ALTER COLUMN image_url SET NOT NULL;
ALTER TABLE variant_option_values ALTER COLUMN image_url SET DEFAULT '';

-- 5. Remove color_code column since we're simplifying to just text and image
ALTER TABLE variant_option_values DROP COLUMN IF EXISTS color_code;

-- 6. Update any existing NULL image_url values to empty string
UPDATE variant_option_values SET image_url = '' WHERE image_url IS NULL;

-- 7. Update any existing NULL value values to display_value if value is NULL
UPDATE variant_option_values SET value = display_value WHERE value IS NULL OR value = '';

-- 8. Add a new index for value for better query performance
CREATE INDEX idx_variant_option_values_value ON variant_option_values(value);

-- 9. Add a new index for image_url for better query performance
CREATE INDEX idx_variant_option_values_image_url ON variant_option_values(image_url);

-- 10. Add a check constraint to ensure value is not empty
ALTER TABLE variant_option_values ADD CONSTRAINT check_value_not_empty 
    CHECK (value != '');

-- 11. Update any existing data to ensure consistency
-- Set empty image_url to empty string if NULL
UPDATE variant_option_values SET image_url = '' WHERE image_url IS NULL;

-- Set value to display_value if value is empty or NULL
UPDATE variant_option_values SET value = display_value 
WHERE value IS NULL OR value = '';

-- 12. Add a comment to document the simplified structure
COMMENT ON TABLE variant_options IS 'Simplified variant options without type and display_name - all options support both text and image values';
COMMENT ON TABLE variant_option_values IS 'Variant option values with both value and optional image_url';
COMMENT ON COLUMN variant_option_values.value IS 'The text value for this option (e.g., "Red", "XL")';
COMMENT ON COLUMN variant_option_values.image_url IS 'The image URL for this option (can be empty string)';
COMMENT ON COLUMN variant_option_values.display_value IS 'The display text for this option (e.g., "Red", "Extra Large")'; 