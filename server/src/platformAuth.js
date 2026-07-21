const crypto = require('crypto');

const sessions = new Map(); // token -> { createdAt }

function platformPassword() {
  return String(process.env.PLATFORM_ADMIN_PASSWORD || '').trim();
}

function isPlatformConfigured() {
  return platformPassword().length >= 6;
}

function createSession() {
  const token = crypto.randomBytes(32).toString('hex');
  sessions.set(token, { createdAt: Date.now() });
  return token;
}

function revokeSession(token) {
  sessions.delete(String(token || ''));
}

function isValidSession(token) {
  if (!token) return false;
  const row = sessions.get(token);
  if (!row) return false;
  // 7 أيام
  if (Date.now() - row.createdAt > 7 * 24 * 60 * 60 * 1000) {
    sessions.delete(token);
    return false;
  }
  return true;
}

function requirePlatformAdmin(req, res, next) {
  if (!isPlatformConfigured()) {
    return res.status(503).json({
      error: 'PLATFORM_ADMIN_PASSWORD غير مضبوط على الخادم',
    });
  }
  const header = String(req.headers.authorization || '');
  const token = header.toLowerCase().startsWith('bearer ')
    ? header.slice(7).trim()
    : String(req.headers['x-platform-token'] || '').trim();
  if (!isValidSession(token)) {
    return res.status(401).json({ error: 'يلزم تسجيل دخول الإدارة' });
  }
  req.platformToken = token;
  return next();
}

module.exports = {
  platformPassword,
  isPlatformConfigured,
  createSession,
  revokeSession,
  isValidSession,
  requirePlatformAdmin,
};
