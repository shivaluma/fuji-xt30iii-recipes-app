import type { MetadataRoute } from "next";
import { connection } from "next/server";
import { publishedGallery, publishedRecipes } from "@/lib/server/data";
import { SITE } from "@/lib/site-config";

/** Rendered per request (the build prerenders from an empty database); the recipe query itself is cached. */
export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  await connection();
  const rows = await publishedRecipes();
  const gallery = await publishedGallery();
  const latest = rows.reduce((m, r) => (r.updatedAt > m ? r.updatedAt : m), "") || undefined;
  return [
    { url: SITE.url, lastModified: latest, changeFrequency: "weekly", priority: 1 },
    { url: `${SITE.url}/recipes`, lastModified: latest, changeFrequency: "daily", priority: 0.9 },
    ...(gallery.length
      ? [{ url: `${SITE.url}/gallery`, changeFrequency: "weekly" as const, priority: 0.8, images: gallery.slice(0, 1000).map((g) => `${SITE.url}/api/media/${g.file}`) }]
      : []),
    ...rows.map((r) => ({
      url: `${SITE.url}/recipes/${r.slug}`,
      lastModified: r.updatedAt,
      changeFrequency: "monthly" as const,
      priority: 0.8,
      images: r.photos.map((p) => `${SITE.url}/api/media/${p.file}`),
    })),
  ];
}
