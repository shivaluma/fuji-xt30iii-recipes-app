import Link from "next/link";
import { ArrowUpRight } from "lucide-react";
import { RecipeCard } from "@/components/recipe/recipe-card";
import { RecipeThumb } from "@/components/recipe/recipe-thumb";
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion";
import { HeroFilm } from "@/components/site/hero-film";
import { Reveal } from "@/components/site/reveal";
import { TryIt } from "@/components/site/try-it";
import { FILM_SIMULATION_NAMES, RecipeSettingsSchema, type FilmSimulation } from "@/lib/recipe/schema";
import { publishedRecipes, toCard } from "@/lib/server/data";
import { GENERATIONS, GENERATION_LABEL, camerasIn } from "@/lib/recipe/cameras";
import { DEFAULT_PHOTO, HERO } from "@/lib/site-config";

const look = (sim: FilmSimulation) => RecipeSettingsSchema.parse({ filmSimulation: sim });

const FEATURES: { title: string; body: string; sim: FilmSimulation }[] = [
  { title: "Preview before you shoot", body: "See any recipe on your own photos — every simulation from X‑Trans IV and V bodies, rendered on your device in real time.", sim: "classicChrome" },
  { title: "Tune every setting", body: "Parameter cards with −/+ steppers and ranges from your camera — pick your body and FilmLab hides what it can’t do.", sim: "nostalgicNeg" },
  { title: "Screenshot to recipe", body: "Snap a recipe card, a forum post or a friend’s story. FilmLab reads it on‑device first; you review every field.", sim: "acrosR" },
  { title: "C1–C7, without the dread", body: "Arrange sets of seven, see a per‑setting diff, back up first. Camera writing is experimental and off by default.", sim: "eterna" },
];

const GENERATION_BLURB = {
  V: "X‑Processor 5 bodies: every simulation incl. REALA ACE and NOSTALGIC Neg. Includes X‑Trans 4‑sensor bodies like the X‑T30 III and X‑S20.",
  IV: "X‑Processor 4 bodies: CLASSIC Neg. and Color Chrome FX Blue on most; X‑Trans IV recipes also work on X‑Trans V cameras.",
} as const;

const FAQ = [
  ["Is the preview what my camera will produce?", "No — it's FilmLab's own approximation, rendered on your device. It's great for comparing looks and choosing a starting point. Only a JPEG produced by the camera itself is the real thing, and FilmLab always labels which is which."],
  ["Does my photo get uploaded?", "Not for previews: the web demo renders in your browser and the app renders on your iPhone. Only when you choose AI recipe reading for a hard-to-read screenshot is that image sent to the FilmLab server for that one request, and it isn't stored."],
  ["Which cameras are supported?", "Fujifilm X-Trans IV and X-Trans V bodies — from the X-T3 and X100V to the X-T5, X100VI and X-T30 III. Every recipe is tagged X-Trans IV or V and shows which cameras can take it as written, which need small changes, and which can't (e.g. REALA ACE on an X-T4). Feature lists for bodies other than the X-T30 III come from community reports."],
  ["What's the difference between X-Trans IV and V recipes?", "It's about the image processor. X-Trans V (X-Processor 5) cameras add NOSTALGIC Neg. and REALA ACE, so recipes built on them won't work on X-Trans IV. X-Trans IV recipes generally work on X-Trans V bodies, although colours can render a little differently."],
  ["Can it write recipes to my camera?", "Camera writing over USB-C is experimental, off by default and currently limited to the X-T30 III. When enabled it backs up all seven slots, shows a per-setting diff, asks you to confirm, and reads the slot back to verify. Other recognised bodies are read-only for now."],
  ["How do I import a recipe I found online?", "Take a screenshot (or paste the text) and FilmLab reads it — on-device first, with AI only when the on-device pass can't read everything. You review every field before saving."],
];

function SectionTitle({ children, aside }: { children: React.ReactNode; aside?: React.ReactNode }) {
  return (
    <div className="flex flex-wrap items-end justify-between gap-4">
      <h2 className="font-display text-6xl font-normal uppercase leading-[0.85] tracking-[-0.05em] sm:text-8xl">{children}</h2>
      {aside}
    </div>
  );
}

const pillDark = "group inline-flex items-center gap-1.5 rounded-full bg-foreground px-5 py-3 text-sm font-medium text-background transition-opacity hover:opacity-85 active:scale-[.98]";
const pillSoft = "group inline-flex items-center gap-1.5 rounded-full border border-hairline bg-surface px-5 py-3 text-sm font-medium transition-colors hover:bg-surface-raised active:scale-[.98]";
const arrow = <ArrowUpRight className="size-4 transition-transform group-hover:-translate-y-0.5 group-hover:translate-x-0.5" />;

function SimTile({ sim, className }: { sim: FilmSimulation; className?: string }) {
  return (
    <Link href={`/recipes?sim=${sim}`} className={`group relative block overflow-hidden rounded-[20px] bg-surface ${className ?? ""}`}>
      <RecipeThumb settings={look(sim)} className="size-full object-cover transition-transform duration-700 ease-out group-hover:scale-105" />
      <span className="absolute bottom-2 left-2 rounded-full bg-white/90 px-2.5 py-1 text-[11px] font-medium text-black backdrop-blur">{FILM_SIMULATION_NAMES[sim]}</span>
    </Link>
  );
}

export default async function Home() {
  const recipes = (await publishedRecipes()).map(toCard);
  const enter = "animate-in fade-in slide-in-from-bottom-4 fill-mode-both duration-700 ease-out motion-reduce:animate-none";

  return (
    <>
      {/* HERO — photo with cut-out panels (desktop); stacked on mobile */}
      <section className="mx-auto max-w-6xl px-5 sm:px-8 lg:px-10 pt-10 sm:pt-20">
        <h1 className={`font-display text-[13vw] font-normal leading-[0.92] tracking-[-0.055em] sm:text-7xl lg:hidden ${enter}`}>
          Find your look before the shutter
        </h1>

        <div className={`relative mt-8 h-[72svh] max-h-[720px] min-h-[420px] lg:mt-0 lg:h-[680px] ${enter}`} style={{ animationDelay: "80ms" }}>
          <div className="absolute inset-0 overflow-hidden rounded-[var(--fl-notch)]">
            <HeroFilm src={HERO.src} credit={HERO.credit} position={HERO.position} />
          </div>

          {/* top-left: headline */}
          <div className="absolute left-0 top-0 hidden rounded-br-[var(--fl-notch)] bg-background pb-5 pr-8 lg:block">
            <h1 className="font-display text-[4.25rem] font-normal leading-[0.92] tracking-[-0.055em]">
              Find your look<br />before the shutter
            </h1>
            <span className="fl-notch fl-notch-br -right-[var(--fl-notch)] top-0" />
            <span className="fl-notch fl-notch-br -bottom-[var(--fl-notch)] left-0" />
          </div>

          {/* top-right: two more looks */}
          <div className="absolute right-0 top-0 hidden gap-4 rounded-bl-[var(--fl-notch)] bg-background pb-4 pl-4 lg:flex">
            <SimTile sim="acrosR" className="size-32" />
            <SimTile sim="classicNeg" className="size-32" />
            <span className="fl-notch fl-notch-bl -left-[var(--fl-notch)] top-0" />
            <span className="fl-notch fl-notch-bl -bottom-[var(--fl-notch)] right-0" />
          </div>

          {/* bottom-left: actions */}
          <div className="absolute bottom-0 left-0 hidden gap-2 rounded-tr-[var(--fl-notch)] bg-background pr-4 pt-4 lg:flex">
            <Link href="/recipes" className={pillDark}>Browse recipes {arrow}</Link>
            <Link href="/#try" className={pillSoft}>Try it on your photo</Link>
            <span className="fl-notch fl-notch-tr -top-[var(--fl-notch)] left-0" />
            <span className="fl-notch fl-notch-tr -right-[var(--fl-notch)] bottom-0" />
          </div>
        </div>

        <div className={`mt-6 flex flex-wrap gap-3 lg:hidden ${enter}`} style={{ animationDelay: "160ms" }}>
          <Link href="/recipes" className={pillDark}>Browse recipes {arrow}</Link>
          <Link href="/#try" className={pillSoft}>Try it on your photo</Link>
        </div>

        <div className={`mt-12 grid gap-6 border-t border-hairline pt-8 text-muted-foreground sm:grid-cols-[1.4fr_1fr] ${enter}`} style={{ animationDelay: "220ms" }}>
          <p className="max-w-xl text-lg leading-relaxed text-foreground sm:text-xl">
            Preview film simulation recipes on your own photos, tune every setting, and keep your C1–C7 slots in order — for FUJIFILM X‑Trans IV and V cameras.
          </p>
          <p className="text-sm sm:text-right">Free · Previews stay on your device · Unofficial</p>
        </div>
      </section>

      {/* RECIPES */}
      <section className="mx-auto max-w-6xl px-5 sm:px-8 lg:px-10 pt-40 sm:pt-56">
        <Reveal>
          <SectionTitle aside={recipes.length > 0 && <Link href="/recipes" className={pillSoft}>View all {recipes.length} {arrow}</Link>}>Recipes</SectionTitle>
        </Reveal>
        {recipes.length > 0 ? (
          <div className="mt-16 grid gap-x-8 gap-y-16 sm:grid-cols-2 lg:gap-x-10 lg:gap-y-20">
            {recipes.slice(0, 6).map((r, i) => (
              <Reveal key={r.slug} delay={(i % 2) * 0.08}><RecipeCard r={r} size="lg" /></Reveal>
            ))}
          </div>
        ) : (
          <Reveal className="mt-16">
            <div className="grid items-center gap-8 rounded-[var(--fl-radius-card)] bg-surface p-8 sm:grid-cols-[1fr_1.2fr] sm:p-14">
              <div>
                <p className="font-display text-3xl font-normal tracking-[-0.03em]">The first recipes are on their way.</p>
                <p className="mt-3 text-muted-foreground">Meanwhile, try the looks on Mt Fuji — or on your own photo.</p>
                <Link href="/#try" className={`${pillDark} mt-6`}>Try the preview {arrow}</Link>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <SimTile sim="classicChrome" className="aspect-[4/3]" />
                <SimTile sim="velvia" className="aspect-[4/3]" />
              </div>
            </div>
          </Reveal>
        )}
      </section>

      {/* FEATURES — service-list rows */}
      <section id="features" className="mx-auto max-w-6xl scroll-mt-24 px-5 sm:px-8 lg:px-10 pt-40 sm:pt-56">
        <Reveal><SectionTitle>Features</SectionTitle></Reveal>
        <div className="mt-16 border-t border-hairline">
          {FEATURES.map((f, i) => (
            <Reveal key={f.title}>
              <div className="group grid items-center gap-5 border-b border-hairline py-10 sm:grid-cols-[3rem_1fr_1.1fr_11rem] sm:gap-10 sm:py-12">
                <span className="font-mono text-sm text-tertiary">0{i + 1}</span>
                <h3 className="font-display text-3xl font-normal leading-tight tracking-[-0.035em] sm:text-4xl">{f.title}</h3>
                <p className="max-w-md leading-relaxed text-muted-foreground">{f.body}</p>
                <div className="relative aspect-[4/3] overflow-hidden rounded-2xl bg-surface sm:w-44">
                  <RecipeThumb settings={look(f.sim)} className="size-full object-cover transition-transform duration-700 ease-out group-hover:scale-105" />
                </div>
              </div>
            </Reveal>
          ))}
        </div>
      </section>

      {/* TRY IT */}
      <section id="try" className="mx-auto max-w-6xl scroll-mt-24 px-5 sm:px-8 lg:px-10 pt-40 sm:pt-56">
        <Reveal>
          <SectionTitle aside={<p className="max-w-xs text-muted-foreground">Pick a simulation, drag the divider, or drop in your own photo. It renders in your browser.</p>}>Try it</SectionTitle>
        </Reveal>
        <Reveal delay={0.08} className="mt-16"><TryIt /></Reveal>
      </section>

      {/* CAMERAS — one row per X-Trans family */}
      <section className="mx-auto max-w-6xl px-5 pt-40 sm:px-8 sm:pt-56 lg:px-10">
        <Reveal><SectionTitle aside={<p className="max-w-xs text-muted-foreground">Pick your body in the app and every recipe shows what works on it.</p>}>Cameras</SectionTitle></Reveal>
        <div className="mt-16 border-t border-hairline">
          {GENERATIONS.map((g) => (
            <Reveal key={g}>
              <div className="grid gap-6 border-b border-hairline py-10 sm:grid-cols-[1fr_1.6fr] sm:gap-10 sm:py-12">
                <div>
                  <h3 className="font-display text-4xl font-normal tracking-[-0.04em] sm:text-5xl">{GENERATION_LABEL[g]}</h3>
                  <p className="mt-4 max-w-sm leading-relaxed text-muted-foreground">{GENERATION_BLURB[g]}</p>
                </div>
                <ul className="grid grid-cols-2 content-start gap-x-8 sm:grid-cols-3">
                  {camerasIn(g).map((c) => (
                    <li key={c.id} className="border-b border-hairline py-3">
                      <Link href={`/recipes?camera=${c.id}`} className="group flex items-baseline justify-between gap-2 transition-opacity hover:opacity-60">
                        <span className="font-display text-xl tracking-[-0.02em]">{c.name}</span>
                        <ArrowUpRight className="size-3.5 shrink-0 text-tertiary" />
                      </Link>
                      <p className="mt-0.5 truncate text-xs text-tertiary">{c.sensor.replace(/\s*\(.*\)/, "")}</p>
                    </li>
                  ))}
                </ul>
              </div>
            </Reveal>
          ))}
        </div>
      </section>

      {/* FAQ */}
      <section id="faq" className="mx-auto grid max-w-6xl scroll-mt-24 gap-12 px-5 sm:px-8 lg:px-10 pt-40 sm:pt-56 lg:grid-cols-[1fr_1.5fr]">
        <Reveal><SectionTitle>FAQ</SectionTitle></Reveal>
        <Reveal delay={0.06}>
          <Accordion className="border-t border-hairline">
            {FAQ.map(([q, a]) => (
              <AccordionItem key={q} value={q} className="border-hairline">
                <AccordionTrigger className="py-7 text-left font-display text-xl font-normal tracking-[-0.02em] hover:no-underline">{q}</AccordionTrigger>
                <AccordionContent className="pb-7 pr-8 text-base leading-relaxed text-muted-foreground">{a}</AccordionContent>
              </AccordionItem>
            ))}
          </Accordion>
        </Reveal>
      </section>

      {/* CTA — card on a photo */}
      <section className="mx-auto max-w-6xl px-5 sm:px-8 lg:px-10 pt-40 sm:pt-56">
        <Reveal>
          <div className="relative overflow-hidden rounded-[var(--fl-notch)]">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={DEFAULT_PHOTO} alt="" aria-hidden className="absolute inset-0 size-full object-cover" style={{ objectPosition: HERO.position }} />
            <div className="relative flex min-h-[600px] items-end p-3 sm:p-8">
              <div className="w-full max-w-md rounded-[20px] bg-background p-8 sm:p-12">
                <p className="font-display text-4xl font-normal leading-[0.95] tracking-[-0.045em] sm:text-5xl">Your next look is one recipe away.</p>
                <p className="mt-5 leading-relaxed text-muted-foreground">Browse the collection, or drop a screenshot into the app and let FilmLab read it.</p>
                <div className="mt-9 flex flex-wrap gap-3">
                  <Link href="/recipes" className={pillDark}>Browse recipes {arrow}</Link>
                  <Link href="/#try" className={pillSoft}>Try the preview</Link>
                </div>
              </div>
            </div>
          </div>
        </Reveal>
      </section>
    </>
  );
}
