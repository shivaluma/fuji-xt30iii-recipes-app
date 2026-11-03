import "server-only";
import { DatabaseSync } from "node:sqlite";
import fs from "node:fs";
import path from "node:path";
import { FilmRecipeSchema, type FilmRecipe } from "@/lib/recipe/schema";

// SQLite via Node's built-in node:sqlite (no native dependencies). The full FilmLab recipe JSON is
// the source of truth; a few columns are denormalized for listing and filtering.

export type RecipeStatus = "draft" | "published";
export type CoverKind = "approximate-preview" | "camera-jpeg" | "photo";

export type RecipePhoto = { id: string; file: string; kind: CoverKind; position: number };

export type RecipeRow = {
  id: string;
  slug: string;
  name: string;
  summary: string;
  body: string;
  filmSimulation: FilmRecipe["settings"]["filmSimulation"];
  recipe: FilmRecipe;
  coverFile: string | null;
  coverKind: CoverKind | null;
  status: RecipeStatus;
  createdAt: string;
  updatedAt: string;
  publishedAt: string | null;
  downloads: number;
  /** Sample photos (only loaded by getRecipe); the cover is one of them. */
  photos: RecipePhoto[];
};

export const MAX_PHOTOS = 12;

const DATA_DIR = process.env.DATA_DIR ?? path.join(process.cwd(), "data");
export const UPLOAD_DIR = path.join(DATA_DIR, "uploads");
const DB_PATH = process.env.DATABASE_PATH ?? path.join(DATA_DIR, "filmlab.db");

let db: DatabaseSync | null = null;

function open(): DatabaseSync {
  if (db) return db;
  fs.mkdirSync(/*turbopackIgnore: true*/ path.dirname(DB_PATH), { recursive: true });
  fs.mkdirSync(/*turbopackIgnore: true*/ UPLOAD_DIR, { recursive: true });
  db = new DatabaseSync(DB_PATH);
  db.exec(`
    PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS recipes (
      id TEXT PRIMARY KEY,
      slug TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      summary TEXT NOT NULL DEFAULT '',
      body TEXT NOT NULL DEFAULT '',
      film_simulation TEXT NOT NULL,
      recipe_json TEXT NOT NULL,
      cover_file TEXT,
      cover_kind TEXT,
      status TEXT NOT NULL DEFAULT 'draft',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      published_at TEXT
    );
    CREATE INDEX IF NOT EXISTS recipes_status ON recipes(status, published_at);
    CREATE TABLE IF NOT EXISTS recipe_photos (
      id TEXT PRIMARY KEY,
      recipe_id TEXT NOT NULL,
      file TEXT NOT NULL,
      kind TEXT NOT NULL,
      position INTEGER NOT NULL,
      created_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS recipe_photos_recipe ON recipe_photos(recipe_id, position);
    CREATE TABLE IF NOT EXISTS gallery_photos (
      id TEXT PRIMARY KEY,
      file TEXT NOT NULL,
      title TEXT NOT NULL DEFAULT '',
      caption TEXT NOT NULL DEFAULT '',
      recipe_id TEXT,
      width INTEGER,
      height INTEGER,
      position INTEGER NOT NULL,
      created_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS gallery_photos_position ON gallery_photos(position);
    CREATE INDEX IF NOT EXISTS gallery_photos_recipe ON gallery_photos(recipe_id);
  `);
  // Additive migrations for existing databases.
  const columns = (db.prepare("PRAGMA table_info(recipes)").all() as { name: string }[]).map((c) => c.name);
  if (!columns.includes("downloads")) db.exec("ALTER TABLE recipes ADD COLUMN downloads INTEGER NOT NULL DEFAULT 0");
  // Covers predate the photo gallery: make sure every cover is also a gallery photo.
  db.exec(`
    INSERT INTO recipe_photos (id, recipe_id, file, kind, position, created_at)
    SELECT lower(hex(randomblob(16))), r.id, r.cover_file, COALESCE(r.cover_kind, 'photo'), 0, r.updated_at
    FROM recipes r
    WHERE r.cover_file IS NOT NULL AND NOT EXISTS (SELECT 1 FROM recipe_photos p WHERE p.recipe_id = r.id AND p.file = r.cover_file)
  `);
  return db;
}

export function slugify(name: string) {
  const s = name.normalize("NFKD").replace(/[̀-ͯ]/g, "").toLowerCase()
    .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 60);
  return s || "recipe";
}

function uniqueSlug(d: DatabaseSync, name: string, id: string) {
  const base = slugify(name);
  let slug = base;
  for (let i = 2; ; i++) {
    const row = d.prepare("SELECT id FROM recipes WHERE slug = ?").get(slug) as { id: string } | undefined;
    if (!row || row.id === id) return slug;
    slug = `${base}-${i}`;
  }
}

type DBRow = {
  id: string; slug: string; name: string; summary: string; body: string; film_simulation: string; recipe_json: string;
  cover_file: string | null; cover_kind: string | null; status: string; created_at: string; updated_at: string; published_at: string | null;
  downloads: number | null;
};

const toRow = (r: DBRow): RecipeRow => ({
  id: r.id, slug: r.slug, name: r.name, summary: r.summary, body: r.body,
  filmSimulation: r.film_simulation as RecipeRow["filmSimulation"],
  recipe: FilmRecipeSchema.parse(JSON.parse(r.recipe_json)),
  coverFile: r.cover_file, coverKind: r.cover_kind as CoverKind | null, status: r.status as RecipeStatus,
  createdAt: r.created_at, updatedAt: r.updated_at, publishedAt: r.published_at, downloads: r.downloads ?? 0,
  photos: [],
});

export function upsertRecipe(recipe: FilmRecipe, opts: { status?: RecipeStatus; body?: string } = {}, d = open()): RecipeRow {
  const now = new Date().toISOString();
  const existing = d.prepare("SELECT * FROM recipes WHERE id = ?").get(recipe.id) as DBRow | undefined;
  const status = opts.status ?? (existing?.status as RecipeStatus | undefined) ?? "draft";
  const slug = existing?.slug ?? uniqueSlug(d, recipe.name, recipe.id);
  const publishedAt = status === "published" ? existing?.published_at ?? now : null;
  d.prepare(`
    INSERT INTO recipes (id, slug, name, summary, body, film_simulation, recipe_json, status, created_at, updated_at, published_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET name = excluded.name, summary = excluded.summary, body = excluded.body,
      film_simulation = excluded.film_simulation, recipe_json = excluded.recipe_json, status = excluded.status,
      updated_at = excluded.updated_at, published_at = excluded.published_at
  `).run(recipe.id, slug, recipe.name, recipe.summary, opts.body ?? existing?.body ?? "", recipe.settings.filmSimulation,
    JSON.stringify(recipe), status, existing?.created_at ?? now, now, publishedAt);
  return getRecipe(slug, { includeDrafts: true })!;
}

export function getRecipe(slug: string, { includeDrafts = false } = {}): RecipeRow | null {
  const r = open().prepare(`SELECT * FROM recipes WHERE slug = ? ${includeDrafts ? "" : "AND status = 'published'"}`).get(slug) as DBRow | undefined;
  return r ? { ...toRow(r), photos: listPhotos(r.id) } : null;
}

export function listRecipes(opts: { includeDrafts?: boolean; simulation?: string; query?: string; limit?: number } = {}): RecipeRow[] {
  const where: string[] = [], args: (string | number)[] = [];
  if (!opts.includeDrafts) where.push("status = 'published'");
  if (opts.simulation) { where.push("film_simulation = ?"); args.push(opts.simulation); }
  if (opts.query) { where.push("(name LIKE ? OR summary LIKE ? OR recipe_json LIKE ?)"); const q = `%${opts.query}%`; args.push(q, q, q); }
  const sql = `SELECT * FROM recipes ${where.length ? "WHERE " + where.join(" AND ") : ""}
    ORDER BY COALESCE(published_at, updated_at) DESC LIMIT ?`;
  args.push(opts.limit ?? 200);
  return (open().prepare(sql).all(...args) as DBRow[]).map(toRow);
}

export function updateMeta(slug: string, patch: { status?: RecipeStatus; body?: string }) {
  const row = getRecipe(slug, { includeDrafts: true });
  if (!row) return null;
  return upsertRecipe(row.recipe, { status: patch.status ?? row.status, body: patch.body ?? row.body });
}

function listPhotos(recipeId: string): RecipePhoto[] {
  // node:sqlite rows have a null prototype; copy into plain objects so they can cross into Client Components.
  return (open().prepare("SELECT id, file, kind, position FROM recipe_photos WHERE recipe_id = ? ORDER BY position, created_at").all(recipeId) as RecipePhoto[])
    .map((p) => ({ id: p.id, file: p.file, kind: p.kind, position: p.position }));
}

const removeFile = (file: string) => fs.rmSync(/*turbopackIgnore: true*/ path.join(UPLOAD_DIR, file), { force: true });

/** Adds an uploaded file to the recipe's gallery; it becomes the cover if there is none yet (or `asCover`). */
export function addPhoto(slug: string, file: string, kind: CoverKind, { asCover = false } = {}) {
  const row = getRecipe(slug, { includeDrafts: true });
  if (!row) return null;
  const position = (row.photos.at(-1)?.position ?? -1) + 1;
  const id = crypto.randomUUID();
  open().prepare("INSERT INTO recipe_photos (id, recipe_id, file, kind, position, created_at) VALUES (?, ?, ?, ?, ?, ?)")
    .run(id, row.id, file, kind, position, new Date().toISOString());
  if (asCover || !row.coverFile) setCover(slug, id);
  else touch(row.id);
  return getRecipe(slug, { includeDrafts: true });
}

/** Makes one of the recipe's photos the cover. */
export function setCover(slug: string, photoId: string) {
  const row = getRecipe(slug, { includeDrafts: true });
  const photo = row?.photos.find((p) => p.id === photoId);
  if (!row || !photo) return null;
  open().prepare("UPDATE recipes SET cover_file = ?, cover_kind = ?, updated_at = ? WHERE id = ?").run(photo.file, photo.kind, new Date().toISOString(), row.id);
  return getRecipe(slug, { includeDrafts: true });
}

export function updatePhoto(slug: string, photoId: string, patch: { kind?: CoverKind }) {
  const row = getRecipe(slug, { includeDrafts: true });
  const photo = row?.photos.find((p) => p.id === photoId);
  if (!row || !photo) return null;
  if (patch.kind) {
    open().prepare("UPDATE recipe_photos SET kind = ? WHERE id = ?").run(patch.kind, photoId);
    if (row.coverFile === photo.file) open().prepare("UPDATE recipes SET cover_kind = ? WHERE id = ?").run(patch.kind, row.id);
  }
  touch(row.id);
  return getRecipe(slug, { includeDrafts: true });
}

export function deletePhoto(slug: string, photoId: string) {
  const row = getRecipe(slug, { includeDrafts: true });
  const photo = row?.photos.find((p) => p.id === photoId);
  if (!row || !photo) return null;
  open().prepare("DELETE FROM recipe_photos WHERE id = ?").run(photoId);
  removeFile(photo.file);
  if (row.coverFile === photo.file) {
    const next = row.photos.find((p) => p.id !== photoId);
    if (next) setCover(slug, next.id);
    else open().prepare("UPDATE recipes SET cover_file = NULL, cover_kind = NULL WHERE id = ?").run(row.id);
  }
  touch(row.id);
  return getRecipe(slug, { includeDrafts: true });
}

function touch(recipeId: string) {
  open().prepare("UPDATE recipes SET updated_at = ? WHERE id = ?").run(new Date().toISOString(), recipeId);
}

export function deleteRecipe(slug: string) {
  const row = getRecipe(slug, { includeDrafts: true });
  if (!row) return false;
  const files = new Set([...row.photos.map((p) => p.file), ...(row.coverFile ? [row.coverFile] : [])]);
  files.forEach(removeFile);
  open().prepare("DELETE FROM recipe_photos WHERE recipe_id = ?").run(row.id);
  // Gallery photos are the owner's favourites in their own right: keep them, just unlink.
  open().prepare("UPDATE gallery_photos SET recipe_id = NULL WHERE recipe_id = ?").run(row.id);
  open().prepare("DELETE FROM recipes WHERE slug = ?").run(slug);
  return true;
}

/** Counts a FilmLab-file download (public, unauthenticated; best-effort). */
export function countDownload(slug: string) {
  open().prepare("UPDATE recipes SET downloads = downloads + 1 WHERE slug = ? AND status = 'published'").run(slug);
}

// ---------------------------------------------------------------------------------------------
// Gallery: the owner's favourite photos, each optionally linked to the recipe it was shot with.

export const MAX_GALLERY_PHOTOS = 500;

/** The linked recipe as the gallery shows it. `published` false = linked to a draft (not linked publicly). */
export type GalleryRecipeLink = { slug: string; name: string; filmSimulation: FilmRecipe["settings"]["filmSimulation"]; published: boolean };

export type GalleryItem = {
  id: string; file: string; title: string; caption: string;
  width: number | null; height: number | null; position: number; createdAt: string;
  recipe: GalleryRecipeLink | null;
};

type GalleryDBRow = {
  id: string; file: string; title: string; caption: string; width: number | null; height: number | null; position: number; created_at: string;
  r_slug: string | null; r_name: string | null; r_sim: string | null; r_status: string | null;
};

const toGalleryItem = (g: GalleryDBRow): GalleryItem => ({
  id: g.id, file: g.file, title: g.title, caption: g.caption, width: g.width, height: g.height, position: g.position, createdAt: g.created_at,
  recipe: g.r_slug
    ? { slug: g.r_slug, name: g.r_name!, filmSimulation: g.r_sim as GalleryRecipeLink["filmSimulation"], published: g.r_status === "published" }
    : null,
});

const GALLERY_SELECT = `SELECT g.id, g.file, g.title, g.caption, g.width, g.height, g.position, g.created_at,
  r.slug AS r_slug, r.name AS r_name, r.film_simulation AS r_sim, r.status AS r_status
  FROM gallery_photos g LEFT JOIN recipes r ON r.id = g.recipe_id`;

/** In display order. Public callers pass `publicOnly`, which hides links to draft recipes. */
export function listGallery(opts: { recipeSlug?: string; publicOnly?: boolean } = {}): GalleryItem[] {
  const where = opts.recipeSlug ? "WHERE r.slug = ?" : "";
  const rows = open().prepare(`${GALLERY_SELECT} ${where} ORDER BY g.position, g.created_at`)
    .all(...(opts.recipeSlug ? [opts.recipeSlug] : [])) as GalleryDBRow[];
  return rows.map(toGalleryItem)
    .map((g) => (opts.publicOnly && g.recipe && !g.recipe.published ? { ...g, recipe: null } : g))
    .filter((g) => !(opts.publicOnly && opts.recipeSlug && !g.recipe));
}

export function getGalleryItem(id: string): GalleryItem | null {
  const row = open().prepare(`${GALLERY_SELECT} WHERE g.id = ?`).get(id) as GalleryDBRow | undefined;
  return row ? toGalleryItem(row) : null;
}

const recipeIdFor = (slug: string | null | undefined) => {
  if (!slug) return null;
  const r = open().prepare("SELECT id FROM recipes WHERE slug = ?").get(slug) as { id: string } | undefined;
  if (!r) throw new GalleryError(`No recipe “${slug}”`);
  return r.id;
};

export class GalleryError extends Error {}

/** Adds an uploaded file at the top of the gallery (newest favourites first). */
export function addGalleryPhoto(file: string, meta: { title?: string; caption?: string; recipeSlug?: string | null; width?: number | null; height?: number | null }) {
  const d = open();
  const count = (d.prepare("SELECT COUNT(*) AS n FROM gallery_photos").get() as { n: number }).n;
  if (count >= MAX_GALLERY_PHOTOS) throw new GalleryError(`The gallery holds up to ${MAX_GALLERY_PHOTOS} photos`);
  const recipeId = recipeIdFor(meta.recipeSlug);
  const top = (d.prepare("SELECT MIN(position) AS p FROM gallery_photos").get() as { p: number | null }).p;
  const id = crypto.randomUUID();
  d.prepare("INSERT INTO gallery_photos (id, file, title, caption, recipe_id, width, height, position, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)")
    .run(id, file, meta.title?.trim() ?? "", meta.caption?.trim() ?? "", recipeId, meta.width ?? null, meta.height ?? null,
      (top ?? 1) - 1, new Date().toISOString());
  return getGalleryItem(id)!;
}

/** `recipeSlug: null` unlinks; undefined leaves the link alone. */
export function updateGalleryPhoto(id: string, patch: { title?: string; caption?: string; recipeSlug?: string | null }) {
  const item = getGalleryItem(id);
  if (!item) return null;
  const d = open();
  if (patch.title !== undefined) d.prepare("UPDATE gallery_photos SET title = ? WHERE id = ?").run(patch.title.trim(), id);
  if (patch.caption !== undefined) d.prepare("UPDATE gallery_photos SET caption = ? WHERE id = ?").run(patch.caption.trim(), id);
  if (patch.recipeSlug !== undefined) d.prepare("UPDATE gallery_photos SET recipe_id = ? WHERE id = ?").run(recipeIdFor(patch.recipeSlug), id);
  return getGalleryItem(id);
}

/** Sets the display order to `ids`; photos not listed keep their relative order after them. */
export function reorderGallery(ids: string[]) {
  const d = open();
  const current = (d.prepare("SELECT id FROM gallery_photos ORDER BY position, created_at").all() as { id: string }[]).map((r) => r.id);
  const known = new Set(current);
  const listed = [...new Set(ids)].filter((id) => known.has(id));
  const order = [...listed, ...current.filter((id) => !listed.includes(id))];
  const set = d.prepare("UPDATE gallery_photos SET position = ? WHERE id = ?");
  d.exec("BEGIN");
  try { order.forEach((id, i) => set.run(i, id)); d.exec("COMMIT"); } catch (e) { d.exec("ROLLBACK"); throw e; }
  return listGallery();
}

export function deleteGalleryPhoto(id: string) {
  const item = getGalleryItem(id);
  if (!item) return false;
  open().prepare("DELETE FROM gallery_photos WHERE id = ?").run(id);
  removeFile(item.file);
  return true;
}
