/**
 * إعادة زرع بيانات التجربة على Postgres (Supabase).
 * الاستخدام: npm run seed
 */
const { pool, init, db, nowIso, uuidv4, hashPassword } = require('./db');

async function main() {
  await init();
  await pool.query(`
    TRUNCATE TABLE
      public.progress,
      public.student_homework,
      public.attendance,
      public.sessions,
      public.students,
      public.teachers,
      public.mosque_admins,
      public.mosques
    RESTART IDENTITY CASCADE
  `);

  const ts = nowIso();
  const mosqueId = uuidv4();
  const adminId = uuidv4();
  const teacherId = uuidv4();
  const stu1 = uuidv4();
  const stu2 = uuidv4();

  await db.transaction(async () => {
    await db
      .prepare('INSERT INTO mosques (id, name, created_at) VALUES (?, ?, ?)')
      .run(mosqueId, 'مسجد النور', ts);
    await db
      .prepare(`
        INSERT INTO mosque_admins
          (id, mosque_id, full_name, email, password_hash, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
      `)
      .run(
        adminId,
        mosqueId,
        'إدارة مسجد النور',
        'admin@demo.local',
        hashPassword('demo1234'),
        ts,
      );
    await db
      .prepare(`
        INSERT INTO teachers
          (id, mosque_id, full_name, english_name, english_prefix, login_code, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `)
      .run(teacherId, mosqueId, 'الشيخ إبراهيم', 'Ibrahim', 'IB', 'IB482917', ts);
    await db
      .prepare(`
        INSERT INTO students
          (id, mosque_id, teacher_id, full_name, grade_level, age, parent_phone,
           login_username, login_code, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `)
      .run(
        stu1, mosqueId, teacherId, 'أحمد يوسف', 'الصف الخامس', 11, '0511111111',
        'ahmad_yusuf', 'A7K3M', ts,
      );
    await db
      .prepare(`
        INSERT INTO students
          (id, mosque_id, teacher_id, full_name, grade_level, age, parent_phone,
           login_username, login_code, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `)
      .run(
        stu2, mosqueId, teacherId, 'محمد خالد', 'الصف السادس', 12, '0522222222',
        'mohammad_khaled', 'B4N8PQ', ts,
      );
    await db
      .prepare(`
        INSERT INTO student_homework
          (id, student_id, surah_number, from_ayah, to_ayah, note, assigned_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `)
      .run(uuidv4(), stu1, 2, 1, 5, '', ts);
  });

  console.log('✓ أُعيدت تهيئة قاعدة Postgres مع بيانات التجربة');
  console.log('');
  console.log('حسابات التجربة:');
  console.log('  مسؤول: مسجد النور / admin@demo.local / demo1234');
  console.log('  مدرّس: الشيخ إبراهيم / IB482917');
  console.log('  طالب:  ahmad_yusuf / A7K3M');
  await pool.end();
}

main().catch(async (e) => {
  console.error(e);
  try {
    await pool.end();
  } catch (_) {}
  process.exit(1);
});
