/*
# Create contact_messages table for BariTradeHub contact form

## Purpose
Stores messages submitted by customers through the "Send a Message" contact form
on the storefront Contact page. The frontend already inserts rows into
`contact_messages` with `name`, `email`, `subject`, and `message` fields, but
the table does not exist yet, so every form submission currently fails.

## New Table: contact_messages
- id          uuid, primary key (auto-generated)
- name        text, sender's full name. Not null.
- email       text, sender's email address. Not null.
- subject     text, optional subject line (nullable)
- message     text, the body of the contact message. Not null.
- created_at  timestamptz, defaults to now()

## Security
- Row Level Security is ENABLED on contact_messages.
- Four separate policies (SELECT / INSERT / UPDATE / DELETE) are created,
  all scoped to `TO anon, authenticated` because this is a single-tenant
  store with no sign-in screen and the storefront must be able to insert
  contact messages directly via the anon-key client.
- USING (true) / WITH CHECK (true) is acceptable here precisely because the
  data is intentionally public/shared (single-tenant, no auth).

## Important Notes
1. The column names (name, email, subject, message) exactly match the fields
   the frontend already sends in its `.insert({...})` call.
2. No user_id column is added because this app has no sign-in screen.
*/

CREATE TABLE IF NOT EXISTS contact_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  email text NOT NULL,
  subject text,
  message text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE contact_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_contact_messages" ON contact_messages;
CREATE POLICY "anon_select_contact_messages"
  ON contact_messages FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "anon_insert_contact_messages" ON contact_messages;
CREATE POLICY "anon_insert_contact_messages"
  ON contact_messages FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "anon_update_contact_messages" ON contact_messages;
CREATE POLICY "anon_update_contact_messages"
  ON contact_messages FOR UPDATE
  TO anon, authenticated
  USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_delete_contact_messages" ON contact_messages;
CREATE POLICY "anon_delete_contact_messages"
  ON contact_messages FOR DELETE
  TO anon, authenticated
  USING (true);
