ALTER TABLE products ADD COLUMN variant_mode VARCHAR(20);

UPDATE products SET variant_mode = 'simple' WHERE variant_mode IS NULL;

ALTER TABLE products ALTER COLUMN variant_mode SET NOT NULL;