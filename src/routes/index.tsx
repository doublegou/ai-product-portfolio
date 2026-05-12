import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { ProbabilityMap, type Range } from "@/components/ProbabilityMap";
import { Input } from "@/components/ui/input";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Probabilis — Sr/O Isotope Domain Map (Asia)" },
      { name: "description", content: "Enter Sr (87Sr/86Sr) and δ18O ranges to visualize the most likely isotope domain across Asia." },
    ],
  }),
  component: Index,
});

function Index() {
  const [sr, setSr] = useState<Range>({ min: 0.7095, max: 0.7125 });
  const [o, setO] = useState<Range>({ min: -9, max: -6 });

  return (
    <main className="relative h-screen w-screen overflow-hidden bg-background">
      <ProbabilityMap sr={sr} o={o} />

      {/* Top brand bar */}
      <header className="pointer-events-none absolute left-0 right-0 top-0 z-[400] flex items-center justify-between p-5">
        <div className="glass-panel pointer-events-auto rounded-2xl px-4 py-2.5">
          <div className="flex items-center gap-2.5">
            <div className="h-2.5 w-2.5 rounded-full bg-primary shadow-[0_0_12px] shadow-primary" />
            <h1 className="text-sm font-semibold tracking-tight">Probabilis</h1>
            <span className="text-xs text-muted-foreground">· Isotope Domain Explorer · Asia</span>
          </div>
        </div>
        <div className="glass-panel pointer-events-auto hidden rounded-2xl px-4 py-2.5 md:block">
          <span className="text-xs text-muted-foreground">Research Preview · v0.1</span>
        </div>
      </header>

      {/* Control panel */}
      <section className="absolute right-5 top-20 z-[400] w-[360px] max-w-[calc(100vw-2.5rem)]">
        <div className="glass-panel rounded-3xl p-6">
          <div className="mb-5">
            <h2 className="text-lg font-semibold tracking-tight">Sample Query</h2>
            <p className="mt-1 text-xs text-muted-foreground">
              Enter sample value ranges to query likely isotope domains.
            </p>
          </div>

          <ParamRow
            title="Strontium"
            sub="⁸⁷Sr / ⁸⁶Sr"
            step={0.0001}
            range={sr}
            onChange={setSr}
            decimals={4}
          />
          <div className="my-5 h-px bg-border" />
          <ParamRow
            title="Oxygen"
            sub="δ¹⁸O ‰ (VSMOW)"
            step={0.01}
            range={o}
            onChange={setO}
            decimals={2}
          />
        </div>

        <div className="glass-panel mt-3 flex items-center gap-3 rounded-2xl px-4 py-3">
          <LegendDot color="hsl(45, 90%, 52%)" />
          <div className="h-1.5 flex-1 rounded-full bg-gradient-to-r from-[hsl(45,90%,52%)] to-[hsl(0,90%,52%)]" />
          <LegendDot color="hsl(0, 90%, 52%)" />
          <span className="ml-1 text-[11px] text-muted-foreground">match → strong match</span>
        </div>
      </section>
    </main>
  );
}

function ParamRow({
  title,
  sub,
  step,
  range,
  onChange,
  decimals,
}: {
  title: string;
  sub: string;
  step: number;
  range: Range;
  onChange: (r: Range) => void;
  decimals: number;
}) {
  const update = (k: "min" | "max", v: number) => {
    if (Number.isNaN(v)) return;
    onChange({ ...range, [k]: v });
  };
  return (
    <div>
      <div className="mb-2 flex items-baseline gap-2">
        <span className="text-sm font-semibold">{title}</span>
        <span className="text-[11px] text-muted-foreground">{sub}</span>
      </div>
      <div className="flex items-center gap-2">
        <NumberField
          value={range.min}
          step={step}
          decimals={decimals}
          onChange={(v) => update("min", v)}
        />
        <span className="text-xs text-muted-foreground">to</span>
        <NumberField
          value={range.max}
          step={step}
          decimals={decimals}
          onChange={(v) => update("max", v)}
        />
      </div>
    </div>
  );
}

function NumberField({
  value,
  step,
  decimals,
  onChange,
}: {
  value: number;
  step: number;
  decimals: number;
  onChange: (v: number) => void;
}) {
  return (
    <Input
      type="number"
      step={step}
      defaultValue={value.toFixed(decimals)}
      key={value}
      onChange={(e) => {
        const v = Number(e.target.value);
        if (!Number.isNaN(v)) onChange(v);
      }}
      className="h-9 flex-1 rounded-lg bg-background/60 text-right font-mono text-sm"
    />
  );
}

function LegendDot({ color }: { color: string }) {
  return <span className="h-2.5 w-2.5 rounded-full" style={{ background: color }} />;
}

function LegendDot({ color }: { color: string }) {
  return <span className="h-2.5 w-2.5 rounded-full" style={{ background: color }} />;
}
