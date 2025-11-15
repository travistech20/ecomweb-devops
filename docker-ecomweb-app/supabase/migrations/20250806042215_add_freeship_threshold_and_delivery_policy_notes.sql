-- Migration: Add freeship_threshold and delivery_policy_notes to stores table
-- This migration adds freeship_threshold and delivery_policy_notes fields to the stores table
-- These fields will be used in the checkout page to display shipping information and policies

-- Add new columns to stores table
ALTER TABLE stores 
ADD COLUMN freeship_threshold NUMERIC(12,2) DEFAULT 500000,
ADD COLUMN delivery_policy_notes TEXT;

-- Add comments for documentation
COMMENT ON COLUMN stores.freeship_threshold IS 'Minimum order amount for free shipping (in VND)';
COMMENT ON COLUMN stores.delivery_policy_notes IS 'Delivery policy notes and information to display on checkout page';
