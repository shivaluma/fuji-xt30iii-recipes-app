import Link from "next/link";
import { Film } from "lucide-react";
import { FILM_SIMULATION_NAMES, type FilmSimulation, type RecipeSettings } from "@/lib/recipe/schema";
import { RecipeThumb } from "./recipe-thumb";

export type RecipeCardData = {
  slug: string;
  name: string;
  filmSimulation: FilmSimulation;
  settings: RecipeSettings;
  cover: { url: string; kind: string | null } | null;
  author?: string | null;
};

const coverLabel = (kind: string | null) =>
  kind === "camera-jpeg" ? "Camera JPEG" : kind === "approximate-preview" ? "Approximate preview" : "Photo";

export function RecipeCard({ r }: { r: RecipeCardData }) {
  return (
    <Link href={`/recipes/${r.slug}`} className="group block">
      <div className="relative aspect-square overflow-hidden rounded-3xl border border-border bg-card">
        {r.cover ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={r.cover.url} alt="" className="h-full w-full object-cover transition-transform duration-500 group-hover:scale-[1.03]" />
        ) : (
          <RecipeThumb settings={r.settings} className="h-full w-full object-cover transition-transform duration-500 group-hover:scale-[1.03]" />
        )}
        <span className="absolute bottom-3 right-3 rounded-full bg-black/60 px-3 py-1 text-xs font-semibold backdrop-blur">
          {r.cover ? coverLabel(r.cover.kind) : "Approximate"}
        </span>
      </div>
      <div className="mt-3 px-1">
        <div className="truncate text-lg font-bold">{r.name}</div>
        <div className="mt-0.5 flex items-center gap-1.5 text-sm text-muted-foreground">
          <Film className="size-4 text-primary" /> {FILM_SIMULATION_NAMES[r.filmSimulation]}
          {r.author && <span className="truncate">· {r.author}</span>}
        </div>
      </div>
    </Link>
  );
}
