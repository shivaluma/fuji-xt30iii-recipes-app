import { useCallback, useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { AlertTriangle, Check, CircleX, FileText, ImagePlus, Loader2, RotateCcw, Sparkles, Trash2, Type } from "lucide-react";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { FILM_SIMULATION_NAMES } from "@/lib/recipe/schema";
import type { ExtractionDraft } from "@/lib/extract/mapping";
import { cn } from "@/lib/utils";
import { ApiError, api, draftFromExtraction, jsonInit, pool, prepareImage, saveDraft, type Draft, type ExtractMeta } from "./lib";
import { RecipeEditor, draftProblems } from "./recipe-editor";
import { PendingPhotos } from "./photo-manager";

type Status = "queued" | "reading" | "ready" | "review" | "failed" | "saved";
type Item = {
  id: string;
  label: string;
  file?: File;
  text?: string;
  previewUrl?: string;
  status: Status;
  error?: string;
  draft?: Draft;
  saved?: { slug: string; status: "draft" | "published" };
};

const CONCURRENCY = 2;
const ACCEPT = ["image/jpeg", "image/png", "image/webp", "image/gif", "image/heic", "image/heif"];

const STATUS: Record<Status, { label: string; className: string }> = {
  queued: { label: "Queued", className: "bg-surface text-muted-foreground" },
  reading: { label: "Reading…", className: "bg-surface text-foreground" },
  ready: { label: "Ready", className: "bg-emerald-50 text-emerald-800" },
  review: { label: "Check", className: "bg-amber-50 text-amber-800" },
  failed: { label: "Failed", className: "bg-red-50 text-red-700" },
  saved: { label: "Saved", className: "bg-foreground text-background" },
};

function statusFor(draft: Draft): Status {
  const { errors, needsReview } = draftProblems(draft);
  return errors.length || needsReview ? "review" : "ready";
}

export function ImportPanel({ token, onSaved }: { token: string; onSaved: () => void }) {
  const [items, setItems] = useState<Item[]>([]);
  const [selected, setSelected] = useState<string | null>(null);
  const [dragging, setDragging] = useState(false);
  const [textOpen, setTextOpen] = useState(false);
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [checked, setChecked] = useState<Set<string>>(new Set());
  const [anchor, setAnchor] = useState<number | null>(null);
  const [confirm, setConfirm] = useState<{ ids: string[]; status: "draft" | "published"; flagged: number } | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const update = useCallback((id: string, patch: Partial<Item>) => setItems((xs) => xs.map((x) => (x.id === id ? { ...x, ...patch } : x))), []);

  const extract = useCallback(async (item: Item) => {
    update(item.id, { status: "reading", error: undefined });
    try {
      let body: Record<string, unknown> = { text: item.text };
      if (item.file) {
        const img = await prepareImage(item.file);
        update(item.id, { previewUrl: img.previewUrl });
        body = { imageBase64: img.base64, mediaType: img.mediaType };
      }
      const { draft, meta } = await api<{ draft: ExtractionDraft; meta: ExtractMeta }>("/api/extract", token, jsonInit("POST", body));
      if (!draft.isRecipe || !draft.settings) {
        update(item.id, { status: "failed", error: draft.issues[0]?.message ?? "No recipe found" });
        return;
      }
      const d = draftFromExtraction(draft, meta);
      update(item.id, { status: statusFor(d), draft: d, label: d.name || item.label });
    } catch (e) {
      const err = e as Error;
      const message = err instanceof ApiError && err.status === 429 ? "Hourly extraction limit reached — retry later" :
        err.name === "InvalidStateError" || err.name === "EncodingError" ? "This browser can't open that image" : err.message;
      update(item.id, { status: "failed", error: message });
    }
  }, [token, update]);

  const add = useCallback((files: File[], texts: string[] = []) => {
    const images = files.filter((f) => ACCEPT.includes(f.type) || /\.(heic|heif)$/i.test(f.name));
    if (files.length > images.length) toast.error(`${files.length - images.length} file(s) skipped — use JPEG, PNG, WebP, GIF or HEIC`);
    const fresh: Item[] = [
      ...images.map((file) => ({ id: crypto.randomUUID(), label: file.name, file, previewUrl: URL.createObjectURL(file), status: "queued" as const })),
      ...texts.map((t) => ({ id: crypto.randomUUID(), label: t.trim().split("\n")[0].slice(0, 60) || "Pasted text", text: t, status: "queued" as const })),
    ];
    if (!fresh.length) return;
    setItems((xs) => [...xs, ...fresh]);
    setSelected((s) => s ?? fresh[0].id);
    void pool(fresh, CONCURRENCY, extract);
  }, [extract]);

  // Paste images straight onto the page.
  useEffect(() => {
    function onPaste(e: ClipboardEvent) {
      const target = e.target as HTMLElement | null;
      if (target?.closest("input, textarea")) return;
      const files = [...(e.clipboardData?.files ?? [])];
      if (files.length) { e.preventDefault(); add(files); }
    }
    window.addEventListener("paste", onPaste);
    return () => window.removeEventListener("paste", onPaste);
  }, [add]);

  const current = items.find((x) => x.id === selected) ?? null;
  const count = (s: Status) => items.filter((x) => x.status === s).length;
  const ready = items.filter((x) => x.status === "ready");
  const cost = items.reduce((sum, x) => sum + (x.draft?.meta?.usage.costUSD ?? 0), 0);

  function nextAfter(id: string, list: Item[]) {
    const open = list.filter((x) => x.id !== id && (x.status === "review" || x.status === "ready"));
    return open[0]?.id ?? null;
  }

  async function saveOne(item: Item, status: "draft" | "published") {
    if (!item.draft) return;
    const { recipes } = await saveDraft(token, item.draft, status);
    update(item.id, { status: "saved", saved: { slug: recipes[0].slug, status } });
  }

  async function saveCurrent(status: "draft" | "published") {
    if (!current) return;
    setBusy(true);
    try {
      await saveOne(current, status);
      toast.success(status === "published" ? `Published “${current.draft?.name || "recipe"}”` : "Saved as draft");
      onSaved();
      setSelected(nextAfter(current.id, items));
    } catch (e) { toast.error((e as Error).message); } finally { setBusy(false); }
  }

  /** Saves the given items (skipping anything not savable: still reading, failed, invalid values, already saved). */
  async function saveMany(ids: string[], status: "draft" | "published") {
    const targets = items.filter((x) => ids.includes(x.id) && x.draft && x.status !== "saved" && !draftProblems(x.draft).errors.length);
    setBusy(true);
    let ok = 0;
    for (const item of targets) {
      try { await saveOne(item, status); ok++; } catch (e) { update(item.id, { error: (e as Error).message }); }
    }
    setBusy(false);
    const skipped = ids.length - targets.length;
    toast.success(`${ok} recipe${ok === 1 ? "" : "s"} ${status === "published" ? "published" : "saved as drafts"}${skipped ? ` · ${skipped} skipped` : ""}`);
    setChecked(new Set());
    onSaved();
  }

  /** Bulk save of a selection: flagged drafts need an explicit confirmation first. */
  function requestSave(ids: string[], status: "draft" | "published") {
    const flagged = items.filter((x) => ids.includes(x.id) && x.status === "review").length;
    if (flagged) setConfirm({ ids, status, flagged });
    else void saveMany(ids, status);
  }

  function remove(id: string) {
    setItems((xs) => xs.filter((x) => x.id !== id));
    setChecked((c) => { const n = new Set(c); n.delete(id); return n; });
    if (selected === id) setSelected(nextAfter(id, items));
  }

  function removeMany(ids: string[]) {
    setItems((xs) => xs.filter((x) => !ids.includes(x.id)));
    setChecked(new Set());
    if (selected && ids.includes(selected)) setSelected(null);
  }

  /** Click toggles one card; shift-click selects the range from the last toggled card. */
  function toggleCheck(index: number, shift: boolean) {
    const id = items[index].id;
    setChecked((c) => {
      const n = new Set(c);
      if (shift && anchor !== null) {
        const [a, b] = [Math.min(anchor, index), Math.max(anchor, index)];
        items.slice(a, b + 1).forEach((x) => n.add(x.id));
      } else if (n.has(id)) n.delete(id);
      else n.add(id);
      return n;
    });
    setAnchor(index);
  }
  const selection = items.filter((x) => checked.has(x.id)).map((x) => x.id);
  const allChecked = items.length > 0 && selection.length === items.length;

  const footer = current?.draft && current.status !== "saved" && (() => {
    const { errors } = draftProblems(current.draft);
    return (
      <>
        <Button className="h-10 rounded-full px-5" disabled={busy || errors.length > 0} onClick={() => saveCurrent("published")}>Publish</Button>
        <Button variant="secondary" className="h-10 rounded-full px-5" disabled={busy || errors.length > 0} onClick={() => saveCurrent("draft")}>Save draft</Button>
        <Button variant="ghost" className="h-10 rounded-full px-4" onClick={() => remove(current.id)}>Discard</Button>
        {errors.length > 0 && <span className="px-2 text-sm text-destructive">Fix {errors.length} invalid value{errors.length === 1 ? "" : "s"}</span>}
      </>
    );
  })();

  return (
    <div className="space-y-12">
      {/* Drop zone */}
      <div
        onDragOver={(e) => { e.preventDefault(); setDragging(true); }}
        onDragLeave={() => setDragging(false)}
        onDrop={(e) => { e.preventDefault(); setDragging(false); add([...e.dataTransfer.files]); }}
        className={cn("rounded-[24px] border-2 border-dashed p-10 text-center transition-colors sm:p-14",
          dragging ? "border-foreground bg-surface" : "border-hairline")}
      >
        <ImagePlus className="mx-auto size-8 text-muted-foreground" />
        <p className="mt-5 font-display text-3xl font-normal tracking-[-0.03em]">Drop recipe images here</p>
        <p className="mx-auto mt-3 max-w-lg text-muted-foreground">
          Screenshots, recipe cards, photos of notes — as many as you like. You can also paste with ⌘V. Each one is read into a draft for you to check.
        </p>
        <div className="mt-8 flex flex-wrap justify-center gap-3">
          <Button className="h-11 rounded-full px-6" onClick={() => inputRef.current?.click()}><ImagePlus className="size-4" /> Choose images</Button>
          <Button variant="outline" className="h-11 rounded-full px-6" onClick={() => setTextOpen((o) => !o)}><Type className="size-4" /> Paste text</Button>
        </div>
        <input ref={inputRef} type="file" multiple accept={ACCEPT.join(",")} className="sr-only"
          onChange={(e) => { add([...(e.target.files ?? [])]); e.target.value = ""; }} />
        {textOpen && (
          <div className="mx-auto mt-8 max-w-xl space-y-3 text-left">
            <Textarea rows={6} value={text} onChange={(e) => setText(e.target.value)} className="rounded-xl"
              placeholder={"Film Simulation: Classic Chrome\nGrain: Weak, Small\n…\n\nSeparate several recipes with a line containing ---"} />
            <Button className="rounded-full px-5" disabled={!text.trim()} onClick={() => {
              add([], text.split(/^\s*-{3,}\s*$/m).map((t) => t.trim()).filter(Boolean));
              setText(""); setTextOpen(false);
            }}><Sparkles className="size-4" /> Read text</Button>
          </div>
        )}
        <p className="mx-auto mt-8 max-w-xl text-xs leading-relaxed text-tertiary">
          Images are downscaled in your browser, then sent to the server and the configured AI provider for that one request; they aren&apos;t stored. Only publish recipes you have the right to share, with credit.
        </p>
      </div>

      {items.length > 0 && (
        <>
          {/* Queue */}
          <section className="space-y-5">
            <div className="flex flex-wrap items-center justify-between gap-4">
              <p className="text-sm text-muted-foreground">
                {items.length} item{items.length === 1 ? "" : "s"}
                {count("reading") + count("queued") > 0 && ` · ${count("reading") + count("queued")} reading`}
                {count("review") > 0 && ` · ${count("review")} to check`}
                {count("saved") > 0 && ` · ${count("saved")} saved`}
                {cost > 0 && ` · $${cost.toFixed(4)}`}
              </p>
              <div className="flex flex-wrap items-center gap-2">
                <label className="mr-2 inline-flex cursor-pointer items-center gap-2 text-sm text-muted-foreground">
                  <input type="checkbox" className="size-4 accent-foreground" checked={allChecked}
                    onChange={() => setChecked(allChecked ? new Set() : new Set(items.map((x) => x.id)))} />
                  Select all
                </label>
                {selection.length > 0 ? (
                  <>
                    <Button className="rounded-full px-4" disabled={busy} onClick={() => requestSave(selection, "published")}><Check className="size-4" /> Publish {selection.length}</Button>
                    <Button variant="secondary" className="rounded-full px-4" disabled={busy} onClick={() => requestSave(selection, "draft")}>Save {selection.length} as drafts</Button>
                    <Button variant="outline" className="rounded-full px-4" disabled={busy} onClick={() => removeMany(selection)}><Trash2 className="size-4" /> Remove</Button>
                    <Button variant="ghost" className="rounded-full px-3" onClick={() => setChecked(new Set())}>Clear</Button>
                  </>
                ) : ready.length > 0 && (
                  <>
                    <Button className="rounded-full px-4" disabled={busy} onClick={() => saveMany(ready.map((x) => x.id), "published")}><Check className="size-4" /> Publish {ready.length} ready</Button>
                    <Button variant="secondary" className="rounded-full px-4" disabled={busy} onClick={() => saveMany(ready.map((x) => x.id), "draft")}>Save {ready.length} as drafts</Button>
                  </>
                )}
                {count("failed") > 0 && (
                  <Button variant="outline" className="rounded-full px-4" onClick={() => void pool(items.filter((x) => x.status === "failed"), CONCURRENCY, extract)}>
                    <RotateCcw className="size-4" /> Retry failed
                  </Button>
                )}
                {count("saved") > 0 && (
                  <Button variant="ghost" className="rounded-full px-4" onClick={() => { setItems((xs) => xs.filter((x) => x.status !== "saved")); if (current?.status === "saved") setSelected(null); }}>
                    Clear saved
                  </Button>
                )}
              </div>
            </div>
            <div className="-mx-2 flex snap-x scroll-px-2 gap-3 overflow-x-auto px-2 pb-3 pt-2 [scrollbar-width:thin]">
              {items.map((x, index) => (
                <div key={x.id} className="group relative w-44 shrink-0 snap-start">
                  <button type="button" onClick={() => setSelected(x.id)} aria-pressed={selected === x.id}
                    className={cn("block w-full rounded-[18px] p-1.5 text-left outline-none transition-colors focus-visible:ring-2 focus-visible:ring-ring", selected === x.id ? "bg-surface ring-1 ring-foreground/70" : "hover:bg-surface")}>
                    <div className="relative aspect-[4/5] overflow-hidden rounded-[14px] bg-surface ring-1 ring-inset ring-hairline">
                      {x.previewUrl ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img src={x.previewUrl} alt="" className={cn("size-full object-cover", x.status === "reading" && "opacity-60")} />
                      ) : (
                        <div className="flex size-full flex-col gap-2 p-3 pt-9">
                          <FileText className="size-4 shrink-0 text-tertiary" />
                          <p className="line-clamp-[9] whitespace-pre-line font-mono text-[10px] leading-relaxed text-muted-foreground">{x.text}</p>
                        </div>
                      )}
                      <span className={cn("absolute left-2 top-2 inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-medium", STATUS[x.status].className)}>
                        {x.status === "reading" && <Loader2 className="size-3 animate-spin" />}
                        {x.status === "review" && <AlertTriangle className="size-3" />}
                        {x.status === "failed" && <CircleX className="size-3" />}
                        {x.status === "saved" && <Check className="size-3" />}
                        {x.status === "saved" && x.saved?.status === "published" ? "Published" : STATUS[x.status].label}
                      </span>
                    </div>
                    <div className="px-1 pb-1 pt-3">
                      <p className="truncate text-sm font-medium">{x.draft?.name || x.label}</p>
                      <p className="truncate text-xs text-muted-foreground">
                        {x.error ?? (x.draft ? FILM_SIMULATION_NAMES[x.draft.settings.filmSimulation] : x.file ? "Image" : "Text")}
                      </p>
                    </div>
                  </button>
                  <label className={cn("absolute right-3 top-3 grid size-7 cursor-pointer place-items-center rounded-full bg-white/90 shadow-sm transition-opacity",
                    checked.has(x.id) || checked.size > 0 ? "opacity-100" : "opacity-0 focus-within:opacity-100 group-hover:opacity-100")}>
                    <input type="checkbox" className="size-4 cursor-pointer accent-foreground" aria-label={`Select ${x.draft?.name || x.label}`}
                      checked={checked.has(x.id)} onChange={() => {}}
                      onClick={(e) => toggleCheck(index, e.shiftKey)} />
                  </label>
                </div>
              ))}
            </div>
          </section>

          {/* Review */}
          {current && (
            <section className="border-t border-hairline pt-12">
              {current.status === "saved" ? (
                <div className="rounded-[24px] bg-surface p-10 text-center">
                  <p className="font-display text-2xl tracking-[-0.03em]">“{current.draft?.name}” is {current.saved?.status === "published" ? "published" : "saved as a draft"}.</p>
                  <a href={`/recipes/${current.saved?.slug}`} className="mt-4 inline-block text-sm underline underline-offset-4">Open recipe page</a>
                </div>
              ) : current.status === "failed" ? (
                <div className="rounded-[24px] bg-surface p-10 text-center">
                  <p className="font-display text-2xl tracking-[-0.03em]">Couldn&apos;t read this one</p>
                  <p className="mt-2 text-muted-foreground">{current.error}</p>
                  <Button variant="outline" className="mt-6 rounded-full px-5" onClick={() => void extract(current)}><RotateCcw className="size-4" /> Try again</Button>
                </div>
              ) : current.draft ? (
                <RecipeEditor
                  key={current.id}
                  draft={current.draft}
                  sourceImage={current.previewUrl}
                  onChange={(d) => update(current.id, { draft: d, status: statusFor(d) })}
                  footer={footer}
                  photos={<PendingPhotos draft={current.draft} onUpdate={(fn) => setItems((xs) => xs.map((x) => (x.id === current.id && x.draft ? { ...x, draft: fn(x.draft) } : x)))} />}
                />
              ) : (
                <div className="flex items-center justify-center gap-3 rounded-[24px] bg-surface p-14 text-muted-foreground">
                  <Loader2 className="size-5 animate-spin" /> Reading {current.label}…
                </div>
              )}
            </section>
          )}
        </>
      )}

      <Dialog open={!!confirm} onOpenChange={(o) => { if (!o) setConfirm(null); }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{confirm?.flagged} of these still need checking</DialogTitle>
            <DialogDescription>
              The AI wasn&apos;t sure about some values, or found settings this camera doesn&apos;t have. Open them to review, or {confirm?.status === "published" ? "publish" : "save"} them as they are. Drafts with invalid values are always skipped.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="ghost" className="rounded-full" onClick={() => setConfirm(null)}>Review first</Button>
            <Button className="rounded-full" onClick={() => { const c = confirm!; setConfirm(null); void saveMany(c.ids, c.status); }}>
              {confirm?.status === "published" ? "Publish anyway" : "Save anyway"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
