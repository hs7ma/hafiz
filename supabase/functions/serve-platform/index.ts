import { corsHeaders } from "../_shared/http.ts";

const CSS = `
:root {
  --bg0: #f3ebe0; --bg1: #e7f0e4; --ink: #1f2a24; --muted: #5c6b62;
  --olive: #3f5d45; --olive-dark: #2f4635; --card: rgba(255, 252, 247, 0.88);
  --line: rgba(47, 70, 53, 0.14); --danger: #a33b2d; --ok: #2f6b45;
  --shadow: 0 18px 50px rgba(31, 42, 36, 0.08); --radius: 22px;
  --font: "Segoe UI", "Tahoma", "Noto Naskh Arabic", sans-serif;
}
* { box-sizing: border-box; }
html, body { margin: 0; min-height: 100%; font-family: var(--font); color: var(--ink);
  background: radial-gradient(ellipse 90% 60% at 10% -10%, #d7e8d4 0%, transparent 55%),
    radial-gradient(ellipse 70% 50% at 100% 0%, #f0d9b8 0%, transparent 50%),
    linear-gradient(165deg, var(--bg0), var(--bg1)); }
body { direction: rtl; }
.shell { width: min(920px, calc(100% - 32px)); margin: 0 auto; padding: 40px 0 64px; }
.brand h1 { margin: 0; font-size: 2rem; color: var(--olive-dark); }
.brand p { margin: 8px 0 0; color: var(--muted); line-height: 1.6; }
.card { background: var(--card); border: 1px solid var(--line); border-radius: var(--radius);
  box-shadow: var(--shadow); padding: 22px; backdrop-filter: blur(8px); margin-bottom: 14px; }
.grid { display: grid; gap: 14px; }
label { display: grid; gap: 6px; font-weight: 600; font-size: 0.95rem; }
input { font: inherit; padding: 12px 14px; border-radius: 14px; border: 1px solid var(--line);
  background: #fff; color: var(--ink); }
.actions { display: flex; gap: 10px; flex-wrap: wrap; align-items: center; }
.btn-primary, .btn-secondary, .btn-danger, .btn-wa {
  appearance: none; border: 0; border-radius: 999px; padding: 11px 18px; font: inherit;
  font-weight: 700; cursor: pointer; text-decoration: none; display: inline-flex; align-items: center;
}
.btn-primary { background: var(--olive); color: #fff; }
.btn-secondary { background: #fff; color: var(--olive-dark); border: 1px solid var(--line); }
.btn-danger { background: #f6e4e0; color: var(--danger); }
.btn-wa { background: #25D366; color: #fff; }
.muted { color: var(--muted); font-size: 0.92rem; line-height: 1.55; }
.msg { margin-top: 12px; padding: 12px 14px; border-radius: 14px; font-weight: 600; }
.msg.ok { background: #e5f3ea; color: var(--ok); }
.msg.err { background: #f8e8e4; color: var(--danger); }
.msg.hidden, .hidden { display: none; }
.password-box { margin-top: 10px; padding: 10px 12px; border-radius: 12px; background: #fff;
  border: 1px dashed var(--line); font-family: ui-monospace, monospace; direction: ltr; }
table { width: 100%; border-collapse: collapse; font-size: 0.92rem; }
th, td { text-align: right; padding: 10px 8px; border-bottom: 1px solid var(--line); vertical-align: top; }
.badge { display: inline-block; padding: 3px 10px; border-radius: 999px; font-size: 0.8rem; font-weight: 700; }
.badge.pending { background: #fff3d6; color: #8a6a12; }
.badge.approved { background: #e5f3ea; color: var(--ok); }
.badge.rejected { background: #f8e8e4; color: var(--danger); }
.tabs { display: flex; gap: 8px; flex-wrap: wrap; }
.tab { border: 1px solid var(--line); background: #fff; border-radius: 999px; padding: 8px 14px;
  cursor: pointer; font: inherit; }
.tab.active { background: var(--olive); color: #fff; border-color: var(--olive); }
.row-actions { display: flex; gap: 8px; flex-wrap: wrap; }
.table-wrap { overflow-x: auto; }
`;

function apiBase(): string {
  const url = Deno.env.get("SUPABASE_URL") || "";
  return `${url.replace(/\/$/, "")}/functions/v1/hafiz-api`;
}

function anonKey(): string {
  return Deno.env.get("SUPABASE_ANON_KEY") || "";
}

Deno.serve((req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  const html = `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>إدارة حافظ — المساجد</title>
  <style>${CSS}</style>
</head>
<body>
  <main class="shell">
    <header class="brand">
      <h1>إدارة حافظ</h1>
      <p>مراجعة طلبات تسجيل الجوامع، والموافقة أو الرفض، وإرسال كلمة المرور عبر واتساب.</p>
    </header>
    <section id="loginCard" class="card">
      <form id="loginForm" class="grid">
        <label>كلمة مرور إدارة المنصة
          <input name="password" type="password" required autocomplete="current-password" dir="ltr" />
        </label>
        <div class="actions"><button class="btn-primary" type="submit">دخول</button></div>
        <div id="loginMsg" class="msg hidden" role="status"></div>
      </form>
    </section>
    <section id="dash" class="hidden">
      <div class="actions" style="margin-bottom: 16px; justify-content: space-between;">
        <div class="tabs">
          <button type="button" class="tab active" data-tab="pending">طلبات قيد المراجعة</button>
          <button type="button" class="tab" data-tab="all-requests">كل الطلبات</button>
          <button type="button" class="tab" data-tab="mosques">المساجد المعتمدة</button>
        </div>
        <button type="button" class="btn-secondary" id="logoutBtn">خروج</button>
      </div>
      <div id="panel-pending" class="card table-wrap"></div>
      <div id="panel-all-requests" class="card table-wrap hidden"></div>
      <div id="panel-mosques" class="card table-wrap hidden"></div>
      <div id="dashMsg" class="msg hidden" style="margin-top: 14px;"></div>
    </section>
  </main>
  <script>
    const API = ${JSON.stringify(apiBase())};
    const ANON = ${JSON.stringify(anonKey())};
    const TOKEN_KEY = 'hafiz_platform_token';
    let token = localStorage.getItem(TOKEN_KEY) || '';
    const loginCard = document.getElementById('loginCard');
    const dash = document.getElementById('dash');
    const loginMsg = document.getElementById('loginMsg');
    const dashMsg = document.getElementById('dashMsg');

    function showMsg(el, text, ok) {
      el.textContent = text;
      el.className = 'msg ' + (ok ? 'ok' : 'err');
    }
    function authHeaders() {
      return {
        'Content-Type': 'application/json',
        'apikey': ANON,
        'Authorization': 'Bearer ' + (token || ANON),
        'x-platform-token': token,
      };
    }
    async function api(path, options = {}) {
      const res = await fetch(API + path, {
        ...options,
        headers: { ...authHeaders(), ...(options.headers || {}) },
      });
      const json = await res.json().catch(() => ({}));
      if (res.status === 401) {
        token = '';
        localStorage.removeItem(TOKEN_KEY);
        renderAuth();
        throw new Error(json.error || 'انتهت الجلسة');
      }
      if (!res.ok) throw new Error(json.error || 'طلب فاشل');
      return json;
    }
    function renderAuth() {
      const loggedIn = !!token;
      loginCard.classList.toggle('hidden', loggedIn);
      dash.classList.toggle('hidden', !loggedIn);
      if (loggedIn) refresh();
    }
    function statusBadge(status) {
      const map = { pending: 'قيد المراجعة', approved: 'مقبول', rejected: 'مرفوض' };
      return '<span class="badge ' + status + '">' + (map[status] || status) + '</span>';
    }
    function formatDate(v) {
      if (!v) return '—';
      try { return new Date(v).toLocaleString('ar-SA'); } catch { return v; }
    }
    function escapeHtml(s) {
      return String(s || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
    }
    function requestsTable(rows, { actions }) {
      if (!rows.length) return '<p class="muted">لا توجد عناصر.</p>';
      return '<table><thead><tr><th>الجامع</th><th>البريد</th><th>واتساب</th><th>الحالة</th><th>التاريخ</th>' +
        (actions ? '<th>إجراء</th>' : '') + '</tr></thead><tbody>' +
        rows.map((r) => '<tr><td>' + escapeHtml(r.mosque_name) + '</td><td dir="ltr">' +
          escapeHtml(r.email) + '</td><td dir="ltr">' + escapeHtml(r.whatsapp_phone) +
          '</td><td>' + statusBadge(r.status) + '</td><td>' + formatDate(r.created_at) + '</td>' +
          (actions ? '<td class="row-actions" data-id="' + r.id + '"></td>' : '') + '</tr>').join('') +
        '</tbody></table>';
    }
    async function refresh() {
      dashMsg.className = 'msg hidden';
      const [pending, all, mosques] = await Promise.all([
        api('/registration-requests?status=pending'),
        api('/registration-requests'),
        api('/platform/mosques'),
      ]);
      const pendingEl = document.getElementById('panel-pending');
      pendingEl.innerHTML = '<h2 style="margin-top:0">طلبات قيد المراجعة</h2>' + requestsTable(pending.requests, { actions: true });
      pendingEl.querySelectorAll('td.row-actions').forEach((td) => {
        const id = td.getAttribute('data-id');
        td.innerHTML = '<button type="button" class="btn-primary" data-approve="' + id +
          '">موافقة</button> <button type="button" class="btn-danger" data-reject="' + id + '">رفض</button>';
      });
      document.getElementById('panel-all-requests').innerHTML =
        '<h2 style="margin-top:0">كل الطلبات</h2>' + requestsTable(all.requests, { actions: false });
      const m = mosques.mosques || [];
      document.getElementById('panel-mosques').innerHTML = '<h2 style="margin-top:0">المساجد المعتمدة</h2>' +
        (m.length ? '<table><thead><tr><th>اسم المسجد</th><th>البريد</th><th>واتساب</th><th>تاريخ الاعتماد</th></tr></thead><tbody>' +
          m.map((x) => '<tr><td>' + escapeHtml(x.name) + '</td><td dir="ltr">' +
            escapeHtml(x.admin && x.admin.email || '—') + '</td><td dir="ltr">' +
            escapeHtml(x.whatsapp_phone || '—') + '</td><td>' + formatDate(x.created_at) +
            '</td></tr>').join('') + '</tbody></table>' : '<p class="muted">لا مساجد بعد.</p>');
    }
    document.getElementById('loginForm').addEventListener('submit', async (e) => {
      e.preventDefault();
      loginMsg.className = 'msg hidden';
      const password = new FormData(e.target).get('password');
      try {
        const res = await fetch(API + '/platform/login', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'apikey': ANON, 'Authorization': 'Bearer ' + ANON },
          body: JSON.stringify({ password }),
        });
        const json = await res.json().catch(() => ({}));
        if (!res.ok) throw new Error(json.error || 'فشل الدخول');
        token = json.token;
        localStorage.setItem(TOKEN_KEY, token);
        e.target.reset();
        renderAuth();
      } catch (err) {
        showMsg(loginMsg, err.message, false);
      }
    });
    document.getElementById('logoutBtn').addEventListener('click', async () => {
      try { await api('/platform/logout', { method: 'POST' }); } catch (_) {}
      token = ''; localStorage.removeItem(TOKEN_KEY); renderAuth();
    });
    document.querySelectorAll('.tab').forEach((btn) => {
      btn.addEventListener('click', () => {
        document.querySelectorAll('.tab').forEach((b) => b.classList.remove('active'));
        btn.classList.add('active');
        const tab = btn.dataset.tab;
        ['pending', 'all-requests', 'mosques'].forEach((name) => {
          document.getElementById('panel-' + name).classList.toggle('hidden', name !== tab);
        });
      });
    });
    document.getElementById('dash').addEventListener('click', async (e) => {
      const t = e.target;
      if (!(t instanceof HTMLElement)) return;
      const approveId = t.getAttribute('data-approve');
      const rejectId = t.getAttribute('data-reject');
      try {
        if (approveId) {
          t.setAttribute('disabled', 'true');
          const json = await api('/registration-requests/' + approveId + '/approve', { method: 'POST' });
          showMsg(dashMsg, 'تمت الموافقة. كلمة المرور: ' + json.generated_password, true);
          const box = document.createElement('div');
          box.className = 'password-box';
          box.textContent = json.generated_password;
          dashMsg.appendChild(box);
          const wa = document.createElement('a');
          wa.className = 'btn-wa';
          wa.href = json.whatsapp_url;
          wa.target = '_blank';
          wa.rel = 'noopener';
          wa.textContent = 'فتح واتساب لإرسال البيانات';
          wa.style.marginTop = '10px';
          dashMsg.appendChild(wa);
          await refresh();
        }
        if (rejectId) {
          if (!confirm('رفض هذا الطلب؟')) return;
          t.setAttribute('disabled', 'true');
          await api('/registration-requests/' + rejectId + '/reject', { method: 'POST' });
          showMsg(dashMsg, 'تم رفض الطلب.', true);
          await refresh();
        }
      } catch (err) {
        showMsg(dashMsg, err.message, false);
      }
    });
    renderAuth();
  </script>
</body>
</html>`;
  return new Response(html, {
    headers: {
      ...corsHeaders,
      "Content-Type": "text/html; charset=utf-8",
    },
  });
});
