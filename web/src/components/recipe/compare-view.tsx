"use client";

import { useEffect, useRef, useState } from "react";
import { ChevronsLeftRight } from "lucide-react";
import { ResizableHandle, ResizablePanel, ResizablePanelGroup } from "@/components/ui/resizable";
import { cn } from "@/lib/utils";

function useImageCanvas(data: ImageData | null) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const c = ref.current;
    if (!c || !data) return;
    c.width = data.width;
    c.height = data.height;
    c.getContext("2d")!.putImageData(data, 0, 0);
  }, [data]);
  return ref;
}

/**
 * Before/after comparison built on shadcn Resizable: drag the handle (or focus it and use the
 * arrow keys). Both images are drawn at the full container width and anchored to the outer
 * edges, so each panel reveals its own part of a perfectly aligned frame.
 */
export function CompareView({
  original, processed, className, leftLabel = "Original", rightLabel = "Recipe", badge,
}: {
  original: ImageData | null;
  processed: ImageData | null;
  className?: string;
  leftLabel?: string;
  rightLabel?: string;
  badge?: React.ReactNode;
}) {
  const box = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);
  const leftCanvas = useImageCanvas(original);
  const rightCanvas = useImageCanvas(processed);

  useEffect(() => {
    const el = box.current;
    if (!el) return;
    const ro = new ResizeObserver(([entry]) => setWidth(entry.contentRect.width));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const aspect = original ? `${original.width} / ${original.height}` : "3 / 2";
  const canvasStyle = { width: width || "100%", height: "100%" } as const;

  return (
    <div ref={box} className={cn("relative overflow-hidden rounded-[var(--fl-radius-card)] bg-surface", className)} style={{ aspectRatio: aspect }}>
      <ResizablePanelGroup orientation="horizontal" className="absolute inset-0">
        <ResizablePanel defaultSize="50" minSize="0" className="relative overflow-hidden">
          <canvas ref={leftCanvas} aria-label={leftLabel} className="absolute inset-y-0 left-0 max-w-none" style={canvasStyle} />
          <span className="pointer-events-none absolute bottom-3 left-3 rounded-full bg-white/90 px-2.5 py-1 text-[11px] font-medium text-black backdrop-blur">{leftLabel}</span>
        </ResizablePanel>
        <ResizableHandle
          aria-label="Drag to compare original and recipe"
          className="z-10 w-0.5 bg-white shadow-[0_0_10px_rgba(0,0,0,.35)] focus-visible:ring-2 focus-visible:ring-white"
        >
          <span className="pointer-events-none absolute grid size-10 place-items-center rounded-full bg-white text-black shadow-[0_6px_20px_rgba(0,0,0,.25)] transition-transform group-hover:scale-110">
            <ChevronsLeftRight className="size-5" />
          </span>
        </ResizableHandle>
        <ResizablePanel defaultSize="50" minSize="0" className="relative overflow-hidden">
          <canvas ref={rightCanvas} aria-label={rightLabel} className="absolute inset-y-0 right-0 max-w-none" style={canvasStyle} />
          <span className="pointer-events-none absolute bottom-3 right-3 rounded-full bg-white/90 px-2.5 py-1 text-[11px] font-medium text-black backdrop-blur">{rightLabel}</span>
        </ResizablePanel>
      </ResizablePanelGroup>
      {badge && <div className="pointer-events-none absolute left-3 top-3 z-20">{badge}</div>}
    </div>
  );
}
