import "server-only";
import { timingSafeEqual } from "node:crypto";

/**
 * Single-owner write access: `Authorization: Bearer <ADMIN_TOKEN>`. Reads are public.
 * Returns an error Response, or null when authorized.
 */
export function requireAdmin(request: Request): Response | null {
  const expected = process.env.ADMIN_TOKEN;
  if (!expected || expected.length < 16) {
    return Response.json({ error: "Writes are disabled: set ADMIN_TOKEN (16+ characters) on the server." }, { status: 503 });
  }
  const header = request.headers.get("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  const a = Buffer.from(token), b = Buffer.from(expected);
  if (a.length !== b.length || !timingSafeEqual(a, b)) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }
  return null;
}

/** Tiny in-memory rate limiter for expensive endpoints (per process). */
const hits = new Map<string, number[]>();
export function rateLimit(key: string, max: number, windowMs: number): boolean {
  const now = Date.now();
  const recent = (hits.get(key) ?? []).filter((t) => now - t < windowMs);
  if (recent.length >= max) { hits.set(key, recent); return false; }
  recent.push(now);
  hits.set(key, recent);
  return true;
}
