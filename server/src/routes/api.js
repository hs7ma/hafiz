const express = require('express');
const {
  db,
  nowIso,
  uuidv4,
  hashPassword,
  verifyPassword,
} = require('../db');
const {
  englishPrefix,
  teacherCode,
  studentCode,
  studentUsername,
} = require('../codes');

const router = express.Router();

function publicAdmin(admin, mosque) {
  return {
    id: admin.id,
    full_name: admin.full_name,
    email: admin.email,
    mosque_id: admin.mosque_id,
    role: 'mosque_admin',
    mosque_name: mosque?.name || null,
  };
}

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

router.post('/auth/register', async (_req, res) => {
  return res.status(403).json({
    error:
      'التسجيل المباشر مغلق. أرسل طلبًا عبر صفحة التسجيل وانتظر موافقة إدارة حافظ.',
    register_url: '/register',
  });
});

router.post('/auth/login', async (req, res) => {
  const mosqueName = String(req.body.mosque_name || '').trim();
  const email = String(req.body.email || '').trim().toLowerCase();
  const password = String(req.body.password || '');

  const admin = await db
.prepare('SELECT * FROM mosque_admins WHERE email = ?')
    .get(email);
  if (!admin || !verifyPassword(password, admin.password_hash)) {
    return res.status(401).json({ error: 'بيانات الدخول غير صحيحة' });
  }
  const mosque = await db.prepare('SELECT * FROM mosques WHERE id = ?').get(admin.mosque_id);
  if (!mosque || mosque.name !== mosqueName) {
    return res.status(401).json({ error: 'اسم المسجد غير مطابق لهذا الحساب' });
  }
  return res.json({ user: publicAdmin(admin, mosque), mosque });
});

router.post('/auth/teacher-login', async (req, res) => {
  const fullName = String(req.body.full_name || '').trim();
  const code = String(req.body.login_code || '').trim().toUpperCase();
  const teacher = await db
.prepare(`
      SELECT * FROM teachers
      WHERE full_name = ? AND UPPER(login_code) = ?
      LIMIT 1
    `)
    .get(fullName, code);
  if (!teacher) {
    return res.status(401).json({ error: 'اسم المدرّس أو الرمز غير صحيح' });
  }
  const mosque = await db.prepare('SELECT * FROM mosques WHERE id = ?').get(teacher.mosque_id);
  return res.json({
    user: {
      id: teacher.id,
      full_name: teacher.full_name,
      role: 'teacher',
      mosque_id: teacher.mosque_id,
      email: '',
      mosque_name: mosque?.name || null,
    },
    teacher,
    mosque,
  });
});

router.post('/auth/student-login', async (req, res) => {
  const username = String(req.body.username || '').trim();
  const code = String(req.body.login_code || '').trim().toUpperCase();
  const student = await db
.prepare(`
      SELECT * FROM students
      WHERE login_username = ? AND UPPER(login_code) = ?
      LIMIT 1
    `)
    .get(username, code);
  if (!student) {
    return res.status(401).json({ error: 'اسم المستخدم أو الرمز غير صحيح' });
  }
  const mosque = await db.prepare('SELECT * FROM mosques WHERE id = ?').get(student.mosque_id);
  return res.json({
    user: {
      id: student.id,
      full_name: student.full_name,
      role: 'student',
      mosque_id: student.mosque_id,
      email: '',
      mosque_name: mosque?.name || null,
    },
    student,
    mosque,
  });
});

router.post('/teachers', async (req, res) => {
  const mosqueId = String(req.body.mosque_id || '').trim();
  const fullName = String(req.body.full_name || '').trim();
  const englishName = String(req.body.english_name || '').trim();
  if (!mosqueId) return res.status(400).json({ error: 'mosque_id مطلوب' });
  if (!fullName) return res.status(400).json({ error: 'أدخل اسم المدرّس' });
  if (!englishName || !/[A-Za-z]/.test(englishName)) {
    return res.status(400).json({ error: 'الاسم الإنجليزي يجب أن يحتوي أحرفًا لاتينية' });
  }

  try {
    const teacher = await db.transaction(async () => {
      if (!await db.prepare('SELECT id FROM mosques WHERE id = ?').get(mosqueId)) {
        throw httpError(404, 'المسجد غير موجود');
      }
      const dup = await db
.prepare('SELECT id FROM teachers WHERE mosque_id = ? AND full_name = ?')
        .get(mosqueId, fullName);
      if (dup) throw httpError(409, 'يوجد مدرّس بهذا الاسم');

      let code = teacherCode(englishName);
      while (
        await db
          .prepare('SELECT id FROM teachers WHERE mosque_id = ? AND login_code = ?')
          .get(mosqueId, code)
      ) {
        code = teacherCode(englishName);
      }

      const row = {
        id: uuidv4(),
        mosque_id: mosqueId,
        full_name: fullName,
        english_name: englishName,
        english_prefix: englishPrefix(englishName),
        login_code: code,
        created_at: nowIso(),
      };
      await db.prepare(`
        INSERT INTO teachers
          (id, mosque_id, full_name, english_name, english_prefix, login_code, created_at)
        VALUES (@id, @mosque_id, @full_name, @english_name, @english_prefix, @login_code, @created_at)
      `).run(row);
      return row;
    });
    return res.status(201).json({ teacher });
  } catch (e) {
    return res.status(e.status || 500).json({ error: e.message });
  }
});

router.get('/teachers', async (req, res) => {
  const mosqueId = String(req.query.mosque_id || '').trim();
  const teachers = mosqueId
    ? await db.prepare('SELECT * FROM teachers WHERE mosque_id = ?').all(mosqueId)
    : await db.prepare('SELECT * FROM teachers').all();
  return res.json({ teachers });
});

router.patch('/teachers/:id', async (req, res) => {
  const id = req.params.id;
  const fullName = String(req.body.full_name || '').trim();
  const englishName = String(req.body.english_name || '').trim();
  try {
    const teacher = await db.transaction(async () => {
      const existing = await db.prepare('SELECT * FROM teachers WHERE id = ?').get(id);
      if (!existing) throw httpError(404, 'المدرّس غير موجود');
      if (!fullName) throw httpError(400, 'أدخل اسم المدرّس');
      if (!englishName || !/[A-Za-z]/.test(englishName)) {
        throw httpError(400, 'الاسم الإنجليزي يجب أن يحتوي أحرفًا لاتينية');
      }
      const dup = await db
.prepare(`
          SELECT id FROM teachers
          WHERE mosque_id = ? AND full_name = ? AND id != ?
        `)
        .get(existing.mosque_id, fullName, id);
      if (dup) throw httpError(409, 'يوجد مدرّس بهذا الاسم');

      await db.prepare(`
        UPDATE teachers
        SET full_name = ?, english_name = ?, english_prefix = ?
        WHERE id = ?
      `).run(fullName, englishName, englishPrefix(englishName), id);

      return await db.prepare('SELECT * FROM teachers WHERE id = ?').get(id);
    });
    return res.json({ teacher });
  } catch (e) {
    return res.status(e.status || 500).json({ error: e.message });
  }
});

router.delete('/teachers/:id', async (req, res) => {
  const id = req.params.id;
  await db.prepare('DELETE FROM teachers WHERE id = ?').run(id);
  return res.json({ ok: true });
});

router.post('/students', async (req, res) => {
  const mosqueId = String(req.body.mosque_id || '').trim();
  const teacherId = String(req.body.teacher_id || '').trim();
  const fullName = String(req.body.full_name || '').trim();
  const gradeLevel = String(req.body.grade_level || '').trim();
  const age = Number(req.body.age);
  const parentPhone = String(req.body.parent_phone || '').trim();

  if (!mosqueId || !teacherId) {
    return res.status(400).json({ error: 'mosque_id و teacher_id مطلوبان' });
  }
  if (!fullName) return res.status(400).json({ error: 'أدخل الاسم' });
  if (!gradeLevel) return res.status(400).json({ error: 'أدخل المرحلة' });
  if (!Number.isFinite(age) || age < 4 || age > 25) {
    return res.status(400).json({ error: 'العمر بين 4 و 25' });
  }
  if (parentPhone.length < 8) {
    return res.status(400).json({ error: 'رقم ولي الأمر غير صالح' });
  }

  try {
    const student = await db.transaction(async () => {
      const teacher = await db
.prepare('SELECT * FROM teachers WHERE id = ? AND mosque_id = ?')
        .get(teacherId, mosqueId);
      if (!teacher) throw httpError(404, 'المدرّس غير موجود في هذا المسجد');

      const takenRows = await db
        .prepare('SELECT login_username FROM students WHERE mosque_id = ?')
        .all(mosqueId);
      const taken = takenRows.map((s) => s.login_username);

      const row = {
        id: uuidv4(),
        mosque_id: mosqueId,
        teacher_id: teacherId,
        full_name: fullName,
        grade_level: gradeLevel,
        age,
        parent_phone: parentPhone,
        login_username: studentUsername(fullName, taken),
        login_code: studentCode(),
        created_at: nowIso(),
      };
      await db.prepare(`
        INSERT INTO students
          (id, mosque_id, teacher_id, full_name, grade_level, age, parent_phone,
           login_username, login_code, created_at)
        VALUES
          (@id, @mosque_id, @teacher_id, @full_name, @grade_level, @age, @parent_phone,
           @login_username, @login_code, @created_at)
      `).run(row);
      return row;
    });
    return res.status(201).json({ student });
  } catch (e) {
    return res.status(e.status || 500).json({ error: e.message });
  }
});

router.get('/students', async (req, res) => {
  const mosqueId = String(req.query.mosque_id || '').trim();
  const teacherId = String(req.query.teacher_id || '').trim();
  let sql = 'SELECT * FROM students WHERE 1=1';
  const params = [];
  if (mosqueId) {
    sql += ' AND mosque_id = ?';
    params.push(mosqueId);
  }
  if (teacherId) {
    sql += ' AND teacher_id = ?';
    params.push(teacherId);
  }
  return res.json({ students: await db.prepare(sql).all(...params) });
});

router.patch('/students/:id', async (req, res) => {
  const id = req.params.id;
  try {
    const student = await db.transaction(async () => {
      const existing = await db.prepare('SELECT * FROM students WHERE id = ?').get(id);
      if (!existing) throw httpError(404, 'الطالب غير موجود');

      const fullName = req.body.full_name != null
        ? String(req.body.full_name).trim()
        : existing.full_name;
      const gradeLevel = req.body.grade_level != null
        ? String(req.body.grade_level).trim()
        : existing.grade_level;
      const age = req.body.age != null ? Number(req.body.age) : existing.age;
      const parentPhone = req.body.parent_phone != null
        ? String(req.body.parent_phone).trim()
        : existing.parent_phone;

      if (!fullName || !gradeLevel) throw httpError(400, 'بيانات غير كاملة');
      if (!Number.isFinite(age) || age < 4 || age > 25) {
        throw httpError(400, 'العمر بين 4 و 25');
      }

      await db.prepare(`
        UPDATE students
        SET full_name = ?, grade_level = ?, age = ?, parent_phone = ?
        WHERE id = ?
      `).run(fullName, gradeLevel, age, parentPhone, id);

      return await db.prepare('SELECT * FROM students WHERE id = ?').get(id);
    });
    return res.json({ student });
  } catch (e) {
    return res.status(e.status || 500).json({ error: e.message });
  }
});

router.post('/students/:id/regenerate-code', async (req, res) => {
  const id = req.params.id;
  try {
    const student = await db.transaction(async () => {
      const existing = await db.prepare('SELECT * FROM students WHERE id = ?').get(id);
      if (!existing) throw httpError(404, 'الطالب غير موجود');
      const code = studentCode();
      await db.prepare('UPDATE students SET login_code = ? WHERE id = ?').run(code, id);
      return await db.prepare('SELECT * FROM students WHERE id = ?').get(id);
    });
    return res.json({ student, login_code: student.login_code });
  } catch (e) {
    return res.status(e.status || 500).json({ error: e.message });
  }
});

router.delete('/students/:id', async (req, res) => {
  await db.prepare('DELETE FROM students WHERE id = ?').run(req.params.id);
  return res.json({ ok: true });
});

router.post('/sessions/start', async (req, res) => {
  const mosqueId = String(req.body.mosque_id || '').trim();
  const teacherId = String(req.body.teacher_id || '').trim();
  if (!mosqueId || !teacherId) {
    return res.status(400).json({ error: 'mosque_id و teacher_id مطلوبان' });
  }
  const dateOnly = new Date().toISOString().slice(0, 10);

  const result = await db.transaction(async () => {
    let session = await db
.prepare('SELECT * FROM sessions WHERE teacher_id = ? AND session_date = ?')
      .get(teacherId, dateOnly);

    if (!session) {
      session = {
        id: uuidv4(),
        mosque_id: mosqueId,
        teacher_id: teacherId,
        session_date: dateOnly,
        status: 'active',
        started_at: nowIso(),
        ended_at: null,
      };
      await db.prepare(`
        INSERT INTO sessions
          (id, mosque_id, teacher_id, session_date, status, started_at, ended_at)
        VALUES (@id, @mosque_id, @teacher_id, @session_date, @status, @started_at, @ended_at)
      `).run(session);
    }

    const roster = await db
.prepare('SELECT * FROM students WHERE teacher_id = ?')
      .all(teacherId);
    const insertAtt = await db.prepare(`
      INSERT OR IGNORE INTO attendance
        (id, session_id, student_id, status, memorization_level, behavior_score, marked_at)
      VALUES (?, ?, ?, 'unmarked', NULL, NULL, NULL)
    `);
    for (const s of roster) {
      insertAtt.run(uuidv4(), session.id, s.id);
    }

    const attendance = await db
.prepare(`
        SELECT a.*, s.full_name AS student_name
        FROM attendance a
        LEFT JOIN students s ON s.id = a.student_id
        WHERE a.session_id = ?
      `).all(session.id);

    return { session, attendance };
  });

  return res.json(result);
});

router.get('/sessions/today', async (req, res) => {
  const teacherId = String(req.query.teacher_id || '').trim();
  if (!teacherId) return res.status(400).json({ error: 'teacher_id مطلوب' });
  const dateOnly = new Date().toISOString().slice(0, 10);
  const session = await db
.prepare('SELECT * FROM sessions WHERE teacher_id = ? AND session_date = ?')
    .get(teacherId, dateOnly);
  if (!session) return res.json({ session: null, attendance: [] });
  const attendance = await db
.prepare(`
      SELECT a.*, s.full_name AS student_name
      FROM attendance a
      LEFT JOIN students s ON s.id = a.student_id
      WHERE a.session_id = ?
    `)
    .all(session.id);
  return res.json({ session, attendance });
});

router.put('/attendance/:id', async (req, res) => {
  const id = req.params.id;
  try {
    const row = await db.transaction(async () => {
      const existing = await db.prepare('SELECT * FROM attendance WHERE id = ?').get(id);
      if (!existing) throw httpError(404, 'سجل الحضور غير موجود');

      const status = req.body.status != null ? String(req.body.status) : existing.status;
      const attending = status === 'present' || status === 'late';
      let memorization = existing.memorization_level;
      let behavior = existing.behavior_score;
      if (!attending) {
        memorization = null;
        behavior = null;
      } else {
        if (req.body.memorization_level !== undefined) {
          memorization = req.body.memorization_level;
        }
        if (req.body.behavior_score !== undefined) {
          behavior = req.body.behavior_score;
        }
      }

      await db.prepare(`
        UPDATE attendance
        SET status = ?, memorization_level = ?, behavior_score = ?, marked_at = ?
        WHERE id = ?
      `).run(status, memorization, behavior, nowIso(), id);

      return await db.prepare('SELECT * FROM attendance WHERE id = ?').get(id);
    });
    return res.json({ attendance: row });
  } catch (e) {
    return res.status(e.status || 500).json({ error: e.message });
  }
});

router.put('/homework/:studentId', async (req, res) => {
  const studentId = req.params.studentId;
  const surahNumber = Number(req.body.surah_number);
  const fromAyah = Number(req.body.from_ayah);
  const toAyah = Number(req.body.to_ayah);
  const note = String(req.body.note || '');

  if (!Number.isFinite(surahNumber) || surahNumber < 1 || surahNumber > 114) {
    return res.status(400).json({ error: 'رقم السورة غير صالح' });
  }
  if (!Number.isFinite(fromAyah) || !Number.isFinite(toAyah) || toAyah < fromAyah) {
    return res.status(400).json({ error: 'نطاق الآيات غير صالح' });
  }

  try {
    const homework = await db.transaction(async () => {
      if (!await db.prepare('SELECT id FROM students WHERE id = ?').get(studentId)) {
        throw httpError(404, 'الطالب غير موجود');
      }
      const existing = await db
.prepare('SELECT * FROM student_homework WHERE student_id = ?')
        .get(studentId);
      const row = {
        id: existing?.id || uuidv4(),
        student_id: studentId,
        surah_number: surahNumber,
        from_ayah: fromAyah,
        to_ayah: toAyah,
        note,
        assigned_at: nowIso(),
      };
      if (existing) {
        await db.prepare(`
          UPDATE student_homework
          SET surah_number = @surah_number, from_ayah = @from_ayah,
              to_ayah = @to_ayah, note = @note, assigned_at = @assigned_at
          WHERE student_id = @student_id
        `).run(row);
      } else {
        await db.prepare(`
          INSERT INTO student_homework
            (id, student_id, surah_number, from_ayah, to_ayah, note, assigned_at)
          VALUES (@id, @student_id, @surah_number, @from_ayah, @to_ayah, @note, @assigned_at)
        `).run(row);
      }
      return row;
    });
    return res.json({ homework });
  } catch (e) {
    return res.status(e.status || 500).json({ error: e.message });
  }
});

router.get('/homework/:studentId', async (req, res) => {
  const homework =
    await db
      .prepare('SELECT * FROM student_homework WHERE student_id = ?')
      .get(req.params.studentId) || null;
  return res.json({ homework });
});

router.put('/progress/:studentId', async (req, res) => {
  const studentId = req.params.studentId;
  const surahNumber = Number(req.body.surah_number);
  const ayahNumber = Number(req.body.ayah_number);
  if (!Number.isFinite(surahNumber) || !Number.isFinite(ayahNumber)) {
    return res.status(400).json({ error: 'بيانات التقدّم غير صالحة' });
  }
  try {
    const progress = await db.transaction(async () => {
      if (!await db.prepare('SELECT id FROM students WHERE id = ?').get(studentId)) {
        throw httpError(404, 'الطالب غير موجود');
      }
      const existing = await db
.prepare('SELECT * FROM progress WHERE student_id = ?')
        .get(studentId);
      const row = {
        id: existing?.id || uuidv4(),
        student_id: studentId,
        surah_number: surahNumber,
        ayah_number: ayahNumber,
        updated_at: nowIso(),
      };
      if (existing) {
        await db.prepare(`
          UPDATE progress
          SET surah_number = @surah_number, ayah_number = @ayah_number, updated_at = @updated_at
          WHERE student_id = @student_id
        `).run(row);
      } else {
        await db.prepare(`
          INSERT INTO progress (id, student_id, surah_number, ayah_number, updated_at)
          VALUES (@id, @student_id, @surah_number, @ayah_number, @updated_at)
        `).run(row);
      }
      return row;
    });
    return res.json({ progress });
  } catch (e) {
    return res.status(e.status || 500).json({ error: e.message });
  }
});

/** دفع دفعة من عمليات المزامنة من الجهاز (idempotent عبر UUID العميل) */
router.post('/sync/push', async (req, res) => {
  const ops = Array.isArray(req.body.ops) ? req.body.ops : [];
  const applied = [];
  const errors = [];

  await db.transaction(async () => {
    for (const op of ops) {
      try {
        await applyOp(op);
        applied.push(op.id || op.type);
      } catch (e) {
        errors.push({ id: op.id || null, type: op.type, error: e.message });
      }
    }
  });

  return res.json({ applied, errors, server_time: nowIso() });
});

/** سحب لقطة المسجد كاملة */
router.get('/sync/pull', async (req, res) => {
  const mosqueId = String(req.query.mosque_id || '').trim();
  if (!mosqueId) return res.status(400).json({ error: 'mosque_id مطلوب' });

  const mosque = await db.prepare('SELECT * FROM mosques WHERE id = ?').get(mosqueId);
  if (!mosque) return res.status(404).json({ error: 'المسجد غير موجود' });

  const teachers = await db
.prepare('SELECT * FROM teachers WHERE mosque_id = ?')
    .all(mosqueId);
  const students = await db
.prepare('SELECT * FROM students WHERE mosque_id = ?')
    .all(mosqueId);
  const sessions = await db
.prepare('SELECT * FROM sessions WHERE mosque_id = ?')
    .all(mosqueId);
  const attendance = await db
.prepare(`
      SELECT a.* FROM attendance a
      INNER JOIN sessions s ON s.id = a.session_id
      WHERE s.mosque_id = ?
    `)
    .all(mosqueId);
  const student_homework = await db
.prepare(`
      SELECT h.* FROM student_homework h
      INNER JOIN students st ON st.id = h.student_id
      WHERE st.mosque_id = ?
    `)
    .all(mosqueId);
  const progress = await db
.prepare(`
      SELECT p.* FROM progress p
      INNER JOIN students st ON st.id = p.student_id
      WHERE st.mosque_id = ?
    `)
    .all(mosqueId);
  const mosque_admins = await db
.prepare(`
      SELECT id, mosque_id, full_name, email, created_at
      FROM mosque_admins WHERE mosque_id = ?
    `)
    .all(mosqueId);

  return res.json({
    mosque,
    mosque_admins,
    teachers,
    students,
    sessions,
    attendance,
    student_homework,
    progress,
    server_time: nowIso(),
  });
});

async function upsertById(table, id, insertSql, updateSql, row) {
  const exists = await db.prepare(`SELECT id FROM ${table} WHERE id = ?`).get(id);
  if (exists) await updateSql.run(row);
  else await insertSql.run(row);
}

async function applyOp(op) {
  const type = op.type;
  const p = op.payload || {};

  switch (type) {
    case 'upsert_teacher': {
      const row = {
        id: p.id || uuidv4(),
        mosque_id: p.mosque_id,
        full_name: p.full_name,
        english_name: p.english_name,
        english_prefix: p.english_prefix || englishPrefix(p.english_name),
        login_code: p.login_code,
        created_at: p.created_at || nowIso(),
      };
      await upsertById(
        'teachers',
        row.id,
        await db.prepare(`
          INSERT INTO teachers
            (id, mosque_id, full_name, english_name, english_prefix, login_code, created_at)
          VALUES (@id, @mosque_id, @full_name, @english_name, @english_prefix, @login_code, @created_at)
        `),
        await db.prepare(`
          UPDATE teachers SET
            mosque_id=@mosque_id, full_name=@full_name, english_name=@english_name,
            english_prefix=@english_prefix, login_code=@login_code
          WHERE id=@id
        `),
        row,
      );
      break;
    }
    case 'delete_teacher': {
      await db.prepare('DELETE FROM teachers WHERE id = ?').run(p.id);
      break;
    }
    case 'upsert_student': {
      const row = {
        id: p.id || uuidv4(),
        mosque_id: p.mosque_id,
        teacher_id: p.teacher_id,
        full_name: p.full_name,
        grade_level: p.grade_level,
        age: p.age,
        parent_phone: p.parent_phone,
        login_username: p.login_username,
        login_code: p.login_code,
        created_at: p.created_at || nowIso(),
      };
      await upsertById(
        'students',
        row.id,
        await db.prepare(`
          INSERT INTO students
            (id, mosque_id, teacher_id, full_name, grade_level, age, parent_phone,
             login_username, login_code, created_at)
          VALUES
            (@id, @mosque_id, @teacher_id, @full_name, @grade_level, @age, @parent_phone,
             @login_username, @login_code, @created_at)
        `),
        await db.prepare(`
          UPDATE students SET
            mosque_id=@mosque_id, teacher_id=@teacher_id, full_name=@full_name,
            grade_level=@grade_level, age=@age, parent_phone=@parent_phone,
            login_username=@login_username, login_code=@login_code
          WHERE id=@id
        `),
        row,
      );
      break;
    }
    case 'delete_student': {
      await db.prepare('DELETE FROM students WHERE id = ?').run(p.id);
      break;
    }
    case 'upsert_session': {
      const row = {
        id: p.id || uuidv4(),
        mosque_id: p.mosque_id,
        teacher_id: p.teacher_id,
        session_date: p.session_date,
        status: p.status || 'active',
        started_at: p.started_at || nowIso(),
        ended_at: p.ended_at || null,
      };
      const byId = await db.prepare('SELECT id FROM sessions WHERE id = ?').get(row.id);
      const byKey = await db
.prepare('SELECT id FROM sessions WHERE teacher_id = ? AND session_date = ?')
        .get(row.teacher_id, row.session_date);
      if (byId) {
        await db.prepare(`
          UPDATE sessions SET
            mosque_id=@mosque_id, teacher_id=@teacher_id, session_date=@session_date,
            status=@status, started_at=@started_at, ended_at=@ended_at
          WHERE id=@id
        `).run(row);
      } else if (byKey) {
        row.id = byKey.id;
        await db.prepare(`
          UPDATE sessions SET
            mosque_id=@mosque_id, status=@status, started_at=@started_at, ended_at=@ended_at
          WHERE id=@id
        `).run(row);
      } else {
        await db.prepare(`
          INSERT INTO sessions
            (id, mosque_id, teacher_id, session_date, status, started_at, ended_at)
          VALUES (@id, @mosque_id, @teacher_id, @session_date, @status, @started_at, @ended_at)
        `).run(row);
      }
      break;
    }
    case 'upsert_attendance': {
      const row = {
        id: p.id || uuidv4(),
        session_id: p.session_id,
        student_id: p.student_id,
        status: p.status || 'unmarked',
        memorization_level: p.memorization_level ?? null,
        behavior_score: p.behavior_score ?? null,
        marked_at: p.marked_at || nowIso(),
      };
      const byId = await db.prepare('SELECT id FROM attendance WHERE id = ?').get(row.id);
      const byKey = await db
.prepare('SELECT id FROM attendance WHERE session_id = ? AND student_id = ?')
        .get(row.session_id, row.student_id);
      if (byId) {
        await db.prepare(`
          UPDATE attendance SET
            session_id=@session_id, student_id=@student_id, status=@status,
            memorization_level=@memorization_level, behavior_score=@behavior_score,
            marked_at=@marked_at
          WHERE id=@id
        `).run(row);
      } else if (byKey) {
        row.id = byKey.id;
        await db.prepare(`
          UPDATE attendance SET
            status=@status, memorization_level=@memorization_level,
            behavior_score=@behavior_score, marked_at=@marked_at
          WHERE id=@id
        `).run(row);
      } else {
        await db.prepare(`
          INSERT INTO attendance
            (id, session_id, student_id, status, memorization_level, behavior_score, marked_at)
          VALUES
            (@id, @session_id, @student_id, @status, @memorization_level, @behavior_score, @marked_at)
        `).run(row);
      }
      break;
    }
    case 'upsert_homework': {
      const existing = await db
.prepare('SELECT id FROM student_homework WHERE student_id = ?')
        .get(p.student_id);
      const row = {
        id: p.id || existing?.id || uuidv4(),
        student_id: p.student_id,
        surah_number: p.surah_number,
        from_ayah: p.from_ayah,
        to_ayah: p.to_ayah,
        note: p.note || '',
        assigned_at: p.assigned_at || nowIso(),
      };
      if (existing) {
        await db.prepare(`
          UPDATE student_homework SET
            surah_number=@surah_number, from_ayah=@from_ayah, to_ayah=@to_ayah,
            note=@note, assigned_at=@assigned_at
          WHERE student_id=@student_id
        `).run(row);
      } else {
        await db.prepare(`
          INSERT INTO student_homework
            (id, student_id, surah_number, from_ayah, to_ayah, note, assigned_at)
          VALUES (@id, @student_id, @surah_number, @from_ayah, @to_ayah, @note, @assigned_at)
        `).run(row);
      }
      break;
    }
    case 'upsert_progress': {
      const existing = await db
.prepare('SELECT id FROM progress WHERE student_id = ?')
        .get(p.student_id);
      const row = {
        id: p.id || existing?.id || uuidv4(),
        student_id: p.student_id,
        surah_number: p.surah_number,
        ayah_number: p.ayah_number,
        updated_at: p.updated_at || nowIso(),
      };
      if (existing) {
        await db.prepare(`
          UPDATE progress SET
            surah_number=@surah_number, ayah_number=@ayah_number, updated_at=@updated_at
          WHERE student_id=@student_id
        `).run(row);
      } else {
        await db.prepare(`
          INSERT INTO progress (id, student_id, surah_number, ayah_number, updated_at)
          VALUES (@id, @student_id, @surah_number, @ayah_number, @updated_at)
        `).run(row);
      }
      break;
    }
    case 'upsert_mosque': {
      if (!await db.prepare('SELECT id FROM mosques WHERE id = ?').get(p.id)) {
        await db.prepare(
          'INSERT INTO mosques (id, name, created_at) VALUES (?, ?, ?)',
        ).run(p.id, p.name, p.created_at || nowIso());
      } else {
        await db.prepare('UPDATE mosques SET name = ? WHERE id = ?').run(p.name, p.id);
      }
      if (p.admin) {
        const existing = await db
.prepare('SELECT * FROM mosque_admins WHERE id = ?')
          .get(p.admin.id);
        const passwordHash = p.admin.password
          ? hashPassword(p.admin.password)
          : existing?.password_hash || hashPassword('synced');
        const admin = {
          id: p.admin.id,
          mosque_id: p.id,
          full_name: p.admin.full_name,
          email: String(p.admin.email || '').toLowerCase(),
          password_hash: passwordHash,
          created_at: p.admin.created_at || nowIso(),
        };
        if (existing) {
          await db.prepare(`
            UPDATE mosque_admins SET
              mosque_id=@mosque_id, full_name=@full_name, email=@email,
              password_hash=@password_hash
            WHERE id=@id
          `).run(admin);
        } else {
          await db.prepare(`
            INSERT INTO mosque_admins
              (id, mosque_id, full_name, email, password_hash, created_at)
            VALUES (@id, @mosque_id, @full_name, @email, @password_hash, @created_at)
          `).run(admin);
        }
      }
      break;
    }
    default:
      throw new Error(`عملية غير معروفة: ${type}`);
  }
}

module.exports = router;
