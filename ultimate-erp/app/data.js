/* =====================================================================
   The only file that talks to the database.
   Screens call these functions and never touch Supabase directly, so the
   storage layer stays swappable and every query lives in one place.
   ===================================================================== */

const SB = window.supabase.createClient(
  window.ERP_CONFIG.url,
  window.ERP_CONFIG.publishableKey,
  { auth: { persistSession: true, autoRefreshToken: true } }
);

export const db = {
  /* ---------- auth ---------- */
  async signIn(email, password) {
    const { data, error } = await SB.auth.signInWithPassword({ email, password });
    if (error) throw new Error(friendly(error.message));
    return data.user;
  },

  async signUp(email, password, fullName) {
    const { data, error } = await SB.auth.signUp({
      email, password, options: { data: { full_name: fullName } }
    });
    if (error) throw new Error(friendly(error.message));
    // With email confirmation on, there is no session yet — say so plainly.
    return { user: data.user, needsConfirmation: !data.session };
  },

  async signOut() { await SB.auth.signOut(); },

  async currentUser() {
    const { data } = await SB.auth.getSession();
    return data.session ? data.session.user : null;
  },

  onAuthChange(fn) { SB.auth.onAuthStateChange((_e, s) => fn(s ? s.user : null)); },

  /* ---------- company ---------- */
  async myCompanies() {
    const { data, error } = await SB
      .from('company_members')
      .select('role, company:companies(id, name, industry, currency, country)')
      .eq('active', true);
    if (error) throw error;
    return (data || []).map(r => ({ ...r.company, role: r.role }));
  },

  async createCompany(name, industry) {
    const { data, error } = await SB.rpc('create_company', {
      p_name: name, p_industry: industry
    });
    if (error) throw error;
    return data;
  },

  async seedDemoData(companyId) {
    const { error } = await SB.rpc('seed_demo_data', { p_company: companyId });
    if (error) throw error;
  },

  /* ---------- reads ----------
     Row-level security scopes all of these to the signed-in user's
     company, so no query here filters by company_id by hand. */

  async orders() {
    const { data, error } = await SB
      .from('orders')
      .select(`id, doc_no, doc_type, status, source_channel, order_date, due_at,
               tax_rate, delivery_fee, notes, delivery_address,
               contact:contacts(id, name, phone, whatsapp),
               lines:order_lines(id, description, qty, unit_price, discount, unit_cost,
                                 item:items(id, name)),
               payments(id, amount, method, is_deposit, paid_at)`)
      .order('due_at', { ascending: true });
    if (error) throw error;
    return (data || []).map(withTotals);
  },

  async order(id) {
    const all = await this.orders();
    return all.find(o => o.id === id) || null;
  },

  async contacts() {
    const { data, error } = await SB.from('contacts')
      .select('*').eq('active', true).order('name');
    if (error) throw error;
    return data || [];
  },

  async items() {
    const { data, error } = await SB.from('items')
      .select('*').eq('active', true).order('kind').order('name');
    if (error) throw error;
    return data || [];
  },

  async stockOnHand() {
    const { data, error } = await SB.from('stock_on_hand').select('*');
    if (error) throw error;
    const byItem = new Map();
    for (const r of data || []) byItem.set(r.item_id, (byItem.get(r.item_id) || 0) + Number(r.qty_on_hand));
    return byItem;
  },

  async productionJobs() {
    const { data, error } = await SB.from('production_jobs')
      .select(`id, qty_planned, qty_produced, status, due_at, material_cost,
               item:items(id, name), recipe:recipes(id, name)`)
      .order('due_at');
    if (error) throw error;
    return data || [];
  },

  async recipes() {
    const { data, error } = await SB.from('recipes')
      .select(`id, name, yield_qty, labour_minutes, overhead_cost,
               item:items!recipes_item_id_fkey(id, name, sales_price),
               lines:recipe_lines(id, qty, unit, wastage_pct,
                                  component:items!recipe_lines_component_id_fkey(id, name, unit, purchase_price))`)
      .eq('active', true);
    if (error) throw error;
    return data || [];
  },

  async trialBalance() {
    const { data, error } = await SB.from('trial_balance').select('*').order('code');
    if (error) throw error;
    return data || [];
  },

  /* ---------- writes ---------- */
  async addPayment(companyId, orderId, contactId, amount, method, isDeposit) {
    const { error } = await SB.from('payments').insert({
      company_id: companyId, direction: 'in', order_id: orderId,
      contact_id: contactId, amount, method, is_deposit: !!isDeposit
    });
    if (error) throw error;
  },

  async setOrderStatus(orderId, status) {
    const { error } = await SB.from('orders').update({ status }).eq('id', orderId);
    if (error) throw error;
  },

  /* Creating an order: the header gets a gap-free document number from
     the database, then the lines, then an optional deposit. Done in that
     order so a failure never leaves a numbered order with no contents. */
  async createOrder(companyId, { contactId, contactName, dueAt, taxRate, deliveryFee,
                                 notes, sourceChannel, docType, status, lines, deposit }) {
    const { data: docNo, error: numErr } = await SB.rpc('next_doc_number', {
      p_company: companyId, p_doc_type: docType || 'sales_order' });
    if (numErr) throw numErr;

    const { data: order, error } = await SB.from('orders').insert({
      company_id: companyId, doc_type: docType || 'sales_order', doc_no: docNo,
      contact_id: contactId || null, contact_name: contactName || null,
      status: status || 'confirmed', source_channel: sourceChannel || 'manual',
      due_at: dueAt || null, tax_rate: taxRate ?? 0, delivery_fee: deliveryFee ?? 0,
      notes: notes || null
    }).select().single();
    if (error) throw error;

    const rows = (lines || []).filter(l => l.description || l.itemId).map((l, i) => ({
      order_id: order.id, item_id: l.itemId || null,
      description: l.description || '', qty: Number(l.qty) || 0,
      unit_price: Number(l.unitPrice) || 0, line_no: i + 1
    }));
    if (rows.length) {
      const { error: lineErr } = await SB.from('order_lines').insert(rows);
      if (lineErr) throw lineErr;
    }
    if (Number(deposit) > 0) {
      await this.addPayment(companyId, order.id, contactId || null,
        Number(deposit), 'transfer', true);
    }
    return order;
  },

  async updateOrder(orderId, fields) {
    const { error } = await SB.from('orders').update(fields).eq('id', orderId);
    if (error) throw error;
  },

  async replaceOrderLines(orderId, lines) {
    const { error: delErr } = await SB.from('order_lines').delete().eq('order_id', orderId);
    if (delErr) throw delErr;
    const rows = (lines || []).filter(l => l.description || l.itemId).map((l, i) => ({
      order_id: orderId, item_id: l.itemId || null,
      description: l.description || '', qty: Number(l.qty) || 0,
      unit_price: Number(l.unitPrice) || 0, line_no: i + 1
    }));
    if (rows.length) {
      const { error } = await SB.from('order_lines').insert(rows);
      if (error) throw error;
    }
  },

  /* A quote becomes an order. It keeps its own number so the thread back
     to the original enquiry is not lost. */
  async convertQuoteToOrder(companyId, orderId, deposit, contactId) {
    const { data: docNo, error: numErr } = await SB.rpc('next_doc_number', {
      p_company: companyId, p_doc_type: 'sales_order' });
    if (numErr) throw numErr;
    const { error } = await SB.from('orders')
      .update({ doc_type: 'sales_order', doc_no: docNo, status: 'confirmed' })
      .eq('id', orderId);
    if (error) throw error;
    if (Number(deposit) > 0) {
      await this.addPayment(companyId, orderId, contactId || null, Number(deposit), 'transfer', true);
    }
  },

  async recordExpense(companyId, date, memo, accountCode, amount) {
    const { error } = await SB.rpc('post_expense', {
      p_company: companyId, p_date: date, p_memo: memo,
      p_account_code: accountCode, p_amount: amount });
    if (error) throw error;
  },

  async expenseAccounts() {
    const { data, error } = await SB.from('accounts')
      .select('code, name').eq('type', 'expense').eq('active', true).order('code');
    if (error) throw error;
    return data || [];
  },

  async createItem(companyId, fields) {
    const { data, error } = await SB.from('items')
      .insert({ company_id: companyId, ...fields }).select().single();
    if (error) throw error;
    return data;
  },

  /* Finishing a job writes what was really consumed, what was wasted and
     what came out — four kinds of movement, so the stock figure stays
     explainable afterwards. */
  async completeProduction(companyId, jobId, { produced, wasted, consumption, locationId, itemId }) {
    const moves = [];
    for (const c of (consumption || [])) {
      if (Number(c.qtyUsed) > 0) moves.push({
        company_id: companyId, item_id: c.componentId, location_id: locationId || null,
        reason: 'consumption', qty: -Math.abs(Number(c.qtyUsed)),
        unit_cost: Number(c.unitCost) || null,
        source_type: 'production_job', source_id: jobId });
      if (Number(c.qtyWasted) > 0) moves.push({
        company_id: companyId, item_id: c.componentId, location_id: locationId || null,
        reason: 'wastage', qty: -Math.abs(Number(c.qtyWasted)),
        unit_cost: Number(c.unitCost) || null,
        source_type: 'production_job', source_id: jobId });
    }
    const materialCost = (consumption || []).reduce(
      (s, c) => s + (Number(c.qtyUsed) + Number(c.qtyWasted || 0)) * (Number(c.unitCost) || 0), 0);

    if (Number(produced) > 0) moves.push({
      company_id: companyId, item_id: itemId, location_id: locationId || null,
      reason: 'output', qty: Math.abs(Number(produced)),
      unit_cost: Number(produced) ? materialCost / Number(produced) : null,
      source_type: 'production_job', source_id: jobId });

    if (moves.length) {
      const { error } = await SB.from('stock_movements').insert(moves);
      if (error) throw error;
    }
    const { error: jobErr } = await SB.from('production_jobs').update({
      status: 'done', qty_produced: Number(produced) || 0, qty_wasted: Number(wasted) || 0,
      completed_at: new Date().toISOString(),
      material_cost: Math.round(materialCost * 100) / 100
    }).eq('id', jobId);
    if (jobErr) throw jobErr;
  },

  async startProduction(jobId) {
    const { error } = await SB.from('production_jobs')
      .update({ status: 'in_progress', started_at: new Date().toISOString() }).eq('id', jobId);
    if (error) throw error;
  },

  async defaultLocation() {
    const { data, error } = await SB.from('locations')
      .select('id').eq('is_default', true).limit(1).maybeSingle();
    if (error) throw error;
    return data ? data.id : null;
  },

  async addContact(companyId, fields) {
    const { data, error } = await SB.from('contacts')
      .insert({ company_id: companyId, is_customer: true, ...fields })
      .select().single();
    if (error) throw error;
    return data;
  }
};

/* ---------- derived values ----------
   These mirror the SQL views exactly. Order totals are never stored:
   the workbook stored them and 20 of its 41 orders had drifted. */
export function withTotals(o) {
  const subtotal = (o.lines || []).reduce(
    (s, l) => s + Number(l.qty) * Number(l.unit_price) - Number(l.discount || 0), 0);
  const tax = round2(subtotal * Number(o.tax_rate || 0));
  const total = round2(subtotal + tax + Number(o.delivery_fee || 0));
  const paid = round2((o.payments || []).reduce((s, p) => s + Number(p.amount), 0));
  const cost = (o.lines || []).reduce((s, l) => s + Number(l.qty) * Number(l.unit_cost || 0), 0);
  return { ...o, subtotal: round2(subtotal), tax, total, paid,
           balance: round2(total - paid), cost: round2(cost) };
}

/* Per unit, because that is how a cake is sold. Comparing a unit price
   against a whole batch is what made an 80% margin read as 14%. */
export function costRecipe(r) {
  const ingredients = (r.lines || []).reduce(
    (s, l) => s + Number(l.qty) * Number(l.component?.purchase_price || 0), 0);
  const labour = (Number(r.labour_minutes || 0) / 60) * 1000;
  const overhead = Number(r.overhead_cost || 0);
  const batch = ingredients + labour + overhead;
  const yieldQty = Number(r.yield_qty) || 1;
  const perUnit = batch / yieldQty;
  const sell = Number(r.item?.sales_price || 0);
  const profit = sell - perUnit;
  return { ingredients, labour, overhead, batch, perUnit, sell, profit,
           margin: sell ? (profit / sell) * 100 : 0 };
}

const round2 = n => Math.round((Number(n) + Number.EPSILON) * 100) / 100;

/* Supabase's wording is for developers; these people are not developers. */
function friendly(msg) {
  const m = String(msg || '');
  if (/Invalid login credentials/i.test(m)) return 'That email and password do not match.';
  if (/Email not confirmed/i.test(m))       return 'Check your email and confirm the address first.';
  if (/User already registered/i.test(m))   return 'That email already has an account — sign in instead.';
  if (/Password should be/i.test(m))        return 'Use a password of at least 6 characters.';
  if (/rate limit|too many/i.test(m))       return 'Too many attempts. Wait a minute and try again.';
  if (/Failed to fetch|NetworkError/i.test(m)) return 'No connection. Check your network and try again.';
  return m;
}

export { SB };
