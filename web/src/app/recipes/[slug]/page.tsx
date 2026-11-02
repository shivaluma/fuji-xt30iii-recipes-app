import { notFound } from "next/navigation";
import type { Metadata } from "next";
import { Download } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { RecipePreview } from "@/components/recipe/recipe-preview";
import { SettingsGrid } from "@/components/recipe/settings-grid";
import { FILM_SIMULATION_NAMES } from "@/lib/recipe/schema";
import { publishedRecipe, publishedRecipes } from "@/lib/server/data";

/** Prerender published recipes; new ones render on first request. (Cache Components needs ≥1 entry.) */
export async function generateStaticParams() {
  const rows = await publishedRecipes();
  return rows.length ? rows.map((r) => ({ slug: r.slug })) : [{ slug: "none" }];
}

export async function generateMetadata({ params }: PageProps<"/recipes/[slug]">): Promise<Metadata> {
  const r = await publishedRecipe((await params).slug);
  return r ? { title: r.name, description: r.summary || `${FILM_SIMULATION_NAMES[r.filmSimulation]} film recipe for the X-T30 III` } : {};
}

const provenanceLabel: Record<string, string> = {
  filmLabOriginal: "FilmLab original", userCreated: "Original", duplicated: "Adapted", imported: "Imported", cameraSlot: "From a camera slot",
};

async function Recipe({ params }: { params: PageProps<"/recipes/[slug]">["params"] }) {
  const row = await publishedRecipe((await params).slug);
  if (!row) notFound();
  const r = row.recipe;
  return (
    <article className="grid gap-10 lg:grid-cols-[1.25fr_1fr]">
      <div className="space-y-6">
        <header>
          <p className="text-sm font-semibold uppercase tracking-widest text-primary">{FILM_SIMULATION_NAMES[r.settings.filmSimulation]}</p>
          <h1 className="mt-2 text-4xl font-bold tracking-tight sm:text-5xl">{r.name}</h1>
          {r.summary && <p className="mt-3 text-lg text-muted-foreground">{r.summary}</p>}
          <div className="mt-4 flex flex-wrap gap-2">
            <Badge variant="secondary">{provenanceLabel[r.provenance.kind] ?? r.provenance.kind}</Badge>
            {r.provenance.author && <Badge variant="secondary">Credit: {r.provenance.author}</Badge>}
            {r.compatibleCameras.map((c) => <Badge key={c} variant="outline">{c}</Badge>)}
          </div>
        </header>
        {row.coverFile && (
          <figure className="space-y-2">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={`/api/media/${row.coverFile}`} alt={`Sample photo for ${r.name}`} className="w-full rounded-3xl border border-border" />
            <figcaption className="text-xs text-muted-foreground">
              {row.coverKind === "camera-jpeg" ? "JPEG produced by the camera with this recipe." :
                row.coverKind === "approximate-preview" ? "Approximate preview rendered by FilmLab, not camera output." : "Sample photo."}
            </figcaption>
          </figure>
        )}
        <RecipePreview settings={r.settings} />
        {row.body && <div className="whitespace-pre-line leading-relaxed text-muted-foreground">{row.body}</div>}
      </div>
      <aside className="space-y-5">
        <SettingsGrid settings={r.settings} />
        <a href={`/api/recipes/${row.slug}/export`} className="flex items-center justify-center gap-2 rounded-2xl bg-primary py-4 font-bold text-primary-foreground">
          <Download className="size-5" /> Download for FilmLab
        </a>
        <p className="text-xs text-muted-foreground">
          Import the file in the FilmLab app (Library › Import Recipes). &ldquo;—&rdquo; means the recipe doesn&apos;t set it, so the camera keeps its own value.
          {r.provenance.note && <><br />{r.provenance.note}</>}
        </p>
      </aside>
    </article>
  );
}

export default function RecipePage({ params }: PageProps<"/recipes/[slug]">) {
  return (
    <div className="mx-auto max-w-6xl px-5 py-10 pb-20">
      <Recipe params={params} />
    </div>
  );
}
