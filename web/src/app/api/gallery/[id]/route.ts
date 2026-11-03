import { revalidateTag } from "next/cache";
import { z } from "zod";
import { requireAdmin } from "@/lib/server/auth";
import { GalleryError, deleteGalleryPhoto, updateGalleryPhoto } from "@/lib/server/db";
import { GALLERY_TAG } from "@/lib/server/data";
import { galleryJSON } from "@/lib/server/uploads";

const Patch = z.object({
  title: z.string().max(120).optional(),
  caption: z.string().max(1000).optional(),
  /** A recipe slug, or null to unlink. */
  recipe: z.string().max(80).nullable().optional(),
});

/** PATCH {title?, caption?, recipe?: slug | null} — admin only. */
export async function PATCH(request: Request, ctx: RouteContext<"/api/gallery/[id]">) {
  const denied = requireAdmin(request);
  if (denied) return denied;
  const { id } = await ctx.params;
  const parsed = Patch.safeParse(await request.json().catch(() => null));
  if (!parsed.success) return Response.json({ error: "Invalid patch" }, { status: 400 });
  try {
    const item = updateGalleryPhoto(id, { title: parsed.data.title, caption: parsed.data.caption, recipeSlug: parsed.data.recipe });
    if (!item) return Response.json({ error: "Not found" }, { status: 404 });
    revalidateTag(GALLERY_TAG, "max");
    return Response.json({ photo: galleryJSON(item) });
  } catch (e) {
    if (e instanceof GalleryError) return Response.json({ error: e.message }, { status: 400 });
    throw e;
  }
}

export async function DELETE(request: Request, ctx: RouteContext<"/api/gallery/[id]">) {
  const denied = requireAdmin(request);
  if (denied) return denied;
  const { id } = await ctx.params;
  if (!deleteGalleryPhoto(id)) return Response.json({ error: "Not found" }, { status: 404 });
  revalidateTag(GALLERY_TAG, "max");
  return new Response(null, { status: 204 });
}
