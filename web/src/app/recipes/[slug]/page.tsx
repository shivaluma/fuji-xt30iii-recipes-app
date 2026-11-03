import { notFound } from "next/navigation";
import Link from "next/link";
import type { Metadata } from "next";
import { ArrowLeft, ArrowUpRight, Download } from "lucide-react";
import { HeroPreview } from "@/components/recipe/hero-preview";
import { PhotoGallery } from "@/components/recipe/photo-gallery";
import { RecipePreview } from "@/components/recipe/recipe-preview";
import { SettingsGrid } from "@/components/recipe/settings-grid";
import { ShareButton } from "@/components/recipe/share-button";
import { WorksOn } from "@/components/recipe/works-on";
import { GENERATION_LABEL, inferGeneration } from "@/lib/recipe/cameras";
import { Reveal } from "@/components/site/reveal";
import { FILM_SIMULATION_NAMES, type FieldKey } from "@/lib/recipe/schema";
import { GalleryGrid } from "@/components/gallery/gallery-grid";
import { publishedGallery, publishedRecipe, publishedRecipes, toTile } from "@/lib/server/data";
import { JsonLd } from "@/components/site/json-ld";
import { SITE } from "@/lib/site-config";

/** Prerender published recipes; new ones render on first request. (Cache Components needs ≥1 entry.) */
export async function generateStaticParams() {
  const rows = await publishedRecipes();
  return rows.length ? rows.map((r) => ({ slug: r.slug })) : [{ slug: "none" }];
}

export async function generateMetadata({ params }: PageProps<"/recipes/[slug]">): Promise<Metadata> {
  const r = await publishedRecipe((await params).slug);
  if (!r) return { title: "Recipe not found", robots: { index: false } };
  const title = `${r.name} — ${FILM_SIMULATION_NAMES[r.filmSimulation]} recipe`;
  const description = describe(r);
  const url = `/recipes/${r.slug}`;
  const author = r.recipe.provenance.author ?? (r.recipe.provenance.kind === "filmLabOriginal" ? "FilmLab" : undefined);
  return {
    title,
    description,
    alternates: { canonical: url },
    openGraph: {
      type: "article", url, title: `${title} · FilmLab`, description,
      publishedTime: r.publishedAt ?? undefined, modifiedTime: r.updatedAt, authors: author ? [author] : undefined,
    },
    twitter: { card: "summary_large_image", title: `${title} · FilmLab`, description },
  };
}

/** Search snippet: the curator's summary, else a generated line naming the look and the cameras. */
function describe(r: NonNullable<Awaited<ReturnType<typeof publishedRecipe>>>) {
  const g = inferGeneration(r.recipe);
  const base = `${r.name}: a ${FILM_SIMULATION_NAMES[r.filmSimulation]} film simulation recipe for Fujifilm ${g ? GENERATION_LABEL[g] : "X-Trans"} cameras.`;
  const text = r.summary ? `${r.summary.trim()} ${base}` : `${base} Full settings, compatible bodies, and a live preview on your own photo.`;
  return text.length > 300 ? `${text.slice(0, 297).trimEnd()}…` : text;
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
  const shotWith = await publishedGallery(row.slug);
  const settingCount = 1 + (Object.keys(s) as (FieldKey | "filmSimulation")[])
    .filter((k) => k !== "filmSimulation" && (s[k as FieldKey] as { state: string }).state === "value").length;
  const bestFor = [...new Set([...r.tags, ...r.moods.map((m) => MOOD_FALLBACK[m]).filter(Boolean)])]
    .map((t) => BEST_FOR[t]).filter(Boolean);
  const author = r.provenance.author ?? (r.provenance.kind === "filmLabOriginal" ? "FilmLab" : null);
  const generation = inferGeneration(r);
  const madeFor = r.compatibleCameras.find((c) => c !== "X-T30 III") ?? null;

  const pageUrl = `${SITE.url}/recipes/${row.slug}`;
  const jsonLd = {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "CreativeWork", "@id": `${pageUrl}#recipe`, url: pageUrl, name: r.name, description: describe(row),
        genre: "Film simulation recipe", inLanguage: "en",
        about: [{ "@type": "Thing", name: `${FILM_SIMULATION_NAMES[s.filmSimulation]} film simulation` }, ...(generation ? [{ "@type": "Thing", name: `Fujifilm ${GENERATION_LABEL[generation]}` }] : [])],
        keywords: [FILM_SIMULATION_NAMES[s.filmSimulation], ...(generation ? [GENERATION_LABEL[generation]] : []), ...bestFor].join(", "),
        image: row.photos.length ? row.photos.map((p) => `${SITE.url}/api/media/${p.file}`) : `${pageUrl}/opengraph-image`,
        ...(row.publishedAt ? { datePublished: row.publishedAt } : {}),
        dateModified: row.updatedAt,
        ...(author ? { author: author === "FilmLab" ? { "@id": `${SITE.url}/#org` } : { "@type": "Person", name: author } } : {}),
        publisher: { "@id": `${SITE.url}/#org` },
        isPartOf: { "@id": `${SITE.url}/#website` },
      },
      {
        "@type": "BreadcrumbList",
        itemListElement: [
          { "@type": "ListItem", position: 1, name: "FilmLab", item: SITE.url },
          { "@type": "ListItem", position: 2, name: "Recipes", item: `${SITE.url}/recipes` },
          { "@type": "ListItem", position: 3, name: r.name, item: pageUrl },
        ],
      },
    ],
  };

  return (
    <>
      <JsonLd data={jsonLd} />
      <div className="flex items-center justify-between gap-3">
        <Link href="/recipes" className="group inline-flex items-center gap-1.5 text-sm font-medium transition-opacity hover:opacity-60">
          <ArrowLeft className="size-4 transition-transform group-hover:-translate-x-0.5" /> All recipes
        </Link>
        <ShareButton title={r.name} />
      </div>

      <article className="mt-10 grid gap-14 animate-in fade-in slide-in-from-bottom-4 fill-mode-both duration-700 ease-out motion-reduce:animate-none lg:grid-cols-[1.15fr_1fr] lg:gap-20">
        <div className="lg:sticky lg:top-24 lg:self-start">
          {row.photos.length > 0 ? (
            <PhotoGallery
              name={r.name}
              photos={[...row.photos].sort((a, b) => Number(b.file === row.coverFile) - Number(a.file === row.coverFile))
                .map((p) => ({ id: p.id, url: `/api/media/${p.file}`, kind: p.kind }))}
            />
          ) : (
            <HeroPreview settings={s} />
          )}
        </div>

        <div className="flex flex-col gap-12">
          <header>
            <p className="flex flex-wrap items-center gap-x-3 gap-y-2 text-xs font-medium uppercase tracking-[.08em] text-muted-foreground">
              {FILM_SIMULATION_NAMES[s.filmSimulation]}
              {generation && <span className="rounded-full bg-foreground px-2.5 py-1 tracking-normal text-background normal-case">{GENERATION_LABEL[generation]}</span>}
            </p>
            <h1 className="mt-3 font-display text-5xl font-normal leading-[0.92] tracking-[-0.05em] sm:text-6xl">{r.name}</h1>
            {r.summary && <p className="mt-6 text-lg leading-relaxed text-muted-foreground">{r.summary}</p>}
          </header>

          <dl className="grid grid-cols-2 gap-6 border-y border-hairline py-6 text-sm sm:grid-cols-4">
            {author && <div><dt className="text-tertiary">Created by</dt><dd className="mt-1 truncate font-medium">{author}</dd></div>}
            {madeFor && <div><dt className="text-tertiary">Made on</dt><dd className="mt-1 truncate font-medium">{madeFor}</dd></div>}
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

          <WorksOn settings={s} />

          {r.provenance.note && <p className="text-xs text-tertiary">{r.provenance.note}</p>}
        </div>
      </article>

      {shotWith.length > 0 && (
        <section className="mt-40 space-y-10 sm:mt-56">
          <Reveal className="flex flex-wrap items-end justify-between gap-4">
            <h2 className="font-display text-5xl font-normal uppercase leading-[0.88] tracking-[-0.05em] sm:text-6xl">Shot with this recipe</h2>
            <Link href={`/gallery?recipe=${row.slug}`} className="inline-flex items-center gap-1 text-sm font-medium transition-opacity hover:opacity-60">
              See in the gallery <ArrowUpRight className="size-3.5" />
            </Link>
          </Reveal>
          <GalleryGrid photos={shotWith.slice(0, 6).map((g) => ({ ...toTile(g), recipe: null }))} />
        </section>
      )}

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
