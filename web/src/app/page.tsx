import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { RecipeCard } from "@/components/recipe/recipe-card";
import { FILM_SIMULATION_NAMES, FILM_SIMULATIONS } from "@/lib/recipe/schema";
import { publishedRecipes, toCard } from "@/lib/server/data";

export default async function Home() {
  const recipes = (await publishedRecipes()).map(toCard);
  const sims = FILM_SIMULATIONS.filter((s) => recipes.some((r) => r.filmSimulation === s));
  return (
    <div className="mx-auto max-w-6xl px-5 pb-20">
      <section className="py-14 sm:py-20">
        <p className="text-sm font-semibold uppercase tracking-widest text-primary">Fujifilm X-T30 III</p>
        <h1 className="mt-3 max-w-3xl text-4xl font-bold tracking-tight sm:text-6xl">Film recipes you can try before you shoot.</h1>
        <p className="mt-5 max-w-2xl text-lg text-muted-foreground">
          Browse recipes, preview them on a sample or your own photo right in the browser, then import them into the FilmLab iPhone app.
        </p>
        <Link href="/recipes" className="mt-8 inline-flex items-center gap-2 rounded-full bg-primary px-5 py-3 font-semibold text-primary-foreground">
          Browse recipes <ArrowRight className="size-4" />
        </Link>
      </section>

      <section className="space-y-4">
        <h2 className="text-2xl font-bold">Browse by simulation</h2>
        <div className="flex flex-wrap gap-2">
          {sims.map((s) => (
            <Link key={s} href={`/recipes?sim=${s}`} className="rounded-full border border-border bg-card px-4 py-2 text-sm font-semibold hover:border-primary hover:text-primary">
              {FILM_SIMULATION_NAMES[s]}
            </Link>
          ))}
        </div>
      </section>

      <section className="mt-14 space-y-5">
        <div className="flex items-end justify-between">
          <div>
            <h2 className="text-2xl font-bold">Latest recipes</h2>
            <p className="text-muted-foreground">Fresh in the collection</p>
          </div>
          <Link href="/recipes" className="inline-flex items-center gap-1 font-semibold text-primary">See all <ArrowRight className="size-4" /></Link>
        </div>
        <div className="grid grid-cols-2 gap-5 md:grid-cols-3 lg:grid-cols-4">
          {recipes.slice(0, 8).map((r) => <RecipeCard key={r.slug} r={r} />)}
        </div>
      </section>
    </div>
  );
}
