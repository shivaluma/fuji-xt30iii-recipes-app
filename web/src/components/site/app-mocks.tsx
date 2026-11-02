"use client";

import { useState } from "react";
import { motion, useReducedMotion } from "motion/react";
import { Check, ChevronLeft, Eye, Minus, MoreHorizontal, Plus, ScanText, Sparkles, Aperture, ChevronsUpDown, Download } from "lucide-react";
import { cn } from "@/lib/utils";

/* Interactive replicas of FilmLab's own iOS screens (same tokens as Theme.swift). */

const PARAMS = [
  { key: "HIGHLIGHT", values: ["-2", "-1.5", "-1", "-0.5", "0", "+0.5", "+1"], start: 2, palette: "from-white to-neutral-500" },
  { key: "SHADOW", values: ["-1", "0", "+1", "+2"], start: 2, palette: "from-neutral-600 to-neutral-900" },
  { key: "COLOR", values: ["-2", "-1", "0", "+1", "+2", "+3", "+4"], start: 6, palette: "from-red-500 via-yellow-400 via-green-500 to-violet-500" },
  { key: "CCE BLUE", values: ["Off", "Weak", "Strong"], start: 2, palette: "from-blue-600 to-blue-950" },
  { key: "GRAIN", values: ["Off", "Weak", "Strong"], start: 1, palette: "from-neutral-400 to-neutral-700" },
];

export function TuneMock() {
  const [sel, setSel] = useState(2);
  const [vals, setVals] = useState(PARAMS.map((p) => p.start));
  const p = PARAMS[sel];
  const step = (d: number) => setVals((v) => v.map((x, i) => (i === sel ? Math.min(Math.max(x + d, 0), p.values.length - 1) : x)));
  return (
    <div className="flex h-full flex-col bg-black pt-12">
      <div className="flex items-center gap-2 px-4">
        <span className="grid size-9 place-items-center rounded-full bg-surface"><ChevronLeft className="size-4" /></span>
        <div className="mr-auto leading-tight">
          <div className="text-[15px] font-bold">Moody Harbour</div>
          <div className="text-[11px] text-muted-foreground">Tune</div>
        </div>
        <span className="grid size-9 place-items-center rounded-full bg-surface"><Eye className="size-4" /></span>
        <span className="grid size-9 place-items-center rounded-full bg-surface"><MoreHorizontal className="size-4" /></span>
      </div>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src="/samples/landscape.jpg" alt="" className="mx-3 mt-4 aspect-[4/3] rounded-[18px] object-cover saturate-[.85] contrast-[1.08] sepia-[.08]" />
      <div className="mt-5 flex gap-2 overflow-x-auto px-3 pb-2 [scrollbar-width:none]">
        {PARAMS.map((q, i) => (
          <button
            key={q.key}
            onClick={() => setSel(i)}
            className={cn(
              "relative h-[60px] w-[96px] shrink-0 overflow-hidden rounded-small border text-center transition-all duration-300",
              i === sel ? "border-white/80 shadow-[0_0_18px_rgba(51,166,145,.35)]" : "border-hairline bg-surface",
            )}
          >
            <div className={cn("absolute inset-0 bg-gradient-to-r transition-opacity duration-300", q.palette, i === sel ? "opacity-95" : "opacity-15")} />
            <div className="relative text-[9px] font-semibold tracking-[.14em] text-white/85">{q.key}</div>
            <div className="relative text-[15px] font-semibold">{q.values[vals[i]]}</div>
          </button>
        ))}
      </div>
      <div className="mt-4 flex items-center justify-center gap-9">
        <button onClick={() => step(-1)} aria-label="Decrease" className="grid size-12 place-items-center rounded-full border border-hairline bg-surface text-primary transition-transform active:scale-90"><Minus className="size-5" /></button>
        <motion.span key={`${sel}-${vals[sel]}`} initial={{ y: 8, opacity: 0 }} animate={{ y: 0, opacity: 1 }} className="w-20 text-center text-3xl font-bold tabular-nums">{p.values[vals[sel]]}</motion.span>
        <button onClick={() => step(1)} aria-label="Increase" className="grid size-12 place-items-center rounded-full border border-hairline bg-surface text-muted-foreground transition-transform active:scale-90"><Plus className="size-5" /></button>
      </div>
      <div className="mt-auto px-3 pb-6">
        <div className="mb-2 text-[9px] font-semibold tracking-[.16em] text-muted-foreground">FILM SIMULATION</div>
        <div className="flex gap-2">
          {[["Cl. Chrome", "from-slate-500 to-amber-200/70", true], ["Reala Ace", "from-amber-200 to-sky-500", false], ["Nostalgic", "from-amber-400 to-orange-900", false], ["Acros", "from-neutral-900 to-neutral-200", false]].map(([n, g, on]) => (
            <div key={n as string} className="flex flex-col items-center gap-1">
              <div className={cn("size-12 rounded-[10px] bg-gradient-to-br", g as string, on ? "ring-2 ring-primary" : "ring-1 ring-hairline")} />
              <span className={cn("text-[9px]", on ? "font-bold text-primary" : "text-muted-foreground")}>{n as string}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

const CARD_LINES = [
  ["Film Simulation", "Classic Chrome"], ["White Balance", "5200K, R+2 B−3"], ["Highlight", "−1"], ["Shadow", "+0.5"],
  ["Color", "+2"], ["Grain", "Weak, Small"], ["Color Chrome", "Strong"], ["Clarity", "0"],
];

export function ImportMock() {
  const reduce = useReducedMotion();
  return (
    <div className="grid gap-4 sm:grid-cols-[1fr_auto_1fr] sm:items-center">
      <div className="rounded-card border border-hairline bg-[#f4f2ee] p-5 text-[13px] text-neutral-800 shadow-2xl -rotate-2">
        <div className="mb-2 text-xs font-medium text-neutral-500">u/someone · r/fujifilm</div>
        <p className="leading-relaxed">my overcast go-to 👇<br />CC strong, WB 5200K +2R −3B<br />H −1 S +0.5, color +2, grain weak small, clarity 0</p>
      </div>
      <div className="grid place-items-center">
        <span className="grid size-12 place-items-center rounded-full bg-accent text-primary"><Sparkles className="size-5" /></span>
      </div>
      <div className="space-y-1.5 rounded-card border border-hairline bg-surface p-4">
        {CARD_LINES.map(([k, v], i) => (
          <motion.div
            key={k}
            initial={reduce ? { opacity: 0 } : { opacity: 0, x: 16 }}
            whileInView={{ opacity: 1, x: 0 }}
            viewport={{ once: true }}
            transition={{ delay: 0.15 + i * 0.08, duration: 0.45 }}
            className="flex items-center justify-between rounded-xl bg-surface-raised px-3 py-2 text-sm"
          >
            <span className="text-muted-foreground">{k}</span>
            <span className="flex items-center gap-1.5 font-semibold">{v}<Check className="size-3.5 text-primary" /></span>
          </motion.div>
        ))}
      </div>
    </div>
  );
}

const STEPS = ["All 7 slots backed up", "Per-setting diff reviewed", "Read back & verified"];

export function WriteMock() {
  const reduce = useReducedMotion();
  return (
    <div className="mx-auto max-w-md space-y-4">
      <div className="space-y-4 rounded-[28px] border border-white/12 bg-surface p-5">
        <div className="flex items-center gap-2 text-sm font-medium tracking-wide text-muted-foreground"><Aperture className="size-4" /> DESTINATION</div>
        <div className="flex items-center gap-4 rounded-small bg-surface-raised p-4">
          <span className="font-display text-2xl font-bold text-primary">C1</span>
          <div className="mr-auto leading-tight">
            <div className="font-semibold">Moody Harbour</div>
            <div className="text-sm text-muted-foreground">Classic Chrome</div>
          </div>
          <ChevronsUpDown className="size-4 text-muted-foreground" />
        </div>
        <div className="flex items-center justify-center gap-2 rounded-small bg-primary py-4 font-bold text-primary-foreground">
          <Download className="size-5" /> Write to C1
        </div>
      </div>
      <div className="space-y-2">
        {STEPS.map((s, i) => (
          <motion.div
            key={s}
            initial={reduce ? { opacity: 0 } : { opacity: 0, y: 10 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            transition={{ delay: 0.2 + i * 0.15 }}
            className="flex items-center gap-3 text-sm"
          >
            <span className="grid size-6 place-items-center rounded-full bg-accent text-primary"><Check className="size-3.5" /></span>
            {s}
          </motion.div>
        ))}
      </div>
    </div>
  );
}

export function ScanBadge() {
  return <span className="inline-flex items-center gap-1.5 rounded-full bg-accent px-3 py-1 text-xs font-semibold text-primary"><ScanText className="size-3.5" /> On-device first</span>;
}
