import { useEffect, useRef, useState } from "react";

import type { SampleQuery, SampleValue } from "../domain/isotope";

const BASE_MAP_OPTIONS = [
  { key: "o", label: "o" },
  { key: "o_err", label: "o_err" },
  { key: "sr", label: "sr" },
  { key: "sr_err", label: "sr_err" },
] as const;

type BaseMapKey = (typeof BASE_MAP_OPTIONS)[number]["key"];

interface QueryPanelProps {
  query: SampleQuery;
  onQueryChange: (query: SampleQuery) => void;
  onReset: () => void;
  onRun: () => void;
}

export function QueryPanel({
  query,
  onQueryChange,
  onReset,
  onRun,
}: QueryPanelProps) {
  const [selectedBaseMaps, setSelectedBaseMaps] = useState<BaseMapKey[]>([]);

  const updateQuery = <Key extends keyof SampleQuery>(
    key: Key,
    value: SampleQuery[Key],
  ) => {
    onQueryChange({ ...query, [key]: value });
  };

  const toggleBaseMap = (key: BaseMapKey) => {
    setSelectedBaseMaps((current) =>
      current.includes(key)
        ? current.filter((selectedKey) => selectedKey !== key)
        : [...current, key],
    );
  };

  const allBaseMapsSelected = BASE_MAP_OPTIONS.every(({ key }) =>
    selectedBaseMaps.includes(key),
  );

  const toggleAllBaseMaps = () => {
    setSelectedBaseMaps((current) => {
      const hasEveryBaseMap = BASE_MAP_OPTIONS.every(({ key }) =>
        current.includes(key),
      );

      return hasEveryBaseMap ? [] : BASE_MAP_OPTIONS.map(({ key }) => key);
    });
  };

  const runQuery = () => {
    if (document.activeElement instanceof HTMLElement) {
      document.activeElement.blur();
    }

    onRun();
  };

  const printView = () => {
    window.print();
  };

  return (
    <aside className="query-panel" aria-label="Sample query controls">
      <div className="legend-card glass-panel" aria-label="Probability legend">
        <span className="legend-dot legend-dot-low" />
        <span className="legend-track" />
        <span className="legend-dot legend-dot-high" />
        <span className="legend-label">probability 0-1</span>
      </div>

      <section className="base-map-card glass-panel" aria-label="Base map layers">
        <div className="base-map-head">
          <h2>Base Map</h2>
          <button
            aria-pressed={allBaseMapsSelected}
            className={`select-all-button${allBaseMapsSelected ? " is-selected" : ""}`}
            type="button"
            onClick={toggleAllBaseMaps}
          >
            All
          </button>
        </div>

        <div className="base-map-grid">
          {BASE_MAP_OPTIONS.map((option) => {
            const isSelected = selectedBaseMaps.includes(option.key);

            return (
              <button
                aria-pressed={isSelected}
                className={`base-map-option${isSelected ? " is-selected" : ""}`}
                key={option.key}
                type="button"
                onClick={() => toggleBaseMap(option.key)}
              >
                <span className="base-map-indicator" aria-hidden="true" />
                <span>{option.label}</span>
              </button>
            );
          })}
        </div>
      </section>

      <div className="query-card glass-panel">
        <div className="panel-head">
          <div>
            <h2>Sample Query</h2>
          </div>
          <button className="reset-button" type="button" onClick={onReset}>
            Reset
          </button>
        </div>

        <div className="param-stack">
          <ParamGroup title="Strontium">
            <ParameterField
              label={
                <>
                  Strontium (<sup>87</sup>Sr/<sup>86</sup>Sr) central 50%
                </>
              }
              value={query.strontiumCentral50}
              decimals={4}
              onChange={(value) => updateQuery("strontiumCentral50", value)}
            />
            <ParameterField
              label={
                <>
                  Strontium (<sup>87</sup>Sr/<sup>86</sup>Sr) central 90%
                </>
              }
              value={query.strontiumCentral90}
              decimals={4}
              onChange={(value) => updateQuery("strontiumCentral90", value)}
            />
          </ParamGroup>

          <div className="panel-divider" />

          <ParamGroup title="Oxygen">
            <ParameterField
              label={
                <>
                  Oxygen δ<sup>18</sup>O<sub>PO4</sub> ‰(VSMOW) human enamel
                </>
              }
              value={query.oxygenPhosphateVsmowEnamel}
              decimals={2}
              onChange={(value) =>
                updateQuery("oxygenPhosphateVsmowEnamel", value)
              }
            />
            <ParameterField
              label={
                <>
                  Oxygen δ<sup>18</sup>O<sub>carb</sub> ‰(VSMOW) human enamel
                </>
              }
              value={query.oxygenCarbonateVsmowEnamel}
              decimals={2}
              onChange={(value) =>
                updateQuery("oxygenCarbonateVsmowEnamel", value)
              }
            />
            <ParameterField
              label={
                <>
                  Oxygen δ<sup>18</sup>O<sub>carb</sub> ‰(VPDB) human enamel
                </>
              }
              value={query.oxygenCarbonateVpdbEnamel}
              decimals={2}
              onChange={(value) =>
                updateQuery("oxygenCarbonateVpdbEnamel", value)
              }
            />
            <ParameterField
              label={
                <>
                  Oxygen δ<sup>18</sup>O ‰(VSMOW) drinking water
                </>
              }
              value={query.oxygenDrinkingWaterVsmow}
              decimals={2}
              onChange={(value) =>
                updateQuery("oxygenDrinkingWaterVsmow", value)
              }
            />
          </ParamGroup>
        </div>

        <div className="query-actions" aria-label="Sample query actions">
          <button
            className="query-action-button query-action-button-primary"
            type="button"
            onClick={runQuery}
          >
            Run
          </button>
          <button
            className="query-action-button"
            type="button"
            onClick={printView}
          >
            Print
          </button>
        </div>
      </div>
    </aside>
  );
}

function ParamGroup({
  title,
  children,
}: {
  title: string;
  children: React.ReactNode;
}) {
  return (
    <section className="param-group" aria-labelledby={`${title}-param-title`}>
      <div className="param-header">
        <span id={`${title}-param-title`} className="param-title">
          {title}
        </span>
      </div>
      <div className="param-list">{children}</div>
    </section>
  );
}

function ParameterField({
  label,
  value,
  decimals,
  onChange,
}: {
  label: React.ReactNode;
  value: SampleValue;
  decimals: number;
  onChange: (value: SampleValue) => void;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [draft, setDraft] = useState(formatValue(value, decimals));

  useEffect(() => {
    if (document.activeElement !== inputRef.current) {
      setDraft(formatValue(value, decimals));
    }
  }, [decimals, value]);

  const commit = (nextDraft: string) => {
    if (nextDraft.trim() === "") {
      onChange(null);
      return;
    }

    const nextValue = Number(nextDraft);
    if (Number.isFinite(nextValue)) {
      onChange(nextValue);
    }
  };

  return (
    <label className="parameter-field">
      <span className="parameter-label">{label}</span>
      <input
        ref={inputRef}
        aria-label={plainTextFromLabel(label)}
        inputMode="decimal"
        type="text"
        value={draft}
        onBlur={() => {
          if (draft.trim() === "") {
            setDraft("");
            return;
          }

          const nextValue = Number(draft);
          setDraft(
            Number.isFinite(nextValue)
              ? nextValue.toFixed(decimals)
              : formatValue(value, decimals),
          );
        }}
        onChange={(event) => {
          const nextDraft = event.currentTarget.value;
          setDraft(nextDraft);
          commit(nextDraft);
        }}
      />
    </label>
  );
}

function plainTextFromLabel(label: React.ReactNode): string | undefined {
  if (typeof label === "string") {
    return label;
  }

  return undefined;
}

function formatValue(value: SampleValue, decimals: number): string {
  return value === null ? "" : value.toFixed(decimals);
}
