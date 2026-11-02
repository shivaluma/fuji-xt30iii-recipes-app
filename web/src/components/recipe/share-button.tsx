"use client";

import { Share2 } from "lucide-react";
import { toast } from "sonner";

export function ShareButton({ title }: { title: string }) {
  async function share() {
    const url = window.location.href;
    try {
      if (navigator.share) await navigator.share({ title, url });
      else { await navigator.clipboard.writeText(url); toast.success("Link copied"); }
    } catch { /* dismissed */ }
  }
  return (
    <button onClick={share} className="inline-flex items-center gap-2 rounded-full border border-hairline bg-surface-raised px-4 py-2.5 text-sm font-semibold transition-colors hover:bg-white/10 active:scale-95">
      <Share2 className="size-4" /> Share
    </button>
  );
}
