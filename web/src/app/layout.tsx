import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import Link from "next/link";
import { Toaster } from "@/components/ui/sonner";
import "./globals.css";

const geistSans = Geist({ variable: "--font-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

export const metadata: Metadata = {
  title: { default: "FilmLab Recipes", template: "%s · FilmLab Recipes" },
  description: "Film simulation recipes for the Fujifilm X-T30 III — browse, preview approximately in your browser, and import into the FilmLab iPhone app. Unofficial; not affiliated with Fujifilm.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`dark ${geistSans.variable} ${geistMono.variable} h-full antialiased`}>
      <body className="min-h-full flex flex-col bg-background">
        <header className="sticky top-0 z-40 border-b border-border/60 bg-background/80 backdrop-blur">
          <nav className="mx-auto flex h-16 max-w-6xl items-center gap-6 px-5">
            <Link href="/" className="text-lg font-bold tracking-tight">
              Film<span className="text-primary">Lab</span>
            </Link>
            <Link href="/recipes" className="text-sm text-muted-foreground hover:text-foreground">Recipes</Link>
            <span className="ml-auto text-xs text-muted-foreground hidden sm:block">for X-T30 III · unofficial</span>
          </nav>
        </header>
        <main className="flex-1">{children}</main>
        <footer className="border-t border-border/60 py-8 text-center text-xs text-muted-foreground">
          <p>Previews on this site are approximate renderings by FilmLab, not Fujifilm&apos;s imaging engine.</p>
          <p className="mt-1">FilmLab is not affiliated with FUJIFILM. Film simulation names are FUJIFILM trademarks, used descriptively.</p>
        </footer>
        <Toaster />
      </body>
    </html>
  );
}
