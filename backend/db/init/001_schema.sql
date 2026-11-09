CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE branches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  address text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL UNIQUE,
  password_hash text NOT NULL,
  role text NOT NULL CHECK (role IN ('owner', 'branch_admin')),
  branch_id uuid REFERENCES branches(id) ON DELETE RESTRICT,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((role = 'owner' AND branch_id IS NULL) OR (role = 'branch_admin' AND branch_id IS NOT NULL))
);

CREATE TABLE menu_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  category text NOT NULL,
  description text NOT NULL DEFAULT '',
  active boolean NOT NULL DEFAULT true,
  UNIQUE (name, category)
);

CREATE TABLE menu_sizes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  menu_item_id uuid NOT NULL REFERENCES menu_items(id) ON DELETE RESTRICT,
  name text NOT NULL,
  base_price numeric(12,2) NOT NULL CHECK (base_price > 0),
  active boolean NOT NULL DEFAULT true,
  UNIQUE (menu_item_id, name)
);

CREATE TABLE sales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
  recorded_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  order_group_id uuid NOT NULL DEFAULT gen_random_uuid(),
  customer_name text,
  customer_phone text,
  menu_size_id uuid NOT NULL REFERENCES menu_sizes(id) ON DELETE RESTRICT,
  quantity integer NOT NULL CHECK (quantity BETWEEN 1 AND 1000),
  unit_price numeric(12,2) NOT NULL CHECK (unit_price > 0),
  delivery_fee numeric(12,2) NOT NULL DEFAULT 0 CHECK (delivery_fee >= 0),
  total_amount numeric(14,2) NOT NULL CHECK (total_amount > 0),
  order_type text NOT NULL CHECK (order_type IN ('pickup', 'delivery')),
  payment_mode text NOT NULL CHECK (payment_mode IN ('cash', 'bank_transfer', 'personal_use')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE expense_heads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  active boolean NOT NULL DEFAULT true
);

CREATE TABLE expenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
  submitted_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  financial_head text NOT NULL,
  description text NOT NULL,
  amount numeric(14,2) NOT NULL CHECK (amount > 0),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'settled')),
  settlement_mode text CHECK (settlement_mode IN ('cash_adjustment', 'bank_transfer')),
  approved_by uuid REFERENCES users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  settled_at timestamptz,
  CHECK (
    (status = 'pending' AND settlement_mode IS NULL AND approved_by IS NULL AND settled_at IS NULL)
    OR (status = 'settled' AND settlement_mode IS NOT NULL AND approved_by IS NOT NULL AND settled_at IS NOT NULL)
  )
);

CREATE INDEX sales_branch_date_idx ON sales (branch_id, created_at DESC);
CREATE INDEX sales_order_group_idx ON sales (order_group_id);
CREATE INDEX expenses_branch_status_date_idx ON expenses (branch_id, status, created_at DESC);

CREATE TABLE audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id uuid REFERENCES users(id) ON DELETE SET NULL,
  branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_log_created_at_idx ON audit_log (created_at DESC);

INSERT INTO expense_heads (name) VALUES
  ('Ingredients'), ('Packaging'), ('Utilities'), ('Rent'),
  ('Delivery'), ('Maintenance'), ('Other')
ON CONFLICT (name) DO NOTHING;

INSERT INTO branches (name, address) VALUES
  ('Main Branch', 'Configure address'),
  ('North Branch', 'Configure address'),
  ('South Branch', 'Configure address')
ON CONFLICT (name) DO NOTHING;
