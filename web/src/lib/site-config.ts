/**
 * Landing-page hero photo. It's rendered live through each film simulation in the browser.
 * Default: Mt Fuji, photographed by the project owner. Only use photos you own or have permission
 * to publish, and set a credit for anyone else's work.
 * Override at build time with NEXT_PUBLIC_HERO_SRC / NEXT_PUBLIC_HERO_CREDIT (e.g. Dokploy build args).
 */
export const HERO = {
  src: process.env.NEXT_PUBLIC_HERO_SRC || "/hero/mt-fuji.webp",
  credit: process.env.NEXT_PUBLIC_HERO_CREDIT || null,
  /** CSS object-position: keeps the subject in frame on wide and tall screens. */
  position: process.env.NEXT_PUBLIC_HERO_POSITION || "50% 40%",
};

/** Default photo for recipe thumbnails, recipe previews and app mock-ups (same as the hero). */
export const DEFAULT_PHOTO = HERO.src;

/** Canonical origin for metadata, sitemap and structured data. Override with NEXT_PUBLIC_SITE_URL. */
export const SITE = {
  url: (process.env.NEXT_PUBLIC_SITE_URL || "https://filmlab.requiem.one").replace(/\/+$/, ""),
  name: "FilmLab",
  title: "FilmLab — film recipes for Fujifilm X-Trans IV & V",
  description:
    "Preview Fujifilm film simulation recipes for X-Trans IV and X-Trans V cameras on your own photos, see which bodies each recipe works on, and read recipes from screenshots. Unofficial; not affiliated with Fujifilm.",
  keywords: [
    "Fujifilm recipes", "film simulation recipes", "Fuji recipes", "X-Trans IV recipes", "X-Trans V recipes",
    "Classic Chrome", "Classic Negative", "Nostalgic Negative", "Reala Ace", "Acros", "X-T30 III", "X100VI", "X-T5",
  ],
};
