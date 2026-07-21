const fs = require('fs');
const path = require('path');
const { AsyncLocalStorage } = require('async_hooks');
const { Pool, types } = require('pg');
const bcrypt = require('bcryptjs');
const { v4: uuidv4 } = require('uuid');

types.setTypeParser(1082, (v) => v); // date
types.setTypeParser(1114, (v) => (v.includes('T') ? v : `${v.replace(' ', 'T')}Z`));
types.setTypeParser(1184, (v) => new Date(v).toISOString());

function loadDotEnv() {
  const envPath = path.join(__dirname, '..', '.env');
  if (!fs.existsSync(envPath)) return;
  for (const line of fs.readFileSync(envPath, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq <= 0) continue;
    const key = trimmed.slice(0, eq).trim();
    let val = trimmed.slice(eq + 1).trim();
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1);
    }
    if (process.env[key] == null || process.env[key] === '') {
      process.env[key] = val;
    }
  }
}

loadDotEnv();

function resolveDatabaseUrl() {
  if (process.env.DATABASE_URL && process.env.DATABASE_URL.trim()) {
    return process.env.DATABASE_URL.trim();
  }
  const pass = process.env.SUPABASE_DB_PASSWORD;
  const ref = process.env.SUPABASE_PROJECT_REF || 'qlqzdtphwmoohqgqftuv';
  const region = process.env.SUPABASE_REGION || 'ap-southeast-2';
  if (pass) {
    // Pooler IPv4 — تجنّب db.*.supabase.co الذي غالبًا IPv6 فقط
    return `postgresql://postgres.${ref}:${encodeURIComponent(pass)}@aws-0-${region}.pooler.supabase.com:6543/postgres`;
  }
  throw new Error(
    'DATABASE_URL غير مضبوط. ضع رابط Postgres من Supabase في متغير DATABASE_URL.',
  );
}

const databaseUrl = resolveDatabaseUrl();
const pool = new Pool({
  connectionString: databaseUrl,
  ssl: { rejectUnauthorized: false },
  max: 10,
});

const txStorage = new AsyncLocalStorage();

function nowIso() {
  return new Date().toISOString();
}

function hashPassword(password) {
  return bcrypt.hashSync(String(password), 10);
}

function verifyPassword(password, hash) {
  return bcrypt.compareSync(String(password), String(hash || ''));
}

function adaptSql(sql) {
  let s = String(sql);
  if (/INSERT\s+OR\s+IGNORE\s+INTO\s+attendance/i.test(s)) {
    s = s.replace(/INSERT\s+OR\s+IGNORE\s+INTO/i, 'INSERT INTO');
    if (!/ON CONFLICT/i.test(s)) {
      s += ' ON CONFLICT (session_id, student_id) DO NOTHING';
    }
    return s;
  }
  if (/INSERT\s+OR\s+IGNORE\s+INTO/i.test(s)) {
    s = s.replace(/INSERT\s+OR\s+IGNORE\s+INTO/i, 'INSERT INTO');
    if (!/ON CONFLICT/i.test(s)) s += ' ON CONFLICT DO NOTHING';
  }
  return s;
}

function bind(sql, params) {
  const text = adaptSql(sql);
  if (
    params.length === 1 &&
    params[0] != null &&
    typeof params[0] === 'object' &&
    !Array.isArray(params[0])
  ) {
    const obj = params[0];
    const values = [];
    const pgText = text.replace(/@([a-zA-Z_][a-zA-Z0-9_]*)/g, (_, name) => {
      values.push(obj[name]);
      return `$${values.length}`;
    });
    return { text: pgText, values };
  }
  let i = 0;
  const pgText = text.replace(/\?/g, () => `$${++i}`);
  return { text: pgText, values: params };
}

function client() {
  return txStorage.getStore() || pool;
}

function prepare(sql) {
  return {
    get(...params) {
      const q = bind(sql, params);
      return client()
        .query(q.text, q.values)
        .then((r) => r.rows[0]);
    },
    all(...params) {
      const q = bind(sql, params);
      return client()
        .query(q.text, q.values)
        .then((r) => r.rows);
    },
    run(...params) {
      const q = bind(sql, params);
      return client()
        .query(q.text, q.values)
        .then((r) => ({
          changes: r.rowCount || 0,
          lastInsertRowid: null,
        }));
    },
  };
}

async function transaction(fn) {
  // معاملة متداخلة: أعد استخدام العميل الحالي
  if (txStorage.getStore()) {
    return fn();
  }
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    const result = await txStorage.run(c, () => fn());
    await c.query('COMMIT');
    return result;
  } catch (e) {
    try {
      await c.query('ROLLBACK');
    } catch (_) {}
    throw e;
  } finally {
    c.release();
  }
}

const db = { prepare, transaction };

async function migrate() {
  await pool.query(`
    CREATE EXTENSION IF NOT EXISTS "pgcrypto";

    DO $$ BEGIN
      CREATE TYPE user_role AS ENUM ('mosque_admin', 'teacher', 'student');
    EXCEPTION WHEN duplicate_object THEN NULL; END $$;

    DO $$ BEGIN
      CREATE TYPE attendance_status AS ENUM ('unmarked', 'present', 'absent', 'late');
    EXCEPTION WHEN duplicate_object THEN NULL; END $$;

    DO $$ BEGIN
      CREATE TYPE session_status AS ENUM ('active', 'completed', 'cancelled');
    EXCEPTION WHEN duplicate_object THEN NULL; END $$;

    DO $$ BEGIN
      CREATE TYPE memorization_level AS ENUM (
        'not_memorized', 'poor', 'average', 'good', 'very_good', 'excellent'
      );
    EXCEPTION WHEN duplicate_object THEN NULL; END $$;

    CREATE TABLE IF NOT EXISTS public.mosques (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      name text NOT NULL UNIQUE,
      created_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS public.mosque_admins (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      mosque_id uuid NOT NULL REFERENCES public.mosques(id) ON DELETE CASCADE,
      full_name text NOT NULL,
      email text NOT NULL UNIQUE,
      password_hash text,
      created_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS public.teachers (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      mosque_id uuid NOT NULL REFERENCES public.mosques(id) ON DELETE CASCADE,
      full_name text NOT NULL,
      english_name text NOT NULL,
      english_prefix char(2) NOT NULL,
      login_code text NOT NULL,
      created_at timestamptz NOT NULL DEFAULT now(),
      UNIQUE (mosque_id, login_code),
      UNIQUE (mosque_id, full_name)
    );

    CREATE TABLE IF NOT EXISTS public.students (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      mosque_id uuid NOT NULL REFERENCES public.mosques(id) ON DELETE CASCADE,
      teacher_id uuid NOT NULL REFERENCES public.teachers(id) ON DELETE CASCADE,
      full_name text NOT NULL,
      grade_level text NOT NULL,
      age int NOT NULL CHECK (age BETWEEN 4 AND 25),
      parent_phone text NOT NULL,
      login_username text NOT NULL,
      login_code text NOT NULL,
      created_at timestamptz NOT NULL DEFAULT now(),
      UNIQUE (mosque_id, login_username)
    );

    CREATE TABLE IF NOT EXISTS public.sessions (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      mosque_id uuid NOT NULL REFERENCES public.mosques(id) ON DELETE CASCADE,
      teacher_id uuid NOT NULL REFERENCES public.teachers(id) ON DELETE CASCADE,
      session_date date NOT NULL,
      status session_status NOT NULL DEFAULT 'active',
      started_at timestamptz NOT NULL DEFAULT now(),
      ended_at timestamptz,
      UNIQUE (teacher_id, session_date)
    );

    CREATE TABLE IF NOT EXISTS public.attendance (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      session_id uuid NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
      student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
      status attendance_status NOT NULL DEFAULT 'unmarked',
      memorization_level memorization_level,
      behavior_score int CHECK (behavior_score IS NULL OR (behavior_score BETWEEN 0 AND 10)),
      marked_at timestamptz,
      UNIQUE (session_id, student_id)
    );

    CREATE TABLE IF NOT EXISTS public.student_homework (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      student_id uuid NOT NULL UNIQUE REFERENCES public.students(id) ON DELETE CASCADE,
      surah_number int NOT NULL CHECK (surah_number BETWEEN 1 AND 114),
      from_ayah int NOT NULL CHECK (from_ayah >= 1),
      to_ayah int NOT NULL CHECK (to_ayah >= from_ayah),
      note text DEFAULT '',
      assigned_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS public.progress (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      student_id uuid NOT NULL UNIQUE REFERENCES public.students(id) ON DELETE CASCADE,
      surah_number int NOT NULL CHECK (surah_number BETWEEN 1 AND 114),
      ayah_number int NOT NULL CHECK (ayah_number >= 1),
      updated_at timestamptz NOT NULL DEFAULT now()
    );
  `);

  await pool.query(`
    DO $$ BEGIN
      ALTER TABLE public.mosque_admins DROP CONSTRAINT IF EXISTS mosque_admins_id_fkey;
    EXCEPTION WHEN undefined_table THEN NULL;
    END $$;
    ALTER TABLE public.mosque_admins
      ADD COLUMN IF NOT EXISTS password_hash text;
    ALTER TABLE public.mosques
      ADD COLUMN IF NOT EXISTS whatsapp_phone text;
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.mosque_registration_requests (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      mosque_name text NOT NULL,
      email text NOT NULL,
      whatsapp_phone text NOT NULL,
      status text NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'approved', 'rejected')),
      mosque_id uuid REFERENCES public.mosques(id) ON DELETE SET NULL,
      reviewed_at timestamptz,
      created_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX IF NOT EXISTS mosque_registration_requests_status_idx
      ON public.mosque_registration_requests (status);
    CREATE INDEX IF NOT EXISTS mosque_registration_requests_email_idx
      ON public.mosque_registration_requests (email);
  `);
}

async function seedIfEmpty() {
  const r = await pool.query('SELECT COUNT(*)::int AS c FROM mosques');
  if (r.rows[0].c > 0) return false;

  const ts = nowIso();
  const mosqueId = uuidv4();
  const adminId = uuidv4();
  const teacherId = uuidv4();
  const stu1 = uuidv4();
  const stu2 = uuidv4();

  await transaction(async () => {
    await prepare('INSERT INTO mosques (id, name, created_at) VALUES (?, ?, ?)').run(
      mosqueId,
      'مسجد النور',
      ts,
    );
    await prepare(`
      INSERT INTO mosque_admins
        (id, mosque_id, full_name, email, password_hash, created_at)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(
      adminId,
      mosqueId,
      'إدارة مسجد النور',
      'admin@demo.local',
      hashPassword('demo1234'),
      ts,
    );
    await prepare(`
      INSERT INTO teachers
        (id, mosque_id, full_name, english_name, english_prefix, login_code, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `).run(teacherId, mosqueId, 'الشيخ إبراهيم', 'Ibrahim', 'IB', 'IB482917', ts);
    await prepare(`
      INSERT INTO students
        (id, mosque_id, teacher_id, full_name, grade_level, age, parent_phone,
         login_username, login_code, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      stu1,
      mosqueId,
      teacherId,
      'أحمد يوسف',
      'الصف الخامس',
      11,
      '0511111111',
      'ahmad_yusuf',
      'A7K3M',
      ts,
    );
    await prepare(`
      INSERT INTO students
        (id, mosque_id, teacher_id, full_name, grade_level, age, parent_phone,
         login_username, login_code, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      stu2,
      mosqueId,
      teacherId,
      'محمد خالد',
      'الصف السادس',
      12,
      '0522222222',
      'mohammad_khaled',
      'B4N8PQ',
      ts,
    );
    await prepare(`
      INSERT INTO student_homework
        (id, student_id, surah_number, from_ayah, to_ayah, note, assigned_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `).run(uuidv4(), stu1, 2, 1, 5, '', ts);
  });
  return true;
}

let seeded = false;
let readyPromise;

async function init() {
  if (!readyPromise) {
    readyPromise = (async () => {
      await pool.query('SELECT 1');
      await migrate();
      seeded = await seedIfEmpty();
    })();
  }
  await readyPromise;
  return true;
}

module.exports = {
  db,
  pool,
  init,
  databaseUrl,
  dbPath: 'supabase-postgres',
  nowIso,
  uuidv4,
  hashPassword,
  verifyPassword,
  get seeded() {
    return seeded;
  },
};
