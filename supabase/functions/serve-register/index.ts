import { corsHeaders, json } from "../_shared/http.ts";

/** Supabase يمنع تقديم HTML على نطاقه (يُحوَّل إلى text/plain). */
Deno.serve((req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return json({
    message:
      "تسجيل الجامع أصبح من داخل تطبيق حافظ فقط: الشاشة الرئيسية ← تسجيل جامع جديد.",
    app_route: "/register",
  });
});
