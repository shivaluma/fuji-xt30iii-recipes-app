"use client";

import { useEffect, useState, useSyncExternalStore } from "react";
import { toast } from "sonner";
import { Sparkles, Trash2, Upload } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { RecipePreview } from "@/components/recipe/recipe-preview";
import {
  DR_PRIORITIES, DYNAMIC_RANGES, EFFECT_LEVELS, FILM_SIMULATION_NAMES, FILM_SIMULATIONS, GRAIN_SIZES, LABELS, RANGES,
  WHITE_BALANCES, WHITE_BALANCE_NAMES, normalize, validate, type FieldKey, type FilmRecipe, type RecipeSettings,
} from "@/lib/recipe/schema";
import type { ExtractionDraft, ExtractionIssue } from "@/lib/extract/mapping";

type ExtractMeta = { provider: string; model: string; attempts: number; latencyMs: number; usage: { inputTokens: number | null; outputTokens: number | null; costUSD: number | null } };

type Summary = { slug: string; name: string; status: string; filmSimulation: keyof typeof FILM_SIMULATION_NAMES; cover: { url: string; kind: string } | null };

const ENUMS: Partial<Record<FieldKey, readonly string[]>> = {
  grainRoughness: EFFECT_LEVELS, grainSize: GRAIN_SIZES, colorChrome: EFFECT_LEVELS, colorChromeFXBlue: EFFECT_LEVELS,
  whiteBalance: WHITE_BALANCES, dynamicRange: DYNAMIC_RANGES, dRangePriority: DR_PRIORITIES,
};
const FIELD_ORDER: FieldKey[] = [
  "whiteBalance", "kelvin", "wbShiftRed", "wbShiftBlue", "grainRoughness", "grainSize", "colorChrome", "colorChromeFXBlue",
  "dynamicRange", "dRangePriority", "highlight", "shadow", "color", "sharpness", "highISONR", "clarity",
  "monochromaticWarmCool", "monochromaticMagentaGreen", "suggestedExposureCompensation",
];
const selectClass = "h-9 w-full rounded-lg border border-input bg-card px-2 text-sm";

const TOKEN_KEY = "filmlab.adminToken";
const tokenListeners = new Set<() => void>();
function readToken() { try { return localStorage.getItem(TOKEN_KEY) ?? ""; } catch { return ""; } }
function useToken() {
  const token = useSyncExternalStore(
    (cb) => { tokenListeners.add(cb); return () => { tokenListeners.delete(cb); }; },
    readToken,
    () => "",
  );
  const save = (t: string) => { try { localStorage.setItem(TOKEN_KEY, t); } catch {} tokenListeners.forEach((l) => l()); };
  return [token, save] as const;
}

async function api<T>(path: string, token: string, init: RequestInit = {}): Promise<T> {
  const res = await fetch(path, { ...init, headers: { ...(init.headers ?? {}), authorization: `Bearer ${token}` } });
  if (res.status === 204) return undefined as T;
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.error ?? `Request failed (${res.status})`);
  return body as T;
}

const fileToBase64 = (file: File) => new Promise<string>((resolve, reject) => {
  const reader = new FileReader();
  reader.onload = () => resolve(String(reader.result).split(",")[1] ?? "");
  reader.onerror = () => reject(reader.error);
  reader.readAsDataURL(file);
});

type Draft = {
  name: string; summary: string; credit: string; cameraModel: string; body: string; settings: RecipeSettings;
  notes: string[]; uncertain: string[]; issues: ExtractionIssue[]; raw: { field: string; text: string }[]; meta: ExtractMeta | null;
};

export function AdminClient() {
  const [token, setToken] = useToken();
  const [file, setFile] = useState<File | null>(null);
  const [text, setText] = useState("");
  const [extracting, setExtracting] = useState(false);
  const [draft, setDraft] = useState<Draft | null>(null);
  const [recipes, setRecipes] = useState<Summary[]>([]);
  const [version, setVersion] = useState(0);
  const refresh = () => setVersion((v) => v + 1);

  useEffect(() => {
    if (!token) return;
    let cancelled = false;
    api<{ recipes: Summary[] }>("/api/recipes?all=1", token)
      .then((r) => { if (!cancelled) setRecipes(r.recipes); })
      .catch((e: Error) => { if (!cancelled) toast.error(e.message); });
    return () => { cancelled = true; };
  }, [token, version]);

  async function extract() {
    setExtracting(true);
    try {
      const body = { text: text || undefined, imageBase64: file ? await fileToBase64(file) : undefined, mediaType: file?.type };
      const { draft: d, meta } = await api<{ draft: ExtractionDraft; meta: ExtractMeta }>("/api/extract", token, {
        method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body),
      });
      if (!d.isRecipe || !d.settings) { toast.error(d.issues[0]?.message ?? "No recipe found in that input."); return; }
      setDraft({
        name: d.name ?? "", summary: "", credit: d.credit ?? "", cameraModel: d.cameraModel ?? "", body: d.notes.join("\n"),
        settings: d.settings, notes: d.notes, uncertain: d.uncertainFields, issues: d.issues, raw: d.extracted.raw, meta,
      });
      if (d.uncertainFields.length) toast.warning(`Check: ${d.uncertainFields.join(", ")}`);
    } catch (e) {
      toast.error((e as Error).message);
    } finally {
      setExtracting(false);
    }
  }

  function setField(k: FieldKey, raw: string) {
    if (!draft) return;
    const isEnum = !!ENUMS[k];
    const value = raw === "" ? { state: "unset" } : { state: "value", value: isEnum ? raw : Number(raw) };
    setDraft({ ...draft, settings: normalize({ ...draft.settings, [k]: value } as RecipeSettings) });
  }

  async function save(status: "draft" | "published") {
    if (!draft) return;
    const now = new Date().toISOString();
    const recipe: FilmRecipe = {
      id: crypto.randomUUID().toUpperCase(), name: draft.name || "Untitled recipe", summary: draft.summary,
      settings: draft.settings, tags: [], moods: [], isFavorite: false,
      compatibleCameras: ["X-T30 III", ...(draft.cameraModel && draft.cameraModel !== "X-T30 III" ? [draft.cameraModel] : [])],
      provenance: { kind: "imported", author: draft.credit || null, note: `Imported with AI extraction on the web${draft.cameraModel ? `; source made for ${draft.cameraModel}` : ""}.` },
      createdAt: now, updatedAt: now,
    };
    try {
      await api("/api/recipes", token, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ recipe, status, body: draft.body }) });
      toast.success(status === "published" ? "Published" : "Saved as draft");
      setDraft(null); setFile(null); setText("");
      refresh();
    } catch (e) {
      toast.error((e as Error).message);
    }
  }

  const issues = draft ? validate(draft.settings) : [];

  return (
    <div className="space-y-8">
      <Card>
        <CardHeader>
          <CardTitle>Admin token</CardTitle>
          <CardDescription>Stored only in this browser. Must match the server&apos;s ADMIN_TOKEN.</CardDescription>
        </CardHeader>
        <CardContent>
          <Input type="password" value={token} onChange={(e) => setToken(e.target.value)} placeholder="ADMIN_TOKEN" />
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2"><Sparkles className="size-5 text-primary" /> Import a recipe with AI</CardTitle>
          <CardDescription>
            Screenshot, recipe card, photo of notes, or pasted text (e.g. a Reddit comment). A vision model reads it into a draft you review; nothing is saved until you choose.
            Images are sent to the server and Anthropic for this one request. Only publish recipes you have the right to share, with credit.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid gap-4 md:grid-cols-2">
            <div className="space-y-2">
              <Label htmlFor="file">Image</Label>
              <Input id="file" type="file" accept="image/jpeg,image/png,image/webp,image/gif" onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="text">Text</Label>
              <Textarea id="text" rows={4} value={text} onChange={(e) => setText(e.target.value)} placeholder="Film Simulation: Classic Chrome&#10;Grain: Weak, Small&#10;…" />
            </div>
          </div>
          <Button onClick={extract} disabled={!token || extracting || (!file && !text.trim())}>
            <Sparkles className="size-4" /> {extracting ? "Reading…" : "Extract recipe"}
          </Button>
        </CardContent>
      </Card>

      {draft && (
        <Card>
          <CardHeader>
            <CardTitle>Review draft</CardTitle>
            <CardDescription>Fields the source didn&apos;t state are “Not set”. Fix anything that looks wrong before publishing.</CardDescription>
          </CardHeader>
          <CardContent className="grid gap-8 lg:grid-cols-2">
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-3">
                <div className="col-span-2 space-y-1"><Label>Name</Label><Input value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} /></div>
                <div className="space-y-1"><Label>Credit</Label><Input value={draft.credit} onChange={(e) => setDraft({ ...draft, credit: e.target.value })} /></div>
                <div className="space-y-1"><Label>Made for camera</Label><Input value={draft.cameraModel} onChange={(e) => setDraft({ ...draft, cameraModel: e.target.value })} /></div>
                <div className="col-span-2 space-y-1"><Label>Summary</Label><Input value={draft.summary} onChange={(e) => setDraft({ ...draft, summary: e.target.value })} /></div>
              </div>
              <div className="space-y-1">
                <Label>Film simulation</Label>
                <select className={selectClass} value={draft.settings.filmSimulation}
                  onChange={(e) => setDraft({ ...draft, settings: normalize({ ...draft.settings, filmSimulation: e.target.value as RecipeSettings["filmSimulation"] }) })}>
                  {FILM_SIMULATIONS.map((s) => <option key={s} value={s}>{FILM_SIMULATION_NAMES[s]}</option>)}
                </select>
              </div>
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
                {FIELD_ORDER.map((k) => {
                  const f = draft.settings[k] as { state: string; value?: string | number };
                  const na = f.state === "notApplicable";
                  const uncertain = draft.uncertain.includes(k);
                  const options = ENUMS[k];
                  const r = RANGES[k];
                  return (
                    <div key={k} className="space-y-1">
                      <Label className={uncertain ? "text-amber-400" : undefined}>{LABELS[k]}{uncertain ? " ?" : ""}</Label>
                      {options ? (
                        <select className={selectClass} disabled={na} value={f.state === "value" ? String(f.value) : ""} onChange={(e) => setField(k, e.target.value)}>
                          <option value="">{na ? "n/a" : "Not set"}</option>
                          {options.map((o) => <option key={o} value={o}>{k === "whiteBalance" ? WHITE_BALANCE_NAMES[o as keyof typeof WHITE_BALANCE_NAMES] : o}</option>)}
                        </select>
                      ) : (
                        <Input type="number" disabled={na} placeholder={na ? "n/a" : "Not set"} step={r?.step ?? 0.01} min={r?.min} max={r?.max}
                          value={f.state === "value" ? String(f.value) : ""} onChange={(e) => setField(k, e.target.value)} />
                      )}
                    </div>
                  );
                })}
              </div>
              <div className="space-y-1"><Label>Story / notes (shown on the page)</Label>
                <Textarea rows={4} value={draft.body} onChange={(e) => setDraft({ ...draft, body: e.target.value })} /></div>
              {draft.issues.length > 0 && (
                <ul className="space-y-1 text-sm">
                  {draft.issues.map((i, n) => (
                    <li key={n} className={i.severity === "error" ? "text-destructive" : "text-amber-400"}>
                      <span className="mr-1.5 rounded bg-muted px-1.5 py-0.5 text-[10px] uppercase tracking-wide">{i.kind}</span>{i.message}
                    </li>
                  ))}
                </ul>
              )}
              {issues.length > 0 && <ul className="space-y-1 text-sm text-destructive">{issues.map((i) => <li key={i.field}>{i.message}</li>)}</ul>}
              {draft.raw.length > 0 && (
                <details className="text-xs text-muted-foreground">
                  <summary className="cursor-pointer">Source text ({draft.raw.length})</summary>
                  <ul className="mt-1 space-y-0.5">{draft.raw.map((r, n) => <li key={n}><span className="text-foreground">{LABELS[r.field as FieldKey] ?? r.field}</span>: {r.text}</li>)}</ul>
                </details>
              )}
              {draft.meta && (
                <p className="text-xs text-muted-foreground">
                  {draft.meta.model} · {(draft.meta.latencyMs / 1000).toFixed(1)} s · {draft.meta.usage.inputTokens ?? "?"}/{draft.meta.usage.outputTokens ?? "?"} tokens
                  {draft.meta.usage.costUSD !== null && ` · $${draft.meta.usage.costUSD.toFixed(5)}`}{draft.meta.attempts > 1 && ` · ${draft.meta.attempts} attempts`}
                </p>
              )}
              <div className="flex gap-2">
                <Button onClick={() => save("published")} disabled={issues.length > 0}>Publish</Button>
                <Button variant="secondary" onClick={() => save("draft")} disabled={issues.length > 0}>Save draft</Button>
                <Button variant="ghost" onClick={() => setDraft(null)}>Discard</Button>
              </div>
            </div>
            <RecipePreview settings={draft.settings} />
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Recipes</CardTitle>
          <CardDescription>Covers: upload only images you own. Choose what the image is so visitors aren&apos;t misled.</CardDescription>
        </CardHeader>
        <CardContent className="divide-y divide-border">
          {recipes.map((r) => <RecipeRowItem key={r.slug} r={r} token={token} onChange={refresh} />)}
          {!recipes.length && <p className="text-sm text-muted-foreground">{token ? "No recipes yet." : "Enter the admin token to manage recipes."}</p>}
        </CardContent>
      </Card>
    </div>
  );
}

function RecipeRowItem({ r, token, onChange }: { r: Summary; token: string; onChange: () => void }) {
  const [kind, setKind] = useState("photo");
  async function act(fn: () => Promise<unknown>, ok: string) {
    try { await fn(); toast.success(ok); onChange(); } catch (e) { toast.error((e as Error).message); }
  }
  async function upload(file: File) {
    const form = new FormData();
    form.set("file", file); form.set("kind", kind);
    await act(() => api(`/api/recipes/${r.slug}/cover`, token, { method: "POST", body: form }), "Cover uploaded");
  }
  return (
    <div className="flex flex-wrap items-center gap-3 py-3">
      <a href={`/recipes/${r.slug}`} className="min-w-40 flex-1 font-semibold hover:text-primary">{r.name}</a>
      <span className="text-xs text-muted-foreground">{FILM_SIMULATION_NAMES[r.filmSimulation]}</span>
      <Badge variant={r.status === "published" ? "default" : "secondary"}>{r.status}</Badge>
      <Button size="sm" variant="secondary" onClick={() => act(() => api(`/api/recipes/${r.slug}`, token, {
        method: "PATCH", headers: { "content-type": "application/json" }, body: JSON.stringify({ status: r.status === "published" ? "draft" : "published" }),
      }), "Updated")}>{r.status === "published" ? "Unpublish" : "Publish"}</Button>
      <select className="h-7 rounded-md border border-input bg-card px-1 text-xs" value={kind} onChange={(e) => setKind(e.target.value)} aria-label="Cover type">
        <option value="photo">Photo</option>
        <option value="camera-jpeg">Camera JPEG</option>
        <option value="approximate-preview">Approximate preview</option>
      </select>
      <label className="inline-flex h-7 cursor-pointer items-center gap-1 rounded-md bg-secondary px-2 text-xs">
        <Upload className="size-3.5" /> Cover
        <input type="file" className="sr-only" accept="image/jpeg,image/png,image/webp" onChange={(e) => e.target.files?.[0] && upload(e.target.files[0])} />
      </label>
      <Button size="icon-sm" variant="destructive" aria-label={`Delete ${r.name}`}
        onClick={() => confirmDelete(r.name) && act(() => api(`/api/recipes/${r.slug}`, token, { method: "DELETE" }), "Deleted")}>
        <Trash2 className="size-4" />
      </Button>
    </div>
  );
}

const confirmDelete = (name: string) => window.confirm(`Delete “${name}”? This can't be undone.`);
