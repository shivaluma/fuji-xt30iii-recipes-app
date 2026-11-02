import Link from "next/link";
import { ArrowUpRight } from "lucide-react";
import { FILM_SIMULATION_NAMES, type FilmSimulation, type RecipeSettings } from "@/lib/recipe/schema";
import { RecipeThumb } from "./recipe-thumb";
import { GENERATION_LABEL, type Generation } from "@/lib/recipe/cameras";
import { cn } from "@/lib/utils";

export type RecipeCardData = {
  slug: string;
  name: string;
  filmSimulation: FilmSimulation;
  settings: RecipeSettings;
  cover: { url: string; kind: string | null } | null;
  author?: string | null;
  generation?: Generation | null;
};

const coverLabel = (kind: string | null) =>
  kind === "camera-jpeg" ? "Camera JPEG" : kind === "approximate-preview" ? "Approximate" : "Photo";

/** Project-style card: big rounded photo, name and simulation underneath. */
export function RecipeCard({ r, className, size = "md" }: { r: RecipeCardData; className?: string; size?: "md" | "lg" }) {
  const img = "size-full object-cover transition-transform duration-700 ease-out group-hover:scale-[1.04]";
  return (
    <Link href={`/recipes/${r.slug}`} className={cn("group block rounded-[var(--fl-radius-card)] focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-foreground", className)}>
      <div className="relative aspect-[4/3] overflow-hidden rounded-[var(--fl-radius-card)] bg-surface">
        {r.cover ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={r.cover.url} alt="" className={img} />
        ) : (
          <RecipeThumb settings={r.settings} className={img} />
        )}
        <span className="absolute left-3 top-3 rounded-full bg-white/90 px-2.5 py-1 text-[11px] font-medium text-black backdrop-blur">
          {r.cover ? coverLabel(r.cover.kind) : "Approximate"}
        </span>
        {r.generation && (
          <span className="absolute right-3 top-3 rounded-full bg-black/70 px-2.5 py-1 text-[11px] font-medium text-white backdrop-blur">
            {GENERATION_LABEL[r.generation]}
          </span>
        )}
      </div>
      <div className="mt-5 flex items-start justify-between gap-4 px-0.5">
        <div className="min-w-0">
          <div className={cn("truncate font-display font-normal tracking-[-0.03em]", size === "lg" ? "text-2xl sm:text-3xl" : "text-xl")}>{r.name}</div>
          <div className="mt-1.5 truncate text-sm text-muted-foreground">
            {FILM_SIMULATION_NAMES[r.filmSimulation]}{r.author ? ` · ${r.author}` : ""}
          </div>
        </div>
        <ArrowUpRight className="mt-1 size-5 shrink-0 text-tertiary transition-all group-hover:-translate-y-0.5 group-hover:translate-x-0.5 group-hover:text-foreground" />
      </div>
    </Link>
  );
}
