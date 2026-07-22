import { corsHeaders, json } from "../_shared/http.ts";

/** Supabase يمنع تقديم HTML على نطاقه. الإدارة عبر تطبيق hafiz_platform المنفصل. */
Deno.serve((req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return json({
    message:
      "إدارة المنصة عبر تطبيق «hafiz_platform» المنفصل (مجلد platform_app في المستودع).",
    app: "platform_app",
  });
});
