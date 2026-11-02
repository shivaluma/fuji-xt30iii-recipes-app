"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { GENERATIONS, GENERATION_LABEL, camerasIn } from "@/lib/recipe/cameras";

/** "Works on my camera" picker for the recipes list; keeps the other filters in the URL. */
export function CameraFilter({ value }: { value?: string }) {
  const router = useRouter();
  const params = useSearchParams();
  return (
    <select
      aria-label="Works on my camera"
      value={value ?? ""}
      onChange={(e) => {
        const p = new URLSearchParams(params.toString());
        if (e.target.value) p.set("camera", e.target.value); else p.delete("camera");
        p.delete("gen");
        router.push(p.size ? `/recipes?${p}` : "/recipes", { scroll: false });
      }}
      className="h-9 rounded-full border border-hairline bg-background px-3.5 pr-8 text-sm outline-none transition-colors hover:border-foreground/30 focus-visible:ring-2 focus-visible:ring-ring"
    >
      <option value="">Any camera</option>
      {GENERATIONS.map((g) => (
        <optgroup key={g} label={GENERATION_LABEL[g]}>
          {camerasIn(g).map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </optgroup>
      ))}
    </select>
  );
}
