import { OG_SIZE, coverPhoto, defaultPhoto, ogCard } from "@/lib/og";
import { GENERATION_LABEL, inferGeneration } from "@/lib/recipe/cameras";
import { FILM_SIMULATION_NAMES } from "@/lib/recipe/schema";
import { publishedRecipe } from "@/lib/server/data";

export const alt = "FilmLab film recipe card";
export const size = OG_SIZE;
export const contentType = "image/png";

export default async function Image({ params }: { params: Promise<{ slug: string }> }) {
  const r = await publishedRecipe((await params).slug);
  if (!r) return ogCard({ photo: await defaultPhoto(), title: "Film recipes for Fujifilm X-Trans IV & V" });
  const g = inferGeneration(r.recipe);
  return ogCard({
    photo: await coverPhoto(r.coverFile),
    eyebrow: `${FILM_SIMULATION_NAMES[r.filmSimulation]} recipe`,
    title: r.name,
    tag: g ? GENERATION_LABEL[g] : null,
  });
}
