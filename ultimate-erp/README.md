# Ultimate ERP — web app

A browser rebuild of the **Ultimate ERP** Excel application (`Ultimate_ERP_Application.xlsm`).
Sales, purchasing, inventory, payroll and accounting in one platform, with sign-in per
department — the Sage-style shape, without Excel.

**One file, no install:** open `index.html` in any browser. There is nothing to build and
no server to run.

---

## What it does

| Area | Screens | Notes |
|---|---|---|
| Overview | Dashboard | Sales vs purchases by month, spend by account, restocking list, recent orders |
| Sales & purchasing | Invoices & orders, Customers, Vendors, Products & stock | One order screen that flips between **Invoice** (customer) and **Purchase order** (vendor) |
| People & payroll | Employees, Timesheets, Payroll runs | Timesheets feed hours; payroll works out overtime, tax, additions, deductions and net pay |
| Accounts | Ledger, Reports | Income / Expense / COGS, profit & loss, stock valuation, payroll cost |
| Administration | Users & access, Settings | Roles, tax rates, lookup lists, backup & restore |

### The rules carried over from the workbook

These were formulas or VBA in Excel, and they stay **calculated** here — never typed in:

- **Stock on hand** = quantity purchased − quantity invoiced, per product
  (the workbook's `SUMIFS(OrdItem_Qty, …, "PURCHASE") − SUMIFS(…, "INVOICE")`).
  Matching ignores letter case, exactly as Excel's `SUMIFS` did.
- **Value on hand** = purchase price × stock on hand.
- **Order total** = sum of line items + sales tax (**8%** on invoices, **10%** on purchase
  orders, both editable in Settings).
- **Line total** = quantity × price.
- **Picking a product** fills in its description and the right price — sales price on an
  invoice, purchase cost on a purchase order — and switching the order type re-prices the lines.
- **Overtime** — anything past **8 hours in a day** (Settings) is overtime, paid at the
  employee's overtime rate.
- **Payroll tax** — Social Security 6.2%, Medicare 1.45%, State Tax 3.4%, each with its
  annual wage cap. Once someone's gross pay for the year passes the cap, that tax stops.
- **Salaried pay** = annual salary ÷ pay periods per year (Settings → pay frequency).
- **Net pay** = gross − tax − deductions, where gross = regular + overtime + PTO + additions.
- **Deleting an order** removes its line items, so stock corrects itself. Deleting a payroll
  run removes its payslips and pay items.

### Things from the workbook that were deliberately left out

- Rows left behind by deletions in Excel (a vendor, a transaction and a user that had an ID
  and nothing else) — dropped rather than imported as blank records.
- A header row (`Acct. Name / Type`) that had been picked up inside the ledger account list.
- Order-item types stored inconsistently as `Purchase` / `PURCHASE` / blank — normalised,
  with blanks inheriting the parent order's type.
- Stored order totals that had drifted out of step with their line items (20 of the 41
  demo orders). Totals are recalculated instead, so they can never go stale again.
- Excel-only plumbing: AdvancedFilter staging ranges, picture-folder paths, the Dropbox
  share/sync macros, slicer caches.

---

## Signing in

Users came across from the workbook's **User DB** sheet, with their roles:

| Role | Can reach |
|---|---|
| **Admin** | Everything, including Users & Settings |
| **Manager** | Everything except Users & Settings |
| **Sales** | Dashboard, orders, customers, vendors, products |
| **Clerk** | Dashboard, ledger, reports, timesheets, products |

The sign-in screen shows a working test login. **This is not real security yet** — passwords
sit in the data file, as they did in the workbook. It separates departments so each one sees
its own screens while you test. Real per-user security needs accounts on a server; see below.

---

## Where the data lives

Everything is saved in **this browser** (`localStorage`), under the key `erp_db_v1`:

- No setup, works offline, survives refreshes and restarts.
- It is **per browser and per device** — your laptop and your phone each keep their own copy,
  and clearing browsing data wipes it.

**Back it up:** Settings → *Export backup (JSON)*. *Import backup* restores it, and
*Reset to workbook data* returns everything to the original Excel figures.

### Moving to a shared cloud database

Browser storage is for proving the app works. For several people on several devices sharing
one set of records, the data moves to a free hosted database (Supabase), and the app reads
and writes it instead. All of the storage code is deliberately kept in two functions —
`loadDB()` and `saveDB()` — so that swap does not touch the business rules.

That upgrade also brings **real logins**: each person gets an account with a hashed password,
and the database enforces who may read or change what, rather than the app politely hiding
menu items.

---

## Starting data

Real figures from the workbook, so the app opens populated:

| | |
|---|---|
| Products | 66 |
| Orders / line items | 41 / 225 |
| Customers / vendors | 11 / 13 |
| Employees | 33 |
| Timesheet entries | 216 |
| Payroll runs / payslips | 10 / 270 |
| Ledger transactions | 83 |
| Users | 12 |

Rebuilt from `Ultimate_ERP_Application.xlsm` by Excel For Freelancers.
