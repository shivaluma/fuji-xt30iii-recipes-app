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
  open().prepare("DELETE FROM recipes WHERE slug = ?").run(slug);
  return true;
}

/** Counts a FilmLab-file download (public, unauthenticated; best-effort). */
export function countDownload(slug: string) {
  open().prepare("UPDATE recipes SET downloads = downloads + 1 WHERE slug = ? AND status = 'published'").run(slug);
}
