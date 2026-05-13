import { useMemo, useState } from "react";

import { ProbabilityMap } from "./components/ProbabilityMap";
import { QueryPanel } from "./components/QueryPanel";
import { DEFAULT_QUERY, type SampleQuery } from "./domain/isotope";

function App() {
  const [draftQuery, setDraftQuery] = useState<SampleQuery>(DEFAULT_QUERY);
  const [committedQuery, setCommittedQuery] =
    useState<SampleQuery>(DEFAULT_QUERY);

  const effectiveQuery = useMemo<SampleQuery>(
    () => committedQuery,
    [committedQuery],
  );

  const resetQuery = () => {
    setDraftQuery(DEFAULT_QUERY);
    setCommittedQuery(DEFAULT_QUERY);
  };

  const runQuery = () => {
    setCommittedQuery(draftQuery);
  };

  return (
    <main className="app-shell">
      <ProbabilityMap query={effectiveQuery} />

      <header className="brand-bar" aria-label="Application header">
        <div className="brand-pill glass-panel">
          <span className="brand-signal" aria-hidden="true" />
          <h1>MapWeb</h1>
          <span>Isotope Domain Explorer · China</span>
        </div>
      </header>

      <QueryPanel
        query={draftQuery}
        onQueryChange={setDraftQuery}
        onReset={resetQuery}
        onRun={runQuery}
      />
    </main>
  );
}

export default App;
