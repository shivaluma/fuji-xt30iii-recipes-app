import { useSyncExternalStore } from "react";
import type { FilmRecipe, FilmSimulation, RecipeSettings } from "@/lib/recipe/schema";
import type { ExtractionDraft, ExtractionIssue } from "@/lib/extract/mapping";

export type ExtractMeta = { provider: string; model: string; attempts: number; latencyMs: number; usage: { inputTokens: number | null; outputTokens: number | null; costUSD: number | null } };

export type Summary = {
  id: string; slug: string; name: string; summary: string; status: "draft" | "published"; filmSimulation: FilmSimulation; settings: RecipeSettings;
  cover: { url: string; kind: string } | null; publishedAt: string | null; updatedAt: string;
};

/** Everything the editor needs, for a fresh import or an existing recipe. */
export type Draft = {
  /** Set when editing a saved recipe: keeps its id (and so its slug). */
  existing?: { recipe: FilmRecipe; status: "draft" | "published"; slug: string };
  name: string; summary: string; credit: string; cameraModel: string; body: string; tags: string[];
  settings: RecipeSettings;
  uncertain: string[]; issues: ExtractionIssue[]; raw: { field: string; text: string }[]; meta: ExtractMeta | null;
};

/** "Works best for" tags shown on recipe pages. */
export const TAGS: Record<string, string> = {
  everyday: "Everyday", street: "Street", travel: "Travel", landscape: "Landscape", nature: "Nature", portrait: "Portraits",
  sunset: "Golden hour", overcast: "Overcast", night: "Night", urban: "Urban", architecture: "Architecture",
  interior: "Indoors", food: "Food", bw: "Black & white", cinematic: "Cinematic", vintage: "Vintage",
};

const TOKEN_KEY = "filmlab.adminToken";
const tokenListeners = new Set<() => void>();
function readToken() { try { return localStorage.getItem(TOKEN_KEY) ?? ""; } catch { return ""; } }
export function useToken() {
  const token = useSyncExternalStore(
    (cb) => { tokenListeners.add(cb); return () => { tokenListeners.delete(cb); }; },
    readToken,
    () => "",
  );
  const save = (t: string) => { try { if (t) localStorage.setItem(TOKEN_KEY, t); else localStorage.removeItem(TOKEN_KEY); } catch {} tokenListeners.forEach((l) => l()); };
  return [token, save] as const;
}

export class ApiError extends Error { constructor(message: string, readonly status: number) { super(message); } }

export async function api<T>(path: string, token: string, init: RequestInit = {}): Promise<T> {
  const res = await fetch(path, { ...init, headers: { ...(init.headers ?? {}), authorization: `Bearer ${token}` } });
  if (res.status === 204) return undefined as T;
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new ApiError(body.error ?? `Request failed (${res.status})`, res.status);
  return body as T;
}

export const jsonInit = (method: string, body: unknown): RequestInit => ({ method, headers: { "content-type": "application/json" }, body: JSON.stringify(body) });

/**
 * Downscale an image in the browser before sending it for extraction: keeps uploads well under the
 * server's 5 MB limit and cuts vision-token cost. Text on recipe cards stays legible at 2000 px.
 */
export async function prepareImage(file: File, maxEdge = 2000): Promise<{ base64: string; mediaType: string; previewUrl: string }> {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, maxEdge / Math.max(bitmap.width, bitmap.height));
  const w = Math.round(bitmap.width * scale), h = Math.round(bitmap.height * scale);
  const canvas = new OffscreenCanvas(w, h);
  canvas.getContext("2d")!.drawImage(bitmap, 0, 0, w, h);
  bitmap.close();
  const blob = await canvas.convertToBlob({ type: "image/jpeg", quality: 0.9 });
  const base64 = await new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result).split(",")[1] ?? "");
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(blob);
  });
  return { base64, mediaType: "image/jpeg", previewUrl: URL.createObjectURL(blob) };
}

export function draftFromExtraction(d: ExtractionDraft, meta: ExtractMeta | null): Draft {
  return {
    name: d.name ?? "", summary: "", credit: d.credit ?? "", cameraModel: d.cameraModel ?? "", body: d.notes.join("\n"), tags: [],
    settings: d.settings!, uncertain: d.uncertainFields, issues: d.issues, raw: d.extracted.raw, meta,
  };
}

export function draftFromRecipe(recipe: FilmRecipe, status: "draft" | "published", slug: string, body: string): Draft {
  return {
    existing: { recipe, status, slug },
    name: recipe.name, summary: recipe.summary, credit: recipe.provenance.author ?? "",
    cameraModel: recipe.compatibleCameras.find((c) => c !== "X-T30 III") ?? "", body, tags: recipe.tags,
    settings: recipe.settings, uncertain: [], issues: [], raw: [], meta: null,
  };
}

export function recipeFromDraft(draft: Draft): FilmRecipe {
  const now = new Date().toISOString();
  const base = draft.existing?.recipe;
  return {
    ...(base ?? {}),
    id: base?.id ?? crypto.randomUUID().toUpperCase(),
    name: draft.name.trim() || "Untitled recipe",
    summary: draft.summary.trim(),
    settings: draft.settings,
    tags: draft.tags,
    moods: base?.moods ?? [],
    isFavorite: base?.isFavorite ?? false,
    compatibleCameras: ["X-T30 III", ...(draft.cameraModel && draft.cameraModel !== "X-T30 III" ? [draft.cameraModel] : [])],
    provenance: base
      ? { ...base.provenance, author: draft.credit.trim() || null }
      : { kind: "imported", author: draft.credit.trim() || null, note: `Imported with AI extraction on the web${draft.cameraModel ? `; source made for ${draft.cameraModel}` : ""}.` },
    createdAt: base?.createdAt ?? now,
    updatedAt: now,
  } as FilmRecipe;
}

export async function saveDraft(token: string, draft: Draft, status: "draft" | "published") {
  return api<{ recipes: Summary[] }>("/api/recipes", token, jsonInit("POST", { recipe: recipeFromDraft(draft), status, body: draft.body }));
}

/** Run async jobs with a fixed concurrency. */
export async function pool<T>(items: T[], limit: number, job: (item: T) => Promise<void>) {
  const queue = [...items];
  await Promise.all(Array.from({ length: Math.min(limit, queue.length) }, async () => {
    for (let item = queue.shift(); item !== undefined; item = queue.shift()) await job(item);
  }));
}
