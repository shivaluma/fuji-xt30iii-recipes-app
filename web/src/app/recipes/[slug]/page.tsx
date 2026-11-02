import { notFound } from "next/navigation";
import Link from "next/link";
import type { Metadata } from "next";
import { AtSign, CalendarDays, Camera, Download, Film, X } from "lucide-react";
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion";
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
  landscape: "🏞️ Landscape", travel: "✈️ Travel", nature: "🌿 Nature", sunset: "🌅 Golden hour", portrait: "👤 Portraits",
  overcast: "☁️ Overcast", street: "🚶 Street", urban: "🏙️ Urban", architecture: "🏛️ Architecture", night: "🌙 Night",
  interior: "🪟 Indoors", food: "🍜 Food", bw: "⚫ Black & white", cinematic: "🎬 Cinematic", everyday: "📷 Everyday", vintage: "🎞️ Vintage",
};
const MOOD_FALLBACK: Record<string, string> = { cinematic: "cinematic", vintage: "vintage", blackAndWhite: "bw" };

const dateFmt = new Intl.DateTimeFormat("en", { year: "numeric", month: "long", day: "numeric" });

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
  const handle = author?.startsWith("@") ? author : null;

  return (
    <>
      <div className="animate-in fade-in zoom-in-95 fill-mode-both duration-500 ease-out motion-reduce:animate-none">
        <article className="relative grid gap-8 rounded-[32px] border border-hairline bg-[#121213] p-4 sm:p-6 lg:grid-cols-[1.35fr_1fr] lg:gap-12 lg:p-8">
          <div className="z-30 flex justify-end gap-2 lg:absolute lg:right-8 lg:top-8">
            <ShareButton title={r.name} />
            <Link href="/recipes" aria-label="Close" className="grid size-11 place-items-center rounded-full border border-hairline bg-surface-raised transition-colors hover:bg-white/10">
              <X className="size-5" />
            </Link>
          </div>

          <div className="lg:sticky lg:top-24 lg:self-start lg:pt-16">
            {row.coverFile ? (
              <figure className="w-full">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={`/api/media/${row.coverFile}`} alt={`Sample photo for ${r.name}`} className="mx-auto max-h-[78vh] w-auto rounded-small object-contain" />
                <figcaption className="mt-3 text-center text-xs text-tertiary">
                  {row.coverKind === "camera-jpeg" ? "JPEG made by the camera with this recipe" :
                    row.coverKind === "approximate-preview" ? "Approximate preview by FilmLab — not camera output" : "Sample photo"}
                </figcaption>
              </figure>
            ) : (
              <HeroPreview settings={s} />
            )}
          </div>

          <div className="flex flex-col gap-6 lg:pt-16">
            <div>
              <p className="flex items-center gap-2 text-sm font-bold uppercase tracking-[.2em] text-muted-foreground">
                <Film className="size-4 text-primary" /> {FILM_SIMULATION_NAMES[s.filmSimulation]}
              </p>
              <h1 className="mt-3 font-display text-4xl font-bold leading-none tracking-tight sm:text-6xl">{r.name}</h1>
            </div>

            {author && (
              <div>
                <p className="text-xs font-bold uppercase tracking-[.18em] text-tertiary">Created by</p>
                {handle ? (
                  <span className="mt-2 inline-flex items-center gap-2 rounded-full border border-hairline bg-surface px-4 py-2 font-semibold">
                    <AtSign className="size-4 text-primary" />{handle.slice(1)}
                  </span>
                ) : (
                  <p className="mt-1 text-lg font-semibold">{author}</p>
                )}
              </div>
            )}

            {r.summary && <p className="text-lg leading-relaxed text-muted-foreground">{r.summary}</p>}

            <div className="flex flex-wrap gap-x-7 gap-y-2 border-y border-hairline py-4 text-muted-foreground">
              <span className="inline-flex items-center gap-2"><Download className="size-5" />{row.downloads} download{row.downloads === 1 ? "" : "s"}</span>
              {row.publishedAt && <span className="inline-flex items-center gap-2"><CalendarDays className="size-5" />Published {dateFmt.format(new Date(row.publishedAt))}</span>}
            </div>

            {bestFor.length > 0 && (
              <div>
                <p className="font-semibold">Works best for</p>
                <div className="mt-3 flex flex-wrap gap-2">
                  {bestFor.map((b) => <span key={b} className="rounded-full border border-hairline bg-surface px-4 py-2 font-semibold">{b}</span>)}
                </div>
              </div>
            )}

            <div className="rounded-card border border-white/12 bg-surface p-5">
              <div className="flex flex-wrap items-center gap-4">
                <Camera className="size-6 text-muted-foreground" />
                <p className="mr-auto font-display text-lg font-bold leading-snug">Write this look to<br className="hidden sm:block" /> your camera</p>
                <a href={`/api/recipes/${row.slug}/export`} className="inline-flex items-center gap-2 rounded-small bg-primary px-5 py-3 font-bold text-primary-foreground transition-transform active:scale-95">
                  <Download className="size-5" /> Get recipe file
                </a>
              </div>
              <p className="mt-3 text-sm text-muted-foreground">Import into the FilmLab iPhone app (Library › Import), then send it to a C1–C7 slot.</p>
            </div>

            <Accordion defaultValue={["settings"]}>
              <AccordionItem value="settings" className="border-hairline">
                <AccordionTrigger className="py-4 font-display text-xl font-bold hover:no-underline">
                  <span className="mr-auto">Recipe settings</span>
                  <span className="mr-2 text-base font-medium text-muted-foreground">{settingCount} settings</span>
                </AccordionTrigger>
                <AccordionContent className="pb-2">
                  <SettingsGrid settings={s} />
                  <p className="mt-3 text-xs text-tertiary">“—” means the recipe doesn&apos;t set it, so the camera keeps its own value.</p>
                </AccordionContent>
              </AccordionItem>
            </Accordion>

            {r.provenance.note && <p className="text-xs text-tertiary">{r.provenance.note}</p>}
          </div>
        </article>
      </div>

      <section className="mt-20 grid gap-10 lg:grid-cols-[1fr_1.4fr]">
        <Reveal>
          <h2 className="font-display text-3xl font-bold tracking-tight sm:text-4xl">Try it on <span className="italic text-primary">your</span> photo.</h2>
          <p className="mt-3 text-muted-foreground">Drop in a photo and drag the divider. Rendering happens in your browser; nothing is uploaded.</p>
          {row.body && <div className="mt-8 whitespace-pre-line leading-relaxed text-muted-foreground">{row.body}</div>}
        </Reveal>
        <Reveal delay={0.08}><RecipePreview settings={s} /></Reveal>
      </section>
    </>
  );
}

export default function RecipePage({ params }: PageProps<"/recipes/[slug]">) {
  return (
    <div className="mx-auto max-w-7xl px-4 pb-24 pt-24 sm:px-6">
      <Recipe params={params} />
    </div>
  );
}
