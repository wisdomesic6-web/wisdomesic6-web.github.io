/* =====================================================================
   Screens and routing. All data access goes through data.js.
   ===================================================================== */
import { db, costRecipe } from './data.js';

const $  = s => document.querySelector(s);
const $$ = s => Array.from(document.querySelectorAll(s));
const esc = v => String(v ?? '').replace(/[&<>"']/g,
  c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money  = n => '₦' + Number(n||0).toLocaleString('en-NG',{minimumFractionDigits:2,maximumFractionDigits:2});
const money0 = n => '₦' + Math.round(Number(n||0)).toLocaleString('en-NG');
const qty    = n => Number(n||0).toLocaleString('en-NG',{maximumFractionDigits:2});

function dueLabel(iso){
  if (!iso) return '';
  const d = new Date(iso), now = new Date();
  const days = Math.round((new Date(d.toDateString()) - new Date(now.toDateString())) / 86400000);
  if (days === 0)  return 'Today';
  if (days === 1)  return 'Tomorrow';
  if (days === -1) return 'Yesterday';
  if (days < 0)    return Math.abs(days) + ' days late';
  if (days <= 6)   return d.toLocaleDateString('en-NG',{weekday:'long'});
  return d.toLocaleDateString('en-NG',{day:'numeric',month:'short',year:'numeric'});
}
function toast(msg, err){
  const t = $('#toast');
  t.textContent = msg; t.className = 'show' + (err ? ' err' : '');
  clearTimeout(toast._t); toast._t = setTimeout(() => t.className = '', 2800);
}

/* ---------------------------- state ---------------------------- */
const state = { user:null, company:null, role:null, cache:{} };

/* ---------------------------- theme ---------------------------- */
function applyTheme(t){
  document.documentElement.dataset.theme = t;
  const b = $('#themeBtn'); if (b) b.textContent = t === 'dark' ? '☀️' : '🌙';
  try { localStorage.setItem('erp_theme', t); } catch(e){}
}
applyTheme((() => { try { return localStorage.getItem('erp_theme'); } catch(e){ return null; } })()
  || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'));

/* ---------------------------- auth screen ---------------------------- */
let authMode = 'signin';
function setAuthMode(mode){
  authMode = mode;
  const up = mode === 'signup';
  $('#authTitle').textContent  = up ? 'Create your account' : 'Welcome back';
  $('#authSub').textContent    = up ? 'A minute now, and the books keep themselves' : 'Sign in to your business';
  $('#authBtn').textContent    = up ? 'Create account' : 'Sign in';
  $('#switchText').textContent = up ? 'Already have an account?' : 'New here?';
  $('#switchBtn').textContent  = up ? 'Sign in' : 'Create an account';
  $('#nameField').classList.toggle('hidden', !up);
  $('#password').setAttribute('autocomplete', up ? 'new-password' : 'current-password');
  $('#authMsg').innerHTML = '';
}
function showMsg(where, text, kind){
  $(where).innerHTML = `<div class="msg msg-${kind}">${esc(text)}</div>`;
}

$('#switchBtn').onclick = () => setAuthMode(authMode === 'signin' ? 'signup' : 'signin');

$('#authForm').onsubmit = async e => {
  e.preventDefault();
  const btn = $('#authBtn'); btn.disabled = true;
  const original = btn.textContent; btn.textContent = 'Please wait…';
  try {
    const email = $('#email').value.trim(), pw = $('#password').value;
    if (authMode === 'signup'){
      const { needsConfirmation } = await db.signUp(email, pw, $('#fullName').value.trim());
      if (needsConfirmation){
        showMsg('#authMsg', 'Account created. Check your email to confirm the address, then sign in.', 'ok');
        setAuthMode('signin');
        return;
      }
    } else {
      await db.signIn(email, pw);
    }
    await boot();
  } catch (err) {
    showMsg('#authMsg', err.message, 'error');
  } finally {
    btn.disabled = false; btn.textContent = original;
  }
};

/* ---------------------------- onboarding ---------------------------- */
$('#onboardForm').onsubmit = async e => {
  e.preventDefault();
  const btn = $('#onboardBtn'); btn.disabled = true;
  const original = btn.textContent; btn.textContent = 'Setting up…';
  try {
    const id = await db.createCompany($('#bizName').value.trim(), $('#bizType').value);
    if ($('#withDemo').checked) await db.seedDemoData(id);
    await boot();
    toast('Your business is ready');
  } catch (err) {
    showMsg('#onboardMsg', err.message || String(err), 'error');
  } finally {
    btn.disabled = false; btn.textContent = original;
  }
};
$('#signOutEarly').onclick = async () => { await db.signOut(); location.reload(); };
$('#signOutBtn').onclick   = async () => { await db.signOut(); location.reload(); };
$('#themeBtn').onclick = () =>
  applyTheme(document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark');

/* ---------------------------- navigation ---------------------------- */
const SCREENS = {
  home:      {label:'Home',      ico:'⌂'},
  calendar:  {label:'Calendar',  ico:'▦'},
  orders:    {label:'Orders',    ico:'❐'},
  customers: {label:'Customers', ico:'☺'},
  products:  {label:'Products',  ico:'▣'},
  recipes:   {label:'Recipes',   ico:'✎'},
  ledger:    {label:'Ledger',    ico:'≡'}
};
const NAV = {
  owner:   {bottom:['home','calendar','+','orders','more'],
            side:['home','calendar','orders','customers','products','recipes','ledger']},
  admin:   {bottom:['home','calendar','+','orders','more'],
            side:['home','calendar','orders','customers','products','recipes','ledger']},
  manager: {bottom:['home','calendar','+','orders','more'],
            side:['home','calendar','orders','customers','products','recipes','ledger']},
  sales:   {bottom:['home','orders','+','customers','more'],
            side:['home','orders','customers','products']},
  clerk:   {bottom:['home','ledger','+','orders','more'],
            side:['home','ledger','orders','products']},
  viewer:  {bottom:['home','orders','+','products','more'],
            side:['home','orders','products']}
};
const navFor = () => NAV[state.role] || NAV.viewer;

const go = h => { location.hash = h; };
const current = () => (location.hash.replace('#/','').split('/')[0]) || 'home';
const param   = () => location.hash.split('/')[2] || '';

function renderNav(){
  const nav = navFor();
  $('#sbNav').innerHTML = nav.side.map(k =>
    `<div class="sb-item ${current()===k?'active':''}" data-go="${k}">
       <span class="sb-ico">${SCREENS[k].ico}</span>${SCREENS[k].label}</div>`).join('');
  $('#bottomNav').innerHTML = nav.bottom.map(k => {
    if (k === '+')    return `<button class="fab" id="fabBtn" title="Add new">+</button>`;
    if (k === 'more') return `<div class="nav-item" id="moreBtn"><span class="nav-ico">⋯</span>More</div>`;
    return `<div class="nav-item ${current()===k?'active':''}" data-go="${k}">
              <span class="nav-ico">${SCREENS[k].ico}</span>${SCREENS[k].label}</div>`;
  }).join('');
  $$('[data-go]').forEach(el => el.onclick = () => go('#/' + el.dataset.go));
  const fab = $('#fabBtn'); if (fab) fab.onclick = openSheet;
  const more = $('#moreBtn'); if (more) more.onclick = openDrawer;
}

function openDrawer(){
  $('#drawerCompany').textContent = state.company.name;
  $('#drawerRole').textContent = state.role[0].toUpperCase() + state.role.slice(1);
  $('#drawerNav').innerHTML = navFor().side.map(k =>
    `<div class="drawer-item ${current()===k?'active':''}" data-dgo="${k}">
       <span class="sb-ico">${SCREENS[k].ico}</span>${SCREENS[k].label}</div>`).join('');
  $$('[data-dgo]').forEach(el => el.onclick = () => { closeAll(); go('#/' + el.dataset.dgo); });
  $('#drawer').classList.add('open'); $('#scrim').classList.add('open');
}
function openSheet(){
  $('#sheetTitle').textContent = 'Add new';
  const actions = [
    {ico:'₦', name:'Record a payment', why:'Cash, transfer or POS just came in', fn: sheetPayment},
    {ico:'☺', name:'New customer',     why:'Somebody new is buying from you',    fn: sheetCustomer}
  ];
  $('#sheetBody').innerHTML = actions.map((a,i) =>
    `<button class="sheet-action" data-act="${i}">
       <span class="sa-ico">${a.ico}</span>
       <span><span style="font-weight:600;color:var(--heading);font-size:var(--fs-sm)">${esc(a.name)}</span><br>
       <span class="xs muted">${esc(a.why)}</span></span></button>`).join('')
    + `<button class="btn btn-ghost btn-block" id="sheetCancel">Cancel</button>`;
  $$('[data-act]').forEach(el => el.onclick = () => actions[Number(el.dataset.act)].fn());
  $('#sheetCancel').onclick = closeAll;
  $('#sheet').classList.add('open'); $('#scrim').classList.add('open');
}
function closeAll(){
  ['drawer','sheet','scrim'].forEach(id => $('#'+id).classList.remove('open'));
}
$('#scrim').onclick = closeAll;
$('#drawerClose').onclick = closeAll;
$('#burgerBtn').onclick = openDrawer;
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeAll(); });

/* ---------------------------- + sheet forms ---------------------------- */
async function sheetCustomer(){
  $('#sheetTitle').textContent = 'New customer';
  $('#sheetBody').innerHTML = `
    <form id="cForm">
      <div class="field"><label for="cName">Name</label>
        <input class="input" id="cName" required placeholder="Grace Johnson"></div>
      <div class="field"><label for="cPhone">Phone / WhatsApp</label>
        <input class="input" id="cPhone" placeholder="+234 812 345 4567"></div>
      <div class="row"><button type="button" class="btn btn-ghost" id="cCancel">Cancel</button>
        <button class="btn btn-primary" style="flex:1" type="submit">Save customer</button></div>
    </form>`;
  $('#cCancel').onclick = closeAll;
  $('#cForm').onsubmit = async e => {
    e.preventDefault();
    try {
      const phone = $('#cPhone').value.trim();
      await db.addContact(state.company.id, {
        name: $('#cName').value.trim(), phone, whatsapp: phone || null });
      closeAll(); invalidate(); toast('Customer saved'); render();
    } catch (err) { toast(err.message || 'Could not save', true); }
  };
}

async function sheetPayment(){
  $('#sheetTitle').textContent = 'Record a payment';
  const orders = (await cached('orders', () => db.orders()))
    .filter(o => o.balance > 0 && o.doc_type !== 'quote');
  if (!orders.length){
    $('#sheetBody').innerHTML = `<div class="empty">Nothing is owed right now.</div>
      <button class="btn btn-ghost btn-block" id="pCancel">Close</button>`;
    $('#pCancel').onclick = closeAll;
    return;
  }
  $('#sheetBody').innerHTML = `
    <form id="pForm">
      <div class="field"><label for="pOrder">Against which order</label>
        <select class="input" id="pOrder">${orders.map(o =>
          `<option value="${o.id}">${esc(o.doc_no)} · ${esc(o.contact?.name||'')} · ${money(o.balance)} owing</option>`).join('')}</select></div>
      <div class="field"><label for="pAmount">Amount received</label>
        <input class="input" id="pAmount" type="number" step="0.01" min="0.01" required></div>
      <div class="field"><label for="pMethod">How</label>
        <select class="input" id="pMethod"><option>transfer</option><option>cash</option><option>pos</option></select></div>
      <div class="row"><button type="button" class="btn btn-ghost" id="pCancel">Cancel</button>
        <button class="btn btn-primary" style="flex:1" type="submit">Record payment</button></div>
    </form>`;
  $('#pOrder').onchange = () => {
    const o = orders.find(x => x.id === $('#pOrder').value);
    if (o) $('#pAmount').value = o.balance;
  };
  $('#pOrder').onchange();
  $('#pCancel').onclick = closeAll;
  $('#pForm').onsubmit = async e => {
    e.preventDefault();
    const o = orders.find(x => x.id === $('#pOrder').value);
    try {
      await db.addPayment(state.company.id, o.id, o.contact?.id || null,
        Number($('#pAmount').value), $('#pMethod').value, o.paid === 0);
      closeAll(); invalidate(); toast('Payment recorded'); render();
    } catch (err) { toast(err.message || 'Could not record it', true); }
  };
}

/* ---------------------------- cache ---------------------------- */
async function cached(key, fn){
  if (!state.cache[key]) state.cache[key] = await fn();
  return state.cache[key];
}
function invalidate(){ state.cache = {}; }

/* ---------------------------- routing ---------------------------- */
async function render(){
  if (!state.company) return;
  renderNav();
  const screen = current();
  const fn = { home:viewHome, calendar:viewCalendar, orders:viewOrders, order:viewOrder,
               customers:viewCustomers, products:viewProducts, recipes:viewRecipes,
               ledger:viewLedger }[screen];
  if (!fn || !navFor().side.includes(screen === 'order' ? 'orders' : screen)){
    if (screen !== 'order'){ go('#/' + navFor().side[0]); return; }
  }
  $('#view').innerHTML = `<div class="stack"><div class="skeleton"></div>
    <div class="skeleton"></div><div class="skeleton"></div></div>`;
  try {
    $('#view').innerHTML = await (fn || viewHome)();
    bindView();
  } catch (err) {
    console.error(err);
    $('#view').innerHTML = `<div class="card pad">
      <strong>Could not load this screen.</strong>
      <p class="sm muted">${esc(err.message || String(err))}</p>
      <button class="btn btn-secondary btn-sm" onclick="location.reload()">Try again</button></div>`;
  }
  window.scrollTo({top:0});
}
function bindView(){
  $$('[data-open-order]').forEach(el => el.onclick = () => go('#/order/' + el.dataset.openOrder));
  $$('[data-advance]').forEach(el => el.onclick = async () => {
    el.disabled = true;
    try {
      await db.setOrderStatus(el.dataset.orderId, el.dataset.advance);
      invalidate(); toast('Order updated'); render();
    } catch (err) { toast(err.message || 'Could not update', true); el.disabled = false; }
  });
  const back = $('#backBtn'); if (back) back.onclick = () => go('#/orders');
}

/* ---------------------------- screens ---------------------------- */
async function viewHome(){
  const [orders, stock, items] = await Promise.all([
    cached('orders', () => db.orders()),
    cached('stock',  () => db.stockOnHand()),
    cached('items',  () => db.items())
  ]);
  const live = orders.filter(o => o.doc_type !== 'quote');
  const quotes = orders.filter(o => o.doc_type === 'quote');
  const invoiced = live.reduce((s,o) => s + o.total, 0);
  const owed = live.reduce((s,o) => s + Math.max(0, o.balance), 0);
  const dueSoon = live.filter(o => o.due_at && new Date(o.due_at) <= new Date(Date.now()+7*864e5)
                                && !['delivered','paid','closed','cancelled'].includes(o.status));
  const low = items.filter(i => i.reorder_level != null
    && Number(stock.get(i.id) || 0) <= Number(i.reorder_level));
  const stockValue = items.reduce((s,i) => s + Number(stock.get(i.id)||0) * Number(i.purchase_price||0), 0);

  return `
  <div class="page-head"><div>
    <h1>Good ${hour()}, ${esc((state.user.user_metadata?.full_name || state.user.email).split(' ')[0])}</h1>
    <div class="page-sub">${new Date().toLocaleDateString('en-NG',{weekday:'long',day:'numeric',month:'long'})}
      · here is where the business stands</div></div></div>

  <div class="grid2" style="grid-template-columns:repeat(auto-fit,minmax(190px,1fr))">
    ${tile('Invoiced', money0(invoiced), live.length + ' orders')}
    ${tile('You are owed', money0(owed), owed > 0 ? 'chase these' : 'nothing outstanding', owed > 0 ? 'neg' : 'pos')}
    ${tile('Due this week', String(dueSoon.length), dueSoon.length ? 'in production or waiting' : 'nothing due')}
    ${tile('Stock at cost', money0(stockValue), low.length ? low.length + ' running low' : 'all healthy')}
  </div>

  ${quotes.length ? `<div class="card pad" style="margin-top:var(--sp-4);
      background:var(--pending-bg);border-color:transparent;color:var(--pending-fg)">
      <strong>${quotes.length} open ${quotes.length===1?'quote':'quotes'}.</strong>
      Chasing a quote is usually worth more than a new advert.</div>` : ''}

  <div class="grid2" style="margin-top:var(--sp-4)">
    <div class="card">
      <div class="pad between" style="border-bottom:1px solid var(--line)">
        <strong>Coming up</strong><button class="btn btn-ghost btn-sm" data-go="orders">All orders</button></div>
      <div class="pad stack">
        ${dueSoon.length ? dueSoon.slice(0,5).map(orderRow).join('')
          : `<div class="empty">Nothing due in the next seven days.</div>`}
      </div>
    </div>
    <div class="card">
      <div class="pad between" style="border-bottom:1px solid var(--line)">
        <strong>Running low</strong><button class="btn btn-ghost btn-sm" data-go="products">All stock</button></div>
      <div class="pad">
        ${low.length ? low.slice(0,6).map(i => `
          <div class="kv"><span class="sm">${esc(i.name)}</span>
            <span class="money ${Number(stock.get(i.id)||0) <= 0 ? 'neg':''}">
              ${qty(stock.get(i.id)||0)} ${esc(i.unit)}</span></div>`).join('')
          : `<div class="empty">Everything is above its reorder level.</div>`}
      </div>
    </div>
  </div>`;
}
const hour = () => { const h = new Date().getHours();
  return h < 12 ? 'morning' : h < 17 ? 'afternoon' : 'evening'; };
const tile = (label, value, note, cls='') => `
  <div class="card pad"><div class="xs muted" style="text-transform:uppercase;letter-spacing:.05em;font-weight:700">${esc(label)}</div>
    <div class="money ${cls}" style="font-size:21px;margin-top:4px">${esc(value)}</div>
    <div class="xs muted">${esc(note)}</div></div>`;

const PHASES = [
  {key:'confirmed', label:'Confirmed'}, {key:'in_production', label:'In Production'},
  {key:'ready', label:'Ready'}, {key:'delivered', label:'Delivered'}
];
function statusChip(s){
  const map = {in_production:['chip-processing','In Production'], ready:['chip-pending','Ready'],
    delivered:['chip-paid','Delivered'], paid:['chip-paid','Paid'], confirmed:['chip-plain','Confirmed'],
    quoted:['chip-pending','Quoted'], enquiry:['chip-plain','Enquiry'],
    cancelled:['chip-overdue','Cancelled'], lost:['chip-overdue','Lost'], closed:['chip-plain','Closed']};
  const [cls, label] = map[s] || ['chip-plain', s];
  return `<span class="chip ${cls}">${esc(label)}</span>`;
}
function orderRow(o){
  const late = o.due_at && new Date(o.due_at) < new Date()
    && !['delivered','paid','closed'].includes(o.status);
  return `<div class="order" data-open-order="${o.id}">
    <div class="between" style="margin-bottom:6px">
      <strong class="sm">${esc(o.doc_no || '—')}</strong>${statusChip(o.status)}</div>
    <div class="sm" style="font-weight:500;color:var(--heading)">${esc(o.contact?.name || 'Walk-in')}</div>
    <div class="xs muted">${esc((o.lines||[]).map(l => l.description || l.item?.name).join(', ') || '—')}</div>
    <div class="between" style="margin-top:var(--sp-3);align-items:flex-end">
      <div><div class="xs ${late ? 'neg' : 'muted'}" style="font-weight:${late?600:400}">${esc(dueLabel(o.due_at))}</div>
        ${o.balance > 0 ? `<div class="xs neg" style="font-weight:600">Owing ${money(o.balance)}</div>`
                        : `<div class="xs pos" style="font-weight:600">Paid in full</div>`}</div>
      <div class="money">${money(o.total)}</div></div></div>`;
}

async function viewCalendar(){
  const [jobs, orders] = await Promise.all([
    cached('jobs',   () => db.productionJobs()),
    cached('orders', () => db.orders())
  ]);
  const today = new Date(); today.setHours(0,0,0,0);
  const days = Array.from({length:7}, (_,i) => {
    const d = new Date(today); d.setDate(d.getDate()+i);
    const count = jobs.filter(j => j.due_at && sameDay(new Date(j.due_at), d)).length;
    return { d, count };
  });
  const todays = jobs.filter(j => j.due_at && sameDay(new Date(j.due_at), today));
  const done = todays.filter(j => j.status === 'done').length;

  return `
  <div class="page-head"><div><h1>Production Calendar</h1>
    <div class="page-sub">What is due, and whether you can take more work.</div></div></div>

  <div class="card pad">
    <div class="between"><strong class="sm">Today, ${today.toLocaleDateString('en-NG',{weekday:'short',day:'numeric',month:'short'})}</strong>
      <span class="sm pos" style="font-weight:600">${done} of ${todays.length} done</span></div>
    <div style="height:7px;border-radius:99px;background:var(--sand);margin:var(--sp-3) 0 var(--sp-2);overflow:hidden">
      <span style="display:block;height:100%;background:var(--green-600);
        width:${todays.length ? (done/todays.length*100) : 0}%"></span></div>
  </div>

  <div style="display:grid;grid-template-columns:repeat(7,1fr);gap:4px;margin-top:var(--sp-4)">
    ${days.map((x,i) => `
      <div style="text-align:center;padding:var(--sp-2) 0;border-radius:var(--r-md);
        ${i===0 ? 'background:var(--primary);color:#fff' : ''}">
        <div class="xs" style="${i===0?'color:#fff':'color:var(--muted)'};font-weight:600">
          ${x.d.toLocaleDateString('en-NG',{weekday:'short'})}</div>
        <div style="font-weight:600;${i===0?'color:#fff':'color:var(--heading)'}">${x.d.getDate()}</div>
        <div style="font-size:8px;${i===0?'color:#fff':'color:var(--muted)'}">${x.count} job${x.count===1?'':'s'}</div>
      </div>`).join('')}
  </div>

  <div class="between" style="margin:var(--sp-5) 0 var(--sp-3)"><h2 style="font-size:var(--fs-h2)">Today's jobs</h2></div>
  <div class="stack">
    ${todays.length ? todays.map(j => `
      <div class="card pad between">
        <div><div class="xs muted">${esc(j.recipe?.name || 'No recipe')}</div>
          <div style="font-weight:600;color:var(--heading)" class="sm">${esc(j.item?.name || '—')}</div>
          <div class="xs muted">${qty(j.qty_planned)} planned</div></div>
        ${statusChip(j.status === 'in_progress' ? 'in_production' : j.status === 'done' ? 'delivered' : 'confirmed')}
      </div>`).join('')
      : `<div class="card"><div class="empty">Nothing to bake today.</div></div>`}
  </div>`;
}
const sameDay = (a,b) => a.toDateString() === b.toDateString();

async function viewOrders(){
  const orders = await cached('orders', () => db.orders());
  const quotes = orders.filter(o => o.doc_type === 'quote');
  const live = orders.filter(o => o.doc_type !== 'quote');
  return `
  <div class="page-head"><div><h1>Orders &amp; Enquiries</h1>
    <div class="page-sub">A quote becomes an order once the deposit lands.</div></div></div>
  ${quotes.length ? `<h2 style="font-size:var(--fs-h2);margin-bottom:var(--sp-3)">Open quotes</h2>
    <div class="stack" style="margin-bottom:var(--sp-5)">${quotes.map(orderRow).join('')}</div>` : ''}
  <h2 style="font-size:var(--fs-h2);margin-bottom:var(--sp-3)">Orders</h2>
  <div class="stack">${live.length ? live.map(orderRow).join('')
    : `<div class="card"><div class="empty">No orders yet. Tap + to record your first.</div></div>`}</div>`;
}

async function viewOrder(){
  const o = await db.order(param());
  if (!o) return `<div class="card pad">That order could not be found.
    <button class="btn btn-secondary btn-sm" id="backBtn" style="margin-left:var(--sp-3)">Back</button></div>`;
  const idx = PHASES.findIndex(p => p.key === o.status);
  const next = idx >= 0 ? PHASES[idx+1] : null;

  return `
  <div class="page-head"><div><h1>${esc(o.doc_no || 'Order')}</h1>
    <div class="page-sub">${esc(o.contact?.name || 'Walk-in')} · due ${esc(dueLabel(o.due_at))}</div></div>
    <div class="spacer"></div><button class="btn btn-ghost btn-sm" id="backBtn">← All orders</button></div>

  ${idx >= 0 ? `<div class="card pad">
    <div class="stepper">${PHASES.map((p,i) => `
      <div class="step ${i<idx?'done':i===idx?'now':''}">
        <div class="dot">${i<idx?'✓':i+1}</div><div class="lbl">${p.label}</div></div>`).join('')}</div>
    ${next ? `<button class="btn btn-primary btn-block" data-advance="${next.key}" data-order-id="${o.id}"
       style="margin-top:var(--sp-3)">Mark as ${next.label}</button>` : ''}
  </div>` : ''}

  <div class="grid2" style="margin-top:var(--sp-4)">
    <div class="card pad">
      <div class="xs muted" style="text-transform:uppercase;font-weight:700;letter-spacing:.05em">
        ${o.balance > 0 ? 'Balance due' : 'Fully paid'}</div>
      <div class="money money-lg ${o.balance>0?'neg':'pos'}">${money(o.balance>0?o.balance:o.total)}</div>
      <div style="margin-top:var(--sp-4)">
        <div class="kv"><span class="muted sm">Subtotal</span><span class="money">${money(o.subtotal)}</span></div>
        <div class="kv"><span class="muted sm">Tax (${(Number(o.tax_rate)*100).toFixed(1)}%)</span><span class="money">${money(o.tax)}</span></div>
        ${Number(o.delivery_fee) ? `<div class="kv"><span class="muted sm">Delivery</span><span class="money">${money(o.delivery_fee)}</span></div>`:''}
        <div class="kv"><span class="sm" style="font-weight:600">Total</span><span class="money">${money(o.total)}</span></div>
        <div class="kv"><span class="muted sm">Paid</span><span class="money">${money(o.paid)}</span></div>
      </div>
    </div>
    <div class="card pad">
      <div class="xs muted" style="text-transform:uppercase;font-weight:700;letter-spacing:.05em;margin-bottom:var(--sp-3)">Items</div>
      ${(o.lines||[]).map(l => `<div class="kv">
        <span class="sm">${esc(l.description || l.item?.name || '—')}<br>
          <span class="xs muted">${qty(l.qty)} × ${money(l.unit_price)}</span></span>
        <span class="money">${money(Number(l.qty)*Number(l.unit_price))}</span></div>`).join('')}
      ${o.notes ? `<div class="xs muted" style="margin-top:var(--sp-4)">${esc(o.notes)}</div>` : ''}
      <div class="xs muted" style="text-transform:uppercase;font-weight:700;letter-spacing:.05em;margin:var(--sp-5) 0 var(--sp-2)">Payments</div>
      ${(o.payments||[]).length ? (o.payments||[]).map(p => `<div class="kv">
        <span class="sm">${esc(p.is_deposit?'Deposit':'Payment')} · ${esc(p.method||'')}</span>
        <span class="money">${money(p.amount)}</span></div>`).join('')
        : `<div class="xs muted">Nothing received yet.</div>`}
    </div>
  </div>`;
}

async function viewCustomers(){
  const [contacts, orders] = await Promise.all([
    cached('contacts', () => db.contacts()), cached('orders', () => db.orders())]);
  return `
  <div class="page-head"><div><h1>Customers</h1>
    <div class="page-sub">${contacts.length} on your books</div></div></div>
  <div class="tbl-wrap"><table>
    <thead><tr><th>Name</th><th>Phone</th><th class="num">Orders</th><th class="num">Spent</th><th class="num">Owing</th></tr></thead>
    <tbody>${contacts.length ? contacts.map(c => {
      const mine = orders.filter(o => o.contact?.id === c.id);
      const spent = mine.reduce((s,o) => s + o.paid, 0);
      const owing = mine.reduce((s,o) => s + Math.max(0,o.balance), 0);
      return `<tr><td>${esc(c.name)}</td><td>${esc(c.phone||'—')}</td>
        <td class="num">${mine.length}</td><td class="num">${money0(spent)}</td>
        <td class="num ${owing>0?'neg':''}">${owing>0?money0(owing):'—'}</td></tr>`;
    }).join('') : `<tr><td colspan="5"><div class="empty">No customers yet.</div></td></tr>`}</tbody>
  </table></div>`;
}

async function viewProducts(){
  const [items, stock] = await Promise.all([
    cached('items', () => db.items()), cached('stock', () => db.stockOnHand())]);
  return `
  <div class="page-head"><div><h1>Products &amp; Stock</h1>
    <div class="page-sub">Stock comes from movements in and out — it is never typed in.</div></div></div>
  <div class="tbl-wrap"><table>
    <thead><tr><th>Item</th><th>Type</th><th class="num">In stock</th><th class="num">Buy</th>
      <th class="num">Sell</th><th class="num">Value at cost</th><th>Status</th></tr></thead>
    <tbody>${items.map(i => {
      const on = Number(stock.get(i.id) || 0);
      const low = i.reorder_level != null && on <= Number(i.reorder_level);
      const value = on * Number(i.purchase_price || 0);
      return `<tr><td>${esc(i.name)}</td>
        <td><span class="chip chip-plain">${i.kind === 'raw_material' ? 'Raw material'
            : i.kind === 'service' ? 'Service' : 'Finished'}</span></td>
        <td class="num">${i.tracked ? qty(on) + ' ' + esc(i.unit) : '<span class="muted">made to order</span>'}</td>
        <td class="num">${Number(i.purchase_price) ? money0(i.purchase_price) : '—'}</td>
        <td class="num">${Number(i.sales_price) ? money0(i.sales_price) : '—'}</td>
        <td class="num">${i.tracked ? money0(value) : '—'}</td>
        <td>${!i.tracked ? '<span class="chip chip-plain">n/a</span>'
             : on <= 0 ? '<span class="chip chip-overdue">Out</span>'
             : low ? '<span class="chip chip-pending">Low</span>'
             : '<span class="chip chip-paid">OK</span>'}</td></tr>`;
    }).join('')}</tbody></table></div>`;
}

async function viewRecipes(){
  const recipes = await cached('recipes', () => db.recipes());
  if (!recipes.length) return `<div class="page-head"><h1>Recipes</h1></div>
    <div class="card"><div class="empty">No recipes yet.</div></div>`;
  return `<div class="page-head"><div><h1>Recipes</h1>
    <div class="page-sub">What each item really costs to make, per unit.</div></div></div>
  <div class="stack">${recipes.map(r => {
    const c = costRecipe(r);
    return `<div class="card">
      <div class="pad between" style="border-bottom:1px solid var(--line)">
        <strong>${esc(r.item?.name || 'Recipe')}</strong>
        <span class="xs muted">makes ${qty(r.yield_qty)} per batch</span></div>
      <div class="grid2" style="gap:0">
        <div class="pad"><div class="xs muted" style="text-transform:uppercase;font-weight:700">Ingredients</div>
          ${(r.lines||[]).map(l => `<div class="kv"><span class="sm">${esc(l.component?.name||'—')}
            <span class="xs muted">${qty(l.qty)} ${esc(l.unit||l.component?.unit||'')}</span></span>
            <span class="money">${money(Number(l.qty) * Number(l.component?.purchase_price||0))}</span></div>`).join('')}
        </div>
        <div class="pad" style="background:var(--bg)">
          <div class="xs muted" style="text-transform:uppercase;font-weight:700">Per unit</div>
          <div class="kv"><span class="muted sm">Costs you</span><span class="money">${money(c.perUnit)}</span></div>
          <div class="kv"><span class="muted sm">Sells for</span><span class="money">${money(c.sell)}</span></div>
          <div class="kv"><span class="sm" style="font-weight:600">Profit</span>
            <span class="money ${c.profit>=0?'pos':'neg'}">${money(c.profit)}</span></div>
          <div class="kv" style="border-top:2px solid var(--line);font-size:var(--fs-h2);font-weight:700">
            <span>Margin</span><span class="${c.margin>=0?'pos':'neg'}">${c.margin.toFixed(1)}%</span></div>
        </div>
      </div></div>`;
  }).join('')}</div>`;
}

async function viewLedger(){
  const tb = await cached('tb', () => db.trialBalance());
  const sum = t => tb.filter(r => r.type === t).reduce((s,r) => s + Math.abs(Number(r.balance)), 0);
  const income = sum('income'), expense = sum('expense'), net = income - expense;
  return `
  <div class="page-head"><div><h1>Ledger</h1>
    <div class="page-sub">Every figure here comes from entries that balance.</div></div></div>
  <div class="grid2" style="grid-template-columns:repeat(auto-fit,minmax(190px,1fr))">
    ${tile('Money in', money0(income), 'income', 'pos')}
    ${tile('Money out', money0(expense), 'expenses')}
    ${tile('Net', money0(net), net >= 0 ? 'profit' : 'loss', net >= 0 ? 'pos' : 'neg')}
  </div>
  <div class="tbl-wrap" style="margin-top:var(--sp-4)"><table>
    <thead><tr><th>Account</th><th>Type</th><th class="num">Amount</th></tr></thead>
    <tbody>${tb.length ? tb.map(r => `<tr><td>${esc(r.name)}</td>
      <td><span class="chip chip-plain">${esc(r.type)}</span></td>
      <td class="num">${money(Math.abs(Number(r.balance)))}</td></tr>`).join('')
      : `<tr><td colspan="3"><div class="empty">Nothing posted yet.</div></td></tr>`}</tbody>
  </table></div>`;
}

/* ---------------------------- boot ---------------------------- */
async function boot(){
  const user = await db.currentUser();
  if (!user){
    $('#authScreen').classList.remove('hidden');
    $('#onboardScreen').classList.add('hidden');
    $('#appShell').classList.add('hidden');
    $('#bottomNav').style.display = 'none';
    return;
  }
  state.user = user;
  let companies = [];
  try { companies = await db.myCompanies(); }
  catch (err) { showMsg('#authMsg', err.message, 'error'); }

  if (!companies.length){
    $('#authScreen').classList.add('hidden');
    $('#onboardScreen').classList.remove('hidden');
    $('#appShell').classList.add('hidden');
    $('#bottomNav').style.display = 'none';
    return;
  }

  state.company = companies[0];
  state.role = companies[0].role;
  invalidate();

  $('#authScreen').classList.add('hidden');
  $('#onboardScreen').classList.add('hidden');
  $('#appShell').classList.remove('hidden');
  $('#bottomNav').style.display = '';
  $('#sbCompany').textContent = state.company.name;
  const name = state.user.user_metadata?.full_name || state.user.email;
  $('#userName').textContent = name;
  $('#userRole').textContent = state.role[0].toUpperCase() + state.role.slice(1);
  $('#userAvatar').textContent = name.trim()[0].toUpperCase();

  if (!location.hash) location.hash = '#/home';
  await render();
}

window.addEventListener('hashchange', () => { closeAll(); render(); });
window.addEventListener('online',  () => { $('#syncState').textContent = 'Live'; });
window.addEventListener('offline', () => { $('#syncState').textContent = 'Offline'; });
setAuthMode('signin');
boot();

/* exposed for the test harness */
window.__erp = { state, db, costRecipe };
