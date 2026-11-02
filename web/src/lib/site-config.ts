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
