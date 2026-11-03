import { revalidateTag } from "next/cache";
import { z } from "zod";
import { requireAdmin } from "@/lib/server/auth";
import { GalleryError, addGalleryPhoto, listGallery, reorderGallery, type GalleryItem } from "@/lib/server/db";
import { GALLERY_TAG } from "@/lib/server/data";
import { galleryJSON, storeUpload } from "@/lib/server/uploads";

/** Favourites are re-encoded in the browser to 3200 px, so this is generous. */
const MAX_GALLERY_BYTES = 15 * 1024 * 1024;
const MAX_PER_REQUEST = 20;

/**
 * GET /api/gallery?recipe=<slug> — public, in display order; links to draft recipes are hidden.
 * `all=1` (admin token) includes links to drafts.
 */
export async function GET(request: Request) {
  const url = new URL(request.url);
  const all = url.searchParams.get("all") === "1";
  if (all) {
    const denied = requireAdmin(request);
    if (denied) return denied;
  }
  const recipe = url.searchParams.get("recipe") ?? undefined;
  return Response.json({ photos: listGallery({ recipeSlug: recipe, publicOnly: !all }).map(galleryJSON) });
}

const int = (v: FormDataEntryValue | undefined) => {
  const n = Number(v);
  return Number.isInteger(n) && n > 0 && n < 100_000 ? n : null;
};

/**
 * POST multipart/form-data, admin only: one or more `file` parts, each with optional `title`,
 * `caption`, `recipe` (slug), `width`, `height` at the same index. New photos go to the top.
 * Upload only images you own.
 */
export async function POST(request: Request) {
  const denied = requireAdmin(request);
  if (denied) return denied;
  const form = await request.formData().catch(() => null);
  const files = form?.getAll("file") ?? [];
  if (!files.length) return Response.json({ error: "Missing file" }, { status: 400 });
  if (files.length > MAX_PER_REQUEST) return Response.json({ error: `Upload up to ${MAX_PER_REQUEST} photos at a time` }, { status: 400 });
  const field = (name: string) => (form?.getAll(name) ?? []).map(String);
  const [titles, captions, recipes, widths, heights] = ["title", "caption", "recipe", "width", "height"].map(field);
  const added: GalleryItem[] = [];
  for (const [i, file] of files.entries()) {
    const stored = await storeUpload(file, MAX_GALLERY_BYTES);
    if (stored instanceof Response) return stored;
    try {
      added.push(addGalleryPhoto(stored, {
        title: titles[i]?.slice(0, 120), caption: captions[i]?.slice(0, 1000), recipeSlug: recipes[i] || null,
        width: int(widths[i]), height: int(heights[i]),
      }));
    } catch (e) {
      if (e instanceof GalleryError) return Response.json({ error: e.message }, { status: 400 });
      throw e;
    }
  }
  revalidateTag(GALLERY_TAG, "max");
  return Response.json({ photos: added.map(galleryJSON) }, { status: 201 });
}

const Order = z.object({ order: z.array(z.string().uuid()).max(1000) });

/** PUT {order: [ids…]} — admin only: sets the display order. */
export async function PUT(request: Request) {
  const denied = requireAdmin(request);
  if (denied) return denied;
  const parsed = Order.safeParse(await request.json().catch(() => null));
  if (!parsed.success) return Response.json({ error: "Invalid order" }, { status: 400 });
  const photos = reorderGallery(parsed.data.order);
  revalidateTag(GALLERY_TAG, "max");
  return Response.json({ photos: photos.map(galleryJSON) });
}
