import { useEffect, useMemo, useState } from "react";
import { toast } from "sonner";
import { ArrowUpRight, Download, Eye, EyeOff, Loader2, Pencil, Search, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { RecipeThumb } from "@/components/recipe/recipe-thumb";
import { FILM_SIMULATION_NAMES, type FilmRecipe } from "@/lib/recipe/schema";
import { GENERATION_LABEL } from "@/lib/recipe/cameras";
import { cn } from "@/lib/utils";
import { api, draftFromRecipe, jsonInit, preparePhoto, saveDraft, uploadPhotos, type Draft, type RemotePhoto, type Summary } from "./lib";
import { RecipeEditor, draftProblems } from "./recipe-editor";
import { PhotoManager } from "./photo-manager";

type Filter = "all" | "published" | "draft";
type Full = { recipe: FilmRecipe; slug: string; status: "draft" | "published"; body: string; cover: { url: string; kind: string } | null; photos: RemotePhoto[] };

const dateFmt = new Intl.DateTimeFormat("en", { month: "short", day: "numeric", year: "numeric" });

export function RecipesPanel({ token, version, onChange }: { token: string; version: number; onChange: () => void }) {
  const [recipes, setRecipes] = useState<Summary[] | null>(null);
  const [q, setQ] = useState("");
  const [filter, setFilter] = useState<Filter>("all");
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [busy, setBusy] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState<string[] | null>(null);
  const [editing, setEditing] = useState<{ draft: Draft; photos: RemotePhoto[] } | null>(null);

  useEffect(() => {
    let cancelled = false;
    api<{ recipes: Summary[] }>("/api/recipes?all=1", token)
      .then((r) => { if (!cancelled) setRecipes(r.recipes); })
      .catch((e: Error) => { if (!cancelled) toast.error(e.message); });
    return () => { cancelled = true; };
  }, [token, version]);

  const shown = useMemo(() => (recipes ?? []).filter((r) =>
    (filter === "all" || r.status === filter) &&
    (!q.trim() || `${r.name} ${FILM_SIMULATION_NAMES[r.filmSimulation]} ${r.summary}`.toLowerCase().includes(q.trim().toLowerCase())),
  ), [recipes, filter, q]);
  const counts = { all: recipes?.length ?? 0, published: recipes?.filter((r) => r.status === "published").length ?? 0, draft: recipes?.filter((r) => r.status === "draft").length ?? 0 };
  const selection = shown.filter((r) => picked.has(r.slug)).map((r) => r.slug);
  const allPicked = shown.length > 0 && selection.length === shown.length;

  const toggle = (slug: string) => setPicked((p) => { const n = new Set(p); if (n.has(slug)) n.delete(slug); else n.add(slug); return n; });

  async function bulk(slugs: string[], label: string, fn: (slug: string) => Promise<unknown>) {
    setBusy(true);
    let ok = 0;
    for (const slug of slugs) { try { await fn(slug); ok++; } catch (e) { toast.error(`${slug}: ${(e as Error).message}`); } }
    setBusy(false);
    if (ok) toast.success(`${ok} recipe${ok === 1 ? "" : "s"} ${label}`);
    setPicked(new Set());
    onChange();
  }
  const setStatus = (slugs: string[], status: "draft" | "published") =>
    bulk(slugs, status === "published" ? "published" : "unpublished", (s) => api(`/api/recipes/${s}`, token, jsonInit("PATCH", { status })));
  const remove = (slugs: string[]) => bulk(slugs, "deleted", (s) => api(`/api/recipes/${s}`, token, { method: "DELETE" }));

  async function exportJSON(slugs: string[]) {
    setBusy(true);
    try {
      const full = await Promise.all(slugs.map((s) => api<Full>(`/api/recipes/${s}?all=1`, token)));
      const doc = { format: "filmlab.recipes", schemaVersion: 1, exportedAt: new Date().toISOString(), appVersion: "web-admin", recipes: full.map((f) => f.recipe) };
      const url = URL.createObjectURL(new Blob([JSON.stringify(doc, null, 2)], { type: "application/json" }));
      const a = Object.assign(document.createElement("a"), { href: url, download: `filmlab-recipes-${slugs.length}.filmlab.json` });
      a.click();
      URL.revokeObjectURL(url);
    } catch (e) { toast.error((e as Error).message); } finally { setBusy(false); }
  }

  async function openEditor(slug: string) {
    try {
      const f = await api<Full>(`/api/recipes/${slug}?all=1`, token);
      setEditing({ draft: draftFromRecipe(f.recipe, f.status, f.slug, f.body), photos: f.photos });
    } catch (e) { toast.error((e as Error).message); }
  }

  async function saveEdit(status: "draft" | "published") {
    if (!editing) return;
    setBusy(true);
    try {
      await saveDraft(token, editing.draft, status);
      toast.success("Saved");
      setEditing(null);
      onChange();
    } catch (e) { toast.error((e as Error).message); } finally { setBusy(false); }
  }

  if (recipes === null) return <div className="flex items-center gap-2 py-20 text-muted-foreground"><Loader2 className="size-4 animate-spin" /> Loading recipes…</div>;

  return (
    <div className="space-y-8">
      {/* Toolbar */}
      <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div className="inline-flex w-fit rounded-full bg-surface p-1 text-sm">
          {(["all", "published", "draft"] as const).map((f) => (
            <button key={f} type="button" onClick={() => setFilter(f)}
              className={cn("rounded-full px-4 py-1.5 transition-colors", filter === f ? "bg-background shadow-sm" : "text-muted-foreground hover:text-foreground")}>
              {f === "all" ? "All" : f === "published" ? "Published" : "Drafts"} <span className="text-tertiary">{counts[f]}</span>
            </button>
          ))}
        </div>
        <div className="relative lg:w-80">
          <Search className="pointer-events-none absolute left-4 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search recipes" aria-label="Search recipes"
            className="h-10 w-full rounded-full bg-surface pl-11 pr-4 text-sm outline-none ring-foreground/20 placeholder:text-tertiary focus:ring-2" />
        </div>
      </div>

      {/* Bulk bar */}
      {selection.length > 0 && (
        <div className="sticky top-24 z-20 flex flex-wrap items-center gap-2 rounded-full border border-hairline bg-background/95 p-2 pl-5 shadow-[0_8px_30px_rgba(0,0,0,.08)] backdrop-blur">
          <span className="mr-auto text-sm font-medium">{selection.length} selected</span>
          <Button size="sm" className="h-9 rounded-full px-4" disabled={busy} onClick={() => setStatus(selection, "published")}><Eye className="size-4" /> Publish</Button>
          <Button size="sm" variant="secondary" className="h-9 rounded-full px-4" disabled={busy} onClick={() => setStatus(selection, "draft")}><EyeOff className="size-4" /> Unpublish</Button>
          <Button size="sm" variant="outline" className="h-9 rounded-full px-4" disabled={busy} onClick={() => exportJSON(selection)}><Download className="size-4" /> Export</Button>
          <Button size="sm" variant="destructive" className="h-9 rounded-full px-4" disabled={busy} onClick={() => setConfirmDelete(selection)}><Trash2 className="size-4" /> Delete</Button>
          <Button size="sm" variant="ghost" className="h-9 rounded-full px-3" onClick={() => setPicked(new Set())}>Clear</Button>
        </div>
      )}

      {/* List */}
      {shown.length === 0 ? (
        <div className="rounded-[24px] bg-surface px-8 py-20 text-center text-muted-foreground">
          {recipes.length === 0 ? "No recipes yet — import some from the Import tab." : "Nothing matches."}
        </div>
      ) : (
        <div className="border-t border-hairline">
          <label className="flex items-center gap-4 border-b border-hairline py-3 text-xs uppercase tracking-[.08em] text-tertiary">
            <input type="checkbox" className="size-4 accent-foreground" checked={allPicked}
              onChange={() => setPicked(allPicked ? new Set() : new Set(shown.map((r) => r.slug)))} />
            Select all
          </label>
          {shown.map((r) => (
            <div key={r.slug} className={cn("group flex items-center gap-4 border-b border-hairline py-4 transition-colors sm:gap-6", picked.has(r.slug) && "bg-surface/60")}>
              <input type="checkbox" className="size-4 shrink-0 accent-foreground" aria-label={`Select ${r.name}`} checked={picked.has(r.slug)} onChange={() => toggle(r.slug)} />
              <button type="button" onClick={() => openEditor(r.slug)} className="relative aspect-[4/3] w-24 shrink-0 overflow-hidden rounded-xl bg-surface sm:w-28">
                {r.cover ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={r.cover.url} alt="" className="size-full object-cover" />
                ) : (
                  <RecipeThumb settings={r.settings} className="size-full object-cover" />
                )}
              </button>
              <div className="min-w-0 flex-1">
                <button type="button" onClick={() => openEditor(r.slug)} className="block max-w-full truncate text-left font-display text-xl tracking-[-0.02em] hover:opacity-70">{r.name}</button>
                <p className="mt-1 truncate text-sm text-muted-foreground">
                  {FILM_SIMULATION_NAMES[r.filmSimulation]}{r.xTransGeneration ? ` · ${GENERATION_LABEL[r.xTransGeneration]}` : ""} · updated {dateFmt.format(new Date(r.updatedAt))}
                </p>
              </div>
              <span className={cn("hidden rounded-full px-2.5 py-1 text-xs font-medium sm:inline", r.status === "published" ? "bg-foreground text-background" : "bg-surface text-muted-foreground")}>
                {r.status === "published" ? "Published" : "Draft"}
              </span>
              <div className="flex shrink-0 items-center gap-1">
                <Button size="icon" variant="ghost" className="rounded-full" aria-label={r.status === "published" ? `Unpublish ${r.name}` : `Publish ${r.name}`} title={r.status === "published" ? "Unpublish" : "Publish"}
                  disabled={busy} onClick={() => setStatus([r.slug], r.status === "published" ? "draft" : "published")}>
                  {r.status === "published" ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
                </Button>
                <Button size="icon" variant="ghost" className="rounded-full" aria-label={`Edit ${r.name}`} title="Edit" onClick={() => openEditor(r.slug)}><Pencil className="size-4" /></Button>
                {r.status === "published" && (
                  <a href={`/recipes/${r.slug}`} target="_blank" rel="noreferrer" aria-label={`View ${r.name}`} title="View on site"
                    className="hidden size-8 place-items-center rounded-full hover:bg-muted sm:grid"><ArrowUpRight className="size-4" /></a>
                )}
                <Button size="icon" variant="ghost" className="rounded-full text-destructive hover:text-destructive" aria-label={`Delete ${r.name}`} title="Delete" onClick={() => setConfirmDelete([r.slug])}><Trash2 className="size-4" /></Button>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Delete confirmation */}
      <Dialog open={!!confirmDelete} onOpenChange={(o) => { if (!o) setConfirmDelete(null); }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete {confirmDelete?.length === 1 ? "this recipe" : `${confirmDelete?.length} recipes`}?</DialogTitle>
            <DialogDescription>This removes {confirmDelete?.length === 1 ? "it" : "them"} and any cover images for good. Export first if you might want {confirmDelete?.length === 1 ? "it" : "them"} back.</DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="ghost" className="rounded-full" onClick={() => setConfirmDelete(null)}>Cancel</Button>
            <Button variant="destructive" className="rounded-full" disabled={busy} onClick={async () => { const s = confirmDelete ?? []; setConfirmDelete(null); await remove(s); }}>Delete</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Editor */}
      <Dialog open={!!editing} onOpenChange={(o) => { if (!o) setEditing(null); }}>
        <DialogContent className="max-h-[92vh] overflow-y-auto p-6 sm:max-w-6xl sm:p-10">
          {editing && (
            <>
              <DialogHeader className="mb-6">
                <DialogTitle className="font-display text-3xl font-normal tracking-[-0.03em]">Edit recipe</DialogTitle>
                <DialogDescription>Changes go live when you save{editing.draft.existing?.status === "published" ? " — this recipe is published" : ""}.</DialogDescription>
              </DialogHeader>
              <div>
                <RecipeEditor
                  draft={editing.draft}
                  photos={<RemotePhotos token={token} slug={editing.draft.existing!.slug} photos={editing.photos}
                    onChange={(photos) => { setEditing((e) => (e ? { ...e, photos } : e)); onChange(); }} />}
                  onChange={(draft) => setEditing((e) => (e ? { ...e, draft } : e))}
                  footer={(() => {
                    const { errors } = draftProblems(editing.draft);
                    const wasPublished = editing.draft.existing?.status === "published";
                    return (
                      <>
                        <Button className="h-10 rounded-full px-5" disabled={busy || errors.length > 0} onClick={() => saveEdit(wasPublished ? "published" : "draft")}>Save</Button>
                        <Button variant="secondary" className="h-10 rounded-full px-5" disabled={busy || errors.length > 0} onClick={() => saveEdit(wasPublished ? "draft" : "published")}>
                          {wasPublished ? "Save & unpublish" : "Save & publish"}
                        </Button>
                        <Button variant="ghost" className="h-10 rounded-full px-4" onClick={() => setEditing(null)}>Cancel</Button>
                      </>
                    );
                  })()}
                />
              </div>
            </>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}

function RemotePhotos({ token, slug, photos, onChange }: { token: string; slug: string; photos: RemotePhoto[]; onChange: (p: RemotePhoto[]) => void }) {
  const [busy, setBusy] = useState(false);
  async function run(fn: () => Promise<{ photos: RemotePhoto[] }>) {
    setBusy(true);
    try { onChange((await fn()).photos); } catch (e) { toast.error((e as Error).message); } finally { setBusy(false); }
  }
  return (
    <PhotoManager
      busy={busy}
      photos={photos}
      onAdd={(files) => run(async () => uploadPhotos(token, slug, await Promise.all(files.map(async (f) => ({ blob: (await preparePhoto(f)).blob, kind: "photo" as const })))))}
      onRemove={(id) => run(() => api(`/api/recipes/${slug}/photos/${id}`, token, { method: "DELETE" }))}
      onCover={(id) => run(() => api(`/api/recipes/${slug}/photos/${id}`, token, jsonInit("PATCH", { cover: true })))}
      onKind={(id, kind) => run(() => api(`/api/recipes/${slug}/photos/${id}`, token, jsonInit("PATCH", { kind })))}
    />
  );
}
