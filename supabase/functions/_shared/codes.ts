const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function randomInt(max: number): number {
  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  return buf[0] % max;
}

export function englishPrefix(englishName: string): string {
  const letters = String(englishName || "")
    .toUpperCase()
    .replace(/[^A-Z]/g, "");
  if (letters.length >= 2) return letters.slice(0, 2);
  if (letters.length === 1) return `${letters}X`;
  return "XX";
}

export function teacherCode(englishName: string): string {
  const prefix = englishPrefix(englishName);
  const digits = Array.from({ length: 6 }, () => String(randomInt(10))).join("");
  return `${prefix}${digits}`;
}

export function studentCode(): string {
  const len = 5 + randomInt(4);
  return Array.from({ length: len }, () => ALPHABET[randomInt(ALPHABET.length)]).join("");
}

export function studentUsername(fullName: string, taken: string[]): string {
  const base = String(fullName || "")
    .trim()
    .replace(/\s+/g, "_")
    .replace(/[^\w\u0600-\u06FF_]/g, "");
  const root = base || "talib";
  let candidate = root;
  let n = 1;
  const lowerTaken = new Set(taken.map((t) => String(t).toLowerCase()));
  while (lowerTaken.has(candidate.toLowerCase())) {
    candidate = `${root}_${n}`;
    n += 1;
  }
  return candidate;
}

export function mosqueAdminPassword(): string {
  return Array.from({ length: 10 }, () => ALPHABET[randomInt(ALPHABET.length)]).join("");
}

/** رمز دعوة مدرّس: 12 رمزاً من أبجدية آمنة (بدون 0/O/1/I) — يُعرض كـ XXXX-XXXX-XXXX */
export function teacherInviteCode(): string {
  const raw = Array.from({ length: 12 }, () => ALPHABET[randomInt(ALPHABET.length)]).join("");
  return `${raw.slice(0, 4)}-${raw.slice(4, 8)}-${raw.slice(8, 12)}`;
}

export function normalizeInviteCode(code: string): string {
  return String(code || "")
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "");
}

export function formatInviteCode(normalized: string): string {
  const n = normalizeInviteCode(normalized);
  if (n.length !== 12) return n;
  return `${n.slice(0, 4)}-${n.slice(4, 8)}-${n.slice(8, 12)}`;
}

export async function sha256Hex(value: string): Promise<string> {
  const data = new TextEncoder().encode(String(value));
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function isUuid(value: string): boolean {
  return UUID_RE.test(String(value || "").trim());
}

/** Stable UUID for legacy ids like stu-1 (UUID v5 over URL namespace). */
export async function ensureUuid(value: string | null | undefined): Promise<string> {
  const s = String(value || "").trim();
  if (!s) return crypto.randomUUID();
  if (isUuid(s)) return s;
  const ns = "6ba7b810-9dad-11d1-80b4-00c04fd430c8"; // URL namespace
  const nsBytes = ns.replace(/-/g, "");
  const bytes = new Uint8Array(16 + new TextEncoder().encode(`hafiz-id:${s}`).length);
  for (let i = 0; i < 16; i++) bytes[i] = parseInt(nsBytes.slice(i * 2, i * 2 + 2), 16);
  const nameBytes = new TextEncoder().encode(`hafiz-id:${s}`);
  bytes.set(nameBytes, 16);
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-1", bytes.subarray(0, 16 + nameBytes.length)));
  digest[6] = (digest[6] & 0x0f) | 0x50; // version 5
  digest[8] = (digest[8] & 0x3f) | 0x80; // variant
  const hex = Array.from(digest.slice(0, 16)).map((b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}

export function sixDigitOtp(): string {
  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  return String(buf[0] % 1000000).padStart(6, "0");
}

export function randomToken(bytes = 32): string {
  const buf = new Uint8Array(bytes);
  crypto.getRandomValues(buf);
  return Array.from(buf, (b) => b.toString(16).padStart(2, "0")).join("");
}

/** رمز العراق الافتراضي لأرقام تبدأ بـ 0 (مثل 07xxxxxxxx). */
export const DEFAULT_COUNTRY_CODE = "964";


export const STUDENT_COUNT_RANGES = [
  "1-10",
  "11-25",
  "26-50",
  "51-100",
  "101-200",
  "201-500",
  "501-1000",
] as const;

export const TEACHER_COUNT_RANGES = [
  "1-5",
  "6-10",
  "11-20",
  "21-50",
  "51-100",
] as const;

export function normalizeWhatsappDigits(
  phone: string,
  countryCode: string = DEFAULT_COUNTRY_CODE,
): string {
  let digits = String(phone || "").replace(/\D/g, "");
  if (!digits) return "";
  if (digits.startsWith("00")) digits = digits.slice(2);
  if (digits.startsWith("0") && digits.length >= 9) {
    digits = `${countryCode}${digits.slice(1)}`;
  }
  // رقم عراقي محلّي بدون صفر: 7xxxxxxxx → 9647xxxxxxxx
  if (
    countryCode === "964" &&
    digits.length === 10 &&
    digits.startsWith("7") &&
    !digits.startsWith("964")
  ) {
    digits = `964${digits}`;
  }
  return digits;
}

export function looksLikeEmail(email: string): boolean {
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email);
}

export function looksLikeWhatsappPhone(phone: string): boolean {
  const digits = normalizeWhatsappDigits(phone);
  return digits.length >= 10 && digits.length <= 15;
}
