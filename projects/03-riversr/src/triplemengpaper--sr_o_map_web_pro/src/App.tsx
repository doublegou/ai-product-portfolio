import { useCallback, useMemo, useRef, useState } from "react";

import { ProbabilityMap } from "./components/ProbabilityMap";
import { QueryPanel } from "./components/QueryPanel";
import { DEFAULT_QUERY, type SampleQuery } from "./domain/isotope";

function App() {
  const [draftQuery, setDraftQuery] = useState<SampleQuery>(DEFAULT_QUERY);
  const [committedQuery, setCommittedQuery] =
    useState<SampleQuery>(DEFAULT_QUERY);
  const [renderRequestId, setRenderRequestId] = useState(0);
  const [loadingRequestId, setLoadingRequestId] = useState<number | null>(null);
  const nextRequestId = useRef(0);

  const effectiveQuery = useMemo<SampleQuery>(
    () => committedQuery,
    [committedQuery],
  );

  const resetQuery = () => {
    nextRequestId.current += 1;
    setLoadingRequestId(null);
    setDraftQuery(DEFAULT_QUERY);
    setCommittedQuery(DEFAULT_QUERY);
    setRenderRequestId(nextRequestId.current);
  };

  const runQuery = () => {
    if (loadingRequestId !== null) {
      return;
    }

    const requestId = nextRequestId.current + 1;
    nextRequestId.current = requestId;
    setLoadingRequestId(requestId);

    // Let the loading indicator paint before starting the synchronous grid work.
    window.requestAnimationFrame(() => {
      window.requestAnimationFrame(() => {
        if (nextRequestId.current !== requestId) {
          return;
        }

        setCommittedQuery({ ...draftQuery });
        setRenderRequestId(requestId);
      });
    });
  };

  const finishRendering = useCallback((requestId: number) => {
    setLoadingRequestId((currentRequestId) =>
      currentRequestId === requestId ? null : currentRequestId,
    );
  }, []);

  return (
    <main className="app-shell">
      <ProbabilityMap
        query={effectiveQuery}
        renderRequestId={renderRequestId}
        onRenderComplete={finishRendering}
      />

      {loadingRequestId !== null && (
        <div
          className="screen-loading-layer"
          role="status"
          aria-label="Running"
          aria-live="polite"
        >
          <span className="screen-loading-spinner" aria-hidden="true" />
          <span className="screen-loading-text">Running…</span>
        </div>
      )}

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
