import Link from "next/link";
import { ArrowRight, Camera, Check, CircleDashed, Lock, ScanText, SlidersHorizontal } from "lucide-react";
import { RecipeCard } from "@/components/recipe/recipe-card";
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion";
import { HeroFilm } from "@/components/site/hero-film";
import { SimulationMarquee } from "@/components/site/marquee";
import { Reveal } from "@/components/site/reveal";
import { Phone } from "@/components/site/phone";
import { ImportMock, ScanBadge, TuneMock, WriteMock } from "@/components/site/app-mocks";
import { TryIt } from "@/components/site/try-it";
import { publishedRecipes, toCard } from "@/lib/server/data";

const FAQ = [
  ["Is the preview what my camera will produce?", "No — it's FilmLab's own approximation, rendered on your device. It's great for comparing looks and choosing a starting point. Only a JPEG produced by the camera itself is the real thing, and FilmLab always labels which is which."],
  ["Does my photo get uploaded?", "Not for previews: the web demo renders in your browser and the app renders on your iPhone. Only when you choose AI recipe reading for a hard-to-read screenshot is that image sent to the FilmLab server for that one request, and it isn't stored."],
  ["Which cameras are supported?", "FilmLab is built and tuned for the X-T30 III: its 20 film simulations, ranges and C1–C7 custom slots. Recipes for other X-Trans bodies usually translate, and FilmLab flags settings the X-T30 III doesn't have (like Smooth Skin)."],
  ["Can it write recipes to my camera?", "Camera writing over USB-C is experimental and off by default. When enabled it backs up all seven slots, shows a per-setting diff, asks you to confirm, and reads the slot back to verify. FS1–FS3 dial positions are never touched."],
  ["How do I import a recipe I found online?", "Take a screenshot (or paste the text) and FilmLab reads it — on-device first, with AI only when the on-device pass can't read everything. You review every field before saving."],
];

const CAMERAS = [
  { name: "X-T30 III", status: "Designed for" },
  { name: "X-T5", status: "Recipes translate" }, { name: "X-T50", status: "Recipes translate" },
  { name: "X-S20", status: "Recipes translate" }, { name: "X100VI", status: "Recipes translate" }, { name: "X-E5", status: "Recipes translate" },
];

export default async function Home() {
  const recipes = (await publishedRecipes()).map(toCard);
  return (
    <>
      {/* HERO */}
      <section className="relative flex min-h-[100svh] items-end overflow-hidden pb-24 pt-32 sm:items-center sm:pb-0">
        <HeroFilm />
        <div className="relative mx-auto w-full max-w-6xl px-5">
          <div className="animate-in fade-in slide-in-from-bottom-6 fill-mode-both duration-1000 ease-out motion-reduce:animate-none" style={{ animationDelay: "100ms" }}>
            <p className="inline-flex items-center gap-2 rounded-full border border-hairline bg-black/40 px-3.5 py-1.5 text-xs font-semibold uppercase tracking-[.18em] text-primary backdrop-blur">
              <Camera className="size-3.5" /> For FUJIFILM X-T30 III
            </p>
          </div>
          <div className="animate-in fade-in slide-in-from-bottom-6 fill-mode-both duration-1000 ease-out motion-reduce:animate-none" style={{ animationDelay: "180ms" }}>
            <h1 className="mt-6 max-w-4xl font-display text-5xl font-bold leading-[0.95] tracking-tight sm:text-7xl lg:text-8xl">
              Find your look.<br />
              <span className="italic text-primary">Before the shutter.</span>
            </h1>
          </div>
          <div className="animate-in fade-in slide-in-from-bottom-6 fill-mode-both duration-1000 ease-out motion-reduce:animate-none" style={{ animationDelay: "260ms" }}>
            <p className="mt-6 max-w-xl text-lg text-white/75 sm:text-xl">
              Preview film simulation recipes on your own photos, tune every setting with your thumb, and keep your C1–C7 slots in order.
            </p>
          </div>
          <div className="animate-in fade-in slide-in-from-bottom-6 fill-mode-both duration-1000 ease-out motion-reduce:animate-none" style={{ animationDelay: "340ms" }}>
            <div className="mt-9 flex flex-wrap gap-3">
              <Link href="/recipes" className="group inline-flex items-center gap-2 rounded-full bg-primary px-6 py-3.5 font-bold text-primary-foreground transition-transform active:scale-95">
                Browse recipes <ArrowRight className="size-4 transition-transform group-hover:translate-x-1" />
              </Link>
              <Link href="/#try" className="inline-flex items-center gap-2 rounded-full border border-white/25 bg-black/30 px-6 py-3.5 font-bold backdrop-blur transition-colors hover:bg-white/10">
                Try it on your photo
              </Link>
            </div>
            <p className="mt-5 text-sm text-white/55">Free · Previews stay on your device · Unofficial</p>
          </div>
        </div>
      </section>

      <SimulationMarquee />

      {/* INTRO */}
      <section id="features" className="relative mx-auto grid max-w-6xl items-center gap-14 px-5 py-28 lg:grid-cols-2">
        <div className="fl-glow pointer-events-none absolute inset-x-0 top-0 h-96" />
        <Reveal className="relative">
          <p className="text-sm font-semibold uppercase tracking-[.18em] text-primary">Studio</p>
          <h2 className="mt-4 font-display text-4xl font-bold leading-tight tracking-tight sm:text-6xl">
            Every setting.<br /><span className="italic text-primary">One thumb.</span>
          </h2>
          <p className="mt-6 max-w-md text-lg text-muted-foreground">
            Swipe through parameter cards, nudge with −/+, and watch the look change instantly. Ranges come straight from the X-T30 III, so you can&apos;t dial in a value the camera won&apos;t take.
          </p>
          <ul className="mt-8 space-y-3 text-sm">
            {["All 20 film simulations, incl. REALA ACE and Nostalgic Neg.", "Hold to compare with the original", "Unset stays unset — the camera keeps its own value"].map((t) => (
              <li key={t} className="flex items-center gap-3"><span className="grid size-6 place-items-center rounded-full bg-accent text-primary"><Check className="size-3.5" /></span>{t}</li>
            ))}
          </ul>
        </Reveal>
        <Reveal delay={0.1} className="relative">
          <div className="fl-float"><Phone><TuneMock /></Phone></div>
          <p className="mt-6 text-center text-xs text-tertiary">Tap the cards and −/+ — it&apos;s interactive.</p>
        </Reveal>
      </section>

      {/* FEATURE ROWS */}
      <section className="mx-auto max-w-6xl space-y-32 px-5 pb-28">
        <div className="grid items-center gap-12 lg:grid-cols-2">
          <Reveal>
            <ScanBadge />
            <h3 className="mt-4 font-display text-3xl font-bold tracking-tight sm:text-5xl">Screenshot in.<br /><span className="italic text-primary">Recipe out.</span></h3>
            <p className="mt-5 max-w-md text-lg text-muted-foreground">
              Found a recipe on a forum, a card or a friend&apos;s story? Snap it. FilmLab reads it on your iPhone first, and only asks AI for help with the tricky ones. Every field is yours to review — nothing is guessed.
            </p>
          </Reveal>
          <Reveal delay={0.1}><ImportMock /></Reveal>
        </div>

        <div className="grid items-center gap-12 lg:grid-cols-2">
          <Reveal delay={0.1} className="lg:order-2">
            <span className="inline-flex items-center gap-1.5 rounded-full bg-accent px-3 py-1 text-xs font-semibold text-primary"><Lock className="size-3.5" /> Safety first</span>
            <h3 className="mt-4 font-display text-3xl font-bold tracking-tight sm:text-5xl">C1–C7,<br /><span className="italic text-primary">without the dread.</span></h3>
            <p className="mt-5 max-w-md text-lg text-muted-foreground">
              Arrange Sets of seven recipes, see exactly what changes in each slot, and write only after a backup and your explicit tap. Camera writing is experimental and off by default.
            </p>
          </Reveal>
          <Reveal className="lg:order-1"><WriteMock /></Reveal>
        </div>
      </section>

      {/* TRY IT */}
      <section id="try" className="border-y border-hairline bg-surface/40">
        <div className="mx-auto max-w-6xl px-5 py-28">
          <Reveal>
            <div className="flex flex-wrap items-end justify-between gap-6">
              <div>
                <p className="text-sm font-semibold uppercase tracking-[.18em] text-primary"><SlidersHorizontal className="mr-1.5 inline size-4" />Try it</p>
                <h2 className="mt-4 font-display text-4xl font-bold tracking-tight sm:text-6xl">Drag. Compare. <span className="italic text-primary">Decide.</span></h2>
              </div>
              <p className="max-w-sm text-muted-foreground">Pick a simulation, drag the divider, or drop in your own photo. It renders right here in your browser.</p>
            </div>
          </Reveal>
          <Reveal delay={0.1} className="mx-auto mt-10 max-w-4xl"><TryIt /></Reveal>
        </div>
      </section>

      {/* RECIPES */}
      <section className="py-28">
        <div className="mx-auto flex max-w-6xl items-end justify-between gap-4 px-5">
          <Reveal>
            <h2 className="font-display text-4xl font-bold tracking-tight sm:text-5xl">Fresh recipes</h2>
            <p className="mt-2 text-muted-foreground">Starter looks to try tonight</p>
          </Reveal>
          <Link href="/recipes" className="group inline-flex shrink-0 items-center gap-1 font-bold text-primary">See all <ArrowRight className="size-4 transition-transform group-hover:translate-x-1" /></Link>
        </div>
        <div className="mx-auto mt-10 flex max-w-6xl snap-x snap-mandatory gap-5 overflow-x-auto px-5 pb-4 [scrollbar-width:none]">
          {recipes.slice(0, 10).map((r, i) => (
            <div key={r.slug} className="w-64 shrink-0 snap-start animate-in fade-in slide-in-from-right-6 fill-mode-both duration-700 motion-reduce:animate-none sm:w-72" style={{ animationDelay: `${Math.min(i, 6) * 70}ms` }}>
              <RecipeCard r={r} />
            </div>
          ))}
        </div>
      </section>

      {/* COMPATIBILITY */}
      <section className="mx-auto max-w-6xl px-5 pb-28">
        <Reveal>
          <div className="rounded-[32px] border border-hairline bg-surface p-8 sm:p-12">
            <h2 className="font-display text-3xl font-bold tracking-tight sm:text-4xl">Made for the X-T30 III.</h2>
            <p className="mt-3 max-w-2xl text-muted-foreground">Ranges, simulations and slot behaviour are modelled on the X-T30 III (X-Trans CMOS 4, X-Processor 5). Recipes written for other bodies import fine — FilmLab flags anything the X-T30 III can&apos;t do.</p>
            <div className="mt-8 flex flex-wrap gap-2.5">
              {CAMERAS.map((c, i) => (
                <span key={c.name} className={i === 0 ? "inline-flex items-center gap-2 rounded-full border border-primary bg-accent px-4 py-2 font-semibold text-primary" : "inline-flex items-center gap-2 rounded-full border border-hairline bg-surface-raised px-4 py-2 font-semibold"}>
                  {i === 0 ? <Check className="size-4" /> : <CircleDashed className="size-4 text-muted-foreground" />}{c.name}
                  <span className="text-xs font-medium text-muted-foreground">{c.status}</span>
                </span>
              ))}
            </div>
          </div>
        </Reveal>
      </section>

      {/* FAQ */}
      <section id="faq" className="mx-auto max-w-3xl px-5 pb-28">
        <Reveal><h2 className="font-display text-4xl font-bold tracking-tight sm:text-5xl">Questions</h2></Reveal>
        <Reveal delay={0.08}>
          <Accordion className="mt-8">
            {FAQ.map(([q, a]) => (
              <AccordionItem key={q} value={q} className="border-hairline">
                <AccordionTrigger className="py-5 text-left font-display text-lg font-semibold hover:no-underline">{q}</AccordionTrigger>
                <AccordionContent className="pb-5 text-base leading-relaxed text-muted-foreground">{a}</AccordionContent>
              </AccordionItem>
            ))}
          </Accordion>
        </Reveal>
      </section>

      {/* CTA BAND */}
      <section className="px-5 pb-28">
        <Reveal>
          <div className="relative mx-auto max-w-6xl overflow-hidden rounded-[36px] border border-hairline bg-surface px-8 py-16 text-center sm:py-20">
            <div className="fl-glow pointer-events-none absolute inset-0" />
            <ScanText className="relative mx-auto size-10 text-primary" />
            <h2 className="relative mt-5 font-display text-4xl font-bold tracking-tight sm:text-6xl">Your next look is<br /><span className="italic text-primary">one recipe away.</span></h2>
            <div className="relative mt-9 flex flex-wrap justify-center gap-3">
              <Link href="/recipes" className="rounded-full bg-primary px-7 py-3.5 font-bold text-primary-foreground transition-transform active:scale-95">Browse recipes</Link>
              <Link href="/#try" className="rounded-full border border-white/25 px-7 py-3.5 font-bold transition-colors hover:bg-white/10">Try the preview</Link>
            </div>
          </div>
        </Reveal>
      </section>
    </>
  );
}
