import { revalidateTag } from "next/cache";
import { countDownload, getRecipe } from "@/lib/server/db";
import { recipeTag } from "@/lib/server/data";

/** FilmLab transfer document for one recipe — import it in the iOS app (Library › Import). */
export async function GET(_request: Request, ctx: RouteContext<"/api/recipes/[slug]/export">) {
  const { slug } = await ctx.params;
  const row = getRecipe(slug);
  if (!row) return Response.json({ error: "Not found" }, { status: 404 });
  countDownload(row.slug);
  revalidateTag(recipeTag(row.slug), "max");
  const doc = { format: "filmlab.recipes", schemaVersion: 1, exportedAt: new Date().toISOString(), appVersion: "web", recipes: [row.recipe] };
  return new Response(JSON.stringify(doc, null, 2), {
    headers: {
      "content-type": "application/json",
      "content-disposition": `attachment; filename="${row.slug}.filmlab.json"`,
    },
  });
}
