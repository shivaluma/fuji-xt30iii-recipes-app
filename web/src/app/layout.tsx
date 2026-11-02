import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import Link from "next/link";
import { Toaster } from "@/components/ui/sonner";
import { SiteNav } from "@/components/site/site-nav";
import "./globals.css";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin", "vietnamese"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

export const metadata: Metadata = {
  title: { default: "FilmLab — film recipes for the X-T30 III", template: "%s · FilmLab" },
  description: "Preview Fujifilm X-T30 III film simulation recipes on your own photos, read recipes from screenshots, and keep your C1–C7 slots organised. Unofficial; not affiliated with Fujifilm.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`dark ${geistSans.variable} ${geistMono.variable} h-full scroll-smooth antialiased`}>
      <body className="flex min-h-full flex-col bg-background selection:bg-primary selection:text-primary-foreground">
        <a href="#content" className="sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-[60] focus:rounded-full focus:bg-primary focus:px-4 focus:py-2 focus:text-primary-foreground">Skip to content</a>
        <SiteNav />
        <main id="content" className="flex-1">{children}</main>
        <footer className="border-t border-hairline">
          <div className="mx-auto grid max-w-6xl gap-8 px-5 py-14 sm:grid-cols-[1.5fr_1fr_1fr]">
            <div>
              <div className="font-display text-xl font-bold">Film<span className="text-primary">Lab</span></div>
              <p className="mt-2 max-w-sm text-sm text-muted-foreground">Film simulation recipes for the Fujifilm X-T30 III. Preview first, shoot later.</p>
            </div>
            <div className="space-y-2 text-sm">
              <div className="font-semibold">Explore</div>
              <Link href="/recipes" className="block text-muted-foreground hover:text-foreground">All recipes</Link>
              <Link href="/#try" className="block text-muted-foreground hover:text-foreground">Try it</Link>
              <Link href="/#faq" className="block text-muted-foreground hover:text-foreground">FAQ</Link>
            </div>
            <div className="space-y-2 text-sm">
              <div className="font-semibold">Project</div>
              <a href="https://github.com/shivaluma/fuji-xt30iii-recipes-app" className="block text-muted-foreground hover:text-foreground">GitHub</a>
              <Link href="/admin" className="block text-muted-foreground hover:text-foreground">Admin</Link>
            </div>
          </div>
          <div className="border-t border-hairline px-5 py-6 text-center text-xs text-tertiary">
            Previews are approximate renderings by FilmLab, not Fujifilm&apos;s imaging engine. FilmLab is not affiliated with FUJIFILM; film simulation names are FUJIFILM trademarks, used descriptively.
          </div>
        </footer>
        <Toaster />
      </body>
    </html>
  );
}
