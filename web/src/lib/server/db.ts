import "server-only";
import { DatabaseSync } from "node:sqlite";
import fs from "node:fs";
import path from "node:path";
import { FilmRecipeSchema, TransferDocumentSchema, type FilmRecipe } from "@/lib/recipe/schema";

// SQLite via Node's built-in node:sqlite (no native dependencies). The full FilmLab recipe JSON is
// the source of truth; a few columns are denormalized for listing and filtering.

export type RecipeStatus = "draft" | "published";
export type CoverKind = "approximate-preview" | "camera-jpeg" | "photo";

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
};

const DATA_DIR = process.env.DATA_DIR ?? path.join(process.cwd(), "data");
export const UPLOAD_DIR = path.join(DATA_DIR, "uploads");
const DB_PATH = process.env.DATABASE_PATH ?? path.join(DATA_DIR, "filmlab.db");
const SEED_PATH = process.env.SEED_PATH ?? path.join(process.cwd(), "data", "seed-recipes.json");

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
  `);
  // Additive migrations for existing databases.
  const columns = (db.prepare("PRAGMA table_info(recipes)").all() as { name: string }[]).map((c) => c.name);
  if (!columns.includes("downloads")) db.exec("ALTER TABLE recipes ADD COLUMN downloads INTEGER NOT NULL DEFAULT 0");
  seedIfEmpty(db);
  return db;
}

function seedIfEmpty(d: DatabaseSync) {
  const { n } = d.prepare("SELECT COUNT(*) AS n FROM recipes").get() as { n: number };
  if (n > 0 || !fs.existsSync(/*turbopackIgnore: true*/ SEED_PATH)) return;
  const doc = TransferDocumentSchema.parse(JSON.parse(fs.readFileSync(/*turbopackIgnore: true*/ SEED_PATH, "utf8")));
  for (const r of doc.recipes) upsertRecipe(r, { status: "published" }, d);
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
  return r ? toRow(r) : null;
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

export function setCover(slug: string, file: string, kind: CoverKind) {
  const row = getRecipe(slug, { includeDrafts: true });
  if (!row) return null;
  if (row.coverFile && row.coverFile !== file) fs.rmSync(/*turbopackIgnore: true*/ path.join(UPLOAD_DIR, row.coverFile), { force: true });
  open().prepare("UPDATE recipes SET cover_file = ?, cover_kind = ?, updated_at = ? WHERE slug = ?").run(file, kind, new Date().toISOString(), slug);
  return getRecipe(slug, { includeDrafts: true });
}

export function deleteRecipe(slug: string) {
  const row = getRecipe(slug, { includeDrafts: true });
  if (!row) return false;
  if (row.coverFile) fs.rmSync(/*turbopackIgnore: true*/ path.join(UPLOAD_DIR, row.coverFile), { force: true });
  open().prepare("DELETE FROM recipes WHERE slug = ?").run(slug);
  return true;
}

/** Counts a FilmLab-file download (public, unauthenticated; best-effort). */
export function countDownload(slug: string) {
  open().prepare("UPDATE recipes SET downloads = downloads + 1 WHERE slug = ? AND status = 'published'").run(slug);
}
