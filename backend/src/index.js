import express from 'express';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import pg from 'pg';
import { z } from 'zod';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';

const { Pool } = pg;
const required = ['DATABASE_URL', 'JWT_SECRET', 'OWNER_EMAIL', 'OWNER_PASSWORD'];
for (const name of required) {
  if (!process.env[name]) throw new Error(`${name} must be configured`);
}
if (Boolean(process.env.ADDITIONAL_OWNER_EMAIL) !== Boolean(process.env.ADDITIONAL_OWNER_PASSWORD)) {
  throw new Error('ADDITIONAL_OWNER_EMAIL and ADDITIONAL_OWNER_PASSWORD must be configured together');
}
if (process.env.JWT_SECRET.length < 32) throw new Error('JWT_SECRET must be at least 32 characters');

const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const app = express();
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 30,
  standardHeaders: true,
  legacyHeaders: false,
});
app.disable('x-powered-by');
app.use(helmet());
app.use(express.json({ limit: '5mb' }));

const fail = (res, status, message) => res.status(status).json({ error: message });
const asyncRoute = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
const emailSchema = z.string().email().max(254);
const loginSchema = z.object({ email: emailSchema, password: z.string().min(1).max(200) });

app.get('/', (_req, res) => {
  res.type('html').send(`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>House of Sauces · Local API</title>
  <style>
    body{font:16px/1.5 system-ui,sans-serif;background:#f8f6f2;color:#292522;margin:0;padding:40px 20px}
    main{max-width:620px;margin:8vh auto;background:white;border-radius:20px;padding:32px;box-shadow:0 8px 32px #30201016}
    h1{color:#b63a27;margin-bottom:8px}a{color:#96331f}code{background:#f4eee8;padding:3px 6px;border-radius:5px}
    li{margin:10px 0}.pill{display:inline-block;border-radius:20px;background:#e8f5e9;color:#216b31;padding:4px 12px}
  </style>
</head>
<body>
  <main>
    <h1>House of Sauces</h1>
    <p><span class="pill">Local API is running</span></p>
    <p>This address serves the backend API, not the Flutter mobile interface.</p>
    <ul>
      <li><a href="/health">Check API health</a></li>
      <li>Android emulator API base: <code>http://10.0.2.2:3001/api</code></li>
      <li>Owner login email: <code>owner@hos.com</code></li>
    </ul>
    <p>To open the mobile app, install Flutter and Android Studio, then run <code>flutter run</code> from the project's <code>mobile</code> folder with an emulator connected.</p>
  </main>
</body>
</html>`);
});

async function authenticate(req, res, next) {
  const [scheme, token] = (req.get('authorization') || '').split(' ');
  if (scheme !== 'Bearer' || !token) return fail(res, 401, 'Authentication required');
  try {
    const claims = jwt.verify(token, process.env.JWT_SECRET);
    const result = await pool.query(
      'SELECT id, email, role, branch_id, active FROM users WHERE id = $1',
      [claims.sub],
    );
    const user = result.rows[0];
    if (!user || !user.active || user.role !== claims.role) return fail(res, 401, 'Invalid session');
    req.user = user;
    next();
  } catch (error) {
    if (error instanceof jwt.JsonWebTokenError || error instanceof jwt.TokenExpiredError) {
      return fail(res, 401, 'Invalid or expired session');
    }
    next(error);
  }
}
const ownerOnly = (req, res, next) => req.user.role === 'owner'
  ? next()
  : fail(res, 403, 'Owner access required');
const scopeBranch = (req) => req.user.role === 'owner'
  ? (req.query.branchId || req.body?.branchId || null)
  : req.user.branch_id;

app.get('/health', asyncRoute(async (_req, res) => {
  await pool.query('SELECT 1');
  res.json({ status: 'ok' });
}));

app.post('/api/auth/login', loginLimiter, asyncRoute(async (req, res) => {
  const parsed = loginSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Enter a valid email and password');
  const result = await pool.query(
    'SELECT id, email, password_hash, role, branch_id, active FROM users WHERE email = lower($1)',
    [parsed.data.email],
  );
  const user = result.rows[0];
  if (!user || !user.active || !(await bcrypt.compare(parsed.data.password, user.password_hash))) {
    return fail(res, 401, 'Invalid email or password');
  }
  const token = jwt.sign(
    { role: user.role },
    process.env.JWT_SECRET,
    { subject: user.id, expiresIn: process.env.JWT_EXPIRES_IN || '8h' },
  );
  res.json({
    token,
    user: { id: user.id, email: user.email, role: user.role, branchId: user.branch_id },
  });
}));

app.get('/api/auth/me', authenticate, (req, res) => res.json({
  id: req.user.id, email: req.user.email, role: req.user.role, branchId: req.user.branch_id,
}));

app.get('/api/branches', authenticate, asyncRoute(async (req, res) => {
  const result = req.user.role === 'owner'
    ? await pool.query('SELECT id, name, address, active FROM branches ORDER BY name')
    : await pool.query('SELECT id, name, address, active FROM branches WHERE id = $1', [req.user.branch_id]);
  res.json(result.rows);
}));

app.post('/api/branches', authenticate, ownerOnly, asyncRoute(async (req, res) => {
  const parsed = z.object({ name: z.string().trim().min(1).max(120), address: z.string().trim().max(300).optional() }).safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Branch name is required');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await client.query(
      'INSERT INTO branches (name, address) VALUES ($1, $2) RETURNING id, name, address, active',
      [parsed.data.name, parsed.data.address || null],
    );
    await client.query(
      `INSERT INTO audit_log (actor_id, branch_id, action, entity_type, entity_id)
       VALUES ($1, $2, 'branch.created', 'branch', $2)`,
      [req.user.id, result.rows[0].id],
    );
    await client.query('COMMIT');
    res.status(201).json(result.rows[0]);
  } catch (error) {
    await client.query('ROLLBACK');
    if (error.code === '23505') return fail(res, 409, 'Branch name already exists');
    throw error;
  } finally { client.release(); }
}));

app.post('/api/users', authenticate, ownerOnly, asyncRoute(async (req, res) => {
  const parsed = z.object({
    email: emailSchema, password: z.string().min(12).max(200),
    branchId: z.string().uuid(), role: z.literal('branch_admin').default('branch_admin'),
  }).safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Provide a valid email, 12+ character password and branch ID');
  const hash = await bcrypt.hash(parsed.data.password, 12);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await client.query(
      `INSERT INTO users (email, password_hash, role, branch_id)
       VALUES (lower($1), $2, 'branch_admin', $3)
       RETURNING id, email, role, branch_id`,
      [parsed.data.email, hash, parsed.data.branchId],
    );
    await client.query(
      `INSERT INTO audit_log (actor_id, branch_id, action, entity_type, entity_id, details)
       VALUES ($1, $2, 'user.created', 'user', $3, $4::jsonb)`,
      [req.user.id, parsed.data.branchId, result.rows[0].id, JSON.stringify({ email: result.rows[0].email, role: result.rows[0].role })],
    );
    await client.query('COMMIT');
    res.status(201).json(result.rows[0]);
  } catch (error) {
    await client.query('ROLLBACK');
    if (error.code === '23503') return fail(res, 400, 'Branch not found');
    if (error.code === '23505') return fail(res, 409, 'Email is already registered');
    throw error;
  } finally { client.release(); }
}));

app.get('/api/users', authenticate, ownerOnly, asyncRoute(async (req, res) => {
  const parsed = z.object({ branchId: z.string().uuid().optional() }).safeParse(req.query);
  if (!parsed.success) return fail(res, 400, 'Provide a valid branch ID');
  const result = await pool.query(
    `SELECT id, email, role, branch_id, active, created_at
     FROM users
     WHERE role = 'branch_admin'
       AND ($1::uuid IS NULL OR branch_id = $1)
     ORDER BY branch_id, email`,
    [parsed.data.branchId || null],
  );
  res.json(result.rows);
}));

app.patch('/api/users/:id', authenticate, ownerOnly, asyncRoute(async (req, res) => {
  const parsedId = z.string().uuid().safeParse(req.params.id);
  if (!parsedId.success) return fail(res, 400, 'Provide a valid account ID');
  const parsed = z.object({
    email: emailSchema.optional(),
    password: z.string().min(12).max(200).optional(),
    branchId: z.string().uuid().optional(),
    active: z.boolean().optional(),
  }).refine((value) => Object.keys(value).length > 0, {
    message: 'Provide at least one account field to update',
  }).safeParse(req.body);
  if (!parsed.success) {
    return fail(res, 400, 'Provide a valid email, 12+ character password, branch ID, or active status');
  }
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const current = await client.query(
      `SELECT id, email, branch_id, active FROM users
       WHERE id = $1 AND role = 'branch_admin'
       FOR UPDATE`,
      [parsedId.data],
    );
    if (!current.rowCount) {
      await client.query('ROLLBACK');
      return fail(res, 404, 'Active branch admin account not found');
    }
    const updates = parsed.data;
    const passwordHash = updates.password
      ? await bcrypt.hash(updates.password, 12)
      : null;
    const result = await client.query(
      `UPDATE users
       SET email = COALESCE(lower($2), email),
           password_hash = COALESCE($3, password_hash),
           branch_id = COALESCE($4, branch_id),
           active = COALESCE($5, active)
       WHERE id = $1
       RETURNING id, email, role, branch_id, active, created_at`,
      [
        parsedId.data,
        updates.email || null,
        passwordHash,
        updates.branchId || null,
        updates.active ?? null,
      ],
    );
    const previous = current.rows[0];
    await client.query(
      `INSERT INTO audit_log (actor_id, branch_id, action, entity_type, entity_id, details)
       VALUES ($1, $2, $3, 'user', $4, $5::jsonb)`,
      [
        req.user.id,
        previous.branch_id,
        updates.active === false
          ? 'user.disabled'
          : updates.active === true
              ? 'user.enabled'
              : 'user.updated',
        parsedId.data,
        JSON.stringify({
          emailChanged: updates.email !== undefined,
          branchChanged: updates.branchId !== undefined,
          passwordReset: updates.password !== undefined,
          activeChanged: updates.active !== undefined,
          active: result.rows[0].active,
          previousEmail: previous.email,
          email: result.rows[0].email,
          previousBranchId: previous.branch_id,
          branchId: result.rows[0].branch_id,
        }),
      ],
    );
    await client.query('COMMIT');
    res.json(result.rows[0]);
  } catch (error) {
    await client.query('ROLLBACK');
    if (error.code === '23503') return fail(res, 400, 'Branch not found');
    if (error.code === '23505') return fail(res, 409, 'Email is already registered');
    throw error;
  } finally { client.release(); }
}));

app.patch('/api/menu/sizes/:id', authenticate, ownerOnly, asyncRoute(async (req, res) => {
  const parsed = z.object({
    price: z.number().positive().max(100000),
  }).safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Provide a valid positive menu price');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const updated = await client.query(
      `UPDATE menu_sizes ms
       SET base_price = $1
       FROM menu_items mi
       WHERE ms.id = $2 AND ms.menu_item_id = mi.id AND ms.active AND mi.active
       RETURNING ms.id, ms.name AS size_name, ms.base_price, mi.id AS menu_item_id,
                 mi.name AS product_name, mi.category`,
      [parsed.data.price, req.params.id],
    );
    if (!updated.rowCount) {
      await client.query('ROLLBACK');
      return fail(res, 404, 'Active menu price variant not found');
    }
    await client.query(
      `INSERT INTO audit_log (actor_id, action, entity_type, entity_id, details)
       VALUES ($1, 'menu.price_updated', 'menu_size', $2, $3::jsonb)`,
      [
        req.user.id,
        updated.rows[0].id,
        JSON.stringify({
          product: updated.rows[0].product_name,
          category: updated.rows[0].category,
          size: updated.rows[0].size_name,
          price: updated.rows[0].base_price,
        }),
      ],
    );
    await client.query('COMMIT');
    res.json(updated.rows[0]);
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}));

app.get('/api/menu', authenticate, asyncRoute(async (_req, res) => {
  const result = await pool.query(
    `SELECT m.id, m.name, m.category, m.description, m.active,
            COALESCE(json_agg(json_build_object('id', s.id, 'name', s.name, 'price', s.base_price))
              FILTER (WHERE s.id IS NOT NULL), '[]') AS sizes
     FROM menu_items m LEFT JOIN menu_sizes s ON s.menu_item_id = m.id AND s.active
     WHERE m.active GROUP BY m.id ORDER BY m.category, m.name`,
  );
  res.json(result.rows);
}));

app.post('/api/menu', authenticate, ownerOnly, asyncRoute(async (req, res) => {
  const parsed = z.object({
    name: z.string().trim().min(1).max(120), category: z.string().trim().min(1).max(80),
    description: z.string().trim().max(500).default(''),
    sizes: z.array(z.object({ name: z.string().trim().min(1).max(40), price: z.number().positive().max(100000) })).min(1),
  }).superRefine((product, context) => {
    const names = new Set();
    product.sizes.forEach((size, index) => {
      const key = size.name.toLowerCase();
      if (names.has(key)) {
        context.addIssue({
          code: 'custom',
          path: ['sizes', index, 'name'],
          message: 'Size names must be unique for a product',
        });
      }
      names.add(key);
    });
  }).safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Provide a product name, category and at least one valid size and price');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const item = await client.query(
      'INSERT INTO menu_items (name, category, description) VALUES ($1, $2, $3) RETURNING id, name, category, description',
      [parsed.data.name, parsed.data.category, parsed.data.description],
    );
    for (const size of parsed.data.sizes) {
      await client.query('INSERT INTO menu_sizes (menu_item_id, name, base_price) VALUES ($1, $2, $3)',
        [item.rows[0].id, size.name, size.price]);
    }
    await client.query(
      `INSERT INTO audit_log (actor_id, action, entity_type, entity_id, details)
       VALUES ($1, 'menu.created', 'menu_item', $2, $3::jsonb)`,
      [req.user.id, item.rows[0].id, JSON.stringify({ name: item.rows[0].name, category: item.rows[0].category })],
    );
    await client.query('COMMIT');
    res.status(201).json(item.rows[0]);
  } catch (error) {
    await client.query('ROLLBACK');
    if (error.code === '23505') return fail(res, 409, 'A menu item or size already exists');
    throw error;
  } finally { client.release(); }
}));

app.post('/api/menu/import', authenticate, ownerOnly, asyncRoute(async (req, res) => {
  const parsed = z.object({
    records: z.array(z.object({
      name: z.string().trim().min(1).max(120),
      category: z.string().trim().min(1).max(80),
      description: z.string().trim().max(500).default(''),
      size: z.string().trim().min(1).max(40),
      price: z.number().positive().max(100000),
      active: z.boolean().default(true),
    })).min(1).max(5000),
  }).safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Provide up to 5,000 valid menu rows');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const touchedItems = new Set();
    for (const row of parsed.data.records) {
      const item = await client.query(
        `INSERT INTO menu_items (name, category, description, active) VALUES ($1, $2, $3, TRUE)
         ON CONFLICT (name, category) DO UPDATE
           SET active = TRUE,
               description = CASE WHEN EXCLUDED.description <> '' THEN EXCLUDED.description
                                  ELSE menu_items.description END
         RETURNING id`,
        [row.name, row.category, row.description],
      );
      touchedItems.add(item.rows[0].id);
      await client.query(
        `INSERT INTO menu_sizes (menu_item_id, name, base_price, active) VALUES ($1, $2, $3, $4)
         ON CONFLICT (menu_item_id, name) DO UPDATE SET base_price = EXCLUDED.base_price, active = EXCLUDED.active`,
        [item.rows[0].id, row.size, row.price, row.active],
      );
    }
    await client.query(
      `UPDATE menu_items m
       SET active = EXISTS (
         SELECT 1 FROM menu_sizes s WHERE s.menu_item_id = m.id AND s.active
       )
       WHERE m.id = ANY($1::uuid[])`,
      [Array.from(touchedItems)],
    );
    await client.query(
      `INSERT INTO audit_log (actor_id, action, entity_type, details)
       VALUES ($1, 'menu.imported', 'menu', $2::jsonb)`,
      [req.user.id, JSON.stringify({ importedRows: parsed.data.records.length })],
    );
    await client.query('COMMIT');
    res.json({ imported: parsed.data.records.length });
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally { client.release(); }
}));

app.get('/api/expense-heads', authenticate, asyncRoute(async (_req, res) => {
  const result = await pool.query('SELECT name FROM expense_heads WHERE active ORDER BY name');
  res.json(result.rows.map((row) => row.name));
}));

app.get('/api/sales', authenticate, asyncRoute(async (req, res) => {
  const filters = z.object({
    paymentMode: z.enum(['cash', 'bank_transfer', 'personal_use']).optional(),
    orderType: z.enum(['pickup', 'delivery']).optional(),
    category: z.string().trim().min(1).max(80).optional(),
  }).safeParse(req.query);
  if (!filters.success) return fail(res, 400, 'Provide a valid payment mode, order type, or product category');
  const branchId = scopeBranch(req);
  const result = await pool.query(
    `SELECT s.id, s.order_group_id, s.customer_name, s.customer_phone,
            s.branch_id, b.name AS branch_name, s.order_type, s.payment_mode, s.quantity, s.unit_price,
            s.delivery_fee, s.total_amount, s.created_at, m.name AS pizza_name, m.category,
            m.description, ms.name AS size_name
     FROM sales s JOIN branches b ON b.id = s.branch_id
     JOIN menu_sizes ms ON ms.id = s.menu_size_id JOIN menu_items m ON m.id = ms.menu_item_id
     WHERE ($1::uuid IS NULL OR s.branch_id = $1)
       AND ($2::timestamptz IS NULL OR s.created_at >= $2)
       AND ($3::timestamptz IS NULL OR s.created_at < $3)
       AND ($4::uuid IS NULL OR s.menu_size_id = $4)
       AND ($5::text IS NULL OR s.payment_mode = $5)
       AND ($6::text IS NULL OR s.order_type = $6)
       AND ($7::text IS NULL OR m.category = $7)
     ORDER BY s.created_at DESC LIMIT 1000`,
    [
      branchId,
      req.query.from || null,
      req.query.to || null,
      req.query.menuSizeId || null,
      filters.data.paymentMode || null,
      filters.data.orderType || null,
      filters.data.category || null,
    ],
  );
  res.json(result.rows);
}));

app.post('/api/sales', authenticate, asyncRoute(async (req, res) => {
  const parsed = z.object({
    items: z.array(z.object({
      menuSizeId: z.string().uuid(),
      quantity: z.number().int().min(1).max(1000),
    })).min(1).max(100).optional(),
    menuSizeId: z.string().uuid().optional(),
    quantity: z.number().int().min(1).max(1000).optional(),
    orderType: z.enum(['pickup', 'delivery']),
    paymentMode: z.enum(['cash', 'bank_transfer', 'personal_use']),
    deliveryFee: z.number().min(0).max(100000).default(0),
    customerName: z.string().trim().max(120).optional(),
    customerPhone: z.string().trim().regex(/^[0-9+() -]{7,40}$/).optional(),
    branchId: z.string().uuid().optional(),
  }).superRefine((order, context) => {
    if (!order.items && (!order.menuSizeId || !order.quantity)) {
      context.addIssue({ code: 'custom', message: 'Add at least one product to the order' });
    }
    if (order.orderType === 'delivery') {
      if (!order.customerName) {
        context.addIssue({ code: 'custom', path: ['customerName'], message: 'Customer name is required for delivery' });
      }
      if (!order.customerPhone) {
        context.addIssue({ code: 'custom', path: ['customerPhone'], message: 'Customer phone is required for delivery' });
      }
    } else if (order.deliveryFee !== 0) {
      context.addIssue({ code: 'custom', path: ['deliveryFee'], message: 'Pick-up orders cannot include delivery charges' });
    }
  }).safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Provide valid order items, order type and payment mode; delivery requires customer name and phone');
  const branchId = req.user.role === 'owner' ? req.body.branchId : req.user.branch_id;
  if (!branchId) return fail(res, 400, 'Branch is required');
  if (req.user.role === 'owner' && !req.body.branchId) return fail(res, 400, 'Branch is required');
  const items = parsed.data.items ?? [{
    menuSizeId: parsed.data.menuSizeId,
    quantity: parsed.data.quantity,
  }];
  const orderGroupId = randomUUID();
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = [];
    for (const [index, item] of items.entries()) {
      const deliveryFee = parsed.data.orderType === 'delivery' && index === 0
        ? parsed.data.deliveryFee
        : 0;
      const inserted = await client.query(
        `INSERT INTO sales (
           branch_id, recorded_by, order_group_id, customer_name, customer_phone,
           menu_size_id, quantity, unit_price, delivery_fee, total_amount, order_type, payment_mode
         )
         SELECT $1, $2, $3, $4, $5, ms.id, $6::integer, ms.base_price, $7,
                ms.base_price * $6::integer + $7, $8, $9
         FROM menu_sizes ms WHERE ms.id = $10 AND ms.active
         RETURNING id, branch_id, order_group_id, customer_name, customer_phone,
                   menu_size_id, quantity, unit_price, delivery_fee, total_amount,
                   order_type, payment_mode, created_at`,
        [
          branchId,
          req.user.id,
          orderGroupId,
          parsed.data.orderType === 'delivery' ? parsed.data.customerName : null,
          parsed.data.orderType === 'delivery' ? parsed.data.customerPhone : null,
          item.quantity,
          deliveryFee,
          parsed.data.orderType,
          parsed.data.paymentMode,
          item.menuSizeId,
        ],
      );
      if (!inserted.rowCount) {
        await client.query('ROLLBACK');
        return fail(res, 404, 'One or more active menu sizes were not found');
      }
      result.push(inserted.rows[0]);
    }
    await client.query(
      `INSERT INTO audit_log (actor_id, branch_id, action, entity_type, entity_id, details)
       VALUES ($1, $2, 'sale.recorded', 'sales_order', $3, $4::jsonb)`,
      [
        req.user.id,
        branchId,
        orderGroupId,
        JSON.stringify({ itemCount: result.length, orderType: parsed.data.orderType }),
      ],
    );
    await client.query('COMMIT');
    res.status(201).json(result);
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}));

app.get('/api/expenses', authenticate, asyncRoute(async (req, res) => {
  const result = await pool.query(
    `SELECT e.id, e.branch_id, b.name AS branch_name, e.financial_head, e.description, e.amount, e.status,
            e.settlement_mode, e.created_at, e.settled_at, u.email AS submitted_by
     FROM expenses e JOIN branches b ON b.id = e.branch_id JOIN users u ON u.id = e.submitted_by
     WHERE ($1::uuid IS NULL OR e.branch_id = $1) AND ($2::text IS NULL OR e.status = $2)
       AND ($3::timestamptz IS NULL OR e.created_at >= $3)
       AND ($4::timestamptz IS NULL OR e.created_at < $4)
     ORDER BY e.created_at DESC LIMIT 1000`,
    [scopeBranch(req), req.query.status || null, req.query.from || null, req.query.to || null],
  );
  res.json(result.rows);
}));

app.post('/api/expenses', authenticate, asyncRoute(async (req, res) => {
  const parsed = z.object({
    financialHead: z.string().trim().min(1).max(80),
    description: z.string().trim().min(1).max(500),
    amount: z.number().positive().max(10000000),
  }).safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Provide a financial head, description and valid amount');
  const branchId = req.user.role === 'owner' ? req.body.branchId : req.user.branch_id;
  if (!branchId) return fail(res, 400, 'Branch is required');
  if (req.user.role === 'owner' && !req.body.branchId) return fail(res, 400, 'Branch is required');
  const head = await pool.query('SELECT name FROM expense_heads WHERE name = $1 AND active', [parsed.data.financialHead]);
  if (!head.rowCount) return fail(res, 400, 'Choose a predefined financial head');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await client.query(
      `INSERT INTO expenses (branch_id, submitted_by, financial_head, description, amount)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, branch_id, financial_head, description, amount, status, created_at`,
      [branchId, req.user.id, parsed.data.financialHead, parsed.data.description, parsed.data.amount],
    );
    await client.query(
      `INSERT INTO audit_log (actor_id, branch_id, action, entity_type, entity_id)
       VALUES ($1, $2, 'expense.submitted', 'expense', $3)`,
      [req.user.id, branchId, result.rows[0].id],
    );
    await client.query('COMMIT');
    res.status(201).json(result.rows[0]);
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}));

app.post('/api/expenses/:id/settle', authenticate, ownerOnly, asyncRoute(async (req, res) => {
  const parsed = z.object({ settlementMode: z.enum(['cash_adjustment', 'bank_transfer']) }).safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Settlement mode must be cash_adjustment or bank_transfer');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const expense = await client.query('SELECT * FROM expenses WHERE id = $1 FOR UPDATE', [req.params.id]);
    if (!expense.rowCount) {
      await client.query('ROLLBACK');
      return fail(res, 404, 'Expense not found');
    }
    if (expense.rows[0].status !== 'pending') {
      await client.query('ROLLBACK');
      return fail(res, 409, 'Expense is no longer pending');
    }
    if (parsed.data.settlementMode === 'cash_adjustment') {
      await client.query('SELECT id FROM branches WHERE id = $1 FOR UPDATE', [expense.rows[0].branch_id]);
      const cash = await client.query(
        `SELECT COALESCE(SUM(total_amount) FILTER (WHERE payment_mode = 'cash'), 0) -
                COALESCE((SELECT SUM(amount) FROM expenses WHERE branch_id = $1 AND status = 'settled'
                          AND settlement_mode = 'cash_adjustment'
                          AND settled_at >= date_trunc('day', NOW())), 0) AS available
         FROM sales WHERE branch_id = $1 AND created_at >= date_trunc('day', NOW())`,
        [expense.rows[0].branch_id],
      );
      if (Number(cash.rows[0].available) < Number(expense.rows[0].amount)) {
        await client.query('ROLLBACK');
        return fail(res, 409, 'Insufficient recorded branch cash receipts for this settlement');
      }
    }
    const updated = await client.query(
      `UPDATE expenses SET status = 'settled', settlement_mode = $2, approved_by = $3, settled_at = now()
       WHERE id = $1 RETURNING id, branch_id, amount, status, settlement_mode, settled_at`,
      [req.params.id, parsed.data.settlementMode, req.user.id],
    );
    await client.query(
      `INSERT INTO audit_log (actor_id, branch_id, action, entity_type, entity_id, details)
       VALUES ($1, $2, 'expense.settled', 'expense', $3, $4::jsonb)`,
      [req.user.id, expense.rows[0].branch_id, req.params.id, JSON.stringify({ settlementMode: parsed.data.settlementMode })],
    );
    await client.query('COMMIT');
    res.json(updated.rows[0]);
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally { client.release(); }
}));

app.get('/api/analytics/summary', authenticate, asyncRoute(async (req, res) => {
  const filters = z.object({
    paymentMode: z.enum(['cash', 'bank_transfer', 'personal_use']).optional(),
    orderType: z.enum(['pickup', 'delivery']).optional(),
    category: z.string().trim().min(1).max(80).optional(),
  }).safeParse(req.query);
  if (!filters.success) return fail(res, 400, 'Provide a valid payment mode, order type, or product category');
  const result = await pool.query(
    `WITH sales_totals AS (
       SELECT COALESCE(SUM(total_amount) FILTER (
                WHERE payment_mode <> 'personal_use'
                  AND ($4::text IS NULL OR payment_mode = $4)
              ), 0) AS revenue,
              COUNT(DISTINCT order_group_id) FILTER (
                WHERE payment_mode <> 'personal_use'
                  AND ($4::text IS NULL OR payment_mode = $4)
              ) AS order_count,
              COALESCE(SUM(total_amount) FILTER (
                WHERE payment_mode = 'cash' AND ($4::text IS NULL OR payment_mode = $4)
              ), 0) AS cash_revenue,
              COALESCE(SUM(total_amount) FILTER (
                WHERE payment_mode = 'bank_transfer' AND ($4::text IS NULL OR payment_mode = $4)
              ), 0) AS bank_transfer_revenue,
              COALESCE(SUM(delivery_fee) FILTER (
                WHERE payment_mode <> 'personal_use'
                  AND ($4::text IS NULL OR payment_mode = $4)
              ), 0) AS delivery_revenue,
              COALESCE(SUM(total_amount) FILTER (
                WHERE payment_mode = 'personal_use'
                  AND ($4::text IS NULL OR payment_mode = $4)
              ), 0) AS personal_use_amount
       FROM sales s
       JOIN menu_sizes ms ON ms.id = s.menu_size_id
       JOIN menu_items m ON m.id = ms.menu_item_id
       WHERE ($1::uuid IS NULL OR s.branch_id = $1)
         AND ($2::timestamptz IS NULL OR s.created_at >= $2)
         AND ($3::timestamptz IS NULL OR s.created_at < $3)
         AND ($5::text IS NULL OR s.order_type = $5)
         AND ($6::text IS NULL OR m.category = $6)
     ), expense_totals AS (
       SELECT COALESCE(SUM(amount) FILTER (WHERE status = 'settled'), 0) AS expenses,
              COUNT(*) FILTER (WHERE status = 'pending') AS pending_count
       FROM expenses WHERE ($1::uuid IS NULL OR branch_id = $1)
         AND ($2::timestamptz IS NULL OR created_at >= $2) AND ($3::timestamptz IS NULL OR created_at < $3)
     )
     SELECT sales_totals.revenue, sales_totals.order_count, sales_totals.cash_revenue,
            sales_totals.bank_transfer_revenue,
            sales_totals.delivery_revenue,
            sales_totals.personal_use_amount,
            expense_totals.expenses, expense_totals.pending_count,
            sales_totals.revenue - expense_totals.expenses AS net_profit
     FROM sales_totals CROSS JOIN expense_totals`,
    [
      scopeBranch(req),
      req.query.from || null,
      req.query.to || null,
      filters.data.paymentMode || null,
      filters.data.orderType || null,
      filters.data.category || null,
    ],
  );
  res.json(result.rows[0]);
}));

app.get('/api/analytics/branches', authenticate, ownerOnly, asyncRoute(async (req, res) => {
  const filters = z.object({
    branchId: z.string().uuid().optional(),
    paymentMode: z.enum(['cash', 'bank_transfer', 'personal_use']).optional(),
    orderType: z.enum(['pickup', 'delivery']).optional(),
    category: z.string().trim().min(1).max(80).optional(),
  }).safeParse(req.query);
  if (!filters.success) return fail(res, 400, 'Provide a valid payment mode, order type, or product category');
  const result = await pool.query(
    `WITH sales_by_branch AS (
       SELECT s.branch_id,
              COALESCE(SUM(s.total_amount) FILTER (
                WHERE s.payment_mode <> 'personal_use'
                  AND ($4::text IS NULL OR s.payment_mode = $4)
              ), 0) AS revenue,
              COALESCE(SUM(s.total_amount) FILTER (
                WHERE s.payment_mode = 'cash'
                  AND ($4::text IS NULL OR s.payment_mode = $4)
              ), 0) AS cash_revenue,
              COALESCE(SUM(s.total_amount) FILTER (
                WHERE s.payment_mode = 'bank_transfer'
                  AND ($4::text IS NULL OR s.payment_mode = $4)
              ), 0) AS bank_transfer_revenue,
              COALESCE(SUM(s.delivery_fee) FILTER (
                WHERE s.payment_mode <> 'personal_use'
                  AND ($4::text IS NULL OR s.payment_mode = $4)
              ), 0) AS delivery_revenue,
              COALESCE(SUM(s.total_amount) FILTER (
                WHERE s.payment_mode = 'personal_use'
                  AND ($4::text IS NULL OR s.payment_mode = $4)
              ), 0) AS personal_use_amount
       FROM sales s
       JOIN menu_sizes ms ON ms.id = s.menu_size_id
       JOIN menu_items m ON m.id = ms.menu_item_id
       WHERE ($1::timestamptz IS NULL OR s.created_at >= $1)
         AND ($2::timestamptz IS NULL OR s.created_at < $2)
         AND ($3::text IS NULL OR s.order_type = $3)
         AND ($5::text IS NULL OR m.category = $5)
       GROUP BY s.branch_id
     ), expenses_by_branch AS (
       SELECT branch_id,
              COALESCE(SUM(amount) FILTER (WHERE status = 'settled'), 0) AS expenses,
              COUNT(*) FILTER (WHERE status = 'pending') AS pending_count
       FROM expenses
       WHERE ($1::timestamptz IS NULL OR created_at >= $1)
         AND ($2::timestamptz IS NULL OR created_at < $2)
       GROUP BY branch_id
     )
     SELECT b.id AS branch_id, b.name AS branch_name,
            COALESCE(s.revenue, 0) AS revenue,
            COALESCE(s.cash_revenue, 0) AS cash_revenue,
            COALESCE(s.bank_transfer_revenue, 0) AS bank_transfer_revenue,
            COALESCE(s.delivery_revenue, 0) AS delivery_revenue,
            COALESCE(s.personal_use_amount, 0) AS personal_use_amount,
            COALESCE(e.expenses, 0) AS expenses,
            COALESCE(e.pending_count, 0) AS pending_count,
            COALESCE(s.revenue, 0) - COALESCE(e.expenses, 0) AS net_profit
     FROM branches b
     LEFT JOIN sales_by_branch s ON s.branch_id = b.id
     LEFT JOIN expenses_by_branch e ON e.branch_id = b.id
     WHERE b.active AND ($6::uuid IS NULL OR b.id = $6)
     ORDER BY b.name`,
    [
      req.query.from || null,
      req.query.to || null,
      filters.data.orderType || null,
      filters.data.paymentMode || null,
      filters.data.category || null,
      filters.data.branchId || null,
    ],
  );
  res.json(result.rows);
}));

app.get('/api/analytics/hot-selling', authenticate, asyncRoute(async (req, res) => {
  const result = await pool.query(
    `SELECT m.name AS pizza_name, m.category, ms.id AS menu_size_id, ms.name AS size_name, b.id AS branch_id, b.name AS branch_name,
            SUM(s.quantity)::integer AS quantity_sold, SUM(s.total_amount) AS revenue
     FROM sales s JOIN menu_sizes ms ON ms.id = s.menu_size_id
     JOIN menu_items m ON m.id = ms.menu_item_id JOIN branches b ON b.id = s.branch_id
     WHERE ($1::uuid IS NULL OR s.branch_id = $1)
       AND ($2::text IS NULL OR m.category = $2)
       AND ($3::text IS NULL OR ms.name = $3)
       AND ($4::timestamptz IS NULL OR s.created_at >= $4)
       AND ($5::timestamptz IS NULL OR s.created_at < $5)
       AND s.payment_mode <> 'personal_use'
     GROUP BY m.id, m.name, m.category, ms.id, ms.name, b.id, b.name
     ORDER BY quantity_sold DESC LIMIT 100`,
    [scopeBranch(req), req.query.category || null, req.query.size || null, req.query.from || null, req.query.to || null],
  );
  res.json(result.rows);
}));

app.get('/api/audit', authenticate, ownerOnly, asyncRoute(async (req, res) => {
  const result = await pool.query(
    `SELECT a.id, a.action, a.entity_type, a.entity_id, a.details, a.created_at,
            b.name AS branch_name, u.email AS actor_email
     FROM audit_log a LEFT JOIN branches b ON b.id = a.branch_id
     LEFT JOIN users u ON u.id = a.actor_id
     WHERE ($1::uuid IS NULL OR a.branch_id = $1)
       AND ($2::timestamptz IS NULL OR a.created_at >= $2)
       AND ($3::timestamptz IS NULL OR a.created_at < $3)
     ORDER BY a.created_at DESC LIMIT 1000`,
    [req.query.branchId || null, req.query.from || null, req.query.to || null],
  );
  res.json(result.rows);
}));

app.use((error, _req, res, _next) => {
  console.error(error);
  res.status(500).json({ error: 'Internal server error' });
});

const migrationFiles = [
  ['002', '../db/migrations/002_menu_descriptions_and_delivery_fee.sql'],
  ['003', '../db/migrations/003_customer_orders.sql'],
  ['004', '../db/migrations/004_personal_use_payment.sql'],
];

async function applyDatabaseMigrations() {
  const client = await pool.connect();
  let migrationLockAcquired = false;
  let transactionOpen = false;
  try {
    await client.query('SELECT pg_advisory_lock(724993002)');
    migrationLockAcquired = true;
    await client.query(
      `CREATE TABLE IF NOT EXISTS schema_migrations (
         version text PRIMARY KEY,
         applied_at timestamptz NOT NULL DEFAULT now()
       )`,
    );

    const schema = await client.query(
      "SELECT to_regclass('public.branches') AS branches_table",
    );
    if (!schema.rows[0].branches_table) {
      await client.query('BEGIN');
      transactionOpen = true;
      const baseSchema = await readFile(
        new URL('../db/init/001_schema.sql', import.meta.url),
        'utf8',
      );
      await client.query(baseSchema);
      await client.query(
        `INSERT INTO schema_migrations (version) VALUES ('001')
         ON CONFLICT (version) DO NOTHING`,
      );
      await client.query('COMMIT');
      transactionOpen = false;
    } else {
      await client.query(
        `INSERT INTO schema_migrations (version) VALUES ('001')
         ON CONFLICT (version) DO NOTHING`,
      );
    }

    for (const [version, path] of migrationFiles) {
      const applied = await client.query(
        'SELECT 1 FROM schema_migrations WHERE version = $1',
        [version],
      );
      if (applied.rowCount) continue;

      await client.query('BEGIN');
      transactionOpen = true;
      const migration = await readFile(new URL(path, import.meta.url), 'utf8');
      await client.query(migration);
      await client.query(
        'INSERT INTO schema_migrations (version) VALUES ($1)',
        [version],
      );
      await client.query('COMMIT');
      transactionOpen = false;
      console.log(`Applied database migration ${version}`);
    }
  } catch (error) {
    if (transactionOpen) await client.query('ROLLBACK');
    throw error;
  } finally {
    if (migrationLockAcquired) {
      await client.query('SELECT pg_advisory_unlock(724993002)');
    }
    client.release();
  }
}

const port = Number(process.env.PORT || 3000);
async function start() {
  await applyDatabaseMigrations();
  const ownerEmail = process.env.OWNER_EMAIL.toLowerCase();
  const minimumPasswordLength = process.env.NODE_ENV === 'development' ? 10 : 12;
  if (process.env.OWNER_PASSWORD.length < minimumPasswordLength) {
    throw new Error(`OWNER_PASSWORD must be at least ${minimumPasswordLength} characters`);
  }
  const ownerHash = await bcrypt.hash(process.env.OWNER_PASSWORD, 12);
  await pool.query(
    `INSERT INTO users (email, password_hash, role)
     VALUES ($1, $2, 'owner')
     ON CONFLICT (email) DO UPDATE SET password_hash = EXCLUDED.password_hash
     WHERE users.role = 'owner' AND users.branch_id IS NULL`,
    [ownerEmail, ownerHash],
  );
  if (process.env.ADDITIONAL_OWNER_EMAIL) {
    const additionalEmail = emailSchema.safeParse(process.env.ADDITIONAL_OWNER_EMAIL);
    if (!additionalEmail.success) {
      throw new Error('ADDITIONAL_OWNER_EMAIL must be a valid email address');
    }
    const normalizedAdditionalEmail = additionalEmail.data.toLowerCase();
    if (normalizedAdditionalEmail === ownerEmail) {
      throw new Error('ADDITIONAL_OWNER_EMAIL must differ from OWNER_EMAIL');
    }
    if (process.env.ADDITIONAL_OWNER_PASSWORD.length < minimumPasswordLength) {
      throw new Error(`ADDITIONAL_OWNER_PASSWORD must be at least ${minimumPasswordLength} characters`);
    }
    const additionalOwnerHash = await bcrypt.hash(process.env.ADDITIONAL_OWNER_PASSWORD, 12);
    const additionalOwner = await pool.query(
      `INSERT INTO users (email, password_hash, role)
       VALUES ($1, $2, 'owner')
       ON CONFLICT (email) DO UPDATE SET password_hash = EXCLUDED.password_hash
       WHERE users.role = 'owner' AND users.branch_id IS NULL
       RETURNING id`,
      [normalizedAdditionalEmail, additionalOwnerHash],
    );
    if (additionalOwner.rowCount !== 1) {
      throw new Error('ADDITIONAL_OWNER_EMAIL is already assigned to a non-owner account');
    }
  }
  const records = JSON.parse(await readFile(new URL('./default-menu.json', import.meta.url), 'utf8'));
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const items = new Map();
    let seededVariants = 0;
    for (const row of records) {
      const key = `${row.name}\0${row.category}`;
      let itemId = items.get(key);
      if (!itemId) {
        const item = await client.query(
          `INSERT INTO menu_items (name, category, description)
           VALUES ($1, $2, $3)
           ON CONFLICT (name, category) DO UPDATE
             SET description = CASE WHEN menu_items.description = ''
                                     THEN EXCLUDED.description
                                     ELSE menu_items.description END
           RETURNING id`,
          [row.name, row.category, row.description],
        );
        itemId = item.rows[0].id;
        items.set(key, itemId);
      }
      const size = await client.query(
        `INSERT INTO menu_sizes (menu_item_id, name, base_price)
         VALUES ($1, $2, $3) ON CONFLICT (menu_item_id, name) DO NOTHING`,
        [itemId, row.size, row.price],
      );
      seededVariants += size.rowCount;
    }
    if (seededVariants > 0) {
      await client.query(
        `INSERT INTO audit_log (actor_id, action, entity_type, details)
         SELECT id, 'menu.default_seeded', 'menu', $2::jsonb
         FROM users WHERE email = $1`,
        [ownerEmail, JSON.stringify({ importedRows: seededVariants })],
      );
    }
    await client.query('COMMIT');
    if (seededVariants > 0) {
      console.log(`Added ${seededVariants} default menu price variants`);
    }
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally { client.release(); }
  app.listen(port, '0.0.0.0', () => console.log(`House of Sauces API listening on ${port}`));
}
start().catch((error) => {
  console.error('API startup failed', error);
  process.exitCode = 1;
});
