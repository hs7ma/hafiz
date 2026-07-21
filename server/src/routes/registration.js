const express = require('express');
const {
  db,
  nowIso,
  uuidv4,
  hashPassword,
} = require('../db');
const {
  looksLikeEmail,
  mosqueAdminPassword,
  normalizeWhatsappDigits,
  looksLikeWhatsappPhone,
} = require('../codes');
const {
  platformPassword,
  isPlatformConfigured,
  createSession,
  revokeSession,
  requirePlatformAdmin,
} = require('../platformAuth');

const router = express.Router();

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

function publicRequest(row) {
  return {
    id: row.id,
    mosque_name: row.mosque_name,
    email: row.email,
    whatsapp_phone: row.whatsapp_phone,
    status: row.status,
    mosque_id: row.mosque_id || null,
    reviewed_at: row.reviewed_at || null,
    created_at: row.created_at,
  };
}

router.post('/platform/login', (req, res) => {
  if (!isPlatformConfigured()) {
    return res.status(503).json({
      error: 'PLATFORM_ADMIN_PASSWORD غير مضبوط على الخادم',
    });
  }
  const password = String(req.body.password || '');
  if (password !== platformPassword()) {
    return res.status(401).json({ error: 'كلمة مرور الإدارة غير صحيحة' });
  }
  const token = createSession();
  return res.json({ token, role: 'platform_admin' });
});

router.post('/platform/logout', requirePlatformAdmin, (req, res) => {
  revokeSession(req.platformToken);
  return res.json({ ok: true });
});

/** طلب تسجيل عام من صفحة الويب */
router.post('/registration-requests', async (req, res) => {
  const mosqueName = String(req.body.mosque_name || '').trim();
  const email = String(req.body.email || '').trim().toLowerCase();
  const rawPhone = String(req.body.whatsapp_phone || '').trim();
  const whatsappPhone = normalizeWhatsappDigits(rawPhone);

  if (!mosqueName) return res.status(400).json({ error: 'أدخل اسم الجامع' });
  if (!looksLikeEmail(email)) return res.status(400).json({ error: 'البريد غير صالح' });
  if (!looksLikeWhatsappPhone(rawPhone)) {
    return res.status(400).json({ error: 'رقم واتساب غير صالح' });
  }

  try {
    const existsMosque = await db
      .prepare('SELECT id FROM mosques WHERE name = ?')
      .get(mosqueName);
    if (existsMosque) {
      return res.status(409).json({ error: 'يوجد مسجد بهذا الاسم مسبقًا' });
    }

    const existsEmail = await db
      .prepare('SELECT id FROM mosque_admins WHERE email = ?')
      .get(email);
    if (existsEmail) {
      return res.status(409).json({ error: 'البريد مستخدم مسبقًا' });
    }

    const pendingDup = await db
      .prepare(`
        SELECT id FROM mosque_registration_requests
        WHERE status = 'pending' AND (email = ? OR mosque_name = ?)
        LIMIT 1
      `)
      .get(email, mosqueName);
    if (pendingDup) {
      return res.status(409).json({
        error: 'يوجد طلب قيد المراجعة لنفس البريد أو اسم الجامع',
      });
    }

    const row = {
      id: uuidv4(),
      mosque_name: mosqueName,
      email,
      whatsapp_phone: whatsappPhone,
      status: 'pending',
      mosque_id: null,
      reviewed_at: null,
      created_at: nowIso(),
    };
    await db
      .prepare(`
        INSERT INTO mosque_registration_requests
          (id, mosque_name, email, whatsapp_phone, status, mosque_id, reviewed_at, created_at)
        VALUES
          (@id, @mosque_name, @email, @whatsapp_phone, @status, @mosque_id, @reviewed_at, @created_at)
      `)
      .run(row);

    return res.status(201).json({
      request: publicRequest(row),
      message: 'تم إرسال الطلب. انتظر موافقة إدارة حافظ.',
    });
  } catch (e) {
    return res.status(e.status || 500).json({ error: e.message || 'تعذّر إرسال الطلب' });
  }
});

router.get('/registration-requests', requirePlatformAdmin, async (req, res) => {
  const status = String(req.query.status || '').trim();
  let sql = 'SELECT * FROM mosque_registration_requests WHERE 1=1';
  const params = [];
  if (status === 'pending' || status === 'approved' || status === 'rejected') {
    sql += ' AND status = ?';
    params.push(status);
  }
  sql += ' ORDER BY created_at DESC';
  const rows = await db.prepare(sql).all(...params);
  return res.json({ requests: rows.map(publicRequest) });
});

router.get('/platform/mosques', requirePlatformAdmin, async (_req, res) => {
  const rows = await db
    .prepare(`
      SELECT
        m.id,
        m.name,
        m.whatsapp_phone,
        m.created_at,
        a.id AS admin_id,
        a.full_name AS admin_name,
        a.email AS admin_email
      FROM mosques m
      LEFT JOIN mosque_admins a ON a.mosque_id = m.id
      ORDER BY m.created_at DESC
    `)
    .all();
  return res.json({
    mosques: rows.map((r) => ({
      id: r.id,
      name: r.name,
      whatsapp_phone: r.whatsapp_phone || null,
      created_at: r.created_at,
      admin: r.admin_id
        ? {
            id: r.admin_id,
            full_name: r.admin_name,
            email: r.admin_email,
          }
        : null,
    })),
  });
});

router.post('/registration-requests/:id/approve', requirePlatformAdmin, async (req, res) => {
  const id = String(req.params.id || '').trim();
  try {
    const result = await db.transaction(async () => {
      const request = await db
        .prepare('SELECT * FROM mosque_registration_requests WHERE id = ?')
        .get(id);
      if (!request) throw httpError(404, 'الطلب غير موجود');
      if (request.status !== 'pending') {
        throw httpError(409, 'تمت معالجة هذا الطلب مسبقًا');
      }

      const existsMosque = await db
        .prepare('SELECT id FROM mosques WHERE name = ?')
        .get(request.mosque_name);
      if (existsMosque) throw httpError(409, 'يوجد مسجد بهذا الاسم مسبقًا');

      const existsEmail = await db
        .prepare('SELECT id FROM mosque_admins WHERE email = ?')
        .get(request.email);
      if (existsEmail) throw httpError(409, 'البريد مستخدم مسبقًا');

      const plainPassword = mosqueAdminPassword();
      const mosque = {
        id: uuidv4(),
        name: request.mosque_name,
        whatsapp_phone: request.whatsapp_phone,
        created_at: nowIso(),
      };
      const admin = {
        id: uuidv4(),
        mosque_id: mosque.id,
        full_name: `مسؤول ${request.mosque_name}`,
        email: request.email,
        password_hash: hashPassword(plainPassword),
        created_at: nowIso(),
      };

      await db
        .prepare(`
          INSERT INTO mosques (id, name, whatsapp_phone, created_at)
          VALUES (@id, @name, @whatsapp_phone, @created_at)
        `)
        .run(mosque);
      await db
        .prepare(`
          INSERT INTO mosque_admins
            (id, mosque_id, full_name, email, password_hash, created_at)
          VALUES (@id, @mosque_id, @full_name, @email, @password_hash, @created_at)
        `)
        .run(admin);

      const reviewedAt = nowIso();
      await db
        .prepare(`
          UPDATE mosque_registration_requests
          SET status = 'approved', mosque_id = ?, reviewed_at = ?
          WHERE id = ?
        `)
        .run(mosque.id, reviewedAt, id);

      const waDigits = normalizeWhatsappDigits(request.whatsapp_phone);
      const message = [
        'السلام عليكم،',
        `تم اعتماد تسجيل «${mosque.name}» في تطبيق حافظ.`,
        '',
        'بيانات الدخول لإدارة الجامع:',
        `اسم المسجد: ${mosque.name}`,
        `البريد: ${admin.email}`,
        `كلمة المرور: ${plainPassword}`,
        '',
        'ادخل عبر شاشة «إدارة الجامع» في التطبيق.',
      ].join('\n');
      const whatsappUrl = `https://wa.me/${waDigits}?text=${encodeURIComponent(message)}`;

      return {
        request: publicRequest({
          ...request,
          status: 'approved',
          mosque_id: mosque.id,
          reviewed_at: reviewedAt,
        }),
        mosque,
        admin: {
          id: admin.id,
          full_name: admin.full_name,
          email: admin.email,
          mosque_id: admin.mosque_id,
        },
        generated_password: plainPassword,
        whatsapp_url: whatsappUrl,
      };
    });

    return res.json(result);
  } catch (e) {
    return res.status(e.status || 500).json({ error: e.message || 'تعذّرت الموافقة' });
  }
});

router.post('/registration-requests/:id/reject', requirePlatformAdmin, async (req, res) => {
  const id = String(req.params.id || '').trim();
  try {
    const request = await db
      .prepare('SELECT * FROM mosque_registration_requests WHERE id = ?')
      .get(id);
    if (!request) return res.status(404).json({ error: 'الطلب غير موجود' });
    if (request.status !== 'pending') {
      return res.status(409).json({ error: 'تمت معالجة هذا الطلب مسبقًا' });
    }
    const reviewedAt = nowIso();
    await db
      .prepare(`
        UPDATE mosque_registration_requests
        SET status = 'rejected', reviewed_at = ?
        WHERE id = ?
      `)
      .run(reviewedAt, id);
    return res.json({
      request: publicRequest({
        ...request,
        status: 'rejected',
        reviewed_at: reviewedAt,
      }),
    });
  } catch (e) {
    return res.status(500).json({ error: e.message || 'تعذّر الرفض' });
  }
});

module.exports = router;
