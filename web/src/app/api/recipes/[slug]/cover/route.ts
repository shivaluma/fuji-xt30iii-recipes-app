import { revalidateTag } from "next/cache";
import { requireAdmin } from "@/lib/server/auth";
import { addPhoto, getRecipe, type CoverKind } from "@/lib/server/db";
import { RECIPES_TAG, recipeTag } from "@/lib/server/data";
import { PHOTO_KINDS, storeUpload } from "@/lib/server/uploads";

/**
 * POST multipart/form-data: file=<image>, kind=approximate-preview|camera-jpeg|photo.
 * Adds the image to the recipe's photos and makes it the cover. Upload only images you own; the
 * kind is shown on the site so previews are never mistaken for camera output.
 */
export async function POST(request: Request, ctx: RouteContext<"/api/recipes/[slug]/cover">) {
  const denied = requireAdmin(request);
  if (denied) return denied;
  const { slug } = await ctx.params;
  if (!getRecipe(slug, { includeDrafts: true })) return Response.json({ error: "Not found" }, { status: 404 });
  const form = await request.formData().catch(() => null);
  const kind = (form?.get("kind") ?? "photo") as CoverKind;
  if (!PHOTO_KINDS.includes(kind)) return Response.json({ error: "Invalid kind" }, { status: 400 });
  const stored = await storeUpload(form?.get("file"));
  if (stored instanceof Response) return stored;
  const row = addPhoto(slug, stored, kind, { asCover: true });
  revalidateTag(RECIPES_TAG, "max");
  revalidateTag(recipeTag(slug), "max");
  return Response.json({ cover: { url: `/api/media/${stored}`, kind: row?.coverKind } }, { status: 201 });
}
