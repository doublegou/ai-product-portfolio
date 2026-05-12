import { createFileRoute } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { ProbabilityMap, getPeak } from "@/components/ProbabilityMap";
import { Slider } from "@/components/ui/slider";
import { Input } from "@/components/ui/input";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Probabilis — SR/O Probability Map" },
      { name: "description", content: "Scientific map tool: input SR and O parameters to visualize the maximum probability region across the globe." },
    ],
  }),
  component: Index,
});

function Index() {
  const [sr, setSr] = useState(50);
  const [o, setO] = useState(50);
  const peak = useMemo(() => getPeak(sr, o), [sr, o]);

  return (
    <main className="relative h-screen w-screen overflow-hidden bg-background">
      <ProbabilityMap sr={sr} o={o} />

      {/* Top brand bar */}
      <header className="pointer-events-none absolute left-0 right-0 top-0 z-[400] flex items-center justify-between p-5">
        <div className="glass-panel pointer-events-auto rounded-2xl px-4 py-2.5">
          <div className="flex items-center gap-2.5">
            <div className="h-2.5 w-2.5 rounded-full bg-primary shadow-[0_0_12px] shadow-primary" />
            <h1 className="text-sm font-semibold tracking-tight">Probabilis</h1>
            <span className="text-xs text-muted-foreground">· Probability Field Explorer</span>
          </div>
        </div>
        <div className="glass-panel pointer-events-auto hidden rounded-2xl px-4 py-2.5 md:block">
          <span className="text-xs text-muted-foreground">Research Preview · v0.1</span>
        </div>
      </header>

      {/* Control panel */}
      <section className="absolute left-5 top-20 z-[400] w-[340px] max-w-[calc(100vw-2.5rem)]">
        <div className="glass-panel rounded-3xl p-6">
          <div className="mb-5">
            <h2 className="text-lg font-semibold tracking-tight">Parameters</h2>
            <p className="mt-1 text-xs text-muted-foreground">
              Adjust SR and O to compute the spatial probability distribution.
            </p>
          </div>

          <ParamControl label="SR" hint="Spatial response" value={sr} onChange={setSr} />
          <div className="my-5 h-px bg-border" />
          <ParamControl label="O" hint="Observation factor" value={o} onChange={setO} />

          <div className="mt-6 rounded-2xl bg-secondary/60 p-4">
            <div className="mb-2 text-[11px] font-medium uppercase tracking-wider text-muted-foreground">
              Peak Probability Region
            </div>
            <div className="flex items-baseline gap-3 font-mono">
              <Coord label="LAT" value={peak.lat} suffix="°" />
              <Coord label="LNG" value={peak.lng} suffix="°" />
            </div>
            <div className="mt-2 text-[11px] text-muted-foreground">
              Spread σ ≈ {peak.sigma.toFixed(2)}°
            </div>
          </div>
        </div>

        <div className="glass-panel mt-3 flex items-center gap-3 rounded-2xl px-4 py-3">
          <LegendDot color="hsl(220, 90%, 55%)" />
          <div className="h-1.5 flex-1 rounded-full bg-gradient-to-r from-[hsl(220,90%,55%)] via-[hsl(120,90%,55%)] to-[hsl(0,90%,55%)]" />
          <LegendDot color="hsl(0, 90%, 55%)" />
          <span className="ml-1 text-[11px] text-muted-foreground">low → high</span>
        </div>
      </section>
    </main>
  );
}

function ParamControl({
  label,
  hint,
  value,
  onChange,
}: {
  label: string;
  hint: string;
  value: number;
  onChange: (v: number) => void;
}) {
  return (
    <div>
      <div className="mb-2 flex items-baseline justify-between">
        <div>
          <span className="text-sm font-semibold">{label}</span>
          <span className="ml-2 text-[11px] text-muted-foreground">{hint}</span>
        </div>
        <Input
          type="number"
          min={0}
          max={100}
          step={0.1}
          value={value}
          onChange={(e) => {
            const v = Number(e.target.value);
            if (!Number.isNaN(v)) onChange(Math.max(0, Math.min(100, v)));
          }}
          className="h-8 w-20 rounded-lg text-right font-mono text-sm"
        />
      </div>
      <Slider
        value={[value]}
        min={0}
        max={100}
        step={0.1}
        onValueChange={([v]) => onChange(v)}
      />
    </div>
  );
}

function Coord({ label, value, suffix }: { label: string; value: number; suffix?: string }) {
  return (
    <div>
      <div className="text-[10px] font-medium tracking-wider text-muted-foreground">{label}</div>
      <div className="text-lg font-semibold tabular-nums">
        {value.toFixed(2)}
        {suffix}
      </div>
    </div>
  );
}

function LegendDot({ color }: { color: string }) {
  return <span className="h-2.5 w-2.5 rounded-full" style={{ background: color }} />;
}
