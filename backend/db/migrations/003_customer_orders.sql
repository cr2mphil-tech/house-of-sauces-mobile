ALTER TABLE sales
  ADD COLUMN IF NOT EXISTS order_group_id uuid NOT NULL DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS customer_name text,
  ADD COLUMN IF NOT EXISTS customer_phone text;

CREATE INDEX IF NOT EXISTS sales_order_group_idx ON sales (order_group_id);
