const express = require('express');
const cors = require('cors');
const path = require('path');
const os = require('os');
const api = require('./routes/api');
const registration = require('./routes/registration');
const { init, dbPath, seeded } = require('./db');

const PORT = Number(process.env.PORT) || 3000;
const app = express();
const publicDir = path.join(__dirname, '..', 'public');

app.use(cors());
app.use(express.json({ limit: '2mb' }));

app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    service: 'hafiz-server',
    db: dbPath,
    engine: 'postgres',
  });
});

app.use('/api', api);
app.use('/api', registration);

app.get('/register', (_req, res) => {
  res.sendFile(path.join(publicDir, 'register.html'));
});

app.get('/platform', (_req, res) => {
  res.sendFile(path.join(publicDir, 'platform.html'));
});

app.use(express.static(publicDir));

app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ error: 'خطأ داخلي في الخادم' });
});

function lanAddresses() {
  const nets = os.networkInterfaces();
  const out = [];
  for (const name of Object.keys(nets)) {
    for (const net of nets[name] || []) {
      if (net.family === 'IPv4' && !net.internal) out.push(net.address);
    }
  }
  return out;
}

async function main() {
  await init();
  app.listen(PORT, '0.0.0.0', () => {
    const lans = lanAddresses();
    console.log('');
    console.log('✓ خادم حافظ يعمل (Supabase Postgres)');
    console.log(`  محلي:   http://127.0.0.1:${PORT}`);
    for (const ip of lans) {
      console.log(`  الشبكة: http://${ip}:${PORT}`);
    }
    console.log(`  الصحة:  http://127.0.0.1:${PORT}/health`);
    console.log(`  تسجيل المساجد: http://127.0.0.1:${PORT}/register`);
    console.log(`  إدارة المنصة:  http://127.0.0.1:${PORT}/platform`);
    console.log(`  قاعدة البيانات: ${dbPath}`);
    if (seeded) {
      console.log('  ✓ تم زرع بيانات التجربة (مسجد النور / demo)');
    }
    if (!String(process.env.PLATFORM_ADMIN_PASSWORD || '').trim()) {
      console.log('  ⚠ PLATFORM_ADMIN_PASSWORD غير مضبوط — صفحة /platform لن تعمل');
    }
    console.log('');
  });
}

main().catch((err) => {
  console.error('فشل تشغيل الخادم:', err.message || err);
  process.exit(1);
});
