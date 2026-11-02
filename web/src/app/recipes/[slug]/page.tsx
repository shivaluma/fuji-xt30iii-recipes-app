import { notFound } from "next/navigation";
import Link from "next/link";
import type { Metadata } from "next";
import { ArrowLeft, Download } from "lucide-react";
import { HeroPreview } from "@/components/recipe/hero-preview";
import { RecipePreview } from "@/components/recipe/recipe-preview";
import { SettingsGrid } from "@/components/recipe/settings-grid";
import { ShareButton } from "@/components/recipe/share-button";
import { Reveal } from "@/components/site/reveal";
import { FILM_SIMULATION_NAMES, type FieldKey } from "@/lib/recipe/schema";
import { publishedRecipe, publishedRecipes } from "@/lib/server/data";

/** Prerender published recipes; new ones render on first request. (Cache Components needs ≥1 entry.) */
export async function generateStaticParams() {
  const rows = await publishedRecipes();
  return rows.length ? rows.map((r) => ({ slug: r.slug })) : [{ slug: "none" }];
}

export async function generateMetadata({ params }: PageProps<"/recipes/[slug]">): Promise<Metadata> {
  const r = await publishedRecipe((await params).slug);
  return r ? { title: r.name, description: r.summary || `${FILM_SIMULATION_NAMES[r.filmSimulation]} film recipe for the X-T30 III` } : {};
}

const BEST_FOR: Record<string, string> = {
  landscape: "Landscape", travel: "Travel", nature: "Nature", sunset: "Golden hour", portrait: "Portraits",
  overcast: "Overcast", street: "Street", urban: "Urban", architecture: "Architecture", night: "Night",
  interior: "Indoors", food: "Food", bw: "Black & white", cinematic: "Cinematic", everyday: "Everyday", vintage: "Vintage",
};
const MOOD_FALLBACK: Record<string, string> = { cinematic: "cinematic", vintage: "vintage", blackAndWhite: "bw" };

const dateFmt = new Intl.DateTimeFormat("en", { year: "numeric", month: "short", day: "numeric" });

async function Recipe({ params }: { params: PageProps<"/recipes/[slug]">["params"] }) {
  const row = await publishedRecipe((await params).slug);
  if (!row) notFound();
  const r = row.recipe;
  const s = r.settings;
  const settingCount = 1 + (Object.keys(s) as (FieldKey | "filmSimulation")[])
    .filter((k) => k !== "filmSimulation" && (s[k as FieldKey] as { state: string }).state === "value").length;
  const bestFor = [...new Set([...r.tags, ...r.moods.map((m) => MOOD_FALLBACK[m]).filter(Boolean)])]
    .map((t) => BEST_FOR[t]).filter(Boolean);
  const author = r.provenance.author ?? (r.provenance.kind === "filmLabOriginal" ? "FilmLab" : null);

  return (
    <>
      <div className="flex items-center justify-between gap-3">
        <Link href="/recipes" className="group inline-flex items-center gap-1.5 text-sm font-medium transition-opacity hover:opacity-60">
          <ArrowLeft className="size-4 transition-transform group-hover:-translate-x-0.5" /> All recipes
        </Link>
        <ShareButton title={r.name} />
      </div>

      <article className="mt-10 grid gap-14 animate-in fade-in slide-in-from-bottom-4 fill-mode-both duration-700 ease-out motion-reduce:animate-none lg:grid-cols-[1.15fr_1fr] lg:gap-20">
        <div className="lg:sticky lg:top-24 lg:self-start">
          {row.coverFile ? (
            <figure>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={`/api/media/${row.coverFile}`} alt={`Sample photo for ${r.name}`} className="w-full rounded-[var(--fl-radius-card)] bg-surface object-contain" />
              <figcaption className="mt-3 text-xs text-tertiary">
                {row.coverKind === "camera-jpeg" ? "JPEG made by the camera with this recipe" :
                  row.coverKind === "approximate-preview" ? "Approximate preview by FilmLab — not camera output" : "Sample photo"}
              </figcaption>
            </figure>
          ) : (
            <HeroPreview settings={s} />
          )}
        </div>

        <div className="flex flex-col gap-12">
          <header>
            <p className="text-xs font-medium uppercase tracking-[.08em] text-muted-foreground">{FILM_SIMULATION_NAMES[s.filmSimulation]}</p>
            <h1 className="mt-3 font-display text-5xl font-normal leading-[0.92] tracking-[-0.05em] sm:text-6xl">{r.name}</h1>
            {r.summary && <p className="mt-6 text-lg leading-relaxed text-muted-foreground">{r.summary}</p>}
          </header>

          <dl className="grid grid-cols-3 gap-6 border-y border-hairline py-6 text-sm">
            {author && <div><dt className="text-tertiary">Created by</dt><dd className="mt-1 truncate font-medium">{author}</dd></div>}
            {row.publishedAt && <div><dt className="text-tertiary">Published</dt><dd className="mt-1 font-medium">{dateFmt.format(new Date(row.publishedAt))}</dd></div>}
            <div><dt className="text-tertiary">Downloads</dt><dd className="mt-1 font-medium tabular-nums">{row.downloads}</dd></div>
          </dl>

          {bestFor.length > 0 && (
            <div>
              <p className="text-sm text-muted-foreground">Works best for</p>
              <div className="mt-4 flex flex-wrap gap-2.5">
                {bestFor.map((b) => <span key={b} className="rounded-full border border-hairline px-3.5 py-1.5 text-sm">{b}</span>)}
              </div>
            </div>
          )}

          <div className="rounded-[20px] bg-surface p-8">
            <p className="font-display text-2xl font-normal tracking-[-0.03em]">Write this look to your camera</p>
            <p className="mt-3 text-sm leading-relaxed text-muted-foreground">Import the file into the FilmLab iPhone app (Library › Import), then send it to a C1–C7 slot.</p>
            <a href={`/api/recipes/${row.slug}/export`} className="mt-7 inline-flex items-center gap-2 rounded-full bg-foreground px-5 py-3 text-sm font-medium text-background transition-opacity hover:opacity-85 active:scale-[.98]">
              <Download className="size-4" /> Get recipe file
            </a>
          </div>

          <section>
            <div className="mb-6 flex items-baseline justify-between">
              <h2 className="font-display text-2xl font-normal tracking-[-0.03em]">Recipe settings</h2>
              <span className="text-sm text-muted-foreground">{settingCount} settings</span>
            </div>
            <SettingsGrid settings={s} />
            <p className="mt-3 text-xs text-tertiary">“—” means the recipe doesn&apos;t set it, so the camera keeps its own value.</p>
          </section>

          {r.provenance.note && <p className="text-xs text-tertiary">{r.provenance.note}</p>}
        </div>
      </article>

      <section className="mt-40 grid gap-12 sm:mt-56 lg:grid-cols-[1fr_1.6fr] lg:gap-20">
        <Reveal>
          <h2 className="font-display text-5xl font-normal uppercase leading-[0.88] tracking-[-0.05em] sm:text-6xl">Try it on your photo</h2>
          <p className="mt-5 max-w-sm text-muted-foreground">Drop in a photo and drag the divider. Rendering happens in your browser; nothing is uploaded.</p>
          {row.body && <div className="mt-8 whitespace-pre-line leading-relaxed text-muted-foreground">{row.body}</div>}
        </Reveal>
        <Reveal delay={0.08}><RecipePreview settings={s} /></Reveal>
      </section>
    </>
  );
}

export default function RecipePage({ params }: PageProps<"/recipes/[slug]">) {
  return (
    <div className="mx-auto max-w-6xl px-5 pt-8 sm:px-8 sm:pt-14 lg:px-10">
      <Recipe params={params} />
    </div>
  );
}
