/*
# Fix storefront / admin schema mismatch

## Problem
The storefront (index-XgHM_wUN.js) queries `products` and `categories`
expecting columns that don't exist in the database:
  products: slug, origin, unit, short_description, rating, review_count,
            original_price, in_stock, is_featured, is_bestseller, category_id
  categories table: does not exist at all

The admin page (admin.html) manages products using a simpler set of
columns (product_id, name, category text, weight, price, mrp, stock,
image_url, description, is_active). So product edits made in admin
never reach the storefront because the storefront query
`select("*, category:categories(*)")` fails on missing columns/tables.

## Fix
1. Create a `categories` table (id, slug, name, sort_order, created_at).
2. Add the missing columns to `products`.
3. Add a BEFORE INSERT/UPDATE trigger `sync_storefront_fields` that
   auto-populates the storefront-only columns from the admin-managed
   columns so both pages work from one table without manual syncing:
     - slug            ← slugify(name) when null/empty
     - original_price  ← mrp
     - in_stock        ← stock > 0
     - unit            ← weight
     - short_description ← left(description, 150)
     - category_id     ← lookup/create categories row by category text
     - rating / review_count / origin / is_featured / is_bestseller
       get sensible defaults when null
4. Backfill existing rows so they show up immediately.
5. RLS on categories (same anon/authenticated public pattern).
*/

-- ── categories table ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text UNIQUE NOT NULL,
  name text NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_categories" ON categories;
CREATE POLICY "anon_select_categories"
  ON categories FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "anon_insert_categories" ON categories;
CREATE POLICY "anon_insert_categories"
  ON categories FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "anon_update_categories" ON categories;
CREATE POLICY "anon_update_categories"
  ON categories FOR UPDATE
  TO anon, authenticated
  USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_delete_categories" ON categories;
CREATE POLICY "anon_delete_categories"
  ON categories FOR DELETE
  TO anon, authenticated
  USING (true);

-- ── add missing columns to products ───────────────────────────
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS slug text,
  ADD COLUMN IF NOT EXISTS origin text,
  ADD COLUMN IF NOT EXISTS unit text,
  ADD COLUMN IF NOT EXISTS short_description text,
  ADD COLUMN IF NOT EXISTS rating numeric(2,1) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS review_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS original_price numeric(10,2),
  ADD COLUMN IF NOT EXISTS in_stock boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS is_featured boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_bestseller boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS category_id uuid REFERENCES categories(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_products_category_id ON products(category_id);
CREATE INDEX IF NOT EXISTS idx_products_slug ON products(slug);

-- ── sync function ──────────────────────────────────────────────
-- slugify helper
CREATE OR REPLACE FUNCTION slugify(input text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT lower(regexp_replace(regexp_replace(trim(input), '[^a-zA-Z0-9\s-]', '', 'g'), '\s+', '-', 'g'));
$$;

-- ensure a categories row exists for a given category text, return its id
CREATE OR REPLACE FUNCTION ensure_category(cat text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_slug text;
BEGIN
  IF cat IS NULL OR btrim(cat) = '' THEN
    RETURN NULL;
  END IF;
  v_slug := slugify(cat);
  SELECT id INTO v_id FROM categories WHERE slug = v_slug LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO categories (slug, name, sort_order)
    VALUES (v_slug, cat, 0)
    ON CONFLICT (slug) DO UPDATE SET name = EXCLUDED.name
    RETURNING id INTO v_id;
  END IF;
  RETURN v_id;
END;
$$;

-- main sync: populate storefront columns from admin columns
CREATE OR REPLACE FUNCTION sync_storefront_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- slug from name
  IF NEW.slug IS NULL OR btrim(NEW.slug) = '' THEN
    NEW.slug := slugify(NEW.name);
  END IF;

  -- original_price from mrp
  IF NEW.original_price IS NULL AND NEW.mrp IS NOT NULL THEN
    NEW.original_price := NEW.mrp;
  END IF;

  -- in_stock from stock
  NEW.in_stock := (NEW.stock IS NOT NULL AND NEW.stock > 0);

  -- unit from weight
  IF NEW.unit IS NULL AND NEW.weight IS NOT NULL THEN
    NEW.unit := NEW.weight;
  END IF;

  -- short_description from description
  IF (NEW.short_description IS NULL OR btrim(NEW.short_description) = '') AND NEW.description IS NOT NULL THEN
    NEW.short_description := left(NEW.description, 150);
  END IF;

  -- category_id from category text
  IF NEW.category_id IS NULL AND NEW.category IS NOT NULL AND btrim(NEW.category) <> '' THEN
    NEW.category_id := ensure_category(NEW.category);
  END IF;

  -- sensible defaults for storefront-only fields
  IF NEW.origin IS NULL THEN
    NEW.origin := 'Kashmir';
  END IF;
  IF NEW.rating IS NULL THEN
    NEW.rating := 0;
  END IF;
  IF NEW.review_count IS NULL THEN
    NEW.review_count := 0;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS products_sync_storefront ON products;
CREATE TRIGGER products_sync_storefront
  BEFORE INSERT OR UPDATE ON products
  FOR EACH ROW
  EXECUTE FUNCTION sync_storefront_fields();

-- ── backfill existing rows ─────────────────────────────────────
DO $$
DECLARE
  r record;
  v_cat_id uuid;
BEGIN
  FOR r IN SELECT id, category FROM products WHERE category IS NOT NULL AND btrim(category) <> '' LOOP
    v_cat_id := ensure_category(r.category);
    UPDATE products SET category_id = v_cat_id WHERE id = r.id AND category_id IS NULL;
  END LOOP;

  -- populate derived columns for all existing rows
  UPDATE products SET
    slug = COALESCE(NULLIF(slug, ''), slugify(name)),
    original_price = COALESCE(original_price, mrp),
    in_stock = (stock IS NOT NULL AND stock > 0),
    unit = COALESCE(unit, weight),
    short_description = COALESCE(NULLIF(short_description, ''), left(description, 150)),
    origin = COALESCE(origin, 'Kashmir'),
    rating = COALESCE(rating, 0),
    review_count = COALESCE(review_count, 0)
  WHERE true;
END;
$$;