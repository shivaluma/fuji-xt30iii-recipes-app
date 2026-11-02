import { revalidateTag } from "next/cache";
import { z } from "zod";
import { requireAdmin } from "@/lib/server/auth";
import { deletePhoto, setCover, updatePhoto } from "@/lib/server/db";
import { RECIPES_TAG, recipeTag } from "@/lib/server/data";
import { PHOTO_KINDS, photoJSON } from "@/lib/server/uploads";

const Patch = z.object({ cover: z.literal(true).optional(), kind: z.enum(PHOTO_KINDS as [string, ...string[]]).optional() });

/** PATCH {cover: true} makes this photo the cover; {kind} changes what the photo is labelled as. */
export async function PATCH(request: Request, ctx: RouteContext<"/api/recipes/[slug]/photos/[id]">) {
  const denied = requireAdmin(request);
  if (denied) return denied;
  const { slug, id } = await ctx.params;
  const parsed = Patch.safeParse(await request.json().catch(() => null));
  if (!parsed.success) return Response.json({ error: "Invalid patch" }, { status: 400 });
  let row = parsed.data.kind ? updatePhoto(slug, id, { kind: parsed.data.kind as never }) : null;
  if (parsed.data.cover) row = setCover(slug, id);
  if (!row) return Response.json({ error: "Not found" }, { status: 404 });
  revalidateTag(RECIPES_TAG, "max");
  revalidateTag(recipeTag(slug), "max");
  return Response.json({ photos: row.photos.map((p) => photoJSON(p, row.coverFile)) });
}

export async function DELETE(request: Request, ctx: RouteContext<"/api/recipes/[slug]/photos/[id]">) {
  const denied = requireAdmin(request);
  if (denied) return denied;
  const { slug, id } = await ctx.params;
  const row = deletePhoto(slug, id);
  if (!row) return Response.json({ error: "Not found" }, { status: 404 });
  revalidateTag(RECIPES_TAG, "max");
  revalidateTag(recipeTag(slug), "max");
  return Response.json({ photos: row.photos.map((p) => photoJSON(p, row.coverFile)) });
}
