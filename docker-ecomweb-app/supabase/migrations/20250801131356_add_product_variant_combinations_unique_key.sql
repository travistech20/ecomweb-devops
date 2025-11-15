-- create unique key for product_variant_combinations
ALTER TABLE product_variant_combinations ADD CONSTRAINT product_variant_combinations_unique_key UNIQUE (variant_id, option_id, option_value_id);