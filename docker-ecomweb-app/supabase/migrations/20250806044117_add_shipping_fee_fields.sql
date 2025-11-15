-- Migration: Add shipping_fee_enabled and shipping_fee_default to stores table
-- This migration adds shipping_fee_enabled and shipping_fee_default fields to the stores table
-- These fields will be used to control whether stores have shipping fees and what the default fee is

-- Add new columns to stores table
ALTER TABLE stores 
ADD COLUMN shipping_fee_enabled BOOLEAN DEFAULT true,
ADD COLUMN shipping_fee_default NUMERIC(12,2) DEFAULT 0;

-- Add comments for documentation
COMMENT ON COLUMN stores.shipping_fee_enabled IS 'Whether the store has shipping fees (true) or offers free shipping (false)';
COMMENT ON COLUMN stores.shipping_fee_default IS 'Default shipping fee amount for the store (in VND)';
