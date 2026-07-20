/**
 * إعادة تهيئة قاعدة البيانات ببيانات التجربة.
 * يحذف hafiz.sqlite ثم يعيد إنشاء الجداول والبذرة عند التشغيل التالي.
 *
 * الاستخدام: npm run seed
 */
const fs = require('fs');
const path = require('path');

const dbPath = path.join(__dirname, '..', 'data', 'hafiz.sqlite');
const wal = `${dbPath}-wal`;
const shm = `${dbPath}-shm`;

for (const p of [dbPath, wal, shm]) {
  if (fs.existsSync(p)) fs.unlinkSync(p);
}

// استيراد db يشغّل migrate + seed
require('./db');
console.log('✓ أُعيدت تهيئة قاعدة البيانات مع بيانات التجربة');
console.log(`  الملف: ${dbPath}`);
console.log('');
console.log('حسابات التجربة:');
console.log('  مسؤول: مسجد النور / admin@demo.local / demo1234');
console.log('  مدرّس: الشيخ إبراهيم / IB482917');
console.log('  طالب:  ahmad_yusuf / A7K3M');
