import { corsHeaders, error, json, readJson, bearerToken } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";
import {
  englishPrefix,
  ensureUuid,
  looksLikeEmail,
  looksLikeWhatsappPhone,
  mosqueAdminPassword,
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
} from "../_shared/codes.ts";
import { hashPassword, verifyPassword } from "../_shared/password.ts";

type ActorSession = {
  token: string;
  role: "mosque_admin" | "teacher" | "student";
  actor_id: string;
  mosque_id: string;
};

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
    if (method === "POST" && path === "/platform/login") {
      const body = await readJson(req);
      const configured = String(Deno.env.get("PLATFORM_ADMIN_PASSWORD") || "").trim();
      if (configured.length < 6) {
        return error("PLATFORM_ADMIN_PASSWORD غير مضبوط على Edge Function secrets", 503);
      }
      if (String(body.password || "") !== configured) {
        return error("كلمة مرور الإدارة غير صحيحة", 401);
      }
      const token = randomToken();
      const expires = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
      const sb = serviceClient();
      const { error: err } = await sb.from("platform_sessions").insert({
        token,
        expires_at: expires,
      });
      if (err) return error(err.message, 500);
      return json({ token, role: "platform_admin" });
    }

    if (method === "POST" && path === "/platform/logout") {
      const token = await requirePlatform(req);
      if (!token) return error("يلزم تسجيل دخول الإدارة", 401);
      const sb = serviceClient();
      await sb.from("platform_sessions").delete().eq("token", token);
      return json({ ok: true });
    }

    // ---- Registration email OTP (app-owned, code only — no magic links) ----
    if (method === "POST" && path === "/registration/email-otp/send") {
      const body = await readJson(req);
      const email = String(body.email || "").trim().toLowerCase();
      if (!looksLikeEmail(email)) return error("البريد غير صالح");
      const code = sixDigitOtp();
      const codeHash = await sha256Hex(code);
      const expiresAt = new Date(Date.now() + 15 * 60 * 1000).toISOString();
      const sb = serviceClient();
      await sb.from("registration_email_otps").delete().eq("email", email).is("consumed_at", null);

      let delivery: "email" | "manual" = "email";
      let sendError: string | null = null;
      try {
        const apiKey = String(Deno.env.get("RESEND_API_KEY") || "").trim();
        if (!apiKey) throw new Error("RESEND_API_KEY missing");
        const from =
          String(Deno.env.get("AUTH_EMAIL_FROM") || "").trim() ||
          "Hafiz <onboarding@resend.dev>";
        const html =
          `<h2>رمز التحقق — حافظ</h2><p>أدخل هذا الرمز في التطبيق:</p>` +
          `<p style="font-size:36px;font-weight:700;letter-spacing:8px;text-align:center">${code}</p>` +
          `<p>لا تفتح أي رابط. ينتهي خلال 15 دقيقة.</p>`;
        const res = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${apiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            from,
            to: [email],
            subject: "رمز التحقق — حافظ",
            html,
            text: `Hafiz code: ${code}`,
          }),
        });
        if (!res.ok) {
          const t = await res.text();
          if (t.includes("testing emails") || t.includes("verify a domain") || res.status === 403) {
            delivery = "manual";
            sendError = "resend_testing_mode";
          } else {
            throw new Error(`Resend ${res.status}: ${t}`);
          }
        }
      } catch (e) {
        delivery = "manual";
        sendError = e instanceof Error ? e.message : String(e);
      }

      const { error: insErr } = await sb.from("registration_email_otps").insert({
        email,
        code_hash: codeHash,
        code_plain: delivery === "manual" ? code : null,
        delivery,
        expires_at: expiresAt,
      });
      if (insErr) return error(insErr.message, 500);

      // #region agent log
      fetch('http://127.0.0.1:7508/ingest/8ce7454f-a04c-4250-8d9a-628369f96a33',{method:'POST',headers:{'Content-Type':'application/json','X-Debug-Session-Id':'d34801'},body:JSON.stringify({sessionId:'d34801',hypothesisId:'E1',location:'registration/email-otp/send',message:'otp_created',data:{delivery,sendError,domain:email.split('@')[1]||''},timestamp:Date.now()})}).catch(()=>{});
      // #endregion

      return json({
        ok: true,
        delivery,
        expires_at: expiresAt,
        message: delivery === "email"
          ? "أُرسل رمز التحقق إلى بريدك. أدخله في التطبيق."
          : "تعذّر الإرسال التلقائي لهذا البريد. اطلب الرمز من إدارة منصة حافظ (يظهر لديهم لـ15 دقيقة)، أو وثّق نطاقاً في Resend.",
      });
    }

    if (method === "POST" && path === "/registration/email-otp/verify") {
      const body = await readJson(req);
      const email = String(body.email || "").trim().toLowerCase();
      const code = String(body.code || "").trim();
      if (!looksLikeEmail(email)) return error("البريد غير صالح");
      if (!/^\d{6}$/.test(code)) return error("أدخل الرمز المكوّن من 6 أرقام");
      const sb = serviceClient();
      const codeHash = await sha256Hex(code);
      const { data: row } = await sb
        .from("registration_email_otps")
        .select("*")
        .eq("email", email)
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
        .from("registration_email_otps")
        .update({ consumed_at: new Date().toISOString(), code_plain: null })
        .eq("id", row.id);
      const proof = randomToken(24);
      const proofExp = new Date(Date.now() + 2 * 60 * 60 * 1000).toISOString();
      await sb.from("registration_proofs").delete().eq("email", email);
      const { error: pErr } = await sb.from("registration_proofs").insert({
        token: proof,
        email,
        expires_at: proofExp,
      });
      if (pErr) return error(pErr.message, 500);
      return json({
        ok: true,
        registration_proof: proof,
        email,
        expires_at: proofExp,
        message: "تم التحقق من البريد بنجاح",
      });
    }

    // ---- Registration (in-app, requires verified email session OR registration proof) ----
    if (method === "POST" && path === "/registration-requests") {
      const body = await readJson(req);
      const proofToken = String(
        body.registration_proof || req.headers.get("x-registration-proof") || "",
      ).trim();
      let email = "";
      let emailVerifiedAt = new Date().toISOString();
      let authUserId: string | null = null;

      const verified = await requireVerifiedAuthEmail(req);
      if (verified) {
        email = verified.email;
        emailVerifiedAt = verified.emailVerifiedAt;
        authUserId = verified.userId;
      } else if (proofToken) {
        const sbProof = serviceClient();
        const { data: proof } = await sbProof
          .from("registration_proofs")
          .select("*")
          .eq("token", proofToken)
          .maybeSingle();
        if (!proof) return error("يلزم التحقق من البريد أولاً", 401);
        if (new Date(proof.expires_at).getTime() < Date.now()) {
          return error("انتهت جلسة التحقق — أعد إرسال الرمز", 401);
        }
        email = String(proof.email).toLowerCase();
        emailVerifiedAt = proof.created_at || emailVerifiedAt;
      } else {
        return error("يلزم التحقق من البريد الإلكتروني من داخل التطبيق أولاً", 401);
      }

      const mosqueName = String(body.mosque_name || "").trim();
      const emailFromBody = String(body.email || "").trim().toLowerCase();
      if (emailFromBody && emailFromBody !== email) {
        return error("البريد لا يطابق الجلسة المتحقّق منها", 400);
      }

      const rawPhone = String(body.whatsapp_phone || "").trim();
      const whatsappPhone = normalizeWhatsappDigits(rawPhone);
      const governorate = String(body.governorate || "").trim();
      const district = String(body.district || "").trim();
      const area = String(body.area || "").trim();
      const studentsRange = String(body.students_range || "").trim();
      const teachersRange = String(body.teachers_range || "").trim();

      if (!mosqueName) return error("أدخل اسم الجامع");
      if (!looksLikeWhatsappPhone(rawPhone) && !looksLikeWhatsappPhone(whatsappPhone)) {
        return error("رقم واتساب غير صالح");
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

      const { data: existsEmail } = await sb
        .from("mosque_admins")
        .select("id")
        .eq("email", email)
        .maybeSingle();
      if (existsEmail) return error("البريد مستخدم مسبقًا — يمكنك الدخول مباشرة", 409);

      const { data: pendingDup } = await sb
        .from("mosque_registration_requests")
        .select("id")
        .eq("status", "pending")
        .or(`email.eq.${email},mosque_name.eq.${mosqueName}`)
        .limit(1)
        .maybeSingle();
      if (pendingDup) {
        return error("يوجد طلب قيد المراجعة لنفس البريد أو اسم الجامع", 409);
      }

      const row = {
        mosque_name: mosqueName,
        email,
        whatsapp_phone: whatsappPhone,
        governorate,
        district,
        area,
        students_range: studentsRange,
        teachers_range: teachersRange,
        email_verified_at: emailVerifiedAt,
        auth_user_id: authUserId,
        status: "pending",
      };
      const { data, error: err } = await sb
        .from("mosque_registration_requests")
        .insert(row)
        .select("*")
        .single();
      if (err) return error(err.message, 500);
      return json(
        {
          request: publicRequest(data),
          message: "تم إرسال الطلب. يمكنك متابعة حالته من داخل التطبيق.",
        },
        201,
      );
    }

    // حالة طلب التسجيل بالبريد (من داخل التطبيق)
    if (method === "GET" && path === "/registration-requests/status") {
      const url = new URL(req.url);
      const email = String(url.searchParams.get("email") || "").trim().toLowerCase();
      if (!looksLikeEmail(email)) return error("البريد غير صالح");
      const sb = serviceClient();
      const { data, error: err } = await sb
        .from("mosque_registration_requests")
        .select("*")
        .eq("email", email)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (err) return error(err.message, 500);
      if (!data) {
        return json({
          found: false,
          message: "لا يوجد طلب تسجيل لهذا البريد",
        });
      }
      const reqPublic = publicRequest(data);
      return json({
        found: true,
        request: reqPublic,
        status_label: statusLabelAr(String(data.status)),
        message:
          data.status === "pending"
            ? "طلبك قيد مراجعة إدارة حافظ."
            : data.status === "approved"
            ? "تمت الموافقة. استخدم بيانات الدخول المرسلة عبر واتساب."
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

    // رموز تحقق يدوية عند فشل Resend (يظهر الرمز لإدارة المنصة فقط)
    if (method === "GET" && path === "/platform/manual-otps") {
      const token = await requirePlatform(req);
      if (!token) return error("يلزم تسجيل دخول الإدارة", 401);
      const sb = serviceClient();
      const { data, error: err } = await sb
        .from("registration_email_otps")
        .select("id, email, code_plain, delivery, expires_at, created_at")
        .eq("delivery", "manual")
        .is("consumed_at", null)
        .gt("expires_at", new Date().toISOString())
        .order("created_at", { ascending: false })
        .limit(50);
      if (err) return error(err.message, 500);
      return json({ otps: data || [] });
    }

    if (method === "GET" && path === "/platform/mosques") {
      const token = await requirePlatform(req);
      if (!token) return error("يلزم تسجيل دخول الإدارة", 401);
      const sb = serviceClient();
      const { data: mosques, error: err } = await sb
        .from("mosques")
        .select("id, name, whatsapp_phone, created_at")
        .order("created_at", { ascending: false });
      if (err) return error(err.message, 500);
      const { data: admins } = await sb
        .from("mosque_admins")
        .select("id, mosque_id, full_name, email");
      const byMosque = new Map((admins || []).map((a) => [a.mosque_id, a]));
      return json({
        mosques: (mosques || []).map((m) => {
          const a = byMosque.get(m.id);
          return {
            id: m.id,
            name: m.name,
            whatsapp_phone: m.whatsapp_phone || null,
            created_at: m.created_at,
            admin: a
              ? { id: a.id, full_name: a.full_name, email: a.email }
              : null,
          };
        }),
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
        .eq("email", request.email)
        .maybeSingle();
      if (existsEmail) return error("البريد مستخدم مسبقًا", 409);

      const body = await readJson(req);
      const requestedPassword = String(body.password || body.admin_password || "").trim();
      let plainPassword = requestedPassword;
      if (plainPassword) {
        if (plainPassword.length < 6) {
          return error("كلمة المرور يجب أن تكون 6 أحرف على الأقل");
        }
      } else {
        plainPassword = mosqueAdminPassword();
      }
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
        const { data: authData, error: authErr } = await sb.auth.admin.createUser({
          email: request.email,
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
        if (authErr) {
          // قد يكون المستخدم موجوداً من تحقق OTP دون ربطه بالطلب
          const msg = String(authErr.message || "");
          if (/already|registered|exists/i.test(msg)) {
            const listed = await sb.auth.admin.listUsers({ page: 1, perPage: 1000 });
            const found = (listed.data?.users || []).find(
              (u) => (u.email || "").toLowerCase() === String(request.email).toLowerCase(),
            );
            if (!found) {
              await sb.from("mosques").delete().eq("id", mosqueId);
              return error(authErr.message || "تعذّر إنشاء حساب الدخول", 500);
            }
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
            if (updErr) {
              await sb.from("mosques").delete().eq("id", mosqueId);
              return error(updErr.message || "تعذّر تحديث حساب الدخول", 500);
            }
          } else {
            await sb.from("mosques").delete().eq("id", mosqueId);
            return error(authErr.message || "تعذّر إنشاء حساب الدخول", 500);
          }
        } else {
          authUserId = authData.user.id;
        }
      }

      const { error: aErr } = await sb.from("mosque_admins").insert({
        id: adminId,
        mosque_id: mosqueId,
        full_name: `مسؤول ${request.mosque_name}`,
        email: request.email,
        password_hash: hashPassword(plainPassword),
        auth_user_id: authUserId,
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
        email: request.email,
        mosque_id: mosqueId,
      };
      const waDigits = normalizeWhatsappDigits(request.whatsapp_phone);
      const message = [
        "السلام عليكم،",
        `تم اعتماد تسجيل «${mosque.name}» في تطبيق حافظ.`,
        "",
        "بيانات الدخول لإدارة الجامع:",
        `اسم المسجد: ${mosque.name}`,
        `البريد: ${admin.email}`,
        `كلمة المرور: ${plainPassword}`,
        "",
        "ادخل عبر شاشة «إدارة الجامع» في التطبيق.",
      ].join("\n");
      const whatsappUrl = `https://wa.me/${waDigits}?text=${encodeURIComponent(message)}`;

      return json({
        request: publicRequest({
          ...request,
          status: "approved",
          mosque_id: mosqueId,
          reviewed_at: reviewedAt,
        }),
        mosque,
        admin,
        generated_password: plainPassword,
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
      return json({
        request: publicRequest({ ...request, status: "rejected", reviewed_at: reviewedAt }),
      });
    }

    // ---- Auth logins ----
    if (method === "POST" && path === "/auth/login") {
      const body = await readJson(req);
      const mosqueName = String(body.mosque_name || "").trim();
      const email = String(body.email || "").trim().toLowerCase();
      const password = String(body.password || "");
      const sb = serviceClient();

      const { data: admin } = await sb
        .from("mosque_admins")
        .select("*")
        .eq("email", email)
        .maybeSingle();
      if (!admin) return error("بيانات الدخول غير صحيحة", 401);

      const { data: mosque } = await sb
        .from("mosques")
        .select("*")
        .eq("id", admin.mosque_id)
        .maybeSingle();
      if (!mosque || mosque.name !== mosqueName) {
        return error("اسم المسجد غير مطابق لهذا الحساب", 401);
      }

      let accessToken: string | null = null;
      let refreshToken: string | null = null;

      // Prefer Supabase Auth when linked
      if (admin.auth_user_id) {
        const { data: signed, error: sErr } = await sb.auth.signInWithPassword({
          email,
          password,
        });
        if (sErr || !signed.session) {
          // fallback to legacy hash
          if (!verifyPassword(password, admin.password_hash)) {
            return error("بيانات الدخول غير صحيحة", 401);
          }
        } else {
          accessToken = signed.session.access_token;
          refreshToken = signed.session.refresh_token;
        }
      } else if (!verifyPassword(password, admin.password_hash)) {
        return error("بيانات الدخول غير صحيحة", 401);
      }

      // Legacy admins without Auth: create Auth user on first successful login
      if (!admin.auth_user_id && verifyPassword(password, admin.password_hash)) {
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
      const currentPassword = String(body.current_password || "");
      const newPassword = String(body.new_password || "");
      if (newPassword.length < 6) {
        return error("كلمة المرور الجديدة يجب أن تكون 6 أحرف على الأقل");
      }
      if (currentPassword === newPassword) {
        return error("كلمة المرور الجديدة مطابقة للحالية");
      }

      const sb = serviceClient();
      const { data: admin } = await sb
        .from("mosque_admins")
        .select("*")
        .eq("id", actor.actor_id)
        .maybeSingle();
      if (!admin) return error("الحساب غير موجود", 404);

      let currentOk = false;
      if (admin.auth_user_id) {
        const { data: signed, error: sErr } = await sb.auth.signInWithPassword({
          email: admin.email,
          password: currentPassword,
        });
        currentOk = !sErr && !!signed.session;
      }
      if (!currentOk) {
        currentOk = verifyPassword(currentPassword, admin.password_hash);
      }
      if (!currentOk) return error("كلمة المرور الحالية غير صحيحة", 401);

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
      const email = String(body.email || "").trim().toLowerCase();
      const password = String(body.password || "");
      const fullName = String(body.full_name || "").trim();
      const code = String(body.login_code || "").trim().toUpperCase();
      const sb = serviceClient();

      // المسار الجديد: بريد + كلمة مرور
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
        return error("أدخل البريد وكلمة المرور، أو الاسم ورمز الدخول");
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
      const expiresAt = new Date(Date.now() + 2 * 60 * 1000).toISOString();
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
        message: "شارك الرمز مع المدرّس خلال دقيقتين. يُستخدم مرة واحدة فقط.",
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
        message: `أنت بصدد التسجيل كمدرّس لصالح مسجد «${mosque.name}»`,
      });
    }

    if (method === "POST" && path === "/teachers/register") {
      const body = await readJson(req);
      const inviteToken = String(body.invite_token || "").trim();
      const fullName = String(body.full_name || "").trim();
      const email = String(body.email || "").trim().toLowerCase();
      const password = String(body.password || "");
      const rawPhone = String(body.whatsapp_phone || "").trim();
      const whatsappPhone = normalizeWhatsappDigits(rawPhone);

      if (!inviteToken) return error("رمز الجلسة مفقود — أعد إدخال رمز الدعوة");
      if (!fullName) return error("أدخل الاسم الكامل");
      if (!looksLikeEmail(email)) return error("البريد غير صالح");
      if (password.length < 6) return error("كلمة المرور يجب أن تكون 6 أحرف على الأقل");
      if (!looksLikeWhatsappPhone(rawPhone) && !looksLikeWhatsappPhone(whatsappPhone)) {
        return error("رقم واتساب غير صالح");
      }

      const sb = serviceClient();
      const tokenHash = await sha256Hex(inviteToken);
      const { data: invite } = await sb
        .from("teacher_invites")
        .select("*")
        .eq("registration_token_hash", tokenHash)
        .limit(1)
        .maybeSingle();

      if (!invite) return error("جلسة التسجيل غير صالحة — أعد إدخال رمز الدعوة", 401);
      if (invite.consumed_at) return error("تم استخدام الدعوة مسبقاً", 409);
      if (new Date(invite.expires_at).getTime() < Date.now()) {
        return error("انتهت صلاحية الدعوة", 410);
      }

      const { data: emailTaken } = await sb
        .from("teachers")
        .select("id")
        .ilike("email", email)
        .limit(1)
        .maybeSingle();
      if (emailTaken) return error("البريد مستخدم مسبقاً", 409);

      const { data: nameTaken } = await sb
        .from("teachers")
        .select("id")
        .eq("mosque_id", invite.mosque_id)
        .eq("full_name", fullName)
        .maybeSingle();
      if (nameTaken) return error("يوجد مدرّس بهذا الاسم في المسجد", 409);

      const teacherId = crypto.randomUUID();
      const now = new Date().toISOString();
      const legacyCode = teacherCode(fullName);
      const prefix = englishPrefix(fullName);

      const { data: authData, error: authErr } = await sb.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        app_metadata: {
          role: "teacher",
          mosque_id: invite.mosque_id,
          teacher_id: teacherId,
        },
        user_metadata: { full_name: fullName },
      });
      if (authErr) {
        const msg = String(authErr.message || "");
        if (/already|registered|exists/i.test(msg)) {
          return error("البريد مسجّل في نظام الدخول مسبقاً", 409);
        }
        return error(authErr.message || "تعذّر إنشاء الحساب", 500);
      }

      const { error: tErr } = await sb.from("teachers").insert({
        id: teacherId,
        mosque_id: invite.mosque_id,
        full_name: fullName,
        english_name: fullName,
        english_prefix: prefix,
        login_code: legacyCode,
        email,
        password_hash: hashPassword(password),
        auth_user_id: authData.user.id,
        whatsapp_phone: whatsappPhone,
        created_at: now,
      });
      if (tErr) {
        await sb.auth.admin.deleteUser(authData.user.id);
        return error(tErr.message, 500);
      }

      await sb
        .from("teacher_invites")
        .update({
          consumed_at: now,
          registration_token_hash: null,
        })
        .eq("id", invite.id);

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
          email,
          mosque_name: mosque?.name || null,
        },
        teacher: {
          id: teacherId,
          full_name: fullName,
          email,
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
      const url = new URL(req.url);
      const mosqueId = (url.searchParams.get("mosque_id") || actor?.mosque_id || "").trim();
      if (!mosqueId) return error("mosque_id مطلوب");
      if (actor && actor.mosque_id !== mosqueId) return error("غير مصرح", 403);

      const sb = serviceClient();
      const { data: mosque } = await sb.from("mosques").select("*").eq("id", mosqueId).maybeSingle();
      if (!mosque) return error("المسجد غير موجود", 404);

      const [
        teachers,
        students,
        sessions,
        mosqueAdmins,
      ] = await Promise.all([
        sb.from("teachers").select("*").eq("mosque_id", mosqueId),
        sb.from("students").select("*").eq("mosque_id", mosqueId),
        sb.from("sessions").select("*").eq("mosque_id", mosqueId),
        sb
          .from("mosque_admins")
          .select("id, mosque_id, full_name, email, created_at")
          .eq("mosque_id", mosqueId),
      ]);

      const sessionIds = (sessions.data || []).map((s) => s.id);
      let attendance: unknown[] = [];
      if (sessionIds.length) {
        const { data } = await sb.from("attendance").select("*").in("session_id", sessionIds);
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
          await applyOp(sb, op, actor.mosque_id);
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

    return error(`مسار غير معروف: ${method} ${path}`, 404);
  } catch (e) {
    console.error(e);
    return error(e instanceof Error ? e.message : "خطأ داخلي", 500);
  }
});

async function applyOp(
  sb: ReturnType<typeof serviceClient>,
  op: { type?: string; payload?: Record<string, unknown> },
  mosqueId: string,
) {
  const type = op.type;
  const p = op.payload || {};
  const now = new Date().toISOString();

  switch (type) {
    case "upsert_teacher": {
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
      const { error: err } = await sb
        .from("teachers")
        .delete()
        .eq("id", await ensureUuid(String(p.id)))
        .eq("mosque_id", mosqueId);
      if (err) throw new Error(err.message || JSON.stringify(err));
      break;
    }
    case "upsert_student": {
      const row = {
        id: await ensureUuid(String(p.id || "")),
        mosque_id: mosqueId,
        teacher_id: await ensureUuid(String(p.teacher_id || "")),
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
      const { error: err } = await sb
        .from("students")
        .delete()
        .eq("id", await ensureUuid(String(p.id)))
        .eq("mosque_id", mosqueId);
      if (err) throw new Error(err.message || JSON.stringify(err));
      break;
    }
    case "upsert_session": {
      const row = {
        id: await ensureUuid(String(p.id || "")),
        mosque_id: mosqueId,
        teacher_id: await ensureUuid(String(p.teacher_id || "")),
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
      const row = {
        id: await ensureUuid(String(p.id || "")),
        session_id: await ensureUuid(String(p.session_id || "")),
        student_id: await ensureUuid(String(p.student_id || "")),
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
      const row = {
        id: await ensureUuid(String(p.id || "")),
        student_id: await ensureUuid(String(p.student_id || "")),
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
      break;
    }
    case "upsert_progress": {
      const row = {
        id: await ensureUuid(String(p.id || "")),
        student_id: await ensureUuid(String(p.student_id || "")),
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
    case "upsert_mosque":
      // Ignore client mosque/admin password sync — managed by platform approve flow
      break;
    default:
      throw new Error(`عملية غير معروفة: ${type}`);
  }
}
