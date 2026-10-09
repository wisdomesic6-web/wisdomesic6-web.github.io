-- =====================================================================
-- 0003 — Stock as a ledger, and production
--
-- The Excel version computed stock as
--     SUMIFS(purchases) - SUMIFS(sales)
-- which cannot express a bakery at all: you never *buy* a cake, you make
-- it out of flour. It also had nowhere to record breakage, a stock count,
-- or an opening balance.
--
-- So stock becomes an append-only ledger of movements. On-hand is the sum
-- of the movements. Every reason a quantity can change gets a row, which
-- means the number is always explainable — you can point at why.
-- =====================================================================

create table locations (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  name        text not null,                 -- 'Main kitchen', 'Shop front'
  is_default  boolean not null default false,
  active      boolean not null default true
);
create index on locations (company_id) where active;
create unique index on locations (company_id) where is_default;

create type movement_reason as enum (
  'opening',        -- starting balance
  'purchase',       -- goods received from a supplier
  'sale',           -- sold / delivered to a customer
  'consumption',    -- used up by a production job
  'output',         -- produced by a production job
  'wastage',        -- burnt, dropped, expired, unsold
  'adjustment',     -- stock count correction
  'transfer_in',
  'transfer_out',
  'return_in',      -- customer returned
  'return_out'      -- returned to supplier
);

create table stock_movements (
  id            bigserial primary key,
  company_id    uuid not null references companies(id) on delete cascade,
  item_id       uuid not null references items(id) on delete restrict,
  location_id   uuid references locations(id) on delete set null,
  reason        movement_reason not null,
  -- Signed: positive adds to stock, negative removes. The check below
  -- keeps the sign honest against the reason.
  qty           numeric(14,4) not null check (qty <> 0),
  unit_cost     numeric(14,4),                -- cost at the time it moved
  batch_no      text,
  expires_on    date,
  -- what caused it: ('sales_order', uuid) / ('production_job', uuid) / …
  source_type   text,
  source_id     uuid,
  note          text,
  moved_at      timestamptz not null default now(),
  created_by    uuid references auth.users(id),
  created_at    timestamptz not null default now(),

  constraint qty_sign_matches_reason check (
    (reason in ('opening','purchase','output','adjustment','transfer_in','return_in')  and qty > 0) or
    (reason in ('sale','consumption','wastage','transfer_out','return_out')            and qty < 0) or
    (reason = 'adjustment')          -- adjustments may go either way
  )
);
create index on stock_movements (company_id, item_id, moved_at desc);
create index on stock_movements (source_type, source_id);
create index on stock_movements (company_id, expires_on) where expires_on is not null;

-- On-hand per item/location. A view keeps it impossible to drift from the
-- movements; if this ever gets slow we swap it for a materialized view
-- refreshed on write, without touching callers.
create view stock_on_hand as
select
  m.company_id,
  m.item_id,
  m.location_id,
  sum(m.qty)                                           as qty_on_hand,
  sum(m.qty * coalesce(m.unit_cost, 0)) filter (where m.qty > 0) as value_in,
  max(m.moved_at)                                      as last_moved_at
from stock_movements m
group by m.company_id, m.item_id, m.location_id;

-- Weighted-average cost: what a unit currently costs us, from what we
-- actually paid, rather than whatever the price list last said.
create or replace function item_avg_cost(p_item uuid)
returns numeric
language sql stable
as $$
  select case
           when sum(qty) filter (where qty > 0 and unit_cost is not null) > 0
           then sum(qty * unit_cost) filter (where qty > 0 and unit_cost is not null)
              / sum(qty)             filter (where qty > 0 and unit_cost is not null)
           else (select purchase_price from items where id = p_item)
         end
  from stock_movements
  where item_id = p_item;
$$;

-- ---------------------------------------------------------------------
-- Production jobs
--
-- For made-to-order work (a wedding cake) a job hangs off the sales order
-- line. For make-to-stock (a tray of bread for the counter) it stands
-- alone. Consuming materials and producing output both write movements,
-- so stock and cost stay in step automatically.
-- ---------------------------------------------------------------------
create type production_status as enum ('planned','in_progress','done','cancelled');

create table production_jobs (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null references companies(id) on delete cascade,
  job_no          text,
  item_id         uuid not null references items(id) on delete restrict,
  recipe_id       uuid references recipes(id) on delete set null,
  qty_planned     numeric(14,4) not null check (qty_planned > 0),
  qty_produced    numeric(14,4) not null default 0,
  qty_wasted      numeric(14,4) not null default 0,
  status          production_status not null default 'planned',
  -- when it must be ready; this is what drives her production calendar
  due_at          timestamptz,
  started_at      timestamptz,
  completed_at    timestamptz,
  -- costs captured at completion, so margin is real rather than estimated
  material_cost   numeric(14,2) not null default 0,
  labour_cost     numeric(14,2) not null default 0,
  overhead_cost   numeric(14,2) not null default 0,
  sales_order_line_id uuid,          -- set in 0004 (made-to-order link)
  notes           text,
  custom          jsonb not null default '{}'::jsonb,
  created_by      uuid references auth.users(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index on production_jobs (company_id, status, due_at);
create index on production_jobs (company_id, due_at);

create trigger production_jobs_touch before update on production_jobs
  for each row execute function touch_updated_at();

-- What a job actually consumed. Starts as a copy of the recipe, then gets
-- corrected to reality — she used 0.7kg, not the 0.6kg the recipe says.
create table production_consumption (
  id            uuid primary key default gen_random_uuid(),
  job_id        uuid not null references production_jobs(id) on delete cascade,
  component_id  uuid not null references items(id) on delete restrict,
  qty_planned   numeric(14,4) not null default 0,
  qty_used      numeric(14,4) not null default 0,
  unit_cost     numeric(14,4) not null default 0
);
create index on production_consumption (job_id);
