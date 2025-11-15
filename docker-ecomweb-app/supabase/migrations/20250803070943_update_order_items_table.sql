-- Migration: Complete Order Items Adaptation to Product Variants
-- This migration adds the missing variant_name column to order_items table

-- Add variant_name column to order_items table
ALTER TABLE order_items ADD COLUMN variant_name TEXT;
