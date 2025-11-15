-- Migration: Add social media links to stores table
-- This migration adds tiktok_link and shopee_link fields to the stores table

-- Add new columns to stores table
ALTER TABLE stores 
ADD COLUMN tiktok_link TEXT,
ADD COLUMN shopee_link TEXT;

-- Add comments for documentation
COMMENT ON COLUMN stores.tiktok_link IS 'TikTok profile or shop link for the store';
COMMENT ON COLUMN stores.shopee_link IS 'Shopee shop link for the store'; 