import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { beforeAll, describe, expect, it, vi } from "vitest";
vi.mock("server-only", () => ({}));

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "filmlab-db-"));
process.env.DATA_DIR = dir;
const db = await import("./db");
const fixture = (await import("../recipe/__fixtures__/sample-recipes.json")).default;
const { FilmRecipeSchema } = await import("../recipe/schema");

const recipe = FilmRecipeSchema.parse(fixture.recipes[0]);
const touchFile = (name: string) => fs.writeFileSync(path.join(db.UPLOAD_DIR, name), "x");
const exists = (name: string) => fs.existsSync(path.join(db.UPLOAD_DIR, name));

describe("recipe photos", () => {
  let slug = "";
  beforeAll(() => {
    slug = db.upsertRecipe(recipe, { status: "published" }).slug;
  });

  it("starts with no photos and no cover", () => {
    const row = db.getRecipe(slug)!;
    expect(row.photos).toEqual([]);
    expect(row.coverFile).toBeNull();
  });

  it("makes the first photo the cover and keeps upload order", () => {
    ["a.jpg", "b.jpg", "c.jpg"].forEach(touchFile);
    db.addPhoto(slug, "a.jpg", "photo");
    db.addPhoto(slug, "b.jpg", "camera-jpeg");
    const row = db.addPhoto(slug, "c.jpg", "photo")!;
    expect(row.photos.map((p) => p.file)).toEqual(["a.jpg", "b.jpg", "c.jpg"]);
    expect(row.coverFile).toBe("a.jpg");
    expect(row.coverKind).toBe("photo");
  });

  it("switches the cover and carries the photo's kind", () => {
    const b = db.getRecipe(slug)!.photos.find((p) => p.file === "b.jpg")!;
    const row = db.setCover(slug, b.id)!;
    expect(row.coverFile).toBe("b.jpg");
    expect(row.coverKind).toBe("camera-jpeg");
  });

  it("relabels the cover's kind too", () => {
    const b = db.getRecipe(slug)!.photos.find((p) => p.file === "b.jpg")!;
    const row = db.updatePhoto(slug, b.id, { kind: "approximate-preview" })!;
    expect(row.coverKind).toBe("approximate-preview");
  });

  it("deleting the cover promotes another photo and removes the file", () => {
    const b = db.getRecipe(slug)!.photos.find((p) => p.file === "b.jpg")!;
    const row = db.deletePhoto(slug, b.id)!;
    expect(exists("b.jpg")).toBe(false);
    expect(row.photos.map((p) => p.file)).toEqual(["a.jpg", "c.jpg"]);
    expect(row.coverFile).toBe("a.jpg");
  });

  it("refuses photo ids from another recipe", () => {
    const other = db.upsertRecipe({ ...recipe, id: "6F1C2A10-0001-4A6B-9C11-0000000000FF", name: "Other" }).slug;
    const a = db.getRecipe(slug)!.photos[0];
    expect(db.setCover(other, a.id)).toBeNull();
    expect(db.deletePhoto(other, a.id)).toBeNull();
  });

  it("returns plain objects (safe to pass to Client Components)", () => {
    for (const p of db.getRecipe(slug)!.photos) expect(Object.getPrototypeOf(p)).toBe(Object.prototype);
  });

  it("deleting a recipe removes all of its photo files", () => {
    expect(db.deleteRecipe(slug)).toBe(true);
    expect(exists("a.jpg")).toBe(false);
    expect(exists("c.jpg")).toBe(false);
  });
});
