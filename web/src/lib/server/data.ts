import "server-only";
import { cacheLife, cacheTag } from "next/cache";
import { getRecipe, listRecipes } from "./db";

// Cached public reads. Mutations call revalidateTag(RECIPES_TAG, "max") / the per-recipe tag.
export const RECIPES_TAG = "recipes";
export const recipeTag = (slug: string) => `recipe:${slug}`;

export async function publishedRecipes(simulation?: string, query?: string) {
  "use cache";
  cacheLife("hours");
  cacheTag(RECIPES_TAG);
  return listRecipes({ simulation, query });
}

export async function publishedRecipe(slug: string) {
  "use cache";
  cacheLife("hours");
  cacheTag(RECIPES_TAG, recipeTag(slug));
  return getRecipe(slug);
}

import type { RecipeRow } from "./db";
import type { RecipeCardData } from "@/components/recipe/recipe-card";
import { inferGeneration } from "@/lib/recipe/cameras";

export const toCard = (r: RecipeRow): RecipeCardData => ({
  slug: r.slug, name: r.name, filmSimulation: r.filmSimulation, settings: r.recipe.settings,
  cover: r.coverFile ? { url: `/api/media/${r.coverFile}`, kind: r.coverKind } : null,
  author: r.recipe.provenance.author ?? null,
  generation: inferGeneration(r.recipe),
});
