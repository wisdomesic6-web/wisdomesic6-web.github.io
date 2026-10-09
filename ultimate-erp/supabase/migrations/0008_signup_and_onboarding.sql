-- =====================================================================
-- 0008 — Sign-up, company creation, and demo data
--
-- 0006/0007 secured everything, which left a gap at the very start: a
-- brand-new user belongs to no company, so the tenant policies correctly
-- refuse to let them create one. And company_members may only be written
-- by an owner of that company, which nobody is yet.
--
-- The fix is not to loosen the policies but to provide one audited,
-- SECURITY DEFINER entry point that does the whole first step atomically.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Every auth user gets a profile row
-- ---------------------------------------------------------------------
create or replace function app.handle_new_user()
returns trigger language plpgsql security definer
set search_path = public
as $$
begin
  insert into profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function app.handle_new_user();

-- ---------------------------------------------------------------------
-- Create a business and make the caller its owner.
--
-- SECURITY DEFINER because the caller is, by definition, not yet a member
-- of anything. It still refuses anonymous callers, and it only ever makes
-- the caller an owner of a company it just created — it cannot be used to
-- join an existing one.
-- ---------------------------------------------------------------------
create or replace function app.create_company(
  p_name text,
  p_industry text default null,
  p_currency char(3) default 'NGN',
  p_country text default 'NG'
) returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_company uuid;
  v_user    uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'You must be signed in to create a business';
  end if;
  if coalesce(trim(p_name), '') = '' then
    raise exception 'A business name is required';
  end if;

  insert into companies (name, industry, currency, country)
  values (trim(p_name), p_industry, p_currency, p_country)
  returning id into v_company;

  insert into company_members (company_id, user_id, role)
  values (v_company, v_user, 'owner');

  insert into locations (company_id, name, is_default)
  values (v_company, 'Main location', true);

  perform seed_chart_of_accounts(v_company);

  insert into company_modules (company_id, module, enabled)
  select v_company, m, true
  from unnest(array['sales','purchasing','inventory','production','accounting']) as m;

  return v_company;
end;
$$;

revoke execute on function app.create_company(text, text, char, text) from public, anon;
grant   execute on function app.create_company(text, text, char, text) to authenticated;

-- ---------------------------------------------------------------------
-- Post a spend as a balanced pair: debit the expense, credit cash.
-- Keeps the "money out" screens honest without asking anyone to think
-- in debits and credits.
-- ---------------------------------------------------------------------
create or replace function app.post_expense(
  p_company uuid, p_date date, p_memo text, p_account_code text, p_amount numeric
) returns uuid
language plpgsql security definer
set search_path = public
as $$
declare v_entry uuid; v_expense uuid; v_cash uuid;
begin
  select id into v_expense from accounts where company_id = p_company and code = p_account_code;
  select id into v_cash    from accounts where company_id = p_company and system_tag = 'cash';
  if v_expense is null or v_cash is null then
    raise exception 'Chart of accounts is missing % or cash', p_account_code;
  end if;

  insert into journal_entries (company_id, entry_date, memo, source_type)
  values (p_company, p_date, p_memo, 'manual')
  returning id into v_entry;

  insert into journal_lines (entry_id, account_id, amount, line_no) values
    (v_entry, v_expense,  p_amount, 1),   -- debit: the cost
    (v_entry, v_cash,    -p_amount, 2);   -- credit: the cash that left

  update journal_entries set posted = true where id = v_entry;
  return v_entry;
end;
$$;

revoke execute on function app.post_expense(uuid, date, text, text, numeric) from public, anon;
grant   execute on function app.post_expense(uuid, date, text, text, numeric) to authenticated;

-- ---------------------------------------------------------------------
-- Optional starting data, so a new business is not staring at six empty
-- screens. Only ever writes into a company the caller already owns.
-- ---------------------------------------------------------------------
create or replace function app.seed_demo_data(p_company uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_loc    uuid;
  v_flour  uuid; v_sugar uuid; v_cocoa uuid; v_butter uuid;
  v_eggs   uuid; v_milk  uuid; v_vanilla uuid;
  v_choc   uuid; v_vani  uuid; v_velvet uuid; v_cup uuid;
  v_recipe uuid;
  v_c1 uuid; v_c2 uuid; v_c3 uuid; v_c4 uuid; v_c5 uuid;
  v_o1 uuid; v_o2 uuid; v_o3 uuid;
  v_line uuid;
begin
  if not app.auth_has_role(p_company, array['owner','admin']::company_role[]) then
    raise exception 'Only an owner or admin may seed a company';
  end if;
  if exists (select 1 from items where company_id = p_company) then
    return;   -- already has data; do nothing rather than duplicate
  end if;

  select id into v_loc from locations where company_id = p_company and is_default limit 1;

  -- raw materials
  insert into items (company_id, kind, name, unit, purchase_price, reorder_level)
  values (p_company,'raw_material','Flour','kg',1200,10)           returning id into v_flour;
  insert into items (company_id, kind, name, unit, purchase_price, reorder_level)
  values (p_company,'raw_material','Sugar','kg',900,10)            returning id into v_sugar;
  insert into items (company_id, kind, name, unit, purchase_price, reorder_level)
  values (p_company,'raw_material','Cocoa powder','kg',6000,3)     returning id into v_cocoa;
  insert into items (company_id, kind, name, unit, purchase_price, reorder_level)
  values (p_company,'raw_material','Butter','kg',4500,5)           returning id into v_butter;
  insert into items (company_id, kind, name, unit, purchase_price, reorder_level)
  values (p_company,'raw_material','Eggs','pcs',150,60)            returning id into v_eggs;
  insert into items (company_id, kind, name, unit, purchase_price, reorder_level)
  values (p_company,'raw_material','Milk','L',1400,10)             returning id into v_milk;
  insert into items (company_id, kind, name, unit, purchase_price, reorder_level)
  values (p_company,'raw_material','Vanilla extract','ml',35,200)  returning id into v_vanilla;

  -- what she sells
  insert into items (company_id, kind, name, unit, sales_price, tracked, shelf_life_days)
  values (p_company,'finished_good','Chocolate Cake (2kg)','each',18000,false,4) returning id into v_choc;
  insert into items (company_id, kind, name, unit, sales_price, tracked, shelf_life_days)
  values (p_company,'finished_good','Vanilla Cake (3kg)','each',24000,false,4)   returning id into v_vani;
  insert into items (company_id, kind, name, unit, sales_price, tracked, shelf_life_days)
  values (p_company,'finished_good','Red Velvet Cake (2kg)','each',21000,false,4) returning id into v_velvet;
  insert into items (company_id, kind, name, unit, sales_price, tracked, shelf_life_days)
  values (p_company,'finished_good','Cupcakes (dozen)','each',9000,false,3)      returning id into v_cup;

  -- a recipe, so cost per cake is real rather than guessed
  insert into recipes (company_id, item_id, name, yield_qty, labour_minutes, overhead_cost)
  values (p_company, v_choc, 'Standard', 2, 90, 1200) returning id into v_recipe;
  insert into recipe_lines (recipe_id, component_id, qty, unit, line_no) values
    (v_recipe, v_flour,  0.5,  'kg', 1),
    (v_recipe, v_sugar,  0.35, 'kg', 2),
    (v_recipe, v_cocoa,  0.2,  'kg', 3),
    (v_recipe, v_butter, 0.2,  'kg', 4),
    (v_recipe, v_eggs,   4,    'pcs',5),
    (v_recipe, v_milk,   0.25, 'L',  6),
    (v_recipe, v_vanilla,10,   'ml', 7);

  -- customers
  insert into contacts (company_id, name, is_customer, phone, whatsapp, city)
  values (p_company,'Grace Johnson',  true,'+234 812 345 4567','+234 812 345 4567','Lagos') returning id into v_c1;
  insert into contacts (company_id, name, is_customer, phone, city)
  values (p_company,'Tolu''s Kitchen',true,'+234 803 221 9087','Ikeja')  returning id into v_c2;
  insert into contacts (company_id, name, is_customer, phone, city)
  values (p_company,'Faith Events',   true,'+234 701 554 2210','Lagos')  returning id into v_c3;
  insert into contacts (company_id, name, is_customer, phone, city)
  values (p_company,'Mariam Stores',  true,'+234 814 009 7745','Surulere') returning id into v_c4;
  insert into contacts (company_id, name, is_customer, phone, whatsapp, city)
  values (p_company,'Amina Bello',    true,'+234 909 110 2234','+234 909 110 2234','Lagos') returning id into v_c5;

  -- ingredients bought in
  insert into stock_movements (company_id, item_id, location_id, reason, qty, unit_cost, note) values
    (p_company, v_flour,  v_loc,'purchase', 50, 1200,'Opening purchase'),
    (p_company, v_sugar,  v_loc,'purchase', 25,  900,'Opening purchase'),
    (p_company, v_cocoa,  v_loc,'purchase',  8, 6000,'Opening purchase'),
    (p_company, v_butter, v_loc,'purchase', 10, 4500,'Opening purchase'),
    (p_company, v_eggs,   v_loc,'purchase',120,  150,'Opening purchase'),
    (p_company, v_milk,   v_loc,'purchase', 20, 1400,'Opening purchase'),
    (p_company, v_vanilla,v_loc,'purchase',500,   35,'Opening purchase');

  -- two live orders and one delivered
  insert into orders (company_id, doc_type, doc_no, contact_id, status, source_channel,
                      order_date, due_at, tax_rate, delivery_fee)
  values (p_company,'sales_order', next_doc_number(p_company,'sales_order'), v_c1,
          'in_production','whatsapp', current_date - 2, now() + interval '1 day', 0.075, 3000)
  returning id into v_o1;
  insert into order_lines (order_id, item_id, description, qty, unit_price, line_no)
  values (v_o1, v_choc, 'Chocolate Cake (2kg), gold trim', 2, 18000, 1) returning id into v_line;
  insert into payments (company_id, direction, order_id, contact_id, amount, method, is_deposit)
  values (p_company,'in', v_o1, v_c1, 20000,'transfer', true);
  insert into production_jobs (company_id, item_id, recipe_id, qty_planned, status,
                               due_at, sales_order_line_id)
  values (p_company, v_choc, v_recipe, 2, 'in_progress', now() + interval '1 day', v_line);

  insert into orders (company_id, doc_type, doc_no, contact_id, status, source_channel,
                      order_date, due_at, tax_rate, delivery_fee)
  values (p_company,'sales_order', next_doc_number(p_company,'sales_order'), v_c2,
          'confirmed','instagram', current_date - 1, now() + interval '3 days', 0.075, 2500)
  returning id into v_o2;
  insert into order_lines (order_id, item_id, description, qty, unit_price, line_no)
  values (v_o2, v_vani, 'Vanilla Cake (3kg)', 3, 24000, 1);
  insert into payments (company_id, direction, order_id, contact_id, amount, method, is_deposit)
  values (p_company,'in', v_o2, v_c2, 30000,'cash', true);

  insert into orders (company_id, doc_type, doc_no, contact_id, status, source_channel,
                      order_date, due_at, tax_rate, delivery_fee)
  values (p_company,'sales_order', next_doc_number(p_company,'sales_order'), v_c3,
          'delivered','phone', current_date - 8, now() - interval '2 days', 0.075, 2000)
  returning id into v_o3;
  insert into order_lines (order_id, item_id, description, qty, unit_price, line_no, unit_cost)
  values (v_o3, v_velvet, 'Red Velvet Cake (2kg)', 4, 21000, 1, 4100);
  insert into payments (company_id, direction, order_id, contact_id, amount, method)
  values (p_company,'in', v_o3, v_c3, 92450,'transfer');

  -- an enquiry that has gone quiet, which is where the money leaks
  insert into orders (company_id, doc_type, doc_no, contact_id, status, source_channel,
                      order_date, due_at, tax_rate, notes)
  values (p_company,'quote', next_doc_number(p_company,'quote'), v_c5,
          'quoted','whatsapp', current_date - 3, now() + interval '17 days', 0.075,
          '3-tier wedding cake, white and gold, "Tunde & Amina". About 120 guests.');

  -- a couple of running costs, posted as proper balanced entries
  perform app.post_expense(p_company, current_date - 5, 'Monthly rent',    '6100', 150000);
  perform app.post_expense(p_company, current_date - 3, 'Gas for the oven','6200',  28000);
  perform app.post_expense(p_company, current_date - 1, 'Packaging boxes', '6400',  19500);
end;
$$;

revoke execute on function app.seed_demo_data(uuid) from public, anon;
grant   execute on function app.seed_demo_data(uuid) to authenticated;
