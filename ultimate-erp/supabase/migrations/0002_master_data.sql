-- =====================================================================
-- 0002 — Master data: contacts, items, recipes
--
-- Two deliberate changes from the Excel original:
--
--  * Customers and vendors become one `contacts` table with flags. The
--    same business is often both, and the workbook had to duplicate them.
--  * Products become `items` with a kind, because a bakery holds raw
--    materials (flour) and sells finished goods (cake) — the workbook
--    could only model one shape of thing.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Contacts
-- ---------------------------------------------------------------------
create table contacts (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references companies(id) on delete cascade,
  code          text,                       -- human-facing reference
  name          text not null,
  is_customer   boolean not null default false,
  is_vendor     boolean not null default false,
  email         text,
  phone         text,
  whatsapp      text,                       -- the channel orders arrive on
  instagram     text,
  address       text,
  city          text,
  state         text,
  postcode      text,
  country       text,
  payment_terms_days smallint not null default 0,
  credit_limit  numeric(14,2),
  notes         text,
  custom        jsonb not null default '{}'::jsonb,   -- user-defined fields
  active        boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index on contacts (company_id) where active;
create index on contacts (company_id, name);
-- lets an intake agent find "that customer who messaged from +234…"
create index on contacts (company_id, phone);
create index on contacts (company_id, whatsapp);

create trigger contacts_touch before update on contacts
  for each row execute function touch_updated_at();

-- ---------------------------------------------------------------------
-- Items: anything bought, made, held or sold
-- ---------------------------------------------------------------------
create type item_kind as enum ('raw_material','finished_good','service');

create table items (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null references companies(id) on delete cascade,
  kind            item_kind not null default 'finished_good',
  sku             text,
  name            text not null,
  description     text,
  unit            text not null default 'each',   -- each, kg, g, litre, hour
  -- Costing. purchase_price is the fallback when there is no movement
  -- history; actual cost comes from stock movements (0003).
  purchase_price  numeric(14,4) not null default 0,
  sales_price     numeric(14,4) not null default 0,
  tracked         boolean not null default true,  -- false for services and
                                                  -- made-to-order one-offs
  reorder_level   numeric(14,4),
  shelf_life_days smallint,                       -- food: drives expiry
  image_url       text,
  custom          jsonb not null default '{}'::jsonb,
  active          boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index on items (company_id) where active;
create index on items (company_id, kind);
create unique index on items (company_id, sku) where sku is not null;

create trigger items_touch before update on items
  for each row execute function touch_updated_at();

-- ---------------------------------------------------------------------
-- Recipes (bill of materials)
--
-- "One 8-inch chocolate cake consumes 0.6kg flour, 0.4kg sugar, 6 eggs."
-- This is what makes true cost per cake possible, and what tells her
-- she is short of flour before Saturday rather than on Saturday.
-- ---------------------------------------------------------------------
create table recipes (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references companies(id) on delete cascade,
  item_id       uuid not null references items(id) on delete cascade,
  name          text not null default 'Standard',
  yield_qty     numeric(14,4) not null default 1,     -- output per batch
  labour_minutes integer not null default 0,
  overhead_cost numeric(14,4) not null default 0,     -- gas, power, packaging
  notes         text,
  active        boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index on recipes (company_id, item_id) where active;

create table recipe_lines (
  id            uuid primary key default gen_random_uuid(),
  recipe_id     uuid not null references recipes(id) on delete cascade,
  component_id  uuid not null references items(id) on delete restrict,
  qty           numeric(14,4) not null check (qty > 0),
  unit          text,
  wastage_pct   numeric(5,2) not null default 0,      -- expected loss
  line_no       smallint not null default 1
);
create index on recipe_lines (recipe_id);

create trigger recipes_touch before update on recipes
  for each row execute function touch_updated_at();
