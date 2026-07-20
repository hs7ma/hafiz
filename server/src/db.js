const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');
const bcrypt = require('bcryptjs');
const { v4: uuidv4 } = require('uuid');

const dataDir = process.env.DATA_DIR
  ? path.resolve(process.env.DATA_DIR)
  : path.join(__dirname, '..', 'data');
const dbPath = path.join(dataDir, 'hafiz.sqlite');

if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

const db = new Database(dbPath);
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

function nowIso() {
  return new Date().toISOString();
}

function migrate() {
  db.exec(`
    CREATE TABLE IF NOT EXISTS mosques (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL UNIQUE,
      created_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS mosque_admins (
      id TEXT PRIMARY KEY,
      mosque_id TEXT NOT NULL REFERENCES mosques(id) ON DELETE CASCADE,
      full_name TEXT NOT NULL,
      email TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      created_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS teachers (
      id TEXT PRIMARY KEY,
      mosque_id TEXT NOT NULL REFERENCES mosques(id) ON DELETE CASCADE,
      full_name TEXT NOT NULL,
      english_name TEXT NOT NULL,
      english_prefix TEXT NOT NULL,
      login_code TEXT NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE (mosque_id, login_code),
      UNIQUE (mosque_id, full_name)
    );

    CREATE TABLE IF NOT EXISTS students (
      id TEXT PRIMARY KEY,
      mosque_id TEXT NOT NULL REFERENCES mosques(id) ON DELETE CASCADE,
      teacher_id TEXT NOT NULL REFERENCES teachers(id) ON DELETE CASCADE,
      full_name TEXT NOT NULL,
      grade_level TEXT NOT NULL,
      age INTEGER NOT NULL,
      parent_phone TEXT NOT NULL,
      login_username TEXT NOT NULL,
      login_code TEXT NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE (mosque_id, login_username)
    );

    CREATE TABLE IF NOT EXISTS sessions (
      id TEXT PRIMARY KEY,
      mosque_id TEXT NOT NULL REFERENCES mosques(id) ON DELETE CASCADE,
      teacher_id TEXT NOT NULL REFERENCES teachers(id) ON DELETE CASCADE,
      session_date TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'active',
      started_at TEXT NOT NULL,
      ended_at TEXT,
      UNIQUE (teacher_id, session_date)
    );

    CREATE TABLE IF NOT EXISTS attendance (
      id TEXT PRIMARY KEY,
      session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
      student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
      status TEXT NOT NULL DEFAULT 'unmarked',
      memorization_level TEXT,
      behavior_score INTEGER,
      marked_at TEXT,
      UNIQUE (session_id, student_id)
    );

    CREATE TABLE IF NOT EXISTS student_homework (
      id TEXT PRIMARY KEY,
      student_id TEXT NOT NULL UNIQUE REFERENCES students(id) ON DELETE CASCADE,
      surah_number INTEGER NOT NULL,
      from_ayah INTEGER NOT NULL,
      to_ayah INTEGER NOT NULL,
      note TEXT DEFAULT '',
      assigned_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS progress (
      id TEXT PRIMARY KEY,
      student_id TEXT NOT NULL UNIQUE REFERENCES students(id) ON DELETE CASCADE,
      surah_number INTEGER NOT NULL,
      ayah_number INTEGER NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_teachers_mosque ON teachers (mosque_id);
    CREATE INDEX IF NOT EXISTS idx_teachers_login ON teachers (full_name, login_code);
    CREATE INDEX IF NOT EXISTS idx_students_teacher ON students (teacher_id);
    CREATE INDEX IF NOT EXISTS idx_students_login ON students (login_username, login_code);
    CREATE INDEX IF NOT EXISTS idx_sessions_teacher_date ON sessions (teacher_id, session_date);
    CREATE INDEX IF NOT EXISTS idx_attendance_session ON attendance (session_id);
    CREATE INDEX IF NOT EXISTS idx_homework_student ON student_homework (student_id);
  `);
}

function hashPassword(password) {
  return bcrypt.hashSync(String(password), 10);
}

function verifyPassword(password, hash) {
  return bcrypt.compareSync(String(password), String(hash || ''));
}

function seedIfEmpty() {
  const count = db.prepare('SELECT COUNT(*) AS c FROM mosques').get().c;
  if (count > 0) return false;

  const ts = nowIso();
  const mosqueId = 'mosque-1';
  const adminId = 'admin-1';
  const teacherId = 'teacher-1';
  const stu1 = 'stu-1';
  const stu2 = 'stu-2';

  const tx = db.transaction(() => {
    db.prepare(
      'INSERT INTO mosques (id, name, created_at) VALUES (?, ?, ?)',
    ).run(mosqueId, 'مسجد النور', ts);

    db.prepare(`
      INSERT INTO mosque_admins (id, mosque_id, full_name, email, password_hash, created_at)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(
      adminId,
      mosqueId,
      'إدارة مسجد النور',
      'admin@demo.local',
      hashPassword('demo1234'),
      ts,
    );

    db.prepare(`
      INSERT INTO teachers
        (id, mosque_id, full_name, english_name, english_prefix, login_code, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `).run(teacherId, mosqueId, 'الشيخ إبراهيم', 'Ibrahim', 'IB', 'IB482917', ts);

    db.prepare(`
      INSERT INTO students
        (id, mosque_id, teacher_id, full_name, grade_level, age, parent_phone,
         login_username, login_code, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      stu1, mosqueId, teacherId, 'أحمد يوسف', 'الصف الخامس', 11, '0511111111',
      'ahmad_yusuf', 'A7K3M', ts,
    );

    db.prepare(`
      INSERT INTO students
        (id, mosque_id, teacher_id, full_name, grade_level, age, parent_phone,
         login_username, login_code, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      stu2, mosqueId, teacherId, 'محمد خالد', 'الصف السادس', 12, '0522222222',
      'mohammad_khaled', 'B4N8PQ', ts,
    );

    db.prepare(`
      INSERT INTO student_homework
        (id, student_id, surah_number, from_ayah, to_ayah, note, assigned_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `).run('hw-1', stu1, 2, 1, 5, '', ts);
  });

  tx();
  return true;
}

migrate();
const seeded = seedIfEmpty();

module.exports = {
  db,
  dbPath,
  nowIso,
  uuidv4,
  hashPassword,
  verifyPassword,
  seeded,
};
