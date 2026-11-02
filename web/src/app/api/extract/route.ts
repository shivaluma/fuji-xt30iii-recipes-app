import { z } from "zod";
import { requireAdmin, rateLimit } from "@/lib/server/auth";
import { runExtraction, ExtractionError } from "@/lib/extract/service";
import { isSupportedImageType } from "@/lib/extract/providers/types";

const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const JsonBody = z.object({
  imageBase64: z.string().optional(),
  mediaType: z.string().optional(),
  text: z.string().max(10000).optional(),
}).refine((b) => b.imageBase64 || b.text, "Send an image, text, or both.");

/**
 * POST /api/extract — read a recipe from an image (screenshot, card, photo of notes) and/or text
 * (e.g. a pasted comment) with the configured vision model. Returns a DRAFT for review; nothing is
 * saved and the image is not stored or logged.
 * Accepts JSON {imageBase64, mediaType, text} or multipart {file, text}. Admin token required
 * (each call costs money).
 */
export async function POST(request: Request) {
  const denied = requireAdmin(request);
  if (denied) return denied;
  if (!rateLimit("extract", 30, 60 * 60 * 1000)) return Response.json({ error: "Extraction limit reached; try again later." }, { status: 429 });

  let image: { data: string; mediaType: string } | undefined;
  let text: string | undefined;
  const contentType = request.headers.get("content-type") ?? "";
  if (contentType.includes("multipart/form-data")) {
    const form = await request.formData();
    const file = form.get("file");
    text = (form.get("text") as string | null) ?? undefined;
    if (file instanceof File && file.size > 0) {
      if (file.size > MAX_IMAGE_BYTES) return Response.json({ error: "Image is larger than 5 MB" }, { status: 413 });
      image = { data: Buffer.from(await file.arrayBuffer()).toString("base64"), mediaType: file.type };
    }
  } else {
    const parsed = JsonBody.safeParse(await request.json().catch(() => null));
    if (!parsed.success) return Response.json({ error: "Send an image, text, or both." }, { status: 400 });
    text = parsed.data.text;
    if (parsed.data.imageBase64) {
      if (parsed.data.imageBase64.length > MAX_IMAGE_BYTES * 1.37) return Response.json({ error: "Image is larger than 5 MB" }, { status: 413 });
      image = { data: parsed.data.imageBase64, mediaType: parsed.data.mediaType ?? "image/jpeg" };
    }
  }
  if (!image && !text?.trim()) return Response.json({ error: "Send an image, text, or both." }, { status: 400 });
  if (image && !isSupportedImageType(image.mediaType)) return Response.json({ error: "Use JPEG, PNG, WebP or GIF" }, { status: 415 });

  try {
    const result = await runExtraction({
      image: image && isSupportedImageType(image.mediaType) ? { data: image.data, mediaType: image.mediaType } : undefined,
      text,
    });
    return Response.json({
      draft: { ...result.draft, model: result.model },
      meta: { provider: result.provider, model: result.model, attempts: result.attempts, latencyMs: result.latencyMs, usage: result.usage },
    });
  } catch (error) {
    if (error instanceof ExtractionError) return Response.json({ error: error.message }, { status: error.status });
    console.error("extract failed:", (error as Error).name); // never log image data
    return Response.json({ error: "Extraction failed" }, { status: 500 });
  }
}
