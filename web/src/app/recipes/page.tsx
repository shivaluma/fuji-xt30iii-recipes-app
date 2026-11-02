import { Suspense } from "react";
import Link from "next/link";
import type { Metadata } from "next";
import { RecipeCard } from "@/components/recipe/recipe-card";
import { Skeleton } from "@/components/ui/skeleton";
import { FILM_SIMULATION_NAMES, FILM_SIMULATIONS, type FilmSimulation } from "@/lib/recipe/schema";
import { publishedRecipes, toCard } from "@/lib/server/data";

export const metadata: Metadata = { title: "Recipes" };

async function Results({ searchParams }: { searchParams: PageProps<"/recipes">["searchParams"] }) {
  const sp = await searchParams;
  const sim = typeof sp.sim === "string" && (FILM_SIMULATIONS as readonly string[]).includes(sp.sim) ? (sp.sim as FilmSimulation) : undefined;
  const q = typeof sp.q === "string" && sp.q.trim() ? sp.q.trim().slice(0, 80) : undefined;
  const recipes = (await publishedRecipes(sim, q)).map(toCard);
  return (
    <>
      <form className="flex gap-2" action="/recipes">
        {sim && <input type="hidden" name="sim" value={sim} />}
        <input name="q" defaultValue={q} placeholder="Search recipes, tags, settings…"
          className="h-11 w-full rounded-full border border-border bg-card px-5 text-sm outline-none focus:border-primary" />
      </form>
      <div className="flex flex-wrap gap-2">
        <Link href={q ? `/recipes?q=${encodeURIComponent(q)}` : "/recipes"}
          className={`rounded-full border px-3.5 py-1.5 text-sm font-medium ${!sim ? "border-primary text-primary" : "border-border bg-card"}`}>All</Link>
        {FILM_SIMULATIONS.map((s) => (
          <Link key={s} href={`/recipes?sim=${s}${q ? `&q=${encodeURIComponent(q)}` : ""}`}
            className={`rounded-full border px-3.5 py-1.5 text-sm font-medium ${sim === s ? "border-primary text-primary" : "border-border bg-card"}`}>
            {FILM_SIMULATION_NAMES[s]}
          </Link>
        ))}
      </div>
      {recipes.length === 0 ? (
        <p className="py-16 text-center text-muted-foreground">No recipes match.</p>
      ) : (
        <div className="grid grid-cols-2 gap-5 md:grid-cols-3 lg:grid-cols-4">
          {recipes.map((r) => <RecipeCard key={r.slug} r={r} />)}
        </div>
      )}
    </>
  );
}

export default function RecipesPage({ searchParams }: PageProps<"/recipes">) {
  return (
    <div className="mx-auto max-w-6xl space-y-6 px-5 py-10 pb-20">
      <h1 className="text-4xl font-bold tracking-tight">Recipes</h1>
      <Suspense fallback={<div className="grid grid-cols-2 gap-5 md:grid-cols-4">{Array.from({ length: 8 }, (_, i) => <Skeleton key={i} className="aspect-square rounded-3xl" />)}</div>}>
        <Results searchParams={searchParams} />
      </Suspense>
    </div>
  );
}
