# Design brief — ERP platform

Everything a designer needs to mock this up. Screens, what sits on each one,
the states that must exist, and the order to draw them in.

---

## 1. What this is

A business management platform for small and mid-size businesses — the work
Sage and Odoo do, but built for a bakery owner on a phone rather than an
accountant at a desk.

One company signs up, switches on the parts it needs, and runs its selling,
buying, stock, staff and books in one place. Several companies use the same
installation without ever seeing each other.

**The first real customer is a custom-cake bakery.** She takes orders on
WhatsApp and Instagram, bakes to order for a specific date, takes a deposit
and collects the balance on delivery. Design for her first; the rest follows.

**The one-line promise:** *you keep running your business the way you already
do, and the records write themselves.*

### This is not a bakery app — design it accordingly

The bakery is the first tenant, not the target market. The same installation
has to serve a cement depot, a pharmacy, a furniture factory and a cleaning
contractor, each seeing a different-looking product. That is already true of
the database: every business is an isolated tenant, modules switch on and off
per company, items can be raw materials or finished goods or services, and
recipes describe *anything made from other things* — cakes, sofas, paint,
bottled water.

So, in the mockups:

- **Nothing bakery-flavoured in the shell.** No cupcake icons, no pastel
  kitchen palette, no cake imagery in the navigation or empty states.
- **Generic labels.** *Products*, not "Cakes". *Production jobs*, not
  "Baking". *Customers*, not "Clients".
- **The logo is a slot**, not a fixed mark — each company drops its own in.
- **Test every screen twice in your head:** does this still look right with
  50 bags of cement in it? With a pallet of paracetamol? If a screen only
  makes sense with cakes on it, redraw it.

The bakery's *data* fills the mockups. The bakery's *personality* does not.

---

## 2. Who uses it

| Role | What they are | What they see |
|---|---|---|
| **Owner / Admin** | The business owner | Everything, plus settings and users |
| **Manager** | Runs daily operations | Everything except settings and users |
| **Sales** | Takes orders, handles customers | Orders, customers, vendors, products |
| **Clerk** | Bookkeeping, data entry | Ledger, reports, timesheets, products |

Most screens are shared. A role simply sees fewer items in the navigation.

---

## 3. Design constraints — read before drawing anything

**Mobile first, and mean it.** The primary user is standing in a kitchen with
flour on her hands, checking what's due tomorrow on a phone. Design at
**360px** first, then tablet, then desktop. Desktop matters for the
accounting and reporting screens, where tables need room.

**One-handed and thumb-reachable.** Primary actions go at the bottom on
mobile, not tucked in a top-right corner.

**Assume a weak connection.** Design a visible "saving…", "saved", and
"couldn't save — will retry" state. Do not assume instant responses.

**Money is the main character.** Naira, large numbers, often in the millions.
Use `₦1,250,000.00`. Numbers in tables right-align and use tabular figures so
columns line up. Never let a total wrap or truncate.

**Dates carry weight.** "Due Saturday" matters more than "created 3 days ago".
Due dates should read as human and urgent — *Tomorrow*, *Sat 12 Oct*,
*2 days late* — not as raw timestamps.

**Light and dark, both designed.** Not an afterthought — bakers work early
mornings and late nights.

**Plain language, never accounting jargon.** The system keeps proper
double-entry books underneath, but the owner should never see the words
"debit", "credit" or "journal" unless she opens the accountant's view. She
sees "money in", "money out", "what you're owed".

---

## 4. Navigation structure

**Desktop:** fixed left sidebar, grouped. **Mobile:** bottom bar with the five
most-used destinations, the rest behind a "More" sheet.

```
OVERVIEW
  Dashboard
  Production calendar        ← the hero screen

SALES & PURCHASING
  Orders & invoices
  Customers
  Vendors
  Products & stock

KITCHEN / PRODUCTION
  Production jobs
  Recipes
  Stock movements

PEOPLE & PAYROLL
  Employees
  Timesheets
  Payroll runs

ACCOUNTS
  Ledger
  Reports

ADMINISTRATION
  Users & access
  Settings
```

Mobile bottom bar: **Calendar · Orders · Add (+) · Customers · More**

The centre **+** is a prominent action button that opens a sheet: *New order,
New payment, New expense, New production job*.

**Top bar everywhere:** company name/switcher, global search, light/dark
toggle, user avatar.

---

## 5. The screens

### 5.1 Sign in
Email and password, a logo, "forgot password". Quiet and confident. Nothing
clever.

### 5.2 Sign up and onboarding
A short wizard, one question per step:
1. Business name
2. What kind of business (bakery, distribution, retail, services, other)
3. Currency and country
4. Which parts do you need — toggles for *Selling, Buying, Stock, Baking/
   Production, Staff & payroll, Accounts*
5. Invite your team (skippable)

Ends on a populated dashboard, not an empty one.

### 5.3 Dashboard
Answers "how is the business doing?" at a glance.

- **KPI tiles:** money in this month, money out, what you're owed, orders due
  this week, stock value, low-stock count
- **A chart:** sales vs purchases over recent months
- **Needs attention:** overdue balances, items at or below zero stock
- **Recent orders:** last 6–8, with status

### 5.4 Production calendar — **the most important screen**
This is the one that saves her the most pain, so give it the most care.

- **Week view by default**, day columns, each job a card
- Each card: customer name, what it is, quantity, due time, a status dot
- **A capacity indicator per day** — "3 of 5 cakes" — so she can see at a
  glance whether Saturday is full before she accepts another order
- Tapping a day opens that day's list; tapping a job opens the job
- Needs a **month view** toggle for planning further out
- Today is clearly marked; overdue work is unmissable

Design the mobile version of this first. It is what she'll open every morning.

### 5.5 Orders list
- Filter chips along the top: *All · Enquiries · Quoted · Confirmed · In
  production · Ready · Delivered · Unpaid*
- Each row: order number, customer, what it is, **due date**, status chip,
  total, and amount still owed
- Search by customer or order number
- On mobile these become cards, not a squeezed table

### 5.6 Order detail — the job screen
The richest screen in the product. A custom cake order has to show:

- **Header:** order number, customer (tap through to them), status, due date
  and time
- **Status pipeline** shown as steps: Enquiry → Quoted → Confirmed → In
  production → Ready → Delivered → Paid. Current step highlighted, with a
  single clear button to advance it.
- **Line items:** description, quantity, unit price, line total. Items can be
  free text ("3-tier wedding cake, gold trim") — not everything comes from a
  product list.
- **Reference photos** — customers send pictures of what they want. A gallery
  with an add button. Needs real space in the design; it's not a minor field.
- **Money panel:** subtotal, VAT (7.5%), delivery fee, total, **deposit paid**,
  **balance due**. Balance due is the number her eye should land on.
- **Payments list:** each payment with date, amount, method (cash, transfer,
  POS). An "add payment" action.
- **Delivery:** address, date, time
- **Notes:** customer-visible notes and private internal notes, kept visually
  distinct
- **Actions:** print/PDF invoice, share on WhatsApp, duplicate, cancel

### 5.7 New order flow (mobile)
Must be fast — she may be typing it while a customer waits on WhatsApp.
Customer (search or create inline) → what they want → due date → price →
deposit. Everything else can wait.

### 5.8 Customers
- **List:** name, phone, total ordered, outstanding balance, last order
- **Profile:** contact details including WhatsApp and Instagram handles, order
  history, total spent, outstanding balance, notes. Buttons to message on
  WhatsApp or start a new order.

### 5.9 Vendors
Same shape as customers, but showing purchases and what you owe them.

### 5.10 Products & stock
- **List:** name, type badge (*Raw material* / *Finished* / *Service*), buy
  price, sell price, **stock on hand**, stock value. Negative or zero stock is
  visually loud.
- **Filters:** all / in stock / out of stock / raw materials / finished goods
- **Item detail:** prices, unit (kg, each, litre), reorder level, shelf life,
  photo, and a **stock movement history** — every purchase, use, sale, waste
  and correction, each with its reason. The stock number is never typed in;
  it's the sum of this history, and the design should make that legible.

### 5.11 Recipes
What turns a bakery into something Sage can't do.

- A recipe belongs to a product: *8-inch chocolate cake*
- **Ingredient lines:** component, quantity, unit, expected wastage %
- **Yield:** how many this batch makes
- **Labour minutes** and **overhead cost**
- **A live cost panel:** ingredients + labour + overhead = cost per unit,
  shown against the selling price, with the margin. Watching that update as
  you change the recipe is the moment this sells itself.

### 5.12 Production jobs
- **List** by status: planned, in progress, done
- **Job detail:** what's being made, quantity, due date, linked order
  - **Ingredients: planned vs actually used** — two columns side by side. The
    recipe says 0.6kg flour; she used 0.7kg. That difference is where money
    quietly leaks, so show it plainly.
  - **Wastage** field
  - **Output:** how many good units came out
  - **Cost summary:** materials + labour + overhead = true cost of this batch
  - Buttons: start, complete, cancel

### 5.13 Stock movements
A ledger view: date, item, reason (purchase, used in production, sold, waste,
count correction, opening balance), quantity in or out, running balance.
Filterable by item and date. Plus an "adjust stock" action for stock counts.

### 5.14 Ledger (money in / money out)
- List: date, description, account, type badge (*Income* / *Expense* / *Cost
  of goods*), amount, notes
- Filters: type, account, date range
- A footer showing money in, money out and the difference for what's shown
- "Add transaction" form: description, date, account, amount, notes, and an
  optional receipt photo

### 5.15 Reports
Each report needs a date-range picker, a print/PDF action, and a chart where a
chart helps:

- **Profit & loss** — income, cost of goods, expenses, net profit, broken down
  by account
- **Stock valuation** — at cost, at retail, potential margin
- **Best sellers and margins** — which products actually make money
- **Payroll cost** by month
- **What you're owed** — aged: current, 30, 60, 90+ days
- **Accountant's view** (admin only) — trial balance with real debits and
  credits, for when a professional needs it

### 5.16 Employees, timesheets, payroll
- **Employees:** name, role, hourly or salary, rate, active toggle
- **Timesheets:** date, employee, clock in, clock out, hours, with overtime
  past 8 hours a day shown separately
- **Payroll run:** pay date, period, list of employees with hours pulled
  automatically, gross, tax, net. Each employee opens a pay breakdown:
  regular pay, overtime, additions (bonus, fuel), deductions (loans,
  insurance), tax lines, gross and net. Plus a printable payslip.

### 5.17 Users & access (admin)
List of people, their role, status. Invite by email. A plain-language
explanation of what each role can reach.

### 5.18 Settings (admin)
Grouped sections: company details and logo; tax rates; document numbering;
which modules are on; editable lists (order statuses, expense accounts,
payroll additions and deductions, employee roles); data export and backup.

### 5.19 Audit log (admin)
Who changed what and when, with before and after. Filterable by person, table
and date. Plain and forensic.

### 5.20 Review queue — *design this, build it later*
Where the AI intake will land. Orders extracted from WhatsApp, Instagram and
photographed invoices arrive here as **drafts awaiting approval**.

Each card shows the **original message** beside **what the system understood**
(customer, item, date, price), with a confidence indicator, and two buttons:
approve, or edit then approve. Nothing posts to the books without a human tap
until she chooses to trust it.

Even though it's built later, mocking it now keeps the design coherent.

---

## 6. Components that repeat

Draw these once and reuse them.

- **Status chip** — green (done, paid), amber (pending, in progress), red
  (overdue, out of stock), grey (closed, cancelled), blue (informational)
- **Money figure** — large, tabular, with currency; negative values distinct
- **Due-date badge** — *Today*, *Tomorrow*, *Sat 12 Oct*, *2 days late*
- **KPI tile** — label, big number, small supporting line
- **Line-item editor** — add, edit, remove rows on a phone without misery
- **Totals panel** — subtotal, tax, total, paid, balance due
- **Search + filter bar**
- **Empty state** — an explanation and an action, never a blank page
- **Confirm dialog** — for anything destructive
- **Toast** — brief confirmation after saving
- **Photo uploader and gallery**
- **Bottom sheet** — the mobile pattern for forms and actions
- **Avatar / initials**

---

## 7. States to design for every screen

Easy to forget, and the reason apps feel unfinished:

1. **Loading** — skeletons, not spinners, where possible
2. **Empty** — first use, with a clear next step
3. **Full** — the normal case, with realistic Nigerian names, products and
   amounts, not "Lorem ipsum" and "$100"
4. **Error** — something failed, with what to do about it
5. **Offline / saving** — the connection dropped, the work is not lost
6. **Permission denied** — a Sales user reaching an accounts screen

---

## 8. Tone and look

**Aim for:** calm, competent, trustworthy. The kind of software a serious
business runs on. Generous spacing, clear hierarchy, restrained colour used to
mean something rather than to decorate.

**Avoid:** heavy corporate blues and grey enterprise gloom, cartoon
illustrations, decorative gradients, cramped data tables, and anything that
makes a kitchen feel like a bank.

Colour should carry meaning: a chip is green because it's paid, not because
green looks nice.

Typography needs two jobs done well: numbers that align in tables, and labels
that stay readable at small sizes in poor light.

---

## 9. What to mock first

Don't draw all twenty screens. In this order:

1. **Production calendar (mobile)** — the hero
2. **Order detail (mobile)** — the richest screen
3. **Orders list (mobile)**
4. **Dashboard (mobile and desktop)**
5. **Recipe editor with the live cost panel (desktop)**
6. **Products & stock list (desktop)**
7. The component set from section 6
8. Everything else

The first three tell us whether the whole thing works. If the calendar and the
order screen feel right on a phone, the rest will follow.

---

## 10. Sending the mockups back

Anything readable works — Figma links, PNG exports, or photos of paper
sketches. Useful to include:

- Which screen and which state each mock shows
- Mobile or desktop
- Any colours or fonts you've settled on, so the build matches exactly
- Anything you deliberately changed from this brief, and why — you may well be
  right

I'll build to whatever you send.
