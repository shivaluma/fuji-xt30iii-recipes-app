import fs from "node:fs";
import path from "node:path";
import { UPLOAD_DIR } from "@/lib/server/db";

const TYPES: Record<string, string> = { jpg: "image/jpeg", png: "image/png", webp: "image/webp" };

export async function GET(_request: Request, ctx: RouteContext<"/api/media/[file]">) {
  const { file } = await ctx.params;
  // Only server-generated names (uuid.ext) — no path traversal.
  if (!/^[0-9a-f-]{36}\.(jpg|png|webp)$/.test(file)) return new Response("Not found", { status: 404 });
  const full = path.join(/*turbopackIgnore: true*/ UPLOAD_DIR, file);
  if (!fs.existsSync(/*turbopackIgnore: true*/ full)) return new Response("Not found", { status: 404 });
  return new Response(fs.readFileSync(/*turbopackIgnore: true*/ full), {
    headers: { "content-type": TYPES[file.split(".").pop()!], "cache-control": "public, max-age=31536000, immutable" },
  });
}
