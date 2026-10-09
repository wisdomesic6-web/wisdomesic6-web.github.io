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
