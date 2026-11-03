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

describe("gallery", () => {
  let slug = "";
  beforeAll(() => {
    slug = db.upsertRecipe({ ...recipe, id: crypto.randomUUID().toUpperCase(), name: "Gallery Test Recipe" }, { status: "published" }).slug;
  });

  it("adds new favourites at the top, with an optional recipe link and size", () => {
    ["g1.jpg", "g2.jpg", "g3.jpg"].forEach(touchFile);
    db.addGalleryPhoto("g1.jpg", { title: "First" });
    db.addGalleryPhoto("g2.jpg", { title: "  Second  ", recipeSlug: slug, width: 3200, height: 2133 });
    db.addGalleryPhoto("g3.jpg", {});
    const all = db.listGallery();
    expect(all.map((g) => g.file)).toEqual(["g3.jpg", "g2.jpg", "g1.jpg"]);
    const second = all[1];
    expect(second.title).toBe("Second");
    expect(second.recipe).toMatchObject({ slug, name: "Gallery Test Recipe", published: true });
    expect([second.width, second.height]).toEqual([3200, 2133]);
    expect(db.listGallery({ recipeSlug: slug }).map((g) => g.file)).toEqual(["g2.jpg"]);
  });

  it("rejects links to recipes that don't exist", () => {
    expect(() => db.addGalleryPhoto("nope.jpg", { recipeSlug: "no-such-recipe" })).toThrow(db.GalleryError);
  });

  it("hides links to draft recipes from the public, but keeps them for the owner", () => {
    db.updateMeta(slug, { status: "draft" });
    const g2 = db.listGallery().find((g) => g.file === "g2.jpg")!;
    expect(g2.recipe?.published).toBe(false);
    expect(db.listGallery({ publicOnly: true }).find((g) => g.file === "g2.jpg")!.recipe).toBeNull();
    expect(db.listGallery({ recipeSlug: slug, publicOnly: true })).toEqual([]);
    db.updateMeta(slug, { status: "published" });
  });

  it("edits title, caption and link; null unlinks", () => {
    const g1 = db.listGallery().find((g) => g.file === "g1.jpg")!;
    const edited = db.updateGalleryPhoto(g1.id, { caption: "Kyoto, dusk", recipeSlug: slug })!;
    expect(edited.caption).toBe("Kyoto, dusk");
    expect(edited.recipe?.slug).toBe(slug);
    expect(db.updateGalleryPhoto(g1.id, { recipeSlug: null })!.recipe).toBeNull();
    expect(db.updateGalleryPhoto("missing", { title: "x" })).toBeNull();
  });

  it("reorders; unknown and missing ids are handled", () => {
    const [a, b, c] = db.listGallery().map((g) => g.id);
    expect(db.reorderGallery([c, "00000000-0000-0000-0000-000000000000", a]).map((g) => g.id)).toEqual([c, a, b]);
  });

  it("unlinks (not deletes) photos when their recipe is deleted; deleting a photo removes its file", () => {
    const g2 = db.listGallery().find((g) => g.file === "g2.jpg")!;
    db.deleteRecipe(slug);
    expect(db.getGalleryItem(g2.id)!.recipe).toBeNull();
    expect(exists("g2.jpg")).toBe(true);
    expect(db.deleteGalleryPhoto(g2.id)).toBe(true);
    expect(exists("g2.jpg")).toBe(false);
    expect(db.deleteGalleryPhoto(g2.id)).toBe(false);
  });
});
