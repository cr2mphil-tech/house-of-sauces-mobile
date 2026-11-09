ALTER TABLE sales
  DROP CONSTRAINT IF EXISTS sales_payment_mode_check;

ALTER TABLE sales
  ADD CONSTRAINT sales_payment_mode_check
  CHECK (payment_mode IN ('cash', 'bank_transfer', 'personal_use'));
