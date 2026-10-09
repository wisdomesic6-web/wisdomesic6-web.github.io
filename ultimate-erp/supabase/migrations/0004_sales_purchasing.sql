-- =====================================================================
-- 0004 — Sales and purchasing documents
--
-- Keeps the workbook's good idea (one order screen that flips between
-- selling and buying) and fixes its three real limits:
--
--   * a status pipeline, so an enquiry can become a quote, then a
--     confirmed order — a custom-cake business lives in those stages
--   * many payments per order, because deposits are normal and the
--     single `payment` column could not hold a deposit plus a balance
--   * a due date and attachments, because the job is "Saturday, this
--     photo" rather than "ship when convenient"
-- =====================================================================

create type doc_type as enum ('quote','sales_order','invoice','purchase_order','bill','credit_note');

create type order_status as enum (
  'enquiry',      -- came in by WhatsApp/IG/phone, not yet priced
  'quoted',       -- she has sent a price
  'confirmed',    -- customer agreed (usually on deposit)
  'in_production',
  'ready',
  'delivered',
  'paid',
  'closed',
  'cancelled',
  'lost'          -- quoted but the customer went elsewhere
);

create table orders (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null references companies(id) on delete cascade,
  doc_type        doc_type not null,
  doc_no          text,                       -- from next_doc_number()
  contact_id      uuid references contacts(id) on delete restrict,
  -- kept for walk-ins and new enquiries, before the person exists as a contact
  contact_name    text,
  contact_phone   text,
  status          order_status not null default 'enquiry',
  source_channel  text,                       -- 'whatsapp','instagram','phone',
                                              -- 'walk_in','website','manual'
  order_date      date not null default current_date,
  due_at          timestamptz,                -- collection / delivery moment
  delivery_address text,
  -- money. Totals are derived from the lines, not typed in: the workbook
  -- stored them and 20 of its 41 orders had drifted out of step.
  tax_rate        numeric(6,4) not null default 0,
  discount        numeric(14,2) not null default 0,
  delivery_fee    numeric(14,2) not null default 0,
  currency        char(3) not null default 'NGN',
  notes           text,
  internal_notes  text,                       -- not shown to the customer
  custom          jsonb not null default '{}'::jsonb,
  created_by      uuid references auth.users(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index on orders (company_id, doc_type, status);
create index on orders (company_id, due_at) where status not in ('cancelled','lost','closed');
create index on orders (company_id, contact_id);
create unique index on orders (company_id, doc_no) where doc_no is not null;

create trigger orders_touch before update on orders
  for each row execute function touch_updated_at();

create table order_lines (
  id            uuid primary key default gen_random_uuid(),
  order_id      uuid not null references orders(id) on delete cascade,
  item_id       uuid references items(id) on delete restrict,
  -- free text so a one-off ("3-tier wedding cake, gold trim") needs no
  -- catalogue entry first
  description   text not null default '',
  qty           numeric(14,4) not null default 1,
  unit_price    numeric(14,4) not null default 0,
  discount      numeric(14,2) not null default 0,
  -- what it cost us to make, captured at delivery for real margin
  unit_cost     numeric(14,4),
  line_no       smallint not null default 1,
  custom        jsonb not null default '{}'::jsonb
);
create index on order_lines (order_id);

-- made-to-order link, declared here now that both tables exist
alter table production_jobs
  add constraint production_jobs_order_line_fk
  foreign key (sales_order_line_id) references order_lines(id) on delete set null;

-- Order totals, always derived
create view order_totals as
select
  o.id as order_id,
  o.company_id,
  coalesce(sum(l.qty * l.unit_price - l.discount), 0)                       as subtotal,
  round(coalesce(sum(l.qty * l.unit_price - l.discount), 0) * o.tax_rate, 2) as tax,
  round(coalesce(sum(l.qty * l.unit_price - l.discount), 0) * (1 + o.tax_rate)
        - o.discount + o.delivery_fee, 2)                                   as total,
  coalesce(sum(l.qty * coalesce(l.unit_cost, 0)), 0)                        as cost
from orders o
left join order_lines l on l.order_id = o.id
group by o.id, o.company_id, o.tax_rate, o.discount, o.delivery_fee;

-- ---------------------------------------------------------------------
-- Payments — many per order, which is what deposits require
-- ---------------------------------------------------------------------
create type payment_direction as enum ('in','out');

create table payments (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references companies(id) on delete cascade,
  direction     payment_direction not null,
  order_id      uuid references orders(id) on delete set null,
  contact_id    uuid references contacts(id) on delete set null,
  payment_no    text,
  amount        numeric(14,2) not null check (amount > 0),
  method        text,                      -- 'cash','transfer','pos','card'
  reference     text,                      -- bank reference / teller no
  is_deposit    boolean not null default false,
  paid_at       timestamptz not null default now(),
  note          text,
  created_by    uuid references auth.users(id),
  created_at    timestamptz not null default now()
);
create index on payments (company_id, paid_at desc);
create index on payments (order_id);

-- What is still owed on each order
create view order_balances as
select
  t.order_id,
  t.company_id,
  t.total,
  coalesce(p.paid, 0)        as paid,
  t.total - coalesce(p.paid, 0) as balance
from order_totals t
left join (
  select order_id, sum(amount) as paid
  from payments where direction = 'in' group by order_id
) p on p.order_id = t.order_id;

-- ---------------------------------------------------------------------
-- Attachments — the reference photo a customer sends is part of the order
-- ---------------------------------------------------------------------
create table attachments (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references companies(id) on delete cascade,
  owner_type    text not null,             -- 'order','contact','payment','item'
  owner_id      uuid not null,
  storage_path  text not null,             -- Supabase Storage object path
  file_name     text,
  mime_type     text,
  size_bytes    bigint,
  caption       text,
  uploaded_by   uuid references auth.users(id),
  created_at    timestamptz not null default now()
);
create index on attachments (company_id, owner_type, owner_id);
