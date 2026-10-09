-- =====================================================================
-- A real custom-cake job, start to finish, exercised against the schema.
--
--   1. A WhatsApp enquiry becomes a quote, then a confirmed order
--   2. Flour and sugar are bought in
--   3. A production job consumes them and produces the cake
--   4. Some batter is wasted
--   5. Deposit, then balance, are paid
--   6. The books balance and the margin is real
--
-- Run with ON_ERROR_STOP=1; every check raises instead of printing, so a
-- silent pass means it genuinely worked.
-- =====================================================================

\set ON_ERROR_STOP on
begin;

create or replace function check_eq(p_label text, p_got numeric, p_want numeric)
returns void language plpgsql as $$
begin
  if p_got is distinct from p_want then
    raise exception 'FAILED %: got %, expected %', p_label, p_got, p_want;
  end if;
  raise notice 'ok  %  = %', p_label, p_got;
end;
$$;

-- ---------------------------------------------------------------------
-- Company, chart of accounts, a second company to prove isolation later
-- ---------------------------------------------------------------------
insert into companies (id, name, industry, currency)
values ('11111111-1111-1111-1111-111111111111', 'Sweet Things Bakery', 'bakery', 'NGN'),
       ('22222222-2222-2222-2222-222222222222', 'Someone Else Ltd',   'retail', 'NGN');

select seed_chart_of_accounts('11111111-1111-1111-1111-111111111111');

insert into locations (id, company_id, name, is_default)
values ('aaaaaaaa-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111', 'Main kitchen', true);

-- ---------------------------------------------------------------------
-- Items: two raw materials, one made-to-order cake
-- ---------------------------------------------------------------------
insert into items (id, company_id, kind, name, unit, purchase_price, sales_price) values
 ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
  'raw_material', 'Flour', 'kg', 1200, 0),
 ('bbbbbbbb-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
  'raw_material', 'Sugar', 'kg', 900, 0),
 ('bbbbbbbb-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111',
  'finished_good', '8-inch chocolate cake', 'each', 0, 25000);

-- Recipe: one cake = 0.6kg flour + 0.4kg sugar, 90 min labour, 1500 overhead
insert into recipes (id, company_id, item_id, yield_qty, labour_minutes, overhead_cost)
values ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        'bbbbbbbb-0000-0000-0000-000000000003', 1, 90, 1500);

insert into recipe_lines (recipe_id, component_id, qty, unit, line_no) values
 ('cccccccc-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', 0.6, 'kg', 1),
 ('cccccccc-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000002', 0.4, 'kg', 2);

-- ---------------------------------------------------------------------
-- 1. The enquiry arrives on WhatsApp
-- ---------------------------------------------------------------------
insert into contacts (id, company_id, name, is_customer, whatsapp, phone)
values ('dddddddd-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        'Mrs Adeyemi', true, '+2348030000000', '+2348030000000');

insert into orders (id, company_id, doc_type, doc_no, contact_id, status,
                    source_channel, due_at, tax_rate, delivery_fee)
values ('eeeeeeee-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        'sales_order',
        next_doc_number('11111111-1111-1111-1111-111111111111', 'sales_order'),
        'dddddddd-0000-0000-0000-000000000001', 'enquiry', 'whatsapp',
        now() + interval '5 days', 0.075, 3000);

insert into order_lines (order_id, item_id, description, qty, unit_price, line_no)
values ('eeeeeeee-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000003',
        '8-inch chocolate cake, gold trim, "Happy 40th"', 1, 25000, 1);

-- totals: 25000 subtotal, +7.5% tax = 1875, +3000 delivery = 29875
select check_eq('order subtotal', (select subtotal from order_totals
                where order_id = 'eeeeeeee-0000-0000-0000-000000000001'), 25000);
select check_eq('order tax',      (select tax from order_totals
                where order_id = 'eeeeeeee-0000-0000-0000-000000000001'), 1875);
select check_eq('order total',    (select total from order_totals
                where order_id = 'eeeeeeee-0000-0000-0000-000000000001'), 29875);

-- document numbering produced a readable, year-scoped reference
do $$
declare v text;
begin
  select doc_no into v from orders where id = 'eeeeeeee-0000-0000-0000-000000000001';
  if v !~ '^SAL-\d{4}-0001$' then
    raise exception 'FAILED doc numbering: got %', v;
  end if;
  raise notice 'ok  doc_no = %', v;
end;
$$;

update orders set status = 'confirmed' where id = 'eeeeeeee-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------------
-- 2. Buy ingredients — 10kg flour at 1250, 5kg sugar at 950
-- ---------------------------------------------------------------------
insert into stock_movements (company_id, item_id, location_id, reason, qty, unit_cost, source_type)
values
 ('11111111-1111-1111-1111-111111111111', 'bbbbbbbb-0000-0000-0000-000000000001',
  'aaaaaaaa-0000-0000-0000-000000000001', 'purchase', 10, 1250, 'manual'),
 ('11111111-1111-1111-1111-111111111111', 'bbbbbbbb-0000-0000-0000-000000000002',
  'aaaaaaaa-0000-0000-0000-000000000001', 'purchase', 5, 950, 'manual');

select check_eq('flour on hand after purchase',
  (select qty_on_hand from stock_on_hand where item_id = 'bbbbbbbb-0000-0000-0000-000000000001'), 10);

-- ---------------------------------------------------------------------
-- 3 & 4. Produce the cake. She actually used 0.7kg flour (spilled some),
--        and wasted 0.1kg of it — reality, not the recipe.
-- ---------------------------------------------------------------------
insert into production_jobs (id, company_id, item_id, recipe_id, qty_planned,
                             status, due_at, sales_order_line_id)
values ('ffffffff-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        'bbbbbbbb-0000-0000-0000-000000000003', 'cccccccc-0000-0000-0000-000000000001',
        1, 'in_progress', now() + interval '4 days',
        (select id from order_lines where order_id = 'eeeeeeee-0000-0000-0000-000000000001'));

insert into production_consumption (job_id, component_id, qty_planned, qty_used, unit_cost) values
 ('ffffffff-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', 0.6, 0.7, 1250),
 ('ffffffff-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000002', 0.4, 0.4, 950);

insert into stock_movements (company_id, item_id, location_id, reason, qty, unit_cost,
                             source_type, source_id) values
 ('11111111-1111-1111-1111-111111111111', 'bbbbbbbb-0000-0000-0000-000000000001',
  'aaaaaaaa-0000-0000-0000-000000000001', 'consumption', -0.7, 1250,
  'production_job', 'ffffffff-0000-0000-0000-000000000001'),
 ('11111111-1111-1111-1111-111111111111', 'bbbbbbbb-0000-0000-0000-000000000002',
  'aaaaaaaa-0000-0000-0000-000000000001', 'consumption', -0.4, 950,
  'production_job', 'ffffffff-0000-0000-0000-000000000001'),
 ('11111111-1111-1111-1111-111111111111', 'bbbbbbbb-0000-0000-0000-000000000001',
  'aaaaaaaa-0000-0000-0000-000000000001', 'wastage', -0.1, 1250,
  'production_job', 'ffffffff-0000-0000-0000-000000000001'),
 ('11111111-1111-1111-1111-111111111111', 'bbbbbbbb-0000-0000-0000-000000000003',
  'aaaaaaaa-0000-0000-0000-000000000001', 'output', 1, 2630,
  'production_job', 'ffffffff-0000-0000-0000-000000000001');

-- flour: 10 bought − 0.7 used − 0.1 wasted = 9.2
select check_eq('flour after production and wastage',
  (select qty_on_hand from stock_on_hand where item_id = 'bbbbbbbb-0000-0000-0000-000000000001'), 9.2);
select check_eq('finished cakes on hand',
  (select qty_on_hand from stock_on_hand where item_id = 'bbbbbbbb-0000-0000-0000-000000000003'), 1);

-- true cost: 0.7×1250 + 0.4×950 = 875 + 380 = 1255 material, +1500 overhead = 2755
update production_jobs
   set qty_produced = 1, qty_wasted = 0.1, status = 'done', completed_at = now(),
       material_cost = (select sum(qty_used * unit_cost) from production_consumption
                         where job_id = 'ffffffff-0000-0000-0000-000000000001'),
       overhead_cost = 1500
 where id = 'ffffffff-0000-0000-0000-000000000001';

select check_eq('material cost from actual usage',
  (select material_cost from production_jobs where id = 'ffffffff-0000-0000-0000-000000000001'), 1255);

update order_lines set unit_cost = 2755
 where order_id = 'eeeeeeee-0000-0000-0000-000000000001';

select check_eq('order cost',
  (select cost from order_totals where order_id = 'eeeeeeee-0000-0000-0000-000000000001'), 2755);

-- ---------------------------------------------------------------------
-- 5. Deposit of 15000, then the balance
-- ---------------------------------------------------------------------
insert into payments (company_id, direction, order_id, contact_id, amount, method, is_deposit)
values ('11111111-1111-1111-1111-111111111111', 'in', 'eeeeeeee-0000-0000-0000-000000000001',
        'dddddddd-0000-0000-0000-000000000001', 15000, 'transfer', true);

select check_eq('balance after deposit',
  (select balance from order_balances where order_id = 'eeeeeeee-0000-0000-0000-000000000001'), 14875);

insert into payments (company_id, direction, order_id, contact_id, amount, method)
values ('11111111-1111-1111-1111-111111111111', 'in', 'eeeeeeee-0000-0000-0000-000000000001',
        'dddddddd-0000-0000-0000-000000000001', 14875, 'cash');

select check_eq('balance after final payment',
  (select balance from order_balances where order_id = 'eeeeeeee-0000-0000-0000-000000000001'), 0);

-- ---------------------------------------------------------------------
-- 6. The books. Sale posted: debit cash 29875, credit sales 28000, tax 1875
-- ---------------------------------------------------------------------
insert into journal_entries (id, company_id, entry_date, memo, source_type, source_id)
values ('99999999-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        current_date, 'Cake order SAL-0001', 'order', 'eeeeeeee-0000-0000-0000-000000000001');

insert into journal_lines (entry_id, account_id, amount, line_no)
select '99999999-0000-0000-0000-000000000001', a.id, v.amt, v.ln
from (values
  ('cash',   29875::numeric, 1::smallint),
  ('sales', -28000::numeric, 2::smallint),
  ('tax',    -1875::numeric, 3::smallint)
) as v(tag, amt, ln)
join accounts a
  on a.system_tag = v.tag
 and a.company_id = '11111111-1111-1111-1111-111111111111';

update journal_entries set posted = true where id = '99999999-0000-0000-0000-000000000001';

select check_eq('journal balances to zero',
  (select sum(amount) from journal_lines where entry_id = '99999999-0000-0000-0000-000000000001'), 0);

-- and an unbalanced entry must be refused
do $$
declare v_ok boolean := false;
begin
  insert into journal_entries (id, company_id, memo)
  values ('99999999-0000-0000-0000-000000000002',
          '11111111-1111-1111-1111-111111111111', 'deliberately wrong');
  insert into journal_lines (entry_id, account_id, amount)
  select '99999999-0000-0000-0000-000000000002', id, 500 from accounts
   where system_tag = 'cash' and company_id = '11111111-1111-1111-1111-111111111111';
  begin
    update journal_entries set posted = true where id = '99999999-0000-0000-0000-000000000002';
  exception when others then
    v_ok := true;
    raise notice 'ok  unbalanced entry rejected: %', sqlerrm;
  end;
  if not v_ok then
    raise exception 'FAILED: an unbalanced journal entry was allowed to post';
  end if;
end;
$$;

-- margin: 29875 total − 1875 tax − 3000 delivery − 2755 cost
select check_eq('gross margin on the job',
  (select t.total - t.tax - o.delivery_fee - t.cost
     from order_totals t join orders o on o.id = t.order_id
    where t.order_id = 'eeeeeeee-0000-0000-0000-000000000001'), 22245);

-- the audit trail recorded the work
do $$
declare n int;
begin
  select count(*) into n from audit_log
   where company_id = '11111111-1111-1111-1111-111111111111';
  if n < 10 then raise exception 'FAILED: audit log only has % rows', n; end if;
  raise notice 'ok  audit log captured % changes', n;
end;
$$;

rollback;
