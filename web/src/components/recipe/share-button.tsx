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
    <button onClick={share} className="inline-flex items-center gap-1.5 rounded-full border border-hairline bg-surface px-3.5 py-1.5 text-sm font-medium transition-colors hover:bg-surface-raised active:scale-[.98]">
      <Share2 className="size-3.5" /> Share
    </button>
  );
}
