import Link from "next/link";
import { Film } from "lucide-react";
import { FILM_SIMULATION_NAMES, type FilmSimulation, type RecipeSettings } from "@/lib/recipe/schema";
import { RecipeThumb } from "./recipe-thumb";
import { cn } from "@/lib/utils";

export type RecipeCardData = {
  slug: string;
  name: string;
  filmSimulation: FilmSimulation;
  settings: RecipeSettings;
  cover: { url: string; kind: string | null } | null;
  author?: string | null;
};

const coverLabel = (kind: string | null) =>
  kind === "camera-jpeg" ? "Camera JPEG" : kind === "approximate-preview" ? "Approximate" : "Photo";

/** Large rounded photo card — the web twin of the app's PhotoRecipeCard. */
export function RecipeCard({ r, className }: { r: RecipeCardData; className?: string }) {
  return (
    <Link href={`/recipes/${r.slug}`} className={cn("group block focus-visible:outline-none", className)}>
      <div className="relative aspect-square overflow-hidden rounded-card border border-hairline bg-surface transition-all duration-500 ease-out group-hover:-translate-y-1 group-hover:border-white/20 group-hover:shadow-[0_24px_60px_-20px_rgba(51,166,145,.45)] group-focus-visible:ring-2 group-focus-visible:ring-primary">
        {r.cover ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={r.cover.url} alt="" className="size-full object-cover transition-transform duration-700 ease-out group-hover:scale-[1.06]" />
        ) : (
          <RecipeThumb settings={r.settings} className="size-full object-cover transition-transform duration-700 ease-out group-hover:scale-[1.06]" />
        )}
        <span className="absolute bottom-3 right-3 rounded-full bg-black/55 px-3 py-1.5 text-xs font-bold backdrop-blur-md">
          {r.cover ? coverLabel(r.cover.kind) : "Approximate"}
        </span>
      </div>
      <div className="mt-3 px-1">
        <div className="truncate font-display text-lg font-bold tracking-tight">{r.name}</div>
        <div className="mt-0.5 flex items-center gap-1.5 text-sm text-muted-foreground">
          <Film className="size-4 shrink-0 text-primary" />
          <span className="truncate">{FILM_SIMULATION_NAMES[r.filmSimulation]}{r.author ? ` · ${r.author}` : ""}</span>
        </div>
      </div>
    </Link>
  );
}
