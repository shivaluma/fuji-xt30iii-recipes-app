"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { cn } from "@/lib/utils";

const LINKS = [
  { href: "/#features", label: "Features" },
  { href: "/#try", label: "Try it" },
  { href: "/recipes", label: "Recipes" },
  { href: "/#faq", label: "FAQ" },
];

/** Floating capsule navigation — the web twin of the app's floating tab bar. */
export function SiteNav() {
  const pathname = usePathname();
  const [scrolled, setScrolled] = useState(false);
  useEffect(() => {
    const on = () => setScrolled(window.scrollY > 24);
    on();
    window.addEventListener("scroll", on, { passive: true });
    return () => window.removeEventListener("scroll", on);
  }, []);
  return (
    <header className="pointer-events-none fixed inset-x-0 top-3 z-50 flex justify-center px-3">
      <nav
        className={cn(
          "pointer-events-auto flex w-full max-w-3xl items-center gap-1 rounded-full border border-hairline p-1.5 pl-5 transition-all duration-500",
          scrolled ? "bg-surface-raised/80 shadow-[0_12px_40px_rgba(0,0,0,.55)] backdrop-blur-xl" : "bg-black/30 backdrop-blur-md",
        )}
      >
        <Link href="/" className="mr-auto font-display text-lg font-bold tracking-tight">
          Film<span className="text-primary">Lab</span>
        </Link>
        {LINKS.map((l) => {
          const active = l.href === pathname || (l.href === "/recipes" && pathname.startsWith("/recipes"));
          return (
            <Link
              key={l.href}
              href={l.href}
              className={cn(
                "hidden rounded-full px-3.5 py-2 text-sm font-semibold transition-colors sm:block",
                active ? "bg-black/55 text-primary" : "text-foreground/80 hover:text-foreground",
              )}
            >
              {l.label}
            </Link>
          );
        })}
        <Link href="/recipes" className="rounded-full bg-primary px-4 py-2 text-sm font-bold text-primary-foreground transition-transform active:scale-95">
          Browse recipes
        </Link>
      </nav>
    </header>
  );
}
