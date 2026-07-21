const { randomInt } = require('crypto');

const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

function englishPrefix(englishName) {
  const letters = String(englishName || '')
    .toUpperCase()
    .replace(/[^A-Z]/g, '');
  if (letters.length >= 2) return letters.slice(0, 2);
  if (letters.length === 1) return `${letters}X`;
  return 'XX';
}

function teacherCode(englishName) {
  const prefix = englishPrefix(englishName);
  const digits = Array.from({ length: 6 }, () => randomInt(0, 10)).join('');
  return `${prefix}${digits}`;
}

function studentCode() {
  const len = 5 + randomInt(0, 4);
  return Array.from({ length: len }, () => ALPHABET[randomInt(0, ALPHABET.length)]).join('');
}

function studentUsername(fullName, taken) {
  const base = String(fullName || '')
    .trim()
    .replace(/\s+/g, '_')
    .replace(/[^\w\u0600-\u06FF_]/g, '');
  const root = base || 'talib';
  let candidate = root;
  let n = 1;
  const lowerTaken = new Set([...taken].map((t) => String(t).toLowerCase()));
  while (lowerTaken.has(candidate.toLowerCase())) {
    candidate = `${root}_${n}`;
    n += 1;
  }
  return candidate;
}

function looksLikeEmail(email) {
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email);
}

/** كلمة مرور لمسؤول الجامع بعد الموافقة (10 أحرف). */
function mosqueAdminPassword() {
  return Array.from({ length: 10 }, () => ALPHABET[randomInt(0, ALPHABET.length)]).join('');
}

/** أرقام فقط لرابط واتساب (wa.me). */
function normalizeWhatsappDigits(phone) {
  let digits = String(phone || '').replace(/\D/g, '');
  if (!digits) return '';
  if (digits.startsWith('00')) digits = digits.slice(2);
  if (digits.startsWith('0') && digits.length >= 9) {
    digits = `966${digits.slice(1)}`;
  }
  return digits;
}

function looksLikeWhatsappPhone(phone) {
  const digits = normalizeWhatsappDigits(phone);
  return digits.length >= 10 && digits.length <= 15;
}

module.exports = {
  englishPrefix,
  teacherCode,
  studentCode,
  studentUsername,
  looksLikeEmail,
  mosqueAdminPassword,
  normalizeWhatsappDigits,
  looksLikeWhatsappPhone,
};
