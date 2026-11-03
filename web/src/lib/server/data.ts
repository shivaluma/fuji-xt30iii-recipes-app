import "server-only";
import { cacheLife, cacheTag } from "next/cache";
import { getRecipe, listGallery, listRecipes } from "./db";

// Cached public reads. Mutations call revalidateTag(RECIPES_TAG, "max") / the per-recipe tag.
export const RECIPES_TAG = "recipes";
export const recipeTag = (slug: string) => `recipe:${slug}`;

export async function publishedRecipes(simulation?: string, query?: string) {
  "use cache";
  cacheLife("hours");
  cacheTag(RECIPES_TAG);
  return listRecipes({ simulation, query });
}

/** Changes to the gallery revalidate this; recipe edits too (names and publish status show on photos). */
export const GALLERY_TAG = "gallery";

export async function publishedGallery(recipeSlug?: string) {
  "use cache";
  cacheLife("hours");
  cacheTag(GALLERY_TAG, RECIPES_TAG);
  return listGallery({ recipeSlug, publicOnly: true });
}

export async function publishedRecipe(slug: string) {
  "use cache";
  cacheLife("hours");
  cacheTag(RECIPES_TAG, recipeTag(slug));
  return getRecipe(slug);
}

import type { GalleryItem, RecipeRow } from "./db";
import type { GalleryTile } from "@/components/gallery/gallery-grid";
import type { RecipeCardData } from "@/components/recipe/recipe-card";
import { inferGeneration } from "@/lib/recipe/cameras";

export const toCard = (r: RecipeRow): RecipeCardData => ({
  slug: r.slug, name: r.name, filmSimulation: r.filmSimulation, settings: r.recipe.settings,
  cover: r.coverFile ? { url: `/api/media/${r.coverFile}`, kind: r.coverKind } : null,
  author: r.recipe.provenance.author ?? null,
  generation: inferGeneration(r.recipe),
});

export const toTile = (g: GalleryItem): GalleryTile => ({
  id: g.id, url: `/api/media/${g.file}`, title: g.title, caption: g.caption, width: g.width, height: g.height,
  recipe: g.recipe ? { slug: g.recipe.slug, name: g.recipe.name, filmSimulation: g.recipe.filmSimulation } : null,
});
