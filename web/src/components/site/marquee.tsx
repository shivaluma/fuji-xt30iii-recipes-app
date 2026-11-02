import { FILM_SIMULATION_NAMES, FILM_SIMULATIONS } from "@/lib/recipe/schema";

/** Infinite, pause-on-hover marquee of all 20 X-T30 III film simulations. */
export function SimulationMarquee() {
  const items = [...FILM_SIMULATIONS, ...FILM_SIMULATIONS];
  return (
    <div className="relative overflow-hidden border-y border-hairline py-5 [mask-image:linear-gradient(90deg,transparent,#000_10%,#000_90%,transparent)]">
      <div className="fl-marquee flex w-max gap-3">
        {items.map((s, i) => (
          <span key={i} aria-hidden={i >= FILM_SIMULATIONS.length} className="whitespace-nowrap rounded-full border border-hairline bg-surface px-5 py-2.5 font-display text-base font-semibold">
            {FILM_SIMULATION_NAMES[s]}
          </span>
        ))}
      </div>
    </div>
  );
}
