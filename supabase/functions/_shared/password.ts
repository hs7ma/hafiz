/** bcrypt verify compatible with bcryptjs hashes ($2a$ / $2b$). */
import bcrypt from "https://esm.sh/bcryptjs@2.4.3";

export function hashPassword(password: string): string {
  return bcrypt.hashSync(String(password), 10);
}

export function verifyPassword(password: string, hash: string | null | undefined): boolean {
  if (!hash) return false;
  try {
    return bcrypt.compareSync(String(password), String(hash));
  } catch {
    return false;
  }
}
