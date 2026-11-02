import { revalidateTag } from "next/cache";
import { requireAdmin } from "@/lib/server/auth";
import { MAX_PHOTOS, addPhoto, getRecipe, type CoverKind } from "@/lib/server/db";
import { RECIPES_TAG, recipeTag } from "@/lib/server/data";
import { PHOTO_KINDS, photoJSON, storeUpload } from "@/lib/server/uploads";

/**
 * POST multipart/form-data: one or more `file` parts, each optionally followed by a `kind`
 * (approximate-preview|camera-jpeg|photo; default photo), plus `cover=<index>` to make one of them
 * the cover. The first photo of a recipe becomes the cover automatically. Upload only images you own.
 */
export async function POST(request: Request, ctx: RouteContext<"/api/recipes/[slug]/photos">) {
  const denied = requireAdmin(request);
  if (denied) return denied;
  const { slug } = await ctx.params;
  const row = getRecipe(slug, { includeDrafts: true });
  if (!row) return Response.json({ error: "Not found" }, { status: 404 });
  const form = await request.formData().catch(() => null);
  const files = form?.getAll("file") ?? [];
  const kinds = (form?.getAll("kind") ?? []).map(String);
  const coverIndex = form?.get("cover") != null ? Number(form.get("cover")) : -1;
  if (!files.length) return Response.json({ error: "Missing file" }, { status: 400 });
  if (row.photos.length + files.length > MAX_PHOTOS) return Response.json({ error: `A recipe can have up to ${MAX_PHOTOS} photos` }, { status: 400 });
  const resolvedKinds = files.map((_, i) => (kinds[i] ?? "photo") as CoverKind);
  if (resolvedKinds.some((k) => !PHOTO_KINDS.includes(k))) return Response.json({ error: "Invalid kind" }, { status: 400 });

  let latest = row;
  for (const [i, file] of files.entries()) {
    const stored = await storeUpload(file);
    if (stored instanceof Response) return stored;
    latest = addPhoto(slug, stored, resolvedKinds[i], { asCover: i === coverIndex }) ?? latest;
  }
  revalidateTag(RECIPES_TAG, "max");
  revalidateTag(recipeTag(slug), "max");
  return Response.json({ photos: latest.photos.map((p) => photoJSON(p, latest.coverFile)) }, { status: 201 });
}
