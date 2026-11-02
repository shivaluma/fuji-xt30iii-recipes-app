import { revalidateTag } from "next/cache";
import { z } from "zod";
import { requireAdmin } from "@/lib/server/auth";
import { deleteRecipe, getRecipe, updateMeta } from "@/lib/server/db";
import { RECIPES_TAG, recipeTag } from "@/lib/server/data";
import { photoJSON } from "@/lib/server/uploads";

export async function GET(request: Request, ctx: RouteContext<"/api/recipes/[slug]">) {
  const { slug } = await ctx.params;
  const drafts = new URL(request.url).searchParams.get("all") === "1" && !requireAdmin(request);
  const row = getRecipe(slug, { includeDrafts: drafts });
  if (!row) return Response.json({ error: "Not found" }, { status: 404 });
  return Response.json({
    recipe: row.recipe, slug: row.slug, status: row.status, body: row.body,
    cover: row.coverFile ? { url: `/api/media/${row.coverFile}`, kind: row.coverKind } : null,
    photos: row.photos.map((p) => photoJSON(p, row.coverFile)),
    publishedAt: row.publishedAt, updatedAt: row.updatedAt,
  });
}

const Patch = z.object({ status: z.enum(["draft", "published"]).optional(), body: z.string().max(20000).optional() });

export async function PATCH(request: Request, ctx: RouteContext<"/api/recipes/[slug]">) {
  const denied = requireAdmin(request);
  if (denied) return denied;
  const { slug } = await ctx.params;
  const parsed = Patch.safeParse(await request.json().catch(() => null));
  if (!parsed.success) return Response.json({ error: "Invalid patch" }, { status: 400 });
  const row = updateMeta(slug, parsed.data);
  if (!row) return Response.json({ error: "Not found" }, { status: 404 });
  revalidateTag(RECIPES_TAG, "max");
  revalidateTag(recipeTag(slug), "max");
  return Response.json({ slug: row.slug, status: row.status });
}

export async function DELETE(request: Request, ctx: RouteContext<"/api/recipes/[slug]">) {
  const denied = requireAdmin(request);
  if (denied) return denied;
  const { slug } = await ctx.params;
  if (!deleteRecipe(slug)) return Response.json({ error: "Not found" }, { status: 404 });
  revalidateTag(RECIPES_TAG, "max");
  revalidateTag(recipeTag(slug), "max");
  return new Response(null, { status: 204 });
}
