"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { ArrowUpRight } from "lucide-react";
import { cn } from "@/lib/utils";

const LINKS = [
  { href: "/recipes", label: "Recipes", mobile: true },
  { href: "/gallery", label: "Gallery", mobile: true },
  { href: "/#try", label: "Try it", mobile: true },
  { href: "/#features", label: "Features" },
  { href: "/#faq", label: "FAQ" },
];

export function GitHubMark({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 16 16" aria-hidden className={className} fill="currentColor">
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
    </svg>
  );
}

/** Top bar: a soft grey box holding the wordmark and section links, actions on the right. */
export function SiteNav() {
  const pathname = usePathname();
  const [scrolled, setScrolled] = useState(false);
  useEffect(() => {
    const on = () => setScrolled(window.scrollY > 8);
    on();
    window.addEventListener("scroll", on, { passive: true });
    return () => window.removeEventListener("scroll", on);
  }, []);
  return (
    <header className={cn("sticky top-0 z-50 border-b bg-background transition-colors duration-300", scrolled ? "border-hairline" : "border-transparent")}>
      <nav className="mx-auto flex max-w-6xl items-center justify-between gap-3 px-5 py-4 sm:px-8 sm:py-5 lg:px-10">
        <div className="flex items-center gap-5 rounded-2xl bg-surface px-5 py-3 sm:gap-8">
          <Link href="/" className="font-display text-[15px] font-semibold tracking-tight">©FilmLab</Link>
          {LINKS.map((l) => {
            const active = (l.href === "/recipes" || l.href === "/gallery") && pathname.startsWith(l.href);
            return (
              <Link
                key={l.href}
                href={l.href}
                className={cn(
                  "text-xs font-medium uppercase tracking-[.06em] transition-opacity hover:opacity-60",
                  !l.mobile && "hidden md:block",
                  active && "underline decoration-1 underline-offset-4",
                )}
              >
                {l.label}
              </Link>
            );
          })}
        </div>
        <div className="flex items-center gap-2">
          <Link href="/recipes" className="hidden items-center gap-1 rounded-full border border-hairline bg-surface px-3.5 py-1.5 text-sm font-medium transition-colors hover:bg-surface-raised sm:inline-flex">
            Browse recipes <ArrowUpRight className="size-3.5" />
          </Link>
          <a href="https://github.com/shivaluma/fuji-xt30iii-recipes-app" aria-label="GitHub" className="grid size-8 place-items-center rounded-full border border-hairline bg-surface transition-colors hover:bg-surface-raised">
            <GitHubMark className="size-3.5" />
          </a>
        </div>
      </nav>
    </header>
  );
}
