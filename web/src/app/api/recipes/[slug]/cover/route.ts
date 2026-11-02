import { randomUUID } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { revalidateTag } from "next/cache";
import { requireAdmin } from "@/lib/server/auth";
import { setCover, getRecipe, UPLOAD_DIR, type CoverKind } from "@/lib/server/db";
import { RECIPES_TAG, recipeTag } from "@/lib/server/data";

const TYPES: Record<string, string> = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" };
const KINDS: CoverKind[] = ["approximate-preview", "camera-jpeg", "photo"];
const MAX_BYTES = 10 * 1024 * 1024;

/**
 * POST multipart/form-data: file=<image>, kind=approximate-preview|camera-jpeg|photo.
 * Upload only images you own. The kind is shown on the site so previews are never mistaken for camera output.
 */
export async function POST(request: Request, ctx: RouteContext<"/api/recipes/[slug]/cover">) {
  const denied = requireAdmin(request);
  if (denied) return denied;
  const { slug } = await ctx.params;
  if (!getRecipe(slug, { includeDrafts: true })) return Response.json({ error: "Not found" }, { status: 404 });
  const form = await request.formData().catch(() => null);
  const file = form?.get("file");
  const kind = (form?.get("kind") ?? "photo") as CoverKind;
  if (!(file instanceof File)) return Response.json({ error: "Missing file" }, { status: 400 });
  if (!TYPES[file.type]) return Response.json({ error: "Use JPEG, PNG or WebP" }, { status: 415 });
  if (file.size > MAX_BYTES) return Response.json({ error: "Image is larger than 10 MB" }, { status: 413 });
  if (!KINDS.includes(kind)) return Response.json({ error: "Invalid kind" }, { status: 400 });
  const name = `${randomUUID()}.${TYPES[file.type]}`;
  fs.mkdirSync(/*turbopackIgnore: true*/ UPLOAD_DIR, { recursive: true });
  fs.writeFileSync(/*turbopackIgnore: true*/ path.join(/*turbopackIgnore: true*/ UPLOAD_DIR, name), Buffer.from(await file.arrayBuffer()));
  const row = setCover(slug, name, kind);
  revalidateTag(RECIPES_TAG, "max");
  revalidateTag(recipeTag(slug), "max");
  return Response.json({ cover: { url: `/api/media/${name}`, kind: row?.coverKind } }, { status: 201 });
}
