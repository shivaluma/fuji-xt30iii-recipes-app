import { Suspense } from "react";
import Link from "next/link";
import type { Metadata } from "next";
import { Search } from "lucide-react";
import { RecipeCard } from "@/components/recipe/recipe-card";
import { Skeleton } from "@/components/ui/skeleton";
import { FILM_SIMULATION_NAMES, FILM_SIMULATIONS, type FilmSimulation } from "@/lib/recipe/schema";
import { publishedRecipes, toCard } from "@/lib/server/data";
import { cn } from "@/lib/utils";

export const metadata: Metadata = { title: "Recipes" };

const chip = (active: boolean) =>
  cn("shrink-0 rounded-full border px-4 py-2 text-sm font-semibold transition-all duration-200 active:scale-95",
    active ? "border-primary bg-accent text-primary" : "border-hairline bg-surface hover:border-white/25");

async function Results({ searchParams }: { searchParams: PageProps<"/recipes">["searchParams"] }) {
  const sp = await searchParams;
  const sim = typeof sp.sim === "string" && (FILM_SIMULATIONS as readonly string[]).includes(sp.sim) ? (sp.sim as FilmSimulation) : undefined;
  const q = typeof sp.q === "string" && sp.q.trim() ? sp.q.trim().slice(0, 80) : undefined;
  const recipes = (await publishedRecipes(sim, q)).map(toCard);
  const all = await publishedRecipes();
  const available = FILM_SIMULATIONS.filter((s) => all.some((r) => r.filmSimulation === s));
  const qs = (next: { sim?: string }) => {
    const p = new URLSearchParams();
    if (next.sim) p.set("sim", next.sim);
    if (q) p.set("q", q);
    const str = p.toString();
    return str ? `/recipes?${str}` : "/recipes";
  };
  return (
    <>
      <form action="/recipes" className="relative">
        {sim && <input type="hidden" name="sim" value={sim} />}
        <Search className="pointer-events-none absolute left-5 top-1/2 size-5 -translate-y-1/2 text-muted-foreground" />
        <input name="q" defaultValue={q} placeholder="Search recipes, simulations, moods…" aria-label="Search recipes"
          className="h-14 w-full rounded-full border border-hairline bg-surface pl-14 pr-5 text-base outline-none transition-colors placeholder:text-tertiary focus:border-primary" />
      </form>
      <div className="-mx-5 flex gap-2 overflow-x-auto px-5 pb-1 [scrollbar-width:none]">
        <Link href={qs({})} className={chip(!sim)}>All</Link>
        {available.map((s) => <Link key={s} href={qs({ sim: s })} className={chip(sim === s)}>{FILM_SIMULATION_NAMES[s]}</Link>)}
      </div>
      {recipes.length === 0 ? (
        <p className="py-24 text-center text-muted-foreground">No recipes match{q ? ` “${q}”` : ""}.</p>
      ) : (
        <div className="grid grid-cols-2 gap-x-5 gap-y-9 md:grid-cols-3 lg:grid-cols-4">
          {recipes.map((r, i) => (
            <div key={r.slug} className="animate-in fade-in slide-in-from-bottom-4 fill-mode-both duration-700 motion-reduce:animate-none" style={{ animationDelay: `${Math.min(i, 12) * 50}ms` }}>
              <RecipeCard r={r} />
            </div>
          ))}
        </div>
      )}
    </>
  );
}

export default function RecipesPage({ searchParams }: PageProps<"/recipes">) {
  return (
    <div className="mx-auto max-w-6xl space-y-7 px-5 pb-24 pt-28">
      <div className="animate-in fade-in slide-in-from-bottom-4 fill-mode-both duration-700 motion-reduce:animate-none">
        <h1 className="font-display text-5xl font-bold tracking-tight sm:text-6xl">Recipes</h1>
        <p className="mt-2 text-lg text-muted-foreground">Looks for the X-T30 III — preview any of them on your own photo.</p>
      </div>
      <Suspense fallback={<div className="grid grid-cols-2 gap-5 md:grid-cols-4">{Array.from({ length: 8 }, (_, i) => <Skeleton key={i} className="aspect-square rounded-card" />)}</div>}>
        <Results searchParams={searchParams} />
      </Suspense>
    </div>
  );
}
