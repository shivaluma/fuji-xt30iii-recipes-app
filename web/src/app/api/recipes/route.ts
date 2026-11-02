import { revalidateTag } from "next/cache";
import { z } from "zod";
import { FilmRecipeSchema, TransferDocumentSchema, normalize, validate } from "@/lib/recipe/schema";
import { requireAdmin } from "@/lib/server/auth";
import { listRecipes, upsertRecipe } from "@/lib/server/db";
import { RECIPES_TAG, recipeTag } from "@/lib/server/data";

const summary = (r: ReturnType<typeof listRecipes>[number]) => ({
  id: r.id, slug: r.slug, name: r.name, summary: r.summary, filmSimulation: r.filmSimulation, status: r.status, settings: r.recipe.settings,
  cover: r.coverFile ? { url: `/api/media/${r.coverFile}`, kind: r.coverKind } : null,
  publishedAt: r.publishedAt, updatedAt: r.updatedAt,
});

/** GET /api/recipes?sim=classicChrome&q=night&all=1 (all=1 includes drafts; requires the admin token). */
export async function GET(request: Request) {
  const url = new URL(request.url);
  const all = url.searchParams.get("all") === "1";
  if (all) {
    const denied = requireAdmin(request);
    if (denied) return denied;
  }
  const rows = listRecipes({
    includeDrafts: all,
    simulation: url.searchParams.get("sim") ?? undefined,
    query: url.searchParams.get("q") ?? undefined,
  });
  return Response.json({ recipes: rows.map(summary) });
}

const UpsertBody = z.object({
  recipe: FilmRecipeSchema.optional(),
  document: TransferDocumentSchema.optional(),
  status: z.enum(["draft", "published"]).optional(),
  body: z.string().max(20000).optional(),
}).refine((b) => !!b.recipe !== !!b.document, "Send exactly one of `recipe` or `document`.");

/** POST /api/recipes — create or update by recipe id (FilmLab JSON). Admin only. */
export async function POST(request: Request) {
  const denied = requireAdmin(request);
  if (denied) return denied;
  const parsed = UpsertBody.safeParse(await request.json().catch(() => null));
  if (!parsed.success) return Response.json({ error: "Invalid recipe payload", details: z.treeifyError(parsed.error) }, { status: 400 });
  const recipes = parsed.data.recipe ? [parsed.data.recipe] : parsed.data.document!.recipes;
  const saved = [];
  for (const r of recipes) {
    const settings = normalize(r.settings);
    const errors = validate(settings).filter((i) => i.severity === "error");
    if (errors.length) return Response.json({ error: `“${r.name}” has invalid settings`, issues: errors }, { status: 422 });
    const row = upsertRecipe({ ...r, settings }, { status: parsed.data.status, body: parsed.data.body });
    revalidateTag(recipeTag(row.slug), "max");
    saved.push(summary(row));
  }
  revalidateTag(RECIPES_TAG, "max");
  return Response.json({ recipes: saved }, { status: 201 });
}
