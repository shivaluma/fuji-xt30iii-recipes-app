import type { Metadata } from "next";
import { Inter, Inter_Tight, Geist_Mono } from "next/font/google";
import Link from "next/link";
import { Toaster } from "@/components/ui/sonner";
import { SiteNav } from "@/components/site/site-nav";
import "./globals.css";

const inter = Inter({ variable: "--font-inter", subsets: ["latin", "vietnamese"] });
const interTight = Inter_Tight({ variable: "--font-inter-tight", subsets: ["latin", "vietnamese"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

export const metadata: Metadata = {
  title: { default: "FilmLab — film recipes for the X-T30 III", template: "%s · FilmLab" },
  description: "Preview Fujifilm X-T30 III film simulation recipes on your own photos, read recipes from screenshots, and keep your C1–C7 slots organised. Unofficial; not affiliated with Fujifilm.",
};

const FOOTER_LINKS = [
  { title: "Explore", links: [{ href: "/recipes", label: "All recipes" }, { href: "/#try", label: "Try it" }, { href: "/#features", label: "Features" }, { href: "/#faq", label: "FAQ" }] },
  { title: "Project", links: [{ href: "https://github.com/shivaluma/fuji-xt30iii-recipes-app", label: "GitHub" }, { href: "/admin", label: "Admin" }] },
];

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${inter.variable} ${interTight.variable} ${geistMono.variable} h-full scroll-smooth antialiased`}>
      <body className="flex min-h-full flex-col bg-background text-foreground selection:bg-foreground selection:text-background">
        <a href="#content" className="sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-[60] focus:rounded-full focus:bg-foreground focus:px-4 focus:py-2 focus:text-background">Skip to content</a>
        <SiteNav />
        <main id="content" className="flex-1">{children}</main>
        <footer className="mt-40 overflow-hidden sm:mt-56">
          <div className="mx-auto max-w-6xl px-5 sm:px-8 lg:px-10">
            <div className="grid gap-12 border-t border-hairline pt-16 sm:grid-cols-[2fr_1fr_1fr]">
              <p className="max-w-sm text-muted-foreground">Film simulation recipes for the Fujifilm X‑T30 III. Preview first, shoot later.</p>
              {FOOTER_LINKS.map((col) => (
                <div key={col.title} className="space-y-3.5 text-sm">
                  <div className="text-xs font-medium uppercase tracking-[.08em] text-tertiary">{col.title}</div>
                  {col.links.map((l) => (
                    <Link key={l.href} href={l.href} className="block w-fit transition-opacity hover:opacity-60">{l.label}</Link>
                  ))}
                </div>
              ))}
            </div>
            <div aria-hidden className="mt-24 select-none whitespace-nowrap font-display text-[29vw] font-medium leading-[0.78] tracking-[-0.07em] lg:text-[23rem]">
              FilmLab
            </div>
            <p className="mt-12 border-t border-hairline py-8 text-xs leading-relaxed text-tertiary">
              Previews are approximate renderings by FilmLab, not Fujifilm&apos;s imaging engine. FilmLab is not affiliated with FUJIFILM; film simulation names are FUJIFILM trademarks, used descriptively.
            </p>
          </div>
        </footer>
        <Toaster />
      </body>
    </html>
  );
}
