import { cn } from "@/lib/utils";

/** CSS device frame (no third-party artwork). */
export function Phone({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <div className={cn("relative mx-auto w-[300px] rounded-[3.2rem] border border-white/15 bg-black p-3 shadow-[0_40px_120px_-20px_rgba(51,166,145,.35),0_30px_60px_rgba(0,0,0,.6)]", className)}>
      <div className="absolute left-1/2 top-5 z-10 h-7 w-24 -translate-x-1/2 rounded-full bg-black" />
      <div className="relative h-[600px] overflow-hidden rounded-[2.5rem] bg-black">{children}</div>
    </div>
  );
}
