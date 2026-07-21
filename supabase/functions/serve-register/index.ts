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
  box-shadow: var(--shadow); padding: 22px; backdrop-filter: blur(8px); }
.grid { display: grid; gap: 14px; }
label { display: grid; gap: 6px; font-weight: 600; font-size: 0.95rem; }
input { font: inherit; padding: 12px 14px; border-radius: 14px; border: 1px solid var(--line);
  background: #fff; color: var(--ink); }
.actions { display: flex; gap: 10px; flex-wrap: wrap; }
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
  <title>طلب تسجيل جامع — حافظ</title>
  <style>${CSS}</style>
</head>
<body>
  <main class="shell">
    <header class="brand">
      <h1>حافظ</h1>
      <p>أرسل طلب تسجيل جامعك. سنراجع البيانات ثم نرسل لك كلمة المرور عبر واتساب بعد الموافقة.</p>
    </header>
    <section class="card">
      <form id="form" class="grid">
        <label>اسم الجامع
          <input name="mosque_name" required maxlength="120" placeholder="مثال: مسجد النور" autocomplete="organization" />
        </label>
        <label>البريد الإلكتروني
          <input name="email" type="email" required maxlength="160" placeholder="admin@example.com" autocomplete="email" dir="ltr" />
        </label>
        <label>رقم واتساب
          <input name="whatsapp_phone" required maxlength="20" placeholder="05xxxxxxxx أو 9665xxxxxxxx" inputmode="tel" dir="ltr" />
        </label>
        <p class="muted">بعد الإرسال يبقى الطلب قيد المراجعة. لا يمكن الدخول للتطبيق قبل موافقة إدارة حافظ.</p>
        <div class="actions">
          <button class="btn-primary" type="submit" id="submitBtn">إرسال الطلب</button>
        </div>
        <div id="msg" class="msg hidden" role="status"></div>
      </form>
    </section>
  </main>
  <script>
    const API = ${JSON.stringify(apiBase())};
    const ANON = ${JSON.stringify(anonKey())};
    const form = document.getElementById('form');
    const msg = document.getElementById('msg');
    const submitBtn = document.getElementById('submitBtn');
    function show(text, ok) {
      msg.textContent = text;
      msg.className = 'msg ' + (ok ? 'ok' : 'err');
    }
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      msg.className = 'msg hidden';
      submitBtn.disabled = true;
      const data = Object.fromEntries(new FormData(form).entries());
      try {
        const res = await fetch(API + '/registration-requests', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'apikey': ANON,
            'Authorization': 'Bearer ' + ANON,
          },
          body: JSON.stringify(data),
        });
        const json = await res.json().catch(() => ({}));
        if (!res.ok) throw new Error(json.error || 'تعذّر إرسال الطلب');
        form.reset();
        show(json.message || 'تم إرسال الطلب بنجاح. انتظر الموافقة.', true);
      } catch (err) {
        show(err.message || 'حدث خطأ', false);
      } finally {
        submitBtn.disabled = false;
      }
    });
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
