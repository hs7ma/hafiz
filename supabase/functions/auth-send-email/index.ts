import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";

type EmailData = {
  token: string;
  token_hash: string;
  redirect_to: string;
  email_action_type: string;
  site_url: string;
  token_new?: string;
  token_hash_new?: string;
};

type HookPayload = {
  user: { email: string };
  email_data: EmailData;
};

function subjectFor(action: string, token: string): string {
  switch (action) {
    case "recovery":
      return "Hafiz password reset code";
    case "email_change":
      return "Hafiz email change code";
    case "invite":
      return "Hafiz invitation code";
    case "reauthentication":
      return `${token} is your Hafiz code`;
    default:
      return "Hafiz verification code";
  }
}

function htmlFor(token: string, action: string): string {
  const intro =
    action === "recovery"
      ? "Enter this code in the Hafiz app to reset your password:"
      : action === "invite"
      ? "Enter this code in the Hafiz app to accept your invitation:"
      : "Enter this code in the Hafiz app to continue:";
  return `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<body style="font-family:Tahoma,Arial,sans-serif;line-height:1.6;color:#1a1a1a;background:#f7f7f4;padding:24px;">
  <div style="max-width:480px;margin:0 auto;background:#fff;border-radius:12px;padding:24px;">
    <h2 style="margin:0 0 12px;color:#3d5a40;">رمز التحقق — حافظ</h2>
    <p style="margin:0 0 16px;">${intro}</p>
    <p style="font-size:32px;font-weight:700;letter-spacing:8px;font-family:Consolas,monospace;text-align:center;margin:24px 0;color:#1a1a1a;">${token}</p>
    <p style="margin:0;color:#666;font-size:14px;">ينتهي الرمز خلال ساعة. إذا لم تطلب هذا الرمز فتجاهل الرسالة.</p>
  </div>
</body>
</html>`;
}

async function sendWithResend(to: string, subject: string, html: string, text: string) {
  const apiKey = String(Deno.env.get("RESEND_API_KEY") || "").trim();
  if (!apiKey) {
    throw new Error("RESEND_API_KEY is not configured");
  }
  const from =
    String(Deno.env.get("AUTH_EMAIL_FROM") || "").trim() ||
    "Hafiz <onboarding@resend.dev>";
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ from, to: [to], subject, html, text }),
  });
  if (!res.ok) {
    const body = await res.text();
    // #region agent log
    fetch('http://127.0.0.1:7508/ingest/8ce7454f-a04c-4250-8d9a-628369f96a33',{method:'POST',headers:{'Content-Type':'application/json','X-Debug-Session-Id':'d34801'},body:JSON.stringify({sessionId:'d34801',hypothesisId:'H4b',location:'auth-send-email/resend',message:'resend_failed',data:{status:res.status,body:body.slice(0,300)},timestamp:Date.now()})}).catch(()=>{});
    // #endregion
    if (body.includes("testing emails") || body.includes("verify a domain")) {
      throw new Error(
        "Resend testing mode: can only send to the Resend account email until a domain is verified",
      );
    }
    throw new Error(`Resend ${res.status}: ${body}`);
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("not allowed", { status: 400 });
  }

  const payload = await req.text();
  const headers = Object.fromEntries(req.headers);
  const rawSecret = String(Deno.env.get("SEND_EMAIL_HOOK_SECRET") || "");
  const hookSecret = rawSecret.replace(/^v1,whsec_/, "");
  if (!hookSecret) {
    return Response.json(
      { error: { message: "SEND_EMAIL_HOOK_SECRET missing", http_code: 500 } },
      { status: 500 },
    );
  }

  try {
    const wh = new Webhook(hookSecret);
    const event = wh.verify(payload, headers) as HookPayload;
    const email = String(event.user?.email || "").trim();
    const token = String(event.email_data?.token || "").trim();
    const action = String(event.email_data?.email_action_type || "magiclink");
    if (!email || !token) {
      throw new Error("Missing email or token in hook payload");
    }

    const subject = subjectFor(action, token);
    const html = htmlFor(token, action);
    const text =
      `Hafiz verification code: ${token}\n\nEnter this code in the Hafiz app. It expires in one hour.`;
    await sendWithResend(email, subject, html, text);
    return Response.json({});
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("auth-send-email failed:", message);
    return Response.json(
      { error: { message, http_code: 500 } },
      { status: 500 },
    );
  }
});
