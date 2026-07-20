const express = require('express');
const cors = require('cors');
const os = require('os');
const api = require('./routes/api');
const { init, dbPath, seeded } = require('./db');

const PORT = Number(process.env.PORT) || 3000;
const app = express();

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
    console.log(`  قاعدة البيانات: ${dbPath}`);
    if (seeded) {
      console.log('  ✓ تم زرع بيانات التجربة (مسجد النور / demo)');
    }
    console.log('');
  });
}

main().catch((err) => {
  console.error('فشل تشغيل الخادم:', err.message || err);
  process.exit(1);
});
