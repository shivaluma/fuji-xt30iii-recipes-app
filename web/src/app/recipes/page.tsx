import { Suspense } from "react";
import Link from "next/link";
import type { Metadata } from "next";
import { Search } from "lucide-react";
import { RecipeCard } from "@/components/recipe/recipe-card";
import { CameraFilter } from "@/components/recipe/camera-filter";
import { GENERATIONS, GENERATION_LABEL, cameraById, compatibility, inferGeneration, type Generation } from "@/lib/recipe/cameras";
import { Skeleton } from "@/components/ui/skeleton";
import { FILM_SIMULATION_NAMES, FILM_SIMULATIONS, type FilmSimulation } from "@/lib/recipe/schema";
import { publishedRecipes, toCard } from "@/lib/server/data";
import { cn } from "@/lib/utils";
import { JsonLd } from "@/components/site/json-ld";
import { SITE } from "@/lib/site-config";

export const metadata: Metadata = {
  title: "Fujifilm film simulation recipes",
  description: "Browse film simulation recipes for Fujifilm X-Trans IV and X-Trans V cameras. Filter by look or camera, see the full settings, and preview each recipe on your own photo.",
  // Filtered/search views (?sim, ?gen, ?camera, ?q) all point at the main list.
  alternates: { canonical: "/recipes" },
  openGraph: { url: "/recipes", title: "Fujifilm film simulation recipes · FilmLab" },
  twitter: { card: "summary_large_image", title: "Fujifilm film simulation recipes · FilmLab" },
};

const chip = (active: boolean) =>
  cn("shrink-0 rounded-full border px-3.5 py-1.5 text-sm transition-colors active:scale-[.98]",
    active ? "border-foreground bg-foreground text-background" : "border-hairline hover:border-foreground/30");

async function Results({ searchParams }: { searchParams: PageProps<"/recipes">["searchParams"] }) {
  const sp = await searchParams;
  const sim = typeof sp.sim === "string" && (FILM_SIMULATIONS as readonly string[]).includes(sp.sim) ? (sp.sim as FilmSimulation) : undefined;
  const q = typeof sp.q === "string" && sp.q.trim() ? sp.q.trim().slice(0, 80) : undefined;
  const gen = (GENERATIONS as readonly string[]).includes(String(sp.gen)) ? (sp.gen as Generation) : undefined;
  const camera = typeof sp.camera === "string" ? cameraById(sp.camera) : null;
  const rows = (await publishedRecipes(sim, q))
    .filter((r) => !gen || inferGeneration(r.recipe) === gen)
    .filter((r) => !camera || compatibility(r.recipe.settings, camera).level !== "none");
  const recipes = rows.map(toCard);
  const all = await publishedRecipes();
  const available = FILM_SIMULATIONS.filter((s) => all.some((r) => r.filmSimulation === s));
  const qs = (next: { sim?: string; gen?: string }) => {
    const p = new URLSearchParams();
    if (next.sim) p.set("sim", next.sim);
    if (next.gen) p.set("gen", next.gen);
    else if (camera) p.set("camera", camera.id);
    if (q) p.set("q", q);
    const str = p.toString();
    return str ? `/recipes?${str}` : "/recipes";
  };

  if (all.length === 0) {
    return (
      <div className="rounded-[var(--fl-radius-card)] bg-surface px-8 py-28 text-center">
        <p className="font-display text-3xl font-normal tracking-[-0.03em]">No recipes published yet.</p>
        <p className="mx-auto mt-3 max-w-md text-muted-foreground">The collection is being put together. Meanwhile, try the looks on your own photo.</p>
        <Link href="/#try" className="mt-6 inline-flex rounded-full bg-foreground px-5 py-3 text-sm font-medium text-background transition-opacity hover:opacity-85">Try the preview</Link>
      </div>
    );
  }

  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "CollectionPage",
    name: "Fujifilm film simulation recipes",
    url: `${SITE.url}/recipes`,
    isPartOf: { "@id": `${SITE.url}/#website` },
    mainEntity: {
      "@type": "ItemList",
      numberOfItems: all.length,
      itemListElement: all.map((r, i) => ({ "@type": "ListItem", position: i + 1, url: `${SITE.url}/recipes/${r.slug}`, name: r.name })),
    },
  };

  return (
    <>
      <JsonLd data={jsonLd} />
      <div className="space-y-5">
      <div className="flex flex-col gap-5 border-y border-hairline py-6 lg:flex-row lg:gap-8 lg:items-center">
        <form action="/recipes" className="relative lg:w-80 lg:shrink-0">
          {sim && <input type="hidden" name="sim" value={sim} />}
          <Search className="pointer-events-none absolute left-4 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <input name="q" defaultValue={q} placeholder="Search recipes, moods…" aria-label="Search recipes"
            className="h-11 w-full rounded-full bg-surface pl-11 pr-4 text-sm outline-none ring-foreground/20 transition-shadow placeholder:text-tertiary focus:ring-2" />
        </form>
        <div className="-mx-5 flex gap-2 overflow-x-auto px-5 [scrollbar-width:none] lg:mx-0 lg:px-0">
          <Link href={qs({ gen })} className={chip(!sim)}>All looks</Link>
          {available.map((s) => <Link key={s} href={qs({ sim: s, gen })} className={chip(sim === s)}>{FILM_SIMULATION_NAMES[s]}</Link>)}
        </div>
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <Link href={qs({ sim })} className={chip(!gen && !camera)}>All cameras</Link>
        {GENERATIONS.map((g) => <Link key={g} href={qs({ sim, gen: g })} className={chip(gen === g)}>{GENERATION_LABEL[g]}</Link>)}
        <span className="mx-1 h-5 w-px bg-hairline" aria-hidden />
        <CameraFilter value={camera?.id} />
        {camera && <span className="text-sm text-muted-foreground">Recipes you can dial into your {camera.name}</span>}
      </div>
      </div>
      {recipes.length === 0 ? (
        <p className="py-24 text-center text-muted-foreground">No recipes match{q ? ` “${q}”` : ""}{camera ? ` for the ${camera.name}` : ""}.</p>
      ) : (
        <div className="grid gap-x-8 gap-y-16 sm:grid-cols-2 lg:grid-cols-3 lg:gap-x-10 lg:gap-y-20">
          {recipes.map((r, i) => (
            <div key={r.slug} className="animate-in fade-in slide-in-from-bottom-4 fill-mode-both duration-700 motion-reduce:animate-none" style={{ animationDelay: `${Math.min(i, 9) * 50}ms` }}>
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
    <div className="mx-auto max-w-6xl space-y-16 px-5 pt-12 sm:px-8 sm:pt-20 lg:px-10">
      <div className="flex flex-wrap items-end justify-between gap-4 animate-in fade-in slide-in-from-bottom-4 fill-mode-both duration-700 motion-reduce:animate-none">
        <h1 className="font-display text-7xl font-normal uppercase leading-[0.85] tracking-[-0.055em] sm:text-9xl">Recipes</h1>
        <p className="max-w-xs text-muted-foreground">Looks for Fujifilm X‑Trans IV and V cameras. Preview any of them on your own photo.</p>
      </div>
      <Suspense fallback={<div className="grid gap-8 sm:grid-cols-2 lg:grid-cols-3">{Array.from({ length: 6 }, (_, i) => <Skeleton key={i} className="aspect-[4/3] rounded-[var(--fl-radius-card)]" />)}</div>}>
        <Results searchParams={searchParams} />
      </Suspense>
    </div>
  );
}
