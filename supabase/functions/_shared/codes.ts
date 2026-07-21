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

export function normalizeWhatsappDigits(phone: string): string {
  let digits = String(phone || "").replace(/\D/g, "");
  if (!digits) return "";
  if (digits.startsWith("00")) digits = digits.slice(2);
  if (digits.startsWith("0") && digits.length >= 9) {
    digits = `966${digits.slice(1)}`;
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

export function randomToken(bytes = 32): string {
  const buf = new Uint8Array(bytes);
  crypto.getRandomValues(buf);
  return Array.from(buf, (b) => b.toString(16).padStart(2, "0")).join("");
}
