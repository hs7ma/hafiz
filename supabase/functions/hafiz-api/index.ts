import { corsHeaders, error, json, readJson, bearerToken } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";
import {
  englishPrefix,
  ensureUuid,
  looksLikeEmail,
  looksLikeWhatsappPhone,
  mosqueAdminAuthEmail,
  mosqueAdminPassword,
  mosqueAdminInitialCode,
  normalizeMosqueLoginCode,
  formatMosqueLoginCode,
  looksLikeMosqueAdminPassword,
  normalizeInviteCode,
  normalizeWhatsappDigits,
  randomToken,
  sha256Hex,
  sixDigitOtp,
  studentCode,
  studentUsername,
  STUDENT_COUNT_RANGES,
  TEACHER_COUNT_RANGES,
  teacherCode,
  teacherInviteCode,
  teacherAuthEmail,
} from "../_shared/codes.ts";
import { hashPassword, verifyPassword } from "../_shared/password.ts";
import { sendVerificationCode } from "../_shared/otp_delivery.ts";
import { createAuthUserOptional } from "../_shared/auth_admin.ts";
import { notifyUser, notifyMosqueAdmins, runNoAttendanceCheck } from "../_shared/notifications.ts";

type ActorSession = {
  token: string;
  role: "mosque_admin" | "teacher" | "student";
  actor_id: string;
  mosque_id: string;
};

type NotificationActor = {
  recipientType: "platform" | "mosque_admin" | "teacher" | "student" | "registration";
  recipientId: string;
  mosqueId: string | null;
};

async function resolveNotificationActor(
  req: Request,
  body?: Record<string, unknown>,
): Promise<NotificationActor | null> {
  const platform = await requirePlatform(req);
  if (platform) {
    return { recipientType: "platform", recipientId: "platform", mosqueId: null };
  }
  const actor = await requireActor(req);
  if (actor) {
    return {
      recipientType: actor.role,
      recipientId: actor.actor_id,
      mosqueId: actor.mosque_id,
    };
  }
  const url = new URL(req.url);
  const phone = normalizeWhatsappDigits(
    String(body?.phone || body?.recipient_id || url.searchParams.get("phone") || ""),
  );
  const recipientType = String(body?.recipient_type || url.searchParams.get("recipient_type") || "").trim();
  if (recipientType === "registration" && looksLikeWhatsappPhone(phone)) {
    return { recipientType: "registration", recipientId: phone, mosqueId: null };
  }
  return null;
}

function publicNotification(row: Record<string, unknown>) {
  return {
    id: row.id,
    type: row.type,
    priority: row.priority,
    title: row.title,
    body: row.body,
    entity_ref: row.entity_ref ?? {},
    read_at: row.read_at ?? null,
    created_at: row.created_at,
    mosque_id: row.mosque_id ?? null,
  };
}

function routePath(req: Request): string {
  const url = new URL(req.url);
  // /functions/v1/hafiz-api/<path>
  const parts = url.pathname.split("/").filter(Boolean);
  const idx = parts.indexOf("hafiz-api");
  const rest = idx >= 0 ? parts.slice(idx + 1) : [];
  return "/" + rest.join("/");
}

function publicRequest(row: Record<string, unknown>) {
  return {
    id: row.id,
    mosque_name: row.mosque_name,
    email: row.email,
    whatsapp_phone: row.whatsapp_phone,
    governorate: row.governorate ?? null,
    district: row.district ?? null,
    area: row.area ?? null,
    students_range: row.students_range ?? null,
    teachers_range: row.teachers_range ?? null,
    email_verified_at: row.email_verified_at ?? null,
    status: row.status,
    mosque_id: row.mosque_id ?? null,
    reviewed_at: row.reviewed_at ?? null,
    created_at: row.created_at,
  };
}

function statusLabelAr(status: string): string {
  if (status === "pending") return "قيد المراجعة";
  if (status === "approved") return "مقبول";
  if (status === "rejected") return "مرفوض";
  return status;
}

/** يتحقق من جلسة Supabase Auth بعد OTP البريد ويعيد البريد والمستخدم. */
async function requireVerifiedAuthEmail(
  req: Request,
): Promise<{ email: string; userId: string; emailVerifiedAt: string } | null> {
  const token = bearerToken(req);
  const anon = String(Deno.env.get("SUPABASE_ANON_KEY") || "").trim();
  if (!token || (anon && token === anon)) return null;
  const sb = serviceClient();
  const { data, error: err } = await sb.auth.getUser(token);
  if (err || !data.user?.email) return null;
  const email = data.user.email.trim().toLowerCase();
  if (!looksLikeEmail(email)) return null;
  const confirmed = data.user.email_confirmed_at || data.user.confirmed_at;
  if (!confirmed) return null;
  return {
    email,
    userId: data.user.id,
    emailVerifiedAt: String(confirmed),
  };
}

async function requirePlatform(req: Request) {
  const token = bearerToken(req);
  if (!token) return null;
  const sb = serviceClient();
  const { data } = await sb
    .from("platform_sessions")
    .select("token")
    .eq("token", token)
    .gt("expires_at", new Date().toISOString())
    .maybeSingle();
  return data ? token : null;
}

function configuredPlatformSecret(): string {
  return String(Deno.env.get("PLATFORM_ADMIN_PASSWORD") || "").trim();
}

function isValidPlatformSecret(secret: string): boolean {
  const configured = configuredPlatformSecret();
  return configured.length >= 6 && secret === configured;
}

/** مهلة سماح لإعادة إرسال نفس رمز الدخول عند انقطاع الاتصال قبل وصول الرد. */
const PLATFORM_OTP_REPLAY_WINDOW_MS = 3 * 60 * 1000;

async function loadPlatformAdminPhone(): Promise<string | null> {
  const sb = serviceClient();
  const { data } = await sb
    .from("platform_admin_config")
    .select("phone")
    .eq("id", 1)
    .maybeSingle();
  const phone = normalizeWhatsappDigits(String(data?.phone || ""));
  return looksLikeWhatsappPhone(phone) ? phone : null;
}

async function requireActor(req: Request): Promise<ActorSession | null> {
  // فضّل x-hafiz-token حتى يبقى Authorization = anon JWT لبوابة Supabase
  const token =
    (req.headers.get("x-hafiz-token") || "").trim() || bearerToken(req);
  if (!token) return null;
  const sb = serviceClient();
  const { data } = await sb
    .from("actor_sessions")
    .select("token, role, actor_id, mosque_id")
    .eq("token", token)
    .gt("expires_at", new Date().toISOString())
    .maybeSingle();
  return (data as ActorSession) || null;
}

async function createActorSession(
  role: ActorSession["role"],
  actorId: string,
  mosqueId: string,
  days = 30,
): Promise<string> {
  const token = randomToken();
  const expires = new Date(Date.now() + days * 24 * 60 * 60 * 1000).toISOString();
  const sb = serviceClient();
  const { error: err } = await sb.from("actor_sessions").insert({
    token,
    role,
    actor_id: actorId,
    mosque_id: mosqueId,
    expires_at: expires,
  });
  if (err) throw new Error(err.message || JSON.stringify(err));
  return token;
}

function mosqueLoginPasswordCandidates(raw: string): string[] {
  const trimmed = String(raw || "").trim();
  const normalized = normalizeMosqueLoginCode(trimmed);
  const out: string[] = [];
  if (trimmed) out.push(trimmed);
  if (normalized && !out.includes(normalized)) out.push(normalized);
  return out;
}

async function verifyMosqueAdminPassword(
  sb: ReturnType<typeof serviceClient>,
  admin: Record<string, unknown>,
  email: string,
  candidates: string[],
): Promise<{ ok: boolean; passwordUsed: string | null; accessToken: string | null; refreshToken: string | null }> {
  for (const password of candidates) {
    if (admin.auth_user_id) {
      const { data: signed, error: sErr } = await sb.auth.signInWithPassword({
        email,
        password,
      });
      if (!sErr && signed.session) {
        return {
          ok: true,
          passwordUsed: password,
          accessToken: signed.session.access_token,
          refreshToken: signed.session.refresh_token,
        };
      }
    }
    if (verifyPassword(password, String(admin.password_hash || ""))) {
      return { ok: true, passwordUsed: password, accessToken: null, refreshToken: null };
    }
  }
  return { ok: false, passwordUsed: null, accessToken: null, refreshToken: null };
}

const TEACHER_INVITE_TTL_MS = 3 * 60 * 60 * 1000;

async function loadTeacherInviteByToken(
  sb: ReturnType<typeof serviceClient>,
  inviteToken: string,
) {
  if (!inviteToken) return null;
  const tokenHash = await sha256Hex(inviteToken);
  const { data: invite } = await sb
    .from("teacher_invites")
    .select("*")
    .eq("registration_token_hash", tokenHash)
    .limit(1)
    .maybeSingle();
  if (!invite) return null;
  if (invite.consumed_at) return null;
  if (new Date(invite.expires_at).getTime() < Date.now()) return null;
  return invite;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const path = routePath(req);
  const method = req.method.toUpperCase();

  try {
    // Health
    if (method === "GET" && (path === "/" || path === "/health")) {
      return json({ ok: true, service: "hafiz-api", engine: "supabase-edge" });
    }

    // ---- Platform auth ----
    if (method === "GET" && path === "/platform/login/config") {
      const phone = await loadPlatformAdminPhone();
      if (!phone) {
        return error("رقم هاتف مدير المنصة غير مضبوط في قاعدة البيانات", 503);
      }
      return json({
        phone,
        display_phone: phone.startsWith("964") ? phone.slice(3) : phone,
      });
    }

    if (method === "POST" && path === "/platform/login/otp/send") {
      const body = await readJson(req);
      const secret = String(body.password || body.secret || "").trim();
      if (!isValidPlatformSecret(secret)) {
        return error("الرمز السري غير صحيح", 401);
      }

      const phone = await loadPlatformAdminPhone();
      if (!phone) {
        return error("رقم هاتف مدير المنصة غير مضبوط في قاعدة البيانات", 503);
      }

      const code = sixDigitOtp();
      const codeHash = await sha256Hex(code);
      const expiresAt = new Date(Date.now() + 15 * 60 * 1000).toISOString();
      const sb = serviceClient();
      await sb.from("platform_login_otps").delete().eq("phone", phone).is("consumed_at", null);

      const sent = await sendVerificationCode(phone, code);
      const delivery: "sms" | "manual" = sent.ok ? "sms" : "manual";

      const { error: insErr } = await sb.from("platform_login_otps").insert({
        phone,
        code_hash: codeHash,
        code_plain: delivery === "manual" ? code : null,
        delivery,
        expires_at: expiresAt,
      });
      if (insErr) return error(insErr.message, 500);

      return json({
        ok: true,
        delivery,
        phone,
        expires_at: expiresAt,
        message: delivery === "sms"
          ? "أُرسل رمز التحقق إلى هاتف مدير المنصة."
          : "تعذّر الإرسال التلقائي. استخدم الرمز المعروض أدناه.",
        ...(delivery === "manual" ? { code } : {}),
      });
    }

    if (method === "POST" && path === "/platform/login") {
      const body = await readJson(req);
      const secret = String(body.password || body.secret || "").trim();
      const code = String(body.code || body.otp || "").trim();
      if (!isValidPlatformSecret(secret)) {
        return error("الرمز السري غير صحيح", 401);
      }
      if (!/^\d{6}$/.test(code)) return error("أدخل رمز التحقق المكوّن من 6 أرقام");

      const phone = await loadPlatformAdminPhone();
      if (!phone) {
        return error("رقم هاتف مدير المنصة غير مضبوط في قاعدة البيانات", 503);
      }

      const sb = serviceClient();
      const codeHash = await sha256Hex(code);
      const { data: row } = await sb
        .from("platform_login_otps")
        .select("*")
        .eq("phone", phone)
        .eq("code_hash", codeHash)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      const invalidCode = "رمز التحقق غير صحيح أو لم يعد صالحاً — اطلب رمزاً جديداً";
      if (!row) return error(invalidCode, 401);
      if (new Date(row.expires_at).getTime() < Date.now()) {
        return error("انتهت صلاحية رمز التحقق — اطلب رمزاً جديداً", 410);
      }

      // إن انقطع الاتصال قبل وصول الرد يعيد المتصفح إرسال الطلب نفسه، فنسمح
      // بالرمز المستهلَك حديثاً حتى لا يفشل الدخول بعد نجاحه فعلياً.
      const consumedAt = row.consumed_at
        ? new Date(String(row.consumed_at)).getTime()
        : null;
      if (consumedAt !== null) {
        if (Date.now() - consumedAt > PLATFORM_OTP_REPLAY_WINDOW_MS) {
          return error(invalidCode, 401);
        }
      } else {
        await sb
          .from("platform_login_otps")
          .update({ consumed_at: new Date().toISOString(), code_plain: null })
          .eq("id", row.id);
      }

      const token = randomToken();
      const expires = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
      const { error: err } = await sb.from("platform_sessions").insert({
        token,
        expires_at: expires,
      });
      if (err) return error(err.message, 500);
      return json({
        token,
        role: "platform_admin",
        phone,
      });
    }

    if (method === "POST" && path === "/platform/logout") {
      const token = await requirePlatform(req);
      if (!token) return error("يلزم تسجيل دخول الإدارة", 401);
      const sb = serviceClient();
      await sb.from("platform_sessions").delete().eq("token", token);
      return json({ ok: true });
    }

    // ---- Registration phone OTP ----
    if (method === "POST" && path === "/registration/sms-otp/send") {
      const body = await readJson(req);
      const rawPhone = String(body.phone || body.whatsapp_phone || "").trim();
      const phone = normalizeWhatsappDigits(rawPhone);
      if (!looksLikeWhatsappPhone(rawPhone) && !looksLikeWhatsappPhone(phone)) {
        return error("رقم الهاتف غير صالح");
      }

      const code = sixDigitOtp();
      const codeHash = await sha256Hex(code);
      const expiresAt = new Date(Date.now() + 15 * 60 * 1000).toISOString();
      const sb = serviceClient();
      await sb.from("registration_sms_otps").delete().eq("phone", phone).is("consumed_at", null);

      const sent = await sendVerificationCode(phone, code);
      if (sent.errorCode === "INVALID_PHONE") {
        return error("رقم الهاتف غير صالح");
      }
      const delivery: "sms" | "manual" = sent.ok ? "sms" : "manual";

      const { error: insErr } = await sb.from("registration_sms_otps").insert({
        phone,
        code_hash: codeHash,
        code_plain: delivery === "manual" ? code : null,
        delivery,
        expires_at: expiresAt,
      });
      if (insErr) return error(insErr.message, 500);

      return json({
        ok: true,
        delivery,
        phone,
        expires_at: expiresAt,
        message: delivery === "sms"
          ? "أُرسل رمز التحقق إلى هاتفك."
          : "تعذّر الإرسال التلقائي. اطلب الرمز من إدارة منصة حافظ (يظهر لديهم لـ15 دقيقة).",
      });
    }

    if (method === "POST" && path === "/registration/sms-otp/verify") {
      const body = await readJson(req);
      const rawPhone = String(body.phone || body.whatsapp_phone || "").trim();
      const phone = normalizeWhatsappDigits(rawPhone);
      const code = String(body.code || "").trim();
      if (!looksLikeWhatsappPhone(rawPhone) && !looksLikeWhatsappPhone(phone)) {
        return error("رقم الهاتف غير صالح");
      }
      if (!/^\d{6}$/.test(code)) return error("أدخل الرمز المكوّن من 6 أرقام");

      const sb = serviceClient();
      const codeHash = await sha256Hex(code);
      const { data: row } = await sb
        .from("registration_sms_otps")
        .select("*")
        .eq("phone", phone)
        .eq("code_hash", codeHash)
        .is("consumed_at", null)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (!row) return error("رمز غير صحيح", 401);
      if (new Date(row.expires_at).getTime() < Date.now()) {
        return error("انتهت صلاحية الرمز — اطلب رمزاً جديداً", 410);
      }

      await sb
        .from("registration_sms_otps")
        .update({ consumed_at: new Date().toISOString(), code_plain: null })
        .eq("id", row.id);

      const proof = randomToken(24);
      const proofExp = new Date(Date.now() + 2 * 60 * 60 * 1000).toISOString();
      await sb.from("registration_proofs").delete().eq("phone", phone);
      const { error: pErr } = await sb.from("registration_proofs").insert({
        token: proof,
        phone,
        expires_at: proofExp,
      });
      if (pErr) return error(pErr.message, 500);

      return json({
        ok: true,
        registration_proof: proof,
        phone,
        expires_at: proofExp,
        message: "تم التحقق من الهاتف بنجاح",
      });
    }

    // ---- Registration (in-app, requires SMS-verified phone proof) ----
    if (method === "POST" && path === "/registration-requests") {
      const body = await readJson(req);
      const proofToken = String(
        body.registration_proof || req.headers.get("x-registration-proof") || "",
      ).trim();
      if (!proofToken) {
        return error("يلزم التحقق من الهاتف من داخل التطبيق أولاً", 401);
      }

      const sbProof = serviceClient();
      const { data: proof } = await sbProof
        .from("registration_proofs")
        .select("*")
        .eq("token", proofToken)
        .maybeSingle();
      if (!proof?.phone) return error("يلزم التحقق من الهاتف أولاً", 401);
      if (new Date(proof.expires_at).getTime() < Date.now()) {
        return error("انتهت جلسة التحقق — أعد إرسال الرمز", 401);
      }

      const proofPhone = normalizeWhatsappDigits(String(proof.phone));
      const mosqueName = String(body.mosque_name || "").trim();
      const rawPhone = String(body.whatsapp_phone || body.phone || "").trim();
      const whatsappPhone = normalizeWhatsappDigits(rawPhone);
      if (whatsappPhone !== proofPhone) {
        return error("رقم الهاتف لا يطابق الجلسة المتحقّق منها", 400);
      }

      const governorate = String(body.governorate || "").trim();
      const district = String(body.district || "").trim();
      const area = String(body.area || "").trim();
      const studentsRange = String(body.students_range || "").trim();
      const teachersRange = String(body.teachers_range || "").trim();

      if (!mosqueName) return error("أدخل اسم الجامع");
      if (!looksLikeWhatsappPhone(rawPhone) && !looksLikeWhatsappPhone(whatsappPhone)) {
        return error("رقم الهاتف غير صالح");
      }
      if (!governorate) return error("اختر المحافظة");
      if (!district) return error("اختر القضاء");
      if (!area) return error("أدخل المنطقة");
      if (!(STUDENT_COUNT_RANGES as readonly string[]).includes(studentsRange)) {
        return error("نطاق عدد الطلاب غير صالح");
      }
      if (!(TEACHER_COUNT_RANGES as readonly string[]).includes(teachersRange)) {
        return error("نطاق عدد المدرّسين غير صالح");
      }

      const sb = serviceClient();
      const { data: existsMosque } = await sb
        .from("mosques")
        .select("id")
        .eq("name", mosqueName)
        .maybeSingle();
      if (existsMosque) return error("يوجد مسجد بهذا الاسم مسبقًا", 409);

      const { data: existsPhoneMosque } = await sb
        .from("mosques")
        .select("id")
        .eq("whatsapp_phone", whatsappPhone)
        .maybeSingle();
      if (existsPhoneMosque) {
        return error("رقم الهاتف مستخدم مسبقًا — يمكنك الدخول مباشرة", 409);
      }

      const { data: pendingDup } = await sb
        .from("mosque_registration_requests")
        .select("id")
        .eq("status", "pending")
        .or(`whatsapp_phone.eq.${whatsappPhone},mosque_name.eq.${mosqueName}`)
        .limit(1)
        .maybeSingle();
      if (pendingDup) {
        return error("يوجد طلب قيد المراجعة لنفس الهاتف أو اسم الجامع", 409);
      }

      const verifiedAt = proof.created_at || new Date().toISOString();
      const row = {
        mosque_name: mosqueName,
        email: null,
        whatsapp_phone: whatsappPhone,
        governorate,
        district,
        area,
        students_range: studentsRange,
        teachers_range: teachersRange,
        email_verified_at: verifiedAt,
        auth_user_id: null,
        status: "pending",
      };
      const { data, error: err } = await sb
        .from("mosque_registration_requests")
        .insert(row)
        .select("*")
        .single();
      if (err) return error(err.message, 500);

      await sb.from("registration_proofs").delete().eq("token", proofToken);

      await notifyUser(sb, {
        recipientType: "platform",
        recipientId: "platform",
        type: "mosque_registration_request",
        priority: "critical",
        title: "طلب تسجيل مسجد جديد",
        body: `طلب جديد: «${mosqueName}»`,
        entityRef: { request_id: data.id, mosque_name: mosqueName },
        dedupeKey: `reg_req:${data.id}`,
        foregroundContext: "platform_requests",
      });

      return json(
        {
          request: publicRequest(data),
          message: "تم إرسال الطلب. يمكنك متابعة حالته من داخل التطبيق.",
        },
        201,
      );
    }

    // حالة طلب التسجيل بالهاتف (من داخل التطبيق)
    if (method === "GET" && path === "/registration-requests/status") {
      const url = new URL(req.url);
      const rawPhone = String(url.searchParams.get("phone") || url.searchParams.get("whatsapp_phone") || "").trim();
      const phone = normalizeWhatsappDigits(rawPhone);
      if (!looksLikeWhatsappPhone(rawPhone) && !looksLikeWhatsappPhone(phone)) {
        return error("رقم الهاتف غير صالح");
      }
      const sb = serviceClient();
      const { data, error: err } = await sb
        .from("mosque_registration_requests")
        .select("*")
        .eq("whatsapp_phone", phone)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (err) return error(err.message, 500);
      if (!data) {
        return json({
          found: false,
          message: "لا يوجد طلب تسجيل لهذا الرقم",
        });
      }
      const reqPublic = publicRequest(data);
      const loginCode =
        data.status === "approved" &&
        data.initial_login_code &&
        !data.initial_login_code_consumed_at
          ? formatMosqueLoginCode(String(data.initial_login_code))
          : null;
      return json({
        found: true,
        request: reqPublic,
        status_label: statusLabelAr(String(data.status)),
        login_code: loginCode,
        message:
          data.status === "pending"
            ? "طلبك قيد مراجعة إدارة حافظ."
            : data.status === "approved"
            ? loginCode
              ? "تمت الموافقة. رمز الدخول يظهر أدناه — استخدمه في شاشة «إدارة الجامع»."
              : "تمت الموافقة. إذا سبق لك تسجيل الدخول، استخدم كلمة المرور الجديدة. وإلا تواصل مع إدارة حافظ."
            : "تم رفض الطلب. تواصل مع إدارة حافظ إن لزم.",
      });
    }

    if (method === "GET" && path === "/registration-requests") {
      const token = await requirePlatform(req);
      if (!token) return error("يلزم تسجيل دخول الإدارة", 401);
      const url = new URL(req.url);
      const status = (url.searchParams.get("status") || "").trim();
      const sb = serviceClient();
      let q = sb.from("mosque_registration_requests").select("*").order("created_at", {
        ascending: false,
      });
      if (status === "pending" || status === "approved" || status === "rejected") {
        q = q.eq("status", status);
      }
      const { data, error: err } = await q;
      if (err) return error(err.message, 500);
      return json({ requests: (data || []).map((r) => publicRequest(r)) });
    }

    // رموز تحقق يدوية عند فشل الإرسال التلقائي (يظهر الرمز لإدارة المنصة فقط)
    if (method === "GET" && path === "/platform/manual-otps") {
      const token = await requirePlatform(req);
      if (!token) return error("يلزم تسجيل دخول الإدارة", 401);
      const sb = serviceClient();
      const now = new Date().toISOString();
      const { data: smsOtps, error: smsErr } = await sb
        .from("registration_sms_otps")
        .select("id, phone, code_plain, delivery, expires_at, created_at")
        .eq("delivery", "manual")
        .is("consumed_at", null)
        .gt("expires_at", now)
        .order("created_at", { ascending: false })
        .limit(50);
      if (smsErr) return error(smsErr.message, 500);
      const otps = (smsOtps || []).map((o) => ({ ...o, channel: "sms" as const }));
      return json({ otps });
    }

    if (method === "GET" && path === "/platform/mosques") {
      const token = await requirePlatform(req);
      if (!token) return error("يلزم تسجيل دخول الإدارة", 401);
      const sb = serviceClient();
      const { data: mosques, error: err } = await sb
        .from("mosques")
        .select("id, name, whatsapp_phone, governorate, district, area, created_at")
        .order("created_at", { ascending: false });
      if (err) return error(err.message, 500);
      const { data: admins } = await sb
        .from("mosque_admins")
        .select("id, mosque_id, full_name, email, auth_user_id");
      const { data: teachers } = await sb.from("teachers").select("id, mosque_id");
      const { data: students } = await sb.from("students").select("id, mosque_id");
      const byMosque = new Map((admins || []).map((a) => [a.mosque_id, a]));
      const teacherCounts = new Map<string, number>();
      for (const t of teachers || []) {
        const mid = String(t.mosque_id);
        teacherCounts.set(mid, (teacherCounts.get(mid) || 0) + 1);
      }
      const studentCounts = new Map<string, number>();
      for (const s of students || []) {
        const mid = String(s.mosque_id);
        studentCounts.set(mid, (studentCounts.get(mid) || 0) + 1);
      }
      return json({
        mosques: (mosques || []).map((m) => {
          const a = byMosque.get(m.id);
          return {
            id: m.id,
            name: m.name,
            whatsapp_phone: m.whatsapp_phone || null,
            governorate: m.governorate ?? null,
            district: m.district ?? null,
            area: m.area ?? null,
            created_at: m.created_at,
            teachers_count: teacherCounts.get(String(m.id)) || 0,
            students_count: studentCounts.get(String(m.id)) || 0,
            admin: a
              ? { id: a.id, full_name: a.full_name, email: a.email }
              : null,
          };
        }),
      });
    }

    const deleteMosqueMatch = path.match(/^\/platform\/mosques\/([^/]+)$/);
    if (method === "DELETE" && deleteMosqueMatch) {
      const token = await requirePlatform(req);
      if (!token) return error("يلزم تسجيل دخول الإدارة", 401);
      const mosqueId = deleteMosqueMatch[1];
      const sb = serviceClient();

      const { data: mosque } = await sb
        .from("mosques")
        .select("id, name")
        .eq("id", mosqueId)
        .maybeSingle();
      if (!mosque) return error("المسجد غير موجود", 404);

      const { data: admins } = await sb
        .from("mosque_admins")
        .select("id, auth_user_id")
        .eq("mosque_id", mosqueId);
      const { data: teachers } = await sb
        .from("teachers")
        .select("id, auth_user_id")
        .eq("mosque_id", mosqueId);

      const authUserIds = new Set<string>();
      for (const a of admins || []) {
        if (a.auth_user_id) authUserIds.add(String(a.auth_user_id));
      }
      for (const t of teachers || []) {
        if (t.auth_user_id) authUserIds.add(String(t.auth_user_id));
      }
      for (const uid of authUserIds) {
        try {
          await sb.auth.admin.deleteUser(uid);
        } catch {
          /* ignore missing auth users */
        }
      }

      await sb.from("actor_sessions").delete().eq("mosque_id", mosqueId);

      const { error: delErr } = await sb.from("mosques").delete().eq("id", mosqueId);
      if (delErr) return error(delErr.message, 500);

      return json({
        ok: true,
        deleted_mosque_id: mosqueId,
        deleted_mosque_name: mosque.name,
        message: `تم حذف «${mosque.name}» وجميع بياناته.`,
      });
    }

    // Approve registration
    const approveMatch = path.match(/^\/registration-requests\/([^/]+)\/approve$/);
    if (method === "POST" && approveMatch) {
      const token = await requirePlatform(req);
      if (!token) return error("يلزم تسجيل دخول الإدارة", 401);
      const id = approveMatch[1];
      const sb = serviceClient();

      const { data: request, error: rErr } = await sb
        .from("mosque_registration_requests")
        .select("*")
        .eq("id", id)
        .maybeSingle();
      if (rErr) return error(rErr.message, 500);
      if (!request) return error("الطلب غير موجود", 404);
      if (request.status !== "pending") return error("تمت معالجة هذا الطلب مسبقًا", 409);

      const { data: existsMosque } = await sb
        .from("mosques")
        .select("id")
        .eq("name", request.mosque_name)
        .maybeSingle();
      if (existsMosque) return error("يوجد مسجد بهذا الاسم مسبقًا", 409);

      const { data: existsEmail } = await sb
        .from("mosque_admins")
        .select("id")
        .eq("email", mosqueAdminAuthEmail(request.whatsapp_phone))
        .maybeSingle();
      if (existsEmail) return error("رقم الهاتف مستخدم مسبقًا", 409);

      const codeNormalized = normalizeMosqueLoginCode(mosqueAdminInitialCode());
      const displayCode = formatMosqueLoginCode(codeNormalized);
      const plainPassword = codeNormalized;
      const authEmail = mosqueAdminAuthEmail(request.whatsapp_phone);
      const mosqueId = crypto.randomUUID();
      const adminId = crypto.randomUUID();
      const now = new Date().toISOString();

      const { error: mErr } = await sb.from("mosques").insert({
        id: mosqueId,
        name: request.mosque_name,
        whatsapp_phone: request.whatsapp_phone,
        governorate: request.governorate ?? null,
        district: request.district ?? null,
        area: request.area ?? null,
        students_range: request.students_range ?? null,
        teachers_range: request.teachers_range ?? null,
        created_at: now,
      });
      if (mErr) return error(mErr.message, 500);

      let authUserId = request.auth_user_id ? String(request.auth_user_id) : "";
      if (authUserId) {
        const { error: updErr } = await sb.auth.admin.updateUserById(authUserId, {
          password: plainPassword,
          email_confirm: true,
          app_metadata: {
            role: "mosque_admin",
            mosque_id: mosqueId,
            admin_id: adminId,
          },
          user_metadata: {
            full_name: `مسؤول ${request.mosque_name}`,
          },
        });
        if (updErr) {
          await sb.from("mosques").delete().eq("id", mosqueId);
          return error(updErr.message || "تعذّر تحديث حساب الدخول", 500);
        }
      } else {
        const authResult = await createAuthUserOptional(sb, {
          email: authEmail,
          password: plainPassword,
          email_confirm: true,
          app_metadata: {
            role: "mosque_admin",
            mosque_id: mosqueId,
            admin_id: adminId,
          },
          user_metadata: {
            full_name: `مسؤول ${request.mosque_name}`,
          },
        });
        if (authResult.duplicate) {
          const listed = await sb.auth.admin.listUsers({ page: 1, perPage: 1000 });
          const found = (listed.data?.users || []).find(
            (u) => (u.email || "").toLowerCase() === authEmail.toLowerCase(),
          );
          if (found) {
            authUserId = found.id;
            const { error: updErr } = await sb.auth.admin.updateUserById(authUserId, {
              password: plainPassword,
              email_confirm: true,
              app_metadata: {
                role: "mosque_admin",
                mosque_id: mosqueId,
                admin_id: adminId,
              },
              user_metadata: {
                full_name: `مسؤول ${request.mosque_name}`,
              },
            });
            if (updErr && !/JWT|kid|ES256|unverifiable/i.test(String(updErr.message || ""))) {
              await sb.from("mosques").delete().eq("id", mosqueId);
              return error(updErr.message || "تعذّر تحديث حساب الدخول", 500);
            }
          }
        } else if (authResult.error) {
          await sb.from("mosques").delete().eq("id", mosqueId);
          return error(authResult.error, 500);
        } else if (authResult.userId) {
          authUserId = authResult.userId;
        }
      }

      const { error: aErr } = await sb.from("mosque_admins").insert({
        id: adminId,
        mosque_id: mosqueId,
        full_name: `مسؤول ${request.mosque_name}`,
        email: authEmail,
        password_hash: hashPassword(plainPassword),
        auth_user_id: authUserId || null,
        created_at: now,
      });
      if (aErr) {
        await sb.from("mosques").delete().eq("id", mosqueId);
        return error(aErr.message, 500);
      }

      const reviewedAt = now;
      await sb
        .from("mosque_registration_requests")
        .update({
          status: "approved",
          mosque_id: mosqueId,
          reviewed_at: reviewedAt,
          initial_login_code: displayCode,
          initial_login_code_consumed_at: null,
        })
        .eq("id", id);

      const mosque = {
        id: mosqueId,
        name: request.mosque_name,
        whatsapp_phone: request.whatsapp_phone,
        governorate: request.governorate ?? null,
        district: request.district ?? null,
        area: request.area ?? null,
        students_range: request.students_range ?? null,
        teachers_range: request.teachers_range ?? null,
        created_at: now,
      };
      const admin = {
        id: adminId,
        full_name: `مسؤول ${request.mosque_name}`,
        email: authEmail,
        mosque_id: mosqueId,
      };
      const waDigits = normalizeWhatsappDigits(request.whatsapp_phone);
      const smsResult = await sendVerificationCode(waDigits, displayCode);
      const message = [
        "السلام عليكم،",
        `تم اعتماد تسجيل «${mosque.name}» في تطبيق حافظ.`,
        "",
        "بيانات الدخول لإدارة الجامع:",
        `اسم المسجد: ${mosque.name}`,
        `رقم الهاتف: +${waDigits}`,
        `رمز الدخول: ${displayCode}`,
        "",
        "ادخل عبر شاشة «إدارة الجامع» في التطبيق.",
        "أو اعرض الرمز من «حالة طلب التسجيل» في التطبيق.",
        "يمكنك تغيير رمز الدخول بعد تسجيل الدخول.",
      ].join("\n");
      const whatsappUrl = `https://wa.me/${waDigits}?text=${encodeURIComponent(message)}`;

      if (!smsResult.ok) {
        await notifyUser(sb, {
          recipientType: "platform",
          recipientId: "platform",
          type: "registration_sms_failed",
          priority: "critical",
          title: "فشل إرسال رمز الدخول بعد الاعتماد",
          body: `تعذّر إرسال رمز الدخول لـ «${request.mosque_name}».`,
          entityRef: { request_id: id, mosque_id: mosqueId, whatsapp_url: whatsappUrl },
          dedupeKey: `reg_sms_fail:${id}`,
        });
      }

      const approvedBody = smsResult.ok
        ? `تم اعتماد «${request.mosque_name}». افتح التطبيق لإكمال الإعداد — أُرسل رمز الدخول إلى هاتفك.`
        : `تم اعتماد «${request.mosque_name}». افتح التطبيق لعرض رمز الدخول من «حالة طلب التسجيل».`;

      await notifyUser(sb, {
        recipientType: "mosque_admin",
        recipientId: adminId,
        mosqueId,
        type: "mosque_registration_approved",
        priority: "critical",
        title: "تم اعتماد تسجيل المسجد",
        body: approvedBody,
        entityRef: { mosque_id: mosqueId, request_id: id },
        foregroundContext: "registration_status",
      });
      await notifyUser(sb, {
        recipientType: "registration",
        recipientId: waDigits,
        type: "mosque_registration_approved",
        priority: "critical",
        title: "تم اعتماد تسجيل المسجد",
        body: approvedBody,
        entityRef: { mosque_id: mosqueId, request_id: id },
        dedupeKey: `reg_approved:${id}`,
        foregroundContext: "registration_status",
      });

      return json({
        request: publicRequest({
          ...request,
          status: "approved",
          mosque_id: mosqueId,
          reviewed_at: reviewedAt,
        }),
        mosque,
        admin,
        generated_password: displayCode,
        sms_sent: smsResult.ok,
        sms_error: smsResult.ok ? null : smsResult.error,
        whatsapp_url: whatsappUrl,
      });
    }

    const rejectMatch = path.match(/^\/registration-requests\/([^/]+)\/reject$/);
    if (method === "POST" && rejectMatch) {
      const token = await requirePlatform(req);
      if (!token) return error("يلزم تسجيل دخول الإدارة", 401);
      const id = rejectMatch[1];
      const sb = serviceClient();
      const { data: request } = await sb
        .from("mosque_registration_requests")
        .select("*")
        .eq("id", id)
        .maybeSingle();
      if (!request) return error("الطلب غير موجود", 404);
      if (request.status !== "pending") return error("تمت معالجة هذا الطلب مسبقًا", 409);
      const reviewedAt = new Date().toISOString();
      await sb
        .from("mosque_registration_requests")
        .update({ status: "rejected", reviewed_at: reviewedAt })
        .eq("id", id);

      const waDigits = normalizeWhatsappDigits(String(request.whatsapp_phone || ""));
      await notifyUser(sb, {
        recipientType: "registration",
        recipientId: waDigits,
        type: "mosque_registration_rejected",
        priority: "critical",
        title: "تم رفض طلب التسجيل",
        body: `لم يُقبل طلب «${request.mosque_name}». راجع حالة الطلب في التطبيق.`,
        entityRef: { request_id: id, mosque_name: request.mosque_name },
        dedupeKey: `reg_rejected:${id}`,
        foregroundContext: "registration_status",
      });

      return json({
        request: publicRequest({ ...request, status: "rejected", reviewed_at: reviewedAt }),
      });
    }

    // ---- Auth logins ----
    if (method === "POST" && path === "/auth/login") {
      const body = await readJson(req);
      const mosqueName = String(body.mosque_name || "").trim();
      const rawPhone = String(body.phone || body.whatsapp_phone || "").trim();
      const phone = normalizeWhatsappDigits(rawPhone);
      const passwordCandidates = mosqueLoginPasswordCandidates(String(body.password || ""));
      const sb = serviceClient();

      if (!looksLikeWhatsappPhone(rawPhone) && !looksLikeWhatsappPhone(phone)) {
        return error("رقم الهاتف غير صالح", 400);
      }

      const { data: mosque } = await sb
        .from("mosques")
        .select("*")
        .eq("name", mosqueName)
        .maybeSingle();
      if (!mosque || normalizeWhatsappDigits(String(mosque.whatsapp_phone || "")) !== phone) {
        return error("بيانات الدخول غير صحيحة", 401);
      }

      const { data: admin } = await sb
        .from("mosque_admins")
        .select("*")
        .eq("mosque_id", mosque.id)
        .maybeSingle();
      if (!admin) return error("بيانات الدخول غير صحيحة", 401);

      const email = String(admin.email || mosqueAdminAuthEmail(phone)).toLowerCase();

      const verified = await verifyMosqueAdminPassword(sb, admin, email, passwordCandidates);
      if (!verified.ok || !verified.passwordUsed) {
        return error("بيانات الدخول غير صحيحة", 401);
      }

      let accessToken = verified.accessToken;
      let refreshToken = verified.refreshToken;
      const password = verified.passwordUsed;

      // Legacy admins without Auth: create Auth user on first successful login
      if (!admin.auth_user_id) {
        const { data: created, error: cErr } = await sb.auth.admin.createUser({
          email,
          password,
          email_confirm: true,
          app_metadata: {
            role: "mosque_admin",
            mosque_id: admin.mosque_id,
            admin_id: admin.id,
          },
          user_metadata: { full_name: admin.full_name },
        });
        if (!cErr && created.user) {
          await sb
            .from("mosque_admins")
            .update({ auth_user_id: created.user.id })
            .eq("id", admin.id);
          const { data: signed } = await sb.auth.signInWithPassword({ email, password });
          accessToken = signed.session?.access_token ?? null;
          refreshToken = signed.session?.refresh_token ?? null;
        }
      }

      const sessionToken = await createActorSession(
        "mosque_admin",
        admin.id,
        admin.mosque_id,
      );

      await sb
        .from("mosque_registration_requests")
        .update({
          initial_login_code: null,
          initial_login_code_consumed_at: new Date().toISOString(),
        })
        .eq("whatsapp_phone", phone)
        .eq("status", "approved")
        .not("initial_login_code", "is", null);

      return json({
        user: {
          id: admin.id,
          full_name: admin.full_name,
          email: admin.email,
          mosque_id: admin.mosque_id,
          role: "mosque_admin",
          mosque_name: mosque.name,
        },
        mosque,
        hafiz_token: sessionToken,
        access_token: accessToken,
        refresh_token: refreshToken,
      });
    }

    // تغيير كلمة مرور مسؤول الجامع
    if (method === "POST" && path === "/auth/change-password") {
      const actor = await requireActor(req);
      if (!actor || actor.role !== "mosque_admin") {
        return error("يلزم تسجيل دخول إدارة الجامع", 401);
      }
      const body = await readJson(req);
      const currentCandidates = mosqueLoginPasswordCandidates(String(body.current_password || ""));
      const newPassword = String(body.new_password || "").trim();
      if (!looksLikeMosqueAdminPassword(newPassword)) {
        return error("كلمة المرور الجديدة: 8 أحرف على الأقل وتتضمن حرفاً ورقماً");
      }
      if (currentCandidates.some((c) => c === newPassword || c === normalizeMosqueLoginCode(newPassword))) {
        return error("كلمة المرور الجديدة مطابقة للحالية");
      }

      const sb = serviceClient();
      const { data: admin } = await sb
        .from("mosque_admins")
        .select("*")
        .eq("id", actor.actor_id)
        .maybeSingle();
      if (!admin) return error("الحساب غير موجود", 404);

      const email = String(admin.email || "").toLowerCase();
      const verifiedCurrent = await verifyMosqueAdminPassword(sb, admin, email, currentCandidates);
      if (!verifiedCurrent.ok) return error("كلمة المرور الحالية غير صحيحة", 401);

      const { error: hashErr } = await sb
        .from("mosque_admins")
        .update({ password_hash: hashPassword(newPassword) })
        .eq("id", admin.id);
      if (hashErr) return error(hashErr.message, 500);

      if (admin.auth_user_id) {
        const { error: updErr } = await sb.auth.admin.updateUserById(admin.auth_user_id, {
          password: newPassword,
        });
        if (updErr) return error(updErr.message || "تعذّر تحديث كلمة المرور", 500);
      }

      return json({ ok: true, message: "تم تغيير كلمة المرور بنجاح" });
    }

    if (method === "POST" && path === "/auth/teacher-login") {
      const body = await readJson(req);
      const password = String(body.password || "");
      const fullName = String(body.full_name || "").trim();
      const code = String(body.login_code || "").trim().toUpperCase();
      const sb = serviceClient();

      // المسار الجديد: هاتف + كلمة مرور
      const rawPhone = String(body.phone || body.whatsapp_phone || "").trim();
      const phone = normalizeWhatsappDigits(rawPhone);
      if (rawPhone && password && !String(body.email || "").trim()) {
        if (!looksLikeWhatsappPhone(rawPhone) && !looksLikeWhatsappPhone(phone)) {
          return error("رقم الهاتف غير صالح", 400);
        }
        const { data: teacher } = await sb
          .from("teachers")
          .select("*")
          .eq("whatsapp_phone", phone)
          .limit(1)
          .maybeSingle();
        if (!teacher) return error("بيانات الدخول غير صحيحة", 401);

        const authEmail = String(teacher.email || teacherAuthEmail(phone)).toLowerCase();
        let ok = false;
        if (teacher.auth_user_id) {
          const { data: signed, error: sErr } = await sb.auth.signInWithPassword({
            email: authEmail,
            password,
          });
          ok = !sErr && !!signed.session;
        }
        if (!ok) ok = verifyPassword(password, teacher.password_hash);
        if (!ok) return error("بيانات الدخول غير صحيحة", 401);

        const { data: mosque } = await sb
          .from("mosques")
          .select("*")
          .eq("id", teacher.mosque_id)
          .maybeSingle();
        const sessionToken = await createActorSession(
          "teacher",
          teacher.id,
          teacher.mosque_id,
        );
        return json({
          user: {
            id: teacher.id,
            full_name: teacher.full_name,
            role: "teacher",
            mosque_id: teacher.mosque_id,
            email: teacher.email || authEmail,
            mosque_name: mosque?.name || null,
          },
          teacher,
          mosque,
          hafiz_token: sessionToken,
        });
      }

      // مسار قديم: بريد + كلمة مرور
      const email = String(body.email || "").trim().toLowerCase();
      if (email && password) {
        const { data: teacher } = await sb
          .from("teachers")
          .select("*")
          .ilike("email", email)
          .limit(1)
          .maybeSingle();
        if (!teacher) return error("بيانات الدخول غير صحيحة", 401);

        let ok = false;
        if (teacher.auth_user_id) {
          const { data: signed, error: sErr } = await sb.auth.signInWithPassword({
            email,
            password,
          });
          ok = !sErr && !!signed.session;
        }
        if (!ok) ok = verifyPassword(password, teacher.password_hash);
        if (!ok) return error("بيانات الدخول غير صحيحة", 401);

        const { data: mosque } = await sb
          .from("mosques")
          .select("*")
          .eq("id", teacher.mosque_id)
          .maybeSingle();
        const sessionToken = await createActorSession(
          "teacher",
          teacher.id,
          teacher.mosque_id,
        );
        return json({
          user: {
            id: teacher.id,
            full_name: teacher.full_name,
            role: "teacher",
            mosque_id: teacher.mosque_id,
            email: teacher.email || email,
            mosque_name: mosque?.name || null,
          },
          teacher,
          mosque,
          hafiz_token: sessionToken,
        });
      }

      // مسار قديم (تجريبي/قديم): اسم + رمز دائم
      if (!fullName || !code) {
        return error("أدخل الهاتف وكلمة المرور، أو الاسم ورمز الدخول");
      }
      const { data: teacher } = await sb
        .from("teachers")
        .select("*")
        .eq("full_name", fullName)
        .ilike("login_code", code)
        .limit(1)
        .maybeSingle();
      if (!teacher) return error("اسم المدرّس أو الرمز غير صحيح", 401);
      const { data: mosque } = await sb
        .from("mosques")
        .select("*")
        .eq("id", teacher.mosque_id)
        .maybeSingle();
      const sessionToken = await createActorSession("teacher", teacher.id, teacher.mosque_id);
      return json({
        user: {
          id: teacher.id,
          full_name: teacher.full_name,
          role: "teacher",
          mosque_id: teacher.mosque_id,
          email: teacher.email || "",
          mosque_name: mosque?.name || null,
        },
        teacher,
        mosque,
        hafiz_token: sessionToken,
      });
    }

    // ---- Teacher invites (secure short-lived) ----
    if (method === "POST" && path === "/teachers/invites") {
      const actor = await requireActor(req);
      if (!actor || actor.role !== "mosque_admin") {
        return error("يلزم تسجيل دخول إدارة الجامع", 401);
      }
      const sb = serviceClient();
      const plainCode = teacherInviteCode();
      const codeHash = await sha256Hex(normalizeInviteCode(plainCode));
      const expiresAt = new Date(Date.now() + TEACHER_INVITE_TTL_MS).toISOString();
      const id = crypto.randomUUID();
      const { data: mosque } = await sb
        .from("mosques")
        .select("id, name")
        .eq("id", actor.mosque_id)
        .maybeSingle();
      if (!mosque) return error("المسجد غير موجود", 404);

      const { error: err } = await sb.from("teacher_invites").insert({
        id,
        mosque_id: actor.mosque_id,
        code_hash: codeHash,
        expires_at: expiresAt,
        created_by_admin_id: actor.actor_id,
      });
      if (err) return error(err.message, 500);

      return json({
        invite: {
          id,
          code: plainCode,
          expires_at: expiresAt,
          mosque: { id: mosque.id, name: mosque.name },
        },
        message: "شارك الرمز مع المدرّس خلال 3 ساعات. يُستخدم مرة واحدة فقط.",
      }, 201);
    }

    if (method === "POST" && path === "/teachers/invites/verify") {
      const body = await readJson(req);
      const normalized = normalizeInviteCode(String(body.code || ""));
      if (normalized.length !== 12) return error("رمز الدعوة غير مكتمل");

      const sb = serviceClient();
      const codeHash = await sha256Hex(normalized);
      const { data: invite } = await sb
        .from("teacher_invites")
        .select("*")
        .eq("code_hash", codeHash)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (!invite) return error("رمز الدعوة غير صحيح", 404);
      if (invite.consumed_at) return error("تم استخدام هذا الرمز مسبقاً", 409);
      if (invite.failed_attempts >= 5) {
        return error("تم قفل الرمز بسبب محاولات فاشلة كثيرة", 429);
      }
      if (new Date(invite.expires_at).getTime() < Date.now()) {
        await sb
          .from("teacher_invites")
          .update({ failed_attempts: (invite.failed_attempts || 0) + 1 })
          .eq("id", invite.id);
        return error("انتهت صلاحية الرمز — اطلب رمزاً جديداً من إدارة المسجد", 410);
      }

      const { data: mosque } = await sb
        .from("mosques")
        .select("id, name")
        .eq("id", invite.mosque_id)
        .maybeSingle();
      if (!mosque) return error("المسجد غير موجود", 404);

      const registrationToken = randomToken(24);
      const registrationTokenHash = await sha256Hex(registrationToken);
      await sb
        .from("teacher_invites")
        .update({
          registration_token_hash: registrationTokenHash,
          failed_attempts: 0,
        })
        .eq("id", invite.id);

      return json({
        invite_token: registrationToken,
        invite_id: invite.id,
        expires_at: invite.expires_at,
        mosque: { id: mosque.id, name: mosque.name },
        message: `أنت بصدد التسجيل كمدرّس لصالح «${mosque.name}»`,
      });
    }

    if (method === "POST" && path === "/teachers/sms-otp/send") {
      const body = await readJson(req);
      const inviteToken = String(body.invite_token || "").trim();
      const rawPhone = String(body.phone || body.whatsapp_phone || "").trim();
      const phone = normalizeWhatsappDigits(rawPhone);
      if (!inviteToken) return error("رمز الجلسة مفقود — أعد إدخال رمز الدعوة");
      if (!looksLikeWhatsappPhone(rawPhone) && !looksLikeWhatsappPhone(phone)) {
        return error("رقم الهاتف غير صالح");
      }

      const sb = serviceClient();
      const invite = await loadTeacherInviteByToken(sb, inviteToken);
      if (!invite) return error("جلسة التسجيل غير صالحة — أعد إدخال رمز الدعوة", 401);

      const code = sixDigitOtp();
      const codeHash = await sha256Hex(code);
      const expiresAt = new Date(Date.now() + 15 * 60 * 1000).toISOString();
      await sb
        .from("teacher_registration_sms_otps")
        .delete()
        .eq("invite_id", invite.id)
        .is("consumed_at", null);

      let delivery: "sms" | "manual" = "sms";
      const sent = await sendVerificationCode(phone, code);
      if (!sent.ok) delivery = "manual";
      if (sent.errorCode === "INVALID_PHONE") {
        return error("رقم الهاتف غير صالح");
      }

      const { error: insErr } = await sb.from("teacher_registration_sms_otps").insert({
        invite_id: invite.id,
        phone,
        code_hash: codeHash,
        code_plain: delivery === "manual" ? code : null,
        delivery,
        expires_at: expiresAt,
      });
      if (insErr) return error(insErr.message, 500);

      await sb
        .from("teacher_invites")
        .update({ verified_phone: null, phone_verified_at: null })
        .eq("id", invite.id);

      return json({
        ok: true,
        delivery,
        phone,
        expires_at: expiresAt,
        message: delivery === "sms"
          ? "أُرسل رمز التحقق إلى هاتفك."
          : "تعذّر الإرسال التلقائي. اطلب الرمز من إدارة منصة حافظ.",
        ...(delivery === "manual" ? { code } : {}),
      });
    }

    if (method === "POST" && path === "/teachers/sms-otp/verify") {
      const body = await readJson(req);
      const inviteToken = String(body.invite_token || "").trim();
      const rawPhone = String(body.phone || body.whatsapp_phone || "").trim();
      const phone = normalizeWhatsappDigits(rawPhone);
      const code = String(body.code || "").trim();
      if (!inviteToken) return error("رمز الجلسة مفقود — أعد إدخال رمز الدعوة");
      if (!looksLikeWhatsappPhone(rawPhone) && !looksLikeWhatsappPhone(phone)) {
        return error("رقم الهاتف غير صالح");
      }
      if (!/^\d{6}$/.test(code)) return error("أدخل الرمز المكوّن من 6 أرقام");

      const sb = serviceClient();
      const invite = await loadTeacherInviteByToken(sb, inviteToken);
      if (!invite) return error("جلسة التسجيل غير صالحة — أعد إدخال رمز الدعوة", 401);

      const codeHash = await sha256Hex(code);
      const { data: row } = await sb
        .from("teacher_registration_sms_otps")
        .select("*")
        .eq("invite_id", invite.id)
        .eq("phone", phone)
        .eq("code_hash", codeHash)
        .is("consumed_at", null)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (!row) return error("رمز غير صحيح", 401);
      if (new Date(row.expires_at).getTime() < Date.now()) {
        return error("انتهت صلاحية الرمز — اطلب رمزاً جديداً", 410);
      }

      await sb
        .from("teacher_registration_sms_otps")
        .update({ consumed_at: new Date().toISOString(), code_plain: null })
        .eq("id", row.id);
      await sb
        .from("teacher_invites")
        .update({
          verified_phone: phone,
          phone_verified_at: new Date().toISOString(),
        })
        .eq("id", invite.id);

      return json({ ok: true, phone, message: "تم التحقق من رقم الهاتف." });
    }

    if (method === "POST" && path === "/teachers/register") {
      const body = await readJson(req);
      const inviteToken = String(body.invite_token || "").trim();
      const fullName = String(body.full_name || "").trim();
      const password = String(body.password || "");
      const rawPhone = String(body.whatsapp_phone || body.phone || "").trim();
      const whatsappPhone = normalizeWhatsappDigits(rawPhone);

      if (!inviteToken) return error("رمز الجلسة مفقود — أعد إدخال رمز الدعوة");
      if (!fullName) return error("أدخل الاسم الكامل");
      if (password.length < 6) return error("كلمة المرور يجب أن تكون 6 أحرف على الأقل");
      if (!looksLikeWhatsappPhone(rawPhone) && !looksLikeWhatsappPhone(whatsappPhone)) {
        return error("رقم الهاتف غير صالح");
      }

      const sb = serviceClient();
      const invite = await loadTeacherInviteByToken(sb, inviteToken);
      if (!invite) return error("جلسة التسجيل غير صالحة — أعد إدخال رمز الدعوة", 401);

      if (
        !invite.phone_verified_at ||
        normalizeWhatsappDigits(String(invite.verified_phone || "")) !== whatsappPhone
      ) {
        return error("يلزم التحقق من رقم الهاتف أولاً", 403);
      }

      const { data: phoneTaken } = await sb
        .from("teachers")
        .select("id")
        .eq("whatsapp_phone", whatsappPhone)
        .limit(1)
        .maybeSingle();
      if (phoneTaken) return error("رقم الهاتف مستخدم مسبقاً", 409);

      const { data: nameTaken } = await sb
        .from("teachers")
        .select("id")
        .eq("mosque_id", invite.mosque_id)
        .eq("full_name", fullName)
        .maybeSingle();
      if (nameTaken) return error("يوجد مدرّس بهذا الاسم في المسجد", 409);

      const authEmail = teacherAuthEmail(whatsappPhone);
      const teacherId = crypto.randomUUID();
      const now = new Date().toISOString();
      const legacyCode = teacherCode(fullName);
      const prefix = englishPrefix(fullName);

      const authResult = await createAuthUserOptional(sb, {
        email: authEmail,
        password,
        email_confirm: true,
        app_metadata: {
          role: "teacher",
          mosque_id: invite.mosque_id,
          teacher_id: teacherId,
        },
        user_metadata: { full_name: fullName },
      });
      if (authResult.duplicate) {
        return error("رقم الهاتف مسجّل في نظام الدخول مسبقاً", 409);
      }
      if (authResult.error) {
        return error(authResult.error, 500);
      }

      const { error: tErr } = await sb.from("teachers").insert({
        id: teacherId,
        mosque_id: invite.mosque_id,
        full_name: fullName,
        english_name: fullName,
        english_prefix: prefix,
        login_code: legacyCode,
        email: authEmail,
        password_hash: hashPassword(password),
        auth_user_id: authResult.userId,
        whatsapp_phone: whatsappPhone,
        created_at: now,
      });
      if (tErr) {
        if (authResult.userId) {
          await sb.auth.admin.deleteUser(authResult.userId);
        }
        return error(tErr.message, 500);
      }

      await sb
        .from("teacher_invites")
        .update({
          consumed_at: now,
          registration_token_hash: null,
          verified_phone: null,
          phone_verified_at: null,
        })
        .eq("id", invite.id);

      await notifyMosqueAdmins(sb, String(invite.mosque_id), {
        type: "teacher_joined",
        priority: "informational",
        title: "انضم مدرّس جديد",
        body: `انضم ${fullName} إلى المسجد.`,
        entityRef: { teacher_id: teacherId, mosque_id: invite.mosque_id },
        dedupeKey: `teacher_joined:${teacherId}`,
      });

      const { data: mosque } = await sb
        .from("mosques")
        .select("*")
        .eq("id", invite.mosque_id)
        .maybeSingle();

      const sessionToken = await createActorSession(
        "teacher",
        teacherId,
        invite.mosque_id,
      );

      return json({
        user: {
          id: teacherId,
          full_name: fullName,
          role: "teacher",
          mosque_id: invite.mosque_id,
          email: authEmail,
          mosque_name: mosque?.name || null,
        },
        teacher: {
          id: teacherId,
          full_name: fullName,
          email: authEmail,
          whatsapp_phone: whatsappPhone,
          mosque_id: invite.mosque_id,
          login_code: legacyCode,
          english_name: fullName,
          english_prefix: prefix,
        },
        mosque,
        hafiz_token: sessionToken,
        message: "تم إنشاء حساب المدرّس بنجاح",
      }, 201);
    }

    if (method === "POST" && path === "/auth/student-login") {
      const body = await readJson(req);
      const username = String(body.username || "").trim();
      const code = String(body.login_code || "").trim().toUpperCase();
      const sb = serviceClient();
      const { data: student } = await sb
        .from("students")
        .select("*")
        .eq("login_username", username)
        .ilike("login_code", code)
        .limit(1)
        .maybeSingle();
      if (!student) return error("اسم المستخدم أو الرمز غير صحيح", 401);
      const { data: mosque } = await sb
        .from("mosques")
        .select("*")
        .eq("id", student.mosque_id)
        .maybeSingle();
      const sessionToken = await createActorSession("student", student.id, student.mosque_id);
      return json({
        user: {
          id: student.id,
          full_name: student.full_name,
          role: "student",
          mosque_id: student.mosque_id,
          email: "",
          mosque_name: mosque?.name || null,
        },
        student,
        mosque,
        hafiz_token: sessionToken,
      });
    }

    // ---- Students create ----
    if (method === "POST" && path === "/students") {
      const actor = await requireActor(req);
      const body = await readJson(req);
      const mosqueId = String(body.mosque_id || actor?.mosque_id || "").trim();
      const teacherId = String(body.teacher_id || "").trim();
      const fullName = String(body.full_name || "").trim();
      const gradeLevel = String(body.grade_level || "").trim();
      const age = Number(body.age);
      const parentPhone = String(body.parent_phone || "").trim();

      if (!mosqueId || !teacherId) return error("mosque_id و teacher_id مطلوبان");
      if (actor && actor.mosque_id !== mosqueId) return error("غير مصرح", 403);
      if (actor?.role === "teacher" && actor.actor_id !== teacherId) {
        return error("غير مصرح بإضافة طالب لمدرّس آخر", 403);
      }
      if (actor?.role === "student") return error("غير مصرح", 403);
      if (!fullName) return error("أدخل الاسم");
      if (!gradeLevel) return error("أدخل المرحلة");
      if (!Number.isFinite(age) || age < 4 || age > 25) return error("العمر بين 4 و 25");
      if (parentPhone.length < 8) return error("رقم ولي الأمر غير صالح");

      const sb = serviceClient();
      const { data: teacher } = await sb
        .from("teachers")
        .select("*")
        .eq("id", teacherId)
        .eq("mosque_id", mosqueId)
        .maybeSingle();
      if (!teacher) return error("المدرّس غير موجود في هذا المسجد", 404);

      const { data: takenRows } = await sb
        .from("students")
        .select("login_username")
        .eq("mosque_id", mosqueId);
      const taken = (takenRows || []).map((s) => s.login_username);

      const row = {
        id: crypto.randomUUID(),
        mosque_id: mosqueId,
        teacher_id: teacherId,
        full_name: fullName,
        grade_level: gradeLevel,
        age,
        parent_phone: parentPhone,
        login_username: studentUsername(fullName, taken),
        login_code: studentCode(),
        created_at: new Date().toISOString(),
      };
      const { data, error: err } = await sb.from("students").insert(row).select("*").single();
      if (err) return error(err.message, 500);
      return json({ student: data }, 201);
    }

    // ---- Sync pull ----
    if (method === "GET" && path === "/sync/pull") {
      const actor = await requireActor(req);
      if (!actor) return error("يلزم تسجيل الدخول", 401);
      const url = new URL(req.url);
      const mosqueId = (url.searchParams.get("mosque_id") || actor.mosque_id || "").trim();
      if (!mosqueId) return error("mosque_id مطلوب");
      if (actor.mosque_id !== mosqueId) return error("غير مصرح", 403);

      const sb = serviceClient();
      const { data: mosque } = await sb.from("mosques").select("*").eq("id", mosqueId).maybeSingle();
      if (!mosque) return error("المسجد غير موجود", 404);

      let teachersQuery = sb.from("teachers").select("*").eq("mosque_id", mosqueId);
      let studentsQuery = sb.from("students").select("*").eq("mosque_id", mosqueId);
      let sessionsQuery = sb.from("sessions").select("*").eq("mosque_id", mosqueId);
      let schedulesQuery = sb.from("teacher_class_schedules").select("*").eq("mosque_id", mosqueId);

      if (actor.role === "teacher") {
        teachersQuery = teachersQuery.eq("id", actor.actor_id);
        studentsQuery = studentsQuery.eq("teacher_id", actor.actor_id);
        sessionsQuery = sessionsQuery.eq("teacher_id", actor.actor_id);
        schedulesQuery = schedulesQuery.eq("teacher_id", actor.actor_id);
      } else if (actor.role === "student") {
        const { data: meStudent } = await sb
          .from("students")
          .select("*")
          .eq("id", actor.actor_id)
          .eq("mosque_id", mosqueId)
          .maybeSingle();
        if (!meStudent) return error("الطالب غير موجود", 404);
        const teacherId = String(meStudent.teacher_id);
        teachersQuery = teachersQuery.eq("id", teacherId);
        studentsQuery = studentsQuery.eq("id", actor.actor_id);
        sessionsQuery = sessionsQuery.eq("teacher_id", teacherId);
        schedulesQuery = schedulesQuery.eq("teacher_id", teacherId);
      }

      const [
        teachers,
        students,
        sessions,
        mosqueAdmins,
        schedules,
      ] = await Promise.all([
        teachersQuery,
        studentsQuery,
        sessionsQuery,
        actor.role === "mosque_admin"
          ? sb
            .from("mosque_admins")
            .select("id, mosque_id, full_name, email, created_at")
            .eq("mosque_id", mosqueId)
          : Promise.resolve({ data: [] as unknown[] }),
        schedulesQuery,
      ]);

      const sessionIds = (sessions.data || []).map((s) => s.id);
      let attendance: unknown[] = [];
      if (sessionIds.length) {
        let attQuery = sb.from("attendance").select("*").in("session_id", sessionIds);
        if (actor.role === "student") {
          attQuery = attQuery.eq("student_id", actor.actor_id);
        }
        const { data } = await attQuery;
        attendance = data || [];
      }

      const studentIds = (students.data || []).map((s) => s.id);
      let student_homework: unknown[] = [];
      let progress: unknown[] = [];
      if (studentIds.length) {
        const [hw, pr] = await Promise.all([
          sb.from("student_homework").select("*").in("student_id", studentIds),
          sb.from("progress").select("*").in("student_id", studentIds),
        ]);
        student_homework = hw.data || [];
        progress = pr.data || [];
      }

      return json({
        mosque,
        mosque_admins: mosqueAdmins.data || [],
        teachers: teachers.data || [],
        students: students.data || [],
        sessions: sessions.data || [],
        attendance,
        student_homework,
        progress,
        teacher_class_schedules: schedules.data || [],
        server_time: new Date().toISOString(),
      });
    }

    // ---- Lesson archive (scoped) ----
    if (method === "GET" && path === "/archive/lessons") {
      const actor = await requireActor(req);
      if (!actor) return error("يلزم تسجيل الدخول", 401);
      const url = new URL(req.url);
      const from = (url.searchParams.get("from") || "").trim();
      const to = (url.searchParams.get("to") || "").trim();
      if (!from || !to) return error("from و to مطلوبان (YYYY-MM-DD)");

      const sb = serviceClient();
      let teacherId = actor.actor_id;
      let studentIdFilter: string | null = null;

      if (actor.role === "teacher") {
        teacherId = actor.actor_id;
      } else if (actor.role === "student") {
        const { data: meStudent } = await sb
          .from("students")
          .select("id, teacher_id")
          .eq("id", actor.actor_id)
          .eq("mosque_id", actor.mosque_id)
          .maybeSingle();
        if (!meStudent) return error("الطالب غير موجود", 404);
        teacherId = String(meStudent.teacher_id);
        studentIdFilter = String(meStudent.id);
      } else if (actor.role === "mosque_admin") {
        const qTeacher = (url.searchParams.get("teacher_id") || "").trim();
        if (!qTeacher) return error("teacher_id مطلوب لمسؤول المسجد");
        teacherId = qTeacher;
        const { data: t } = await sb
          .from("teachers")
          .select("id")
          .eq("id", teacherId)
          .eq("mosque_id", actor.mosque_id)
          .maybeSingle();
        if (!t) return error("المدرّس غير موجود في هذا المسجد", 404);
      } else {
        return error("غير مصرح", 403);
      }

      const { data: sessions, error: sessErr } = await sb
        .from("sessions")
        .select("*")
        .eq("mosque_id", actor.mosque_id)
        .eq("teacher_id", teacherId)
        .gte("session_date", from)
        .lte("session_date", to)
        .order("session_date", { ascending: false });
      if (sessErr) return error(sessErr.message, 500);

      const sessionIds = (sessions || []).map((s) => s.id);
      let attendance: unknown[] = [];
      if (sessionIds.length) {
        let attQuery = sb.from("attendance").select("*").in("session_id", sessionIds);
        if (studentIdFilter) attQuery = attQuery.eq("student_id", studentIdFilter);
        const { data } = await attQuery;
        attendance = data || [];
      }

      const { data: students } = await sb
        .from("students")
        .select("id, full_name, teacher_id")
        .eq("mosque_id", actor.mosque_id)
        .eq("teacher_id", teacherId);

      return json({
        teacher_id: teacherId,
        from,
        to,
        sessions: sessions || [],
        attendance,
        students: students || [],
        server_time: new Date().toISOString(),
      });
    }

    // ---- Sync push ----
    if (method === "POST" && path === "/sync/push") {
      const actor = await requireActor(req);
      if (!actor) return error("يلزم تسجيل الدخول", 401);
      const body = await readJson(req);
      const ops = Array.isArray(body.ops) ? body.ops : [];
      const sb = serviceClient();
      const applied: unknown[] = [];
      const errors: { id: unknown; type: unknown; error: string }[] = [];

      for (const raw of ops) {
        const op = raw as { id?: string; type?: string; payload?: Record<string, unknown> };
        try {
          await applyOp(sb, op, actor);
          applied.push(op.id || op.type);
        } catch (e) {
          const errMsg = e instanceof Error
            ? e.message
            : (e && typeof e === "object" && "message" in e)
            ? String((e as { message: unknown }).message)
            : typeof e === "string"
            ? e
            : JSON.stringify(e);
          errors.push({
            id: op.id || null,
            type: op.type,
            error: errMsg || "خطأ غير معروف",
          });
        }
      }

      return json({ applied, errors, server_time: new Date().toISOString() });
    }

    // Teachers create (admin / with actor token)
    if (method === "POST" && path === "/teachers") {
      const actor = await requireActor(req);
      const body = await readJson(req);
      const mosqueId = String(body.mosque_id || actor?.mosque_id || "").trim();
      const fullName = String(body.full_name || "").trim();
      const englishName = String(body.english_name || "").trim();
      if (!mosqueId) return error("mosque_id مطلوب");
      if (actor && actor.mosque_id !== mosqueId) return error("غير مصرح", 403);
      if (!fullName) return error("أدخل اسم المدرّس");
      if (!englishName || !/[A-Za-z]/.test(englishName)) {
        return error("الاسم الإنجليزي يجب أن يحتوي أحرفًا لاتينية");
      }

      const sb = serviceClient();
      const { data: mosque } = await sb.from("mosques").select("id").eq("id", mosqueId).maybeSingle();
      if (!mosque) return error("المسجد غير موجود", 404);

      let code = teacherCode(englishName);
      for (let i = 0; i < 8; i++) {
        const { data: dup } = await sb
          .from("teachers")
          .select("id")
          .eq("mosque_id", mosqueId)
          .eq("login_code", code)
          .maybeSingle();
        if (!dup) break;
        code = teacherCode(englishName);
      }

      const row = {
        id: crypto.randomUUID(),
        mosque_id: mosqueId,
        full_name: fullName,
        english_name: englishName,
        english_prefix: englishPrefix(englishName),
        login_code: code,
        created_at: new Date().toISOString(),
      };
      const { data, error: err } = await sb.from("teachers").insert(row).select("*").single();
      if (err) {
        if (err.code === "23505") return error("يوجد مدرّس بهذا الاسم", 409);
        return error(err.message, 500);
      }
      return json({ teacher: data }, 201);
    }

    // ---- Notifications ----
    if (method === "GET" && path === "/notifications") {
      const actor = await resolveNotificationActor(req);
      if (!actor) return error("يلزم تسجيل الدخول", 401);
      const url = new URL(req.url);
      const limit = Math.min(Number(url.searchParams.get("limit") || 50), 100);
      const sb = serviceClient();
      const { data, error: err } = await sb
        .from("notifications")
        .select("*")
        .eq("recipient_type", actor.recipientType)
        .eq("recipient_id", actor.recipientId)
        .order("created_at", { ascending: false })
        .limit(limit);
      if (err) return error(err.message, 500);
      const unread = (data || []).filter((n) => !n.read_at).length;
      return json({
        notifications: (data || []).map((n) => publicNotification(n as Record<string, unknown>)),
        unread,
      });
    }

    const readMatch = path.match(/^\/notifications\/([^/]+)\/read$/);
    if (method === "POST" && readMatch) {
      const actor = await resolveNotificationActor(req);
      if (!actor) return error("يلزم تسجيل الدخول", 401);
      const id = readMatch[1];
      const sb = serviceClient();
      const { data, error: err } = await sb
        .from("notifications")
        .update({ read_at: new Date().toISOString() })
        .eq("id", id)
        .eq("recipient_type", actor.recipientType)
        .eq("recipient_id", actor.recipientId)
        .select("*")
        .maybeSingle();
      if (err) return error(err.message, 500);
      if (!data) return error("الإشعار غير موجود", 404);
      return json({ notification: publicNotification(data as Record<string, unknown>) });
    }

    if (method === "POST" && path === "/notifications/read-all") {
      const actor = await resolveNotificationActor(req);
      if (!actor) return error("يلزم تسجيل الدخول", 401);
      const sb = serviceClient();
      const { error: err } = await sb
        .from("notifications")
        .update({ read_at: new Date().toISOString() })
        .eq("recipient_type", actor.recipientType)
        .eq("recipient_id", actor.recipientId)
        .is("read_at", null);
      if (err) return error(err.message, 500);
      return json({ ok: true });
    }

    if (method === "POST" && path === "/device-tokens") {
      const body = await readJson(req);
      const actor = await resolveNotificationActor(req, body);
      if (!actor) return error("يلزم تسجيل الدخول", 401);
      const fcmToken = String(body.fcm_token || "").trim();
      const deviceId = String(body.device_id || "").trim();
      const appId = String(body.app_id || "hafiz").trim();
      const foregroundContext = body.foreground_context != null
        ? String(body.foreground_context)
        : null;
      if (!fcmToken || !deviceId) return error("fcm_token و device_id مطلوبان");
      if (appId !== "hafiz" && appId !== "hafiz_platform") {
        return error("app_id غير صالح");
      }
      const sb = serviceClient();
      const { error: err } = await sb.from("device_tokens").upsert({
        recipient_type: actor.recipientType,
        recipient_id: actor.recipientId,
        mosque_id: actor.mosqueId,
        app_id: appId,
        device_id: deviceId,
        fcm_token: fcmToken,
        foreground_context: foregroundContext,
        updated_at: new Date().toISOString(),
      }, { onConflict: "recipient_type,recipient_id,device_id,app_id" });
      if (err) return error(err.message, 500);
      return json({ ok: true });
    }

    if (method === "POST" && path === "/device-tokens/unregister") {
      const body = await readJson(req);
      const actor = await resolveNotificationActor(req, body);
      if (!actor) return error("يلزم تسجيل الدخول", 401);
      const deviceId = String(body.device_id || "").trim();
      const appId = String(body.app_id || "hafiz").trim();
      if (!deviceId) return error("device_id مطلوب");
      const sb = serviceClient();
      await sb.from("device_tokens").delete()
        .eq("recipient_type", actor.recipientType)
        .eq("recipient_id", actor.recipientId)
        .eq("device_id", deviceId)
        .eq("app_id", appId);
      return json({ ok: true });
    }

    if (method === "POST" && path === "/cron/no-attendance") {
      const secret = String(req.headers.get("x-cron-secret") || "").trim();
      const expected = String(Deno.env.get("CRON_SECRET") || "").trim();
      if (!expected || secret !== expected) return error("غير مصرح", 401);
      const sb = serviceClient();
      const sent = await runNoAttendanceCheck(sb);
      return json({ ok: true, sent });
    }

    return error(`مسار غير معروف: ${method} ${path}`, 404);
  } catch (e) {
    console.error(e);
    return error(e instanceof Error ? e.message : "خطأ داخلي", 500);
  }
});

async function loadStudentInMosque(
  sb: ReturnType<typeof serviceClient>,
  studentId: string,
  mosqueId: string,
) {
  const { data } = await sb
    .from("students")
    .select("id, teacher_id, mosque_id")
    .eq("id", studentId)
    .eq("mosque_id", mosqueId)
    .maybeSingle();
  return data;
}

async function loadSessionInMosque(
  sb: ReturnType<typeof serviceClient>,
  sessionId: string,
  mosqueId: string,
) {
  const { data } = await sb
    .from("sessions")
    .select("id, teacher_id, mosque_id")
    .eq("id", sessionId)
    .eq("mosque_id", mosqueId)
    .maybeSingle();
  return data;
}

function normalizeWeekdays(raw: unknown, lecturesPerWeek: number): number[] {
  const list = Array.isArray(raw) ? raw.map((x) => Number(x)) : [];
  const days = [...new Set(list.filter((d) => Number.isInteger(d) && d >= 1 && d <= 7))];
  days.sort((a, b) => a - b);
  if (days.length !== lecturesPerWeek) {
    throw new Error("عدد أيام المحاضرات يجب أن يطابق عدد المحاضرات الأسبوعية");
  }
  return days;
}

async function applyOp(
  sb: ReturnType<typeof serviceClient>,
  op: { type?: string; payload?: Record<string, unknown> },
  actor: ActorSession,
) {
  const type = op.type;
  const p = op.payload || {};
  const now = new Date().toISOString();
  const mosqueId = actor.mosque_id;

  switch (type) {
    case "upsert_teacher": {
      if (actor.role !== "mosque_admin") throw new Error("غير مصرح بتعديل المدرّسين");
      const row = {
        id: await ensureUuid(String(p.id || "")),
        mosque_id: mosqueId,
        full_name: String(p.full_name || ""),
        english_name: String(p.english_name || ""),
        english_prefix: String(p.english_prefix || englishPrefix(String(p.english_name || ""))),
        login_code: String(p.login_code || ""),
        created_at: String(p.created_at || now),
      };
      const { error: err } = await sb.from("teachers").upsert(row);
      if (err) throw new Error(err.message || JSON.stringify(err));
      break;
    }
    case "delete_teacher": {
      if (actor.role !== "mosque_admin") throw new Error("غير مصرح بحذف المدرّسين");
      const { error: err } = await sb
        .from("teachers")
        .delete()
        .eq("id", await ensureUuid(String(p.id)))
        .eq("mosque_id", mosqueId);
      if (err) throw new Error(err.message || JSON.stringify(err));
      break;
    }
    case "upsert_student": {
      if (actor.role === "student") throw new Error("غير مصرح");
      let teacherId = await ensureUuid(String(p.teacher_id || ""));
      if (actor.role === "teacher") {
        teacherId = actor.actor_id;
        const existingId = await ensureUuid(String(p.id || ""));
        const existing = await loadStudentInMosque(sb, existingId, mosqueId);
        if (existing && String(existing.teacher_id) !== actor.actor_id) {
          throw new Error("غير مصرح بتعديل طالب لمدرّس آخر");
        }
      }
      const row = {
        id: await ensureUuid(String(p.id || "")),
        mosque_id: mosqueId,
        teacher_id: teacherId,
        full_name: String(p.full_name || ""),
        grade_level: String(p.grade_level || ""),
        age: Number(p.age),
        parent_phone: String(p.parent_phone || ""),
        login_username: String(p.login_username || ""),
        login_code: String(p.login_code || ""),
        created_at: String(p.created_at || now),
      };
      const { error: err } = await sb.from("students").upsert(row);
      if (err) throw new Error(err.message || JSON.stringify(err));
      break;
    }
    case "delete_student": {
      if (actor.role === "student") throw new Error("غير مصرح");
      const studentId = await ensureUuid(String(p.id));
      const existing = await loadStudentInMosque(sb, studentId, mosqueId);
      if (!existing) throw new Error("الطالب غير موجود");
      if (actor.role === "teacher" && String(existing.teacher_id) !== actor.actor_id) {
        throw new Error("غير مصرح بحذف طالب لمدرّس آخر");
      }
      const { error: err } = await sb
        .from("students")
        .delete()
        .eq("id", studentId)
        .eq("mosque_id", mosqueId);
      if (err) throw new Error(err.message || JSON.stringify(err));
      break;
    }
    case "upsert_session": {
      if (actor.role !== "teacher" && actor.role !== "mosque_admin") {
        throw new Error("غير مصرح");
      }
      const sessionId = await ensureUuid(String(p.id || ""));
      const teacherId = actor.role === "teacher"
        ? actor.actor_id
        : await ensureUuid(String(p.teacher_id || ""));
      if (actor.role === "mosque_admin") {
        const { data: t } = await sb
          .from("teachers")
          .select("id")
          .eq("id", teacherId)
          .eq("mosque_id", mosqueId)
          .maybeSingle();
        if (!t) throw new Error("المدرّس غير موجود في هذا المسجد");
      }
      const existing = await loadSessionInMosque(sb, sessionId, mosqueId);
      if (existing) {
        if (actor.role === "teacher" && String(existing.teacher_id) !== actor.actor_id) {
          throw new Error("غير مصرح بتعديل جلسة لمدرّس آخر");
        }
        if (actor.role === "mosque_admin" && String(existing.teacher_id) !== teacherId) {
          throw new Error("لا يمكن نقل الجلسة إلى مدرّس آخر");
        }
      }
      const row = {
        id: sessionId,
        mosque_id: mosqueId,
        teacher_id: teacherId,
        session_date: String(p.session_date || ""),
        status: String(p.status || "active"),
        started_at: String(p.started_at || now),
        ended_at: p.ended_at ? String(p.ended_at) : null,
      };
      const { error: err } = await sb.from("sessions").upsert(row);
      if (err) throw new Error(err.message || JSON.stringify(err));
      break;
    }
    case "upsert_attendance": {
      if (actor.role !== "teacher" && actor.role !== "mosque_admin") {
        throw new Error("غير مصرح");
      }
      const sessionId = await ensureUuid(String(p.session_id || ""));
      const studentId = await ensureUuid(String(p.student_id || ""));
      const session = await loadSessionInMosque(sb, sessionId, mosqueId);
      if (!session) throw new Error("الجلسة غير موجودة");
      const student = await loadStudentInMosque(sb, studentId, mosqueId);
      if (!student) throw new Error("الطالب غير موجود");
      if (actor.role === "teacher") {
        if (String(session.teacher_id) !== actor.actor_id) {
          throw new Error("غير مصرح بتعديل حضور جلسة لمدرّس آخر");
        }
        if (String(student.teacher_id) !== actor.actor_id) {
          throw new Error("غير مصرح بتعديل حضور طالب لمدرّس آخر");
        }
      }
      const row = {
        id: await ensureUuid(String(p.id || "")),
        session_id: sessionId,
        student_id: studentId,
        status: String(p.status || "unmarked"),
        memorization_level: p.memorization_level ?? null,
        behavior_score: p.behavior_score ?? null,
        marked_at: String(p.marked_at || now),
      };
      const { error: err } = await sb.from("attendance").upsert(row);
      if (err) throw new Error(err.message || JSON.stringify(err));
      break;
    }
    case "upsert_homework": {
      const studentId = await ensureUuid(String(p.student_id || ""));
      const student = await loadStudentInMosque(sb, studentId, mosqueId);
      if (!student) throw new Error("الطالب غير موجود");
      if (actor.role === "teacher" && String(student.teacher_id) !== actor.actor_id) {
        throw new Error("غير مصرح بتعيين واجب لطالب لمدرّس آخر");
      }
      if (actor.role === "student" && studentId !== actor.actor_id) {
        throw new Error("غير مصرح");
      }
      if (actor.role === "student") throw new Error("غير مصرح بتعيين واجب");
      const row = {
        id: await ensureUuid(String(p.id || "")),
        student_id: studentId,
        surah_number: Number(p.surah_number),
        from_ayah: Number(p.from_ayah),
        to_ayah: Number(p.to_ayah),
        note: String(p.note || ""),
        assigned_at: String(p.assigned_at || now),
      };
      const { error: err } = await sb.from("student_homework").upsert(row, {
        onConflict: "student_id",
      });
      if (err) throw new Error(err.message || JSON.stringify(err));

      await notifyUser(sb, {
        recipientType: "student",
        recipientId: String(student.id),
        mosqueId: String(student.mosque_id),
        type: "homework_updated",
        priority: "important",
        title: "واجب جديد",
        body: "حدّث المدرّس واجبك — راجعه من شاشة «اليوم».",
        entityRef: {
          student_id: student.id,
          homework_id: row.id,
          surah_number: row.surah_number,
        },
        dedupeKey: `homework:${studentId}:${row.assigned_at}`,
        foregroundContext: "student_homework",
      });
      break;
    }
    case "upsert_progress": {
      const studentId = await ensureUuid(String(p.student_id || ""));
      const student = await loadStudentInMosque(sb, studentId, mosqueId);
      if (!student) throw new Error("الطالب غير موجود");
      if (actor.role === "student" && studentId !== actor.actor_id) {
        throw new Error("غير مصرح بتعديل تقدّم طالب آخر");
      }
      if (actor.role === "teacher" && String(student.teacher_id) !== actor.actor_id) {
        throw new Error("غير مصرح بتعديل تقدّم طالب لمدرّس آخر");
      }
      const row = {
        id: await ensureUuid(String(p.id || "")),
        student_id: studentId,
        surah_number: Number(p.surah_number),
        ayah_number: Number(p.ayah_number),
        updated_at: String(p.updated_at || now),
      };
      const { error: err } = await sb.from("progress").upsert(row, {
        onConflict: "student_id",
      });
      if (err) throw new Error(err.message || JSON.stringify(err));
      break;
    }
    case "upsert_teacher_schedule": {
      if (actor.role !== "teacher" && actor.role !== "mosque_admin") {
        throw new Error("غير مصرح");
      }
      const teacherId = actor.role === "teacher"
        ? actor.actor_id
        : await ensureUuid(String(p.teacher_id || ""));
      if (actor.role === "mosque_admin") {
        const { data: t } = await sb
          .from("teachers")
          .select("id")
          .eq("id", teacherId)
          .eq("mosque_id", mosqueId)
          .maybeSingle();
        if (!t) throw new Error("المدرّس غير موجود في هذا المسجد");
      }
      const lectures = Number(p.lectures_per_week);
      if (!Number.isInteger(lectures) || lectures < 1 || lectures > 7) {
        throw new Error("عدد المحاضرات الأسبوعية بين 1 و 7");
      }
      const weekdays = normalizeWeekdays(p.weekdays, lectures);
      const { data: existing } = await sb
        .from("teacher_class_schedules")
        .select("id")
        .eq("teacher_id", teacherId)
        .maybeSingle();
      const row = {
        id: existing?.id || await ensureUuid(String(p.id || "")),
        mosque_id: mosqueId,
        teacher_id: teacherId,
        lectures_per_week: lectures,
        weekdays,
        active: p.active === false ? false : true,
        updated_at: String(p.updated_at || now),
      };
      const { error: err } = await sb.from("teacher_class_schedules").upsert(row, {
        onConflict: "teacher_id",
      });
      if (err) throw new Error(err.message || JSON.stringify(err));
      break;
    }
    case "upsert_mosque":
      // Ignore client mosque/admin password sync — managed by platform approve flow
      break;
    default:
      throw new Error(`عملية غير معروفة: ${type}`);
  }
}
