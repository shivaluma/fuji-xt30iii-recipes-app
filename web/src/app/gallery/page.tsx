import { Suspense } from "react";
import Link from "next/link";
import type { Metadata } from "next";
import { GalleryGrid } from "@/components/gallery/gallery-grid";
import { JsonLd } from "@/components/site/json-ld";
import { Skeleton } from "@/components/ui/skeleton";
import { publishedGallery, toTile } from "@/lib/server/data";
import { SITE } from "@/lib/site-config";
import { cn } from "@/lib/utils";

export const metadata: Metadata = {
  title: "Gallery",
  description: "Favourite photos shot on Fujifilm X-series cameras, each linked to the film simulation recipe it was made with.",
  alternates: { canonical: "/gallery" },
  openGraph: { url: "/gallery", title: "Gallery · FilmLab" },
  twitter: { card: "summary_large_image", title: "Gallery · FilmLab" },
};

const chip = (active: boolean) =>
  cn("shrink-0 rounded-full border px-3.5 py-1.5 text-sm transition-colors active:scale-[.98]",
    active ? "border-foreground bg-foreground text-background" : "border-hairline hover:border-foreground/30");

async function Photos({ searchParams }: { searchParams: PageProps<"/gallery">["searchParams"] }) {
  const sp = await searchParams;
  const all = await publishedGallery();
  const recipes = [...new Map(all.flatMap((g) => (g.recipe ? [[g.recipe.slug, g.recipe] as const] : []))).values()];
  const active = typeof sp.recipe === "string" ? recipes.find((r) => r.slug === sp.recipe) : undefined;
  const shown = active ? all.filter((g) => g.recipe?.slug === active.slug) : all;

  if (all.length === 0) {
    return (
      <div className="rounded-[var(--fl-radius-card)] bg-surface px-8 py-28 text-center">
        <p className="font-display text-3xl font-normal tracking-[-0.03em]">The gallery is empty for now.</p>
        <p className="mx-auto mt-3 max-w-md text-muted-foreground">Favourite photos will appear here, each with the recipe it was shot with.</p>
        <Link href="/recipes" className="mt-6 inline-flex rounded-full bg-foreground px-5 py-3 text-sm font-medium text-background transition-opacity hover:opacity-85">Browse recipes</Link>
      </div>
    );
  }

  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "ImageGallery",
    name: "FilmLab gallery",
    url: `${SITE.url}/gallery`,
    isPartOf: { "@id": `${SITE.url}/#website` },
    image: all.slice(0, 50).map((g) => ({
      "@type": "ImageObject",
      contentUrl: `${SITE.url}/api/media/${g.file}`,
      ...(g.title ? { name: g.title } : {}),
      ...(g.caption ? { caption: g.caption } : {}),
      ...(g.width && g.height ? { width: g.width, height: g.height } : {}),
    })),
  };

  return (
    <>
      <JsonLd data={jsonLd} />
      {recipes.length > 0 && (
        <div className="-mx-5 flex gap-2 overflow-x-auto border-y border-hairline px-5 py-6 [scrollbar-width:none] lg:mx-0 lg:px-0">
          <Link href="/gallery" className={chip(!active)}>All photos</Link>
          {recipes.map((r) => <Link key={r.slug} href={`/gallery?recipe=${r.slug}`} className={chip(active?.slug === r.slug)}>{r.name}</Link>)}
        </div>
      )}
      {active && (
        <p className="text-sm text-muted-foreground">
          {shown.length} {shown.length === 1 ? "photo" : "photos"} shot with{" "}
          <Link href={`/recipes/${active.slug}`} className="font-medium text-foreground underline decoration-1 underline-offset-4">{active.name}</Link>
        </p>
      )}
      <GalleryGrid photos={shown.map(toTile)} />
    </>
  );
}

export default function GalleryPage({ searchParams }: PageProps<"/gallery">) {
  return (
    <div className="mx-auto max-w-6xl space-y-10 px-5 pt-12 sm:px-8 sm:pt-20 lg:px-10">
      <div className="flex flex-wrap items-end justify-between gap-4 animate-in fade-in slide-in-from-bottom-4 fill-mode-both duration-700 motion-reduce:animate-none">
        <h1 className="font-display text-7xl font-normal uppercase leading-[0.85] tracking-[-0.055em] sm:text-9xl">Gallery</h1>
        <p className="max-w-xs text-muted-foreground">Favourite frames, straight out of camera. Tap a recipe to shoot the same look.</p>
      </div>
      <Suspense fallback={<div className="columns-1 gap-4 sm:columns-2 lg:columns-3">{Array.from({ length: 6 }, (_, i) => <Skeleton key={i} className={cn("mb-4 rounded-[var(--fl-radius-card)]", i % 2 ? "aspect-[3/4]" : "aspect-[4/3]")} />)}</div>}>
        <Photos searchParams={searchParams} />
      </Suspense>
    </div>
  );
}
