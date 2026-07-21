export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-hafiz-token, x-platform-token",
  "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
};

export function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

export function error(message: string, status = 400): Response {
  return json({ error: message }, status);
}

export async function readJson(req: Request): Promise<Record<string, unknown>> {
  try {
    const body = await req.json();
    if (body && typeof body === "object" && !Array.isArray(body)) {
      return body as Record<string, unknown>;
    }
  } catch (_) {
    /* empty */
  }
  return {};
}

export function bearerToken(req: Request, headerName = "authorization"): string {
  const h = req.headers.get(headerName) || "";
  if (h.toLowerCase().startsWith("bearer ")) return h.slice(7).trim();
  return (
    req.headers.get("x-hafiz-token") ||
    req.headers.get("x-platform-token") ||
    ""
  ).trim();
}
