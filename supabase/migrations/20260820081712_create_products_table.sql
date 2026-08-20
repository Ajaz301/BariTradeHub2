/*
# Create products table for BariTradeHub store

## Purpose
Stores the catalog of Kashmiri dry fruits and saffron products sold on
BariTradeHub. This is a single-tenant store with no sign-in screen, so the
anon-key frontend (both the storefront and the admin page) must be able to
read and write product rows directly.

## New Table: products
- id            uuid, primary key (auto-generated)
- product_id    text, human-readable store SKU (e.g. "BTH-WAL-500"). Unique.
- name          text, product display name (e.g. "Kashmiri Walnuts"). Not null.
- category      text, grouping label (e.g. "Dry Fruits", "Saffron")
- weight        text, pack size as a free-text string (e.g. "500g", "1kg")
- price         numeric(10,2), selling price in INR. Not null. Must be >= 0.
- mrp           numeric(10,2), optional original price for showing discounts
- stock         integer, units available. Defaults to 0. Must be >= 0.
- image_url     text, optional product photo URL
- description   text, optional long description
- is_active     boolean, whether the product shows on the storefront. Default true.
- created_at    timestamptz, defaults to now()
- updated_at    timestamptz, defaults to now()

## Security
- Row Level Security is ENABLED on products.
- Four separate policies (SELECT / INSERT / UPDATE / DELETE) are created,
  all scoped to `TO anon, authenticated` because this is a single-tenant
  store with no sign-in screen and the data is intentionally shared between
  the storefront and the admin page.
- USING (true) / WITH CHECK (true) is acceptable here precisely because the
  data is intentionally public/shared (single-tenant, no auth).

## Important Notes
1. price and mrp are NUMERIC(10,2) so money is stored exactly, not as float.
2. CHECK constraints enforce non-negative prices and stock.
3. updated_at is refreshed automatically via a trigger so callers never
   need to set it manually.
4. A unique constraint on product_id prevents duplicate SKUs.
*/

CREATE TABLE IF NOT EXISTS products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id text UNIQUE NOT NULL,
  name text NOT NULL,
  category text,
  weight text,
  price numeric(10,2) NOT NULL DEFAULT 0 CHECK (price >= 0),
  mrp numeric(10,2) CHECK (mrp IS NULL OR mrp >= 0),
  stock integer NOT NULL DEFAULT 0 CHECK (stock >= 0),
  image_url text,
  description text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE products ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_products" ON products;
CREATE POLICY "anon_select_products"
  ON products FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "anon_insert_products" ON products;
CREATE POLICY "anon_insert_products"
  ON products FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "anon_update_products" ON products;
CREATE POLICY "anon_update_products"
  ON products FOR UPDATE
  TO anon, authenticated
  USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_delete_products" ON products;
CREATE POLICY "anon_delete_products"
  ON products FOR DELETE
  TO anon, authenticated
  USING (true);

-- Auto-refresh updated_at on every row update
CREATE OR REPLACE FUNCTION refresh_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS products_updated_at ON products;
CREATE TRIGGER products_updated_at
  BEFORE UPDATE ON products
  FOR EACH ROW
  EXECUTE FUNCTION refresh_updated_at();
