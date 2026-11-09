# House of Sauces

Multi-branch pizza sales and expense management for Android, with an Express API and PostgreSQL.

## Project layout

- `mobile/` — Flutter app source (Provider state management, role-specific dashboards, charts, Excel menu import and PDF printing).
- `backend/` — REST API, authentication and PostgreSQL schema.
- `docker-compose.yml` — local API and database services.

## Run the backend

1. Copy `.env.example` to `.env`. Set a unique owner password and replace the database and JWT secret placeholders before use. Never deploy with example values.
2. Run `docker compose up --build`. If local ports 3000/5432 are occupied, set `API_PORT` and/or `POSTGRES_HOST_PORT` in `.env`.
3. The API listens on `http://localhost:3001`; the root address shows local setup information and `http://localhost:3001/health` checks readiness. PostgreSQL listens on `localhost:5432`.
4. On first database initialization, three example branches are created; the API seeds the owner account from `.env` when it starts. Add more branches and branch-admin accounts from the owner dashboard.
5. API health check: `GET /health`.

The initial schema in `backend/db/init/001_schema.sql` is applied automatically on a fresh PostgreSQL volume. The API applies the idempotent menu-description and delivery-fee migration on startup; its SQL is also available in `backend/db/migrations/002_menu_descriptions_and_delivery_fee.sql`. To reset local data, remove the `postgres_data` volume with `docker compose down -v` (this deletes local database data).

## Run the Android app

Install Flutter 3.47+ and Android SDK, then:

```powershell
cd mobile
flutter pub get
```

The Android Gradle wrapper/platform files are included. Android has the network permission needed to connect to the API; debug builds allow cleartext HTTP for local testing, while production must use HTTPS.
For Android emulator testing, the default API URL is `http://10.0.2.2:3001/api`. Override it at build/run time with `--dart-define=API_BASE_URL=http://<host>:3001/api`. For USB-connected phones, use the tunnel instructions below instead of the emulator address. For LAN testing, use the development machine's LAN address and do not expose the API to the public internet without TLS and production hardening.

### Google Play release preparation

The Android package ID is `com.houseofsauces.house_of_sauces`; the release version is `1.1.0` (version code `2`). Release builds require a private upload key and never fall back to the Android debug key. Keep `mobile/android/key.properties` and its keystore private and backed up; neither should be committed. Configure `storeFile`, `storePassword`, `keyAlias`, and `keyPassword` in that ignored local properties file.

Deploy the API and PostgreSQL to a production host with a public HTTPS API URL before building. The local Docker Compose setup binds to loopback and is for development only. In PowerShell, set `$env:HOS_API_BASE_URL` to the production API URL ending in `/api`, then run `.\tool\build_production.ps1` from `mobile`; it builds `build\app\outputs\bundle\release\app-release.aab`. Release builds reject non-HTTPS API URLs.

For a Koyeb deployment, build the API service from `backend/Dockerfile`, expose the service's configured port (the API defaults to `3000`), and use `/health` as its health check. Attach a production PostgreSQL instance and configure `DATABASE_URL`, `JWT_SECRET`, `OWNER_EMAIL`, `OWNER_PASSWORD`, `ADDITIONAL_OWNER_EMAIL`, and `ADDITIONAL_OWNER_PASSWORD` as server-side secrets. The API applies versioned schema migrations at startup; its database user must be allowed to create the application tables and the `pgcrypto` extension. Verify the deployed `/health` endpoint and owner logins before setting `HOS_API_BASE_URL` and creating the Play bundle. Do not commit credentials, `key.properties`, or the upload keystore.

### Test on a phone over USB without internet

The app's data and API remain on this computer in Docker/PostgreSQL. An authorized USB connection carries API traffic directly between the phone and computer, so the phone does not need Wi-Fi or mobile data. Keep Docker Desktop and the computer running while using the app.

1. Start Docker Desktop and the backend with `docker compose up -d --build`. Complete the backend setup above first; the API should answer at `http://localhost:3001/health`.
2. Connect the Android phone by USB, enable **Developer options → USB debugging**, and accept the phone's authorization prompt.
3. From PowerShell in the project root, run:

   ```powershell
   .\mobile\run_usb_android.ps1
   ```

   The script checks the local API and USB device, establishes `adb reverse`, builds a debug APK configured to use the USB tunnel, installs it, and launches it. If multiple devices are connected, specify one with `-DeviceSerial <adb-serial>`.

The reverse tunnel is removed when the phone disconnects or reboots. Run the script again after reconnecting. Sales, expenses, and menu data are stored on this computer, not offline-synced to the phone; the app needs the USB connection and local API available for requests. The script installs a debug build for local testing, not a production release.

## API outline

- `POST /api/auth/login` — owner or branch-admin login.
- `GET /api/branches` — owner can list all branches; branch admins see their assigned branch.
- `POST /api/users` — owner creates a branch-admin login.
- `PATCH /api/users/:id` — owner-only account edits, password resets and branch-admin disable/enable; disabling retains transaction history and blocks further logins.
- `GET|POST /api/menu`, `PATCH /api/menu/sizes/:id`, and `POST /api/menu/import` — owner-managed products, editable size prices, descriptions and XLSX import.
- `GET /api/expense-heads` — predefined operational expense categories.
- `POST /api/sales`, `GET /api/sales` — branch-scoped sales order recording and audit listing; one order may contain multiple products and delivery orders record customer name, phone and a manually entered delivery fee. Payment modes are cash, bank transfer, and personal use. Personal-use records remain visible and filterable in the sales report but are excluded from sales revenue, delivery revenue, order counts, profit calculations and hot-selling sales analytics.
- `POST /api/expenses`, `GET /api/expenses` — submit and list expenses.
- `POST /api/expenses/:id/settle` — owner-only approve and settle from cash receipts or by bank transfer.
- `GET /api/analytics/summary`, `GET /api/analytics/branches`, `GET /api/analytics/hot-selling` — date/branch-filtered reports. The owner dashboard provides one-tap payment, pick-up/delivery and category filters, with separate cash and bank-transfer revenue cards and an overall branch-wise breakdown; tapping a branch opens that branch's detailed sales and expense records. Active sales filters carry through to charts, drill-downs and printed reports. Branch net operating result is filtered sales revenue less settled operating expenses for that branch/date range. Expense totals stay scoped to the selected date and branch, not the sales-only filters.
- `GET /api/audit` — owner-only audit history.

An optional second owner account can be bootstrapped by setting `ADDITIONAL_OWNER_EMAIL` and `ADDITIONAL_OWNER_PASSWORD` as backend server secrets. Both values are required together. On startup, the server creates or updates that owner account's password; do not put production credentials in the mobile app or a checked-in file.

Sales reduce no inventory; every sale and expense is stored as an immutable record. Pending expenses are not paid. Cash-adjusted settlements are rejected when the branch's recorded cash receipts are insufficient. Net profit in the dashboard is shown as revenue less settled operating expenses; product cost/COGS is not collected by this version and therefore is not included.

## Menu spreadsheet format

On API startup, the workbook menu is added without overwriting existing menu prices: 45 pizza variants, 12 deals (with deal contents), and 6 other product variants (pasta, fries, rolls and burger). Missing variants are safely added to existing databases, while existing prices and owner-created products are preserved. The calculator's sample orders are not imported.

Select **Download XLSX template** in the owner's Menu tab to save a workbook with the exact import columns and matching category/size suggestions from the current menu. `Active` has a true/false dropdown, and `Base Price` rejects nonpositive values. Keep the `Menu Template` header row unchanged and put one product size per row. Dropdown suggestions are optional: new categories and sizes can also be typed directly. The importer accepts the template headings (`Pizza Name`, `Category`, `Size`, `Base Price`, optional `Active` and `Description`) as well as the supplied workbook's pizza reference, deal and product tables. It scans worksheets, ignores the order calculator examples, and reports a clear message for unsupported or damaged files. Re-importing a matching product/category/size updates its price.

Owners can add products from the Menu tab with one or more size/price variants and optional deal contents. In **Branches & access**, owners can expand each branch to view active and disabled admin emails/account IDs, create accounts, edit email/branch, reset passwords, and disable or re-enable accounts. Disabled accounts cannot sign in, and their sales, expenses and audit history are retained. The login and branch-admin password fields have show/hide controls. Passwords are securely hashed and cannot be revealed after creation; owners can reset a password and view the new value while entering it. Branch sales and individual transaction details include PDF print/share actions; owners can print the current date-range and branch-filtered summary, sales and expenses from the dashboard.

Branch admins can add multiple products to a customer order and see the accumulated total before saving. Delivery orders require the customer's name and phone number; the admin enters delivery charges manually per order. The charge is stored separately from product sales but is included in gross revenue, sales totals, net operating result and printed reports. Pickup orders have no delivery charge.

Owners can update the price of any active menu size or deal variant from the Menu tab; each price change is recorded in the audit history. Owners can also continue to add products and size/price variants manually or import them from XLSX.

## Security and production deployment

Use unique secrets and passwords, HTTPS, a managed secret store, database backups, rate limiting, monitoring, and a reviewed migration/deployment process in production. The compose setup is for local development and does not publish PostgreSQL beyond the local host binding. Login uses bcrypt password hashes and short-lived signed bearer tokens. Configure a unique owner password; other environments require at least 12 characters. Never use sample values in production.
