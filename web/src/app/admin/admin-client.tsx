"use client";

import { useState } from "react";
import { toast } from "sonner";
import { KeyRound, LogOut } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { ApiError, api, useToken } from "./lib";
import { ImportPanel } from "./import-panel";
import { RecipesPanel } from "./recipes-panel";
import { GalleryPanel } from "./gallery-panel";

type Tab = "import" | "recipes" | "gallery";

export function AdminClient() {
  const [token, setToken] = useToken();
  const [tab, setTab] = useState<Tab>("import");
  const [version, setVersion] = useState(0);
  const refresh = () => setVersion((v) => v + 1);

  if (!token) return <SignIn onToken={setToken} />;

  return (
    <div className="space-y-14">
      <div className="flex flex-wrap items-end justify-between gap-6">
        <h1 className="font-display text-7xl font-normal uppercase leading-[0.85] tracking-[-0.055em] sm:text-8xl">Admin</h1>
        <Button variant="ghost" className="rounded-full px-4 text-muted-foreground" onClick={() => setToken("")}><LogOut className="size-4" /> Sign out</Button>
      </div>

      <div className="flex gap-8 border-b border-hairline">
        {([["import", "Import"], ["recipes", "Recipes"], ["gallery", "Gallery"]] as const).map(([k, label]) => (
          <button key={k} type="button" onClick={() => setTab(k)} aria-pressed={tab === k}
            className={cn("-mb-px border-b-2 pb-4 font-display text-2xl tracking-[-0.03em] transition-colors",
              tab === k ? "border-foreground" : "border-transparent text-tertiary hover:text-foreground")}>
            {label}
          </button>
        ))}
      </div>

      {/* Both stay mounted so an import queue survives switching tabs. */}
      <div hidden={tab !== "import"}><ImportPanel token={token} onSaved={refresh} /></div>
      <div hidden={tab !== "recipes"}><RecipesPanel token={token} version={version} onChange={refresh} /></div>
      <div hidden={tab !== "gallery"}><GalleryPanel token={token} version={version} /></div>
    </div>
  );
}

function SignIn({ onToken }: { onToken: (t: string) => void }) {
  const [value, setValue] = useState("");
  const [checking, setChecking] = useState(false);
  async function submit() {
    setChecking(true);
    try {
      await api("/api/recipes?all=1", value.trim());
      onToken(value.trim());
    } catch (err) {
      toast.error(err instanceof ApiError && err.status === 401 ? "That token isn't right." : (err as Error).message);
    } finally { setChecking(false); }
  }
  return (
    <form onSubmit={(e) => { e.preventDefault(); void submit(); }} className="mx-auto max-w-md py-16 text-center">
      <KeyRound className="mx-auto size-8 text-muted-foreground" />
      <h1 className="mt-6 font-display text-5xl font-normal tracking-[-0.045em]">Admin</h1>
      <p className="mt-3 text-muted-foreground">Enter the server&apos;s ADMIN_TOKEN. It&apos;s kept only in this browser.</p>
      <input type="password" autoFocus value={value} onChange={(e) => setValue(e.target.value)} placeholder="Admin token" aria-label="Admin token"
        className="mt-10 h-12 w-full rounded-full bg-surface px-5 text-center outline-none ring-foreground/20 focus:ring-2" />
      <Button type="submit" className="mt-4 h-12 w-full rounded-full" disabled={!value.trim() || checking}>{checking ? "Checking…" : "Continue"}</Button>
    </form>
  );
}
