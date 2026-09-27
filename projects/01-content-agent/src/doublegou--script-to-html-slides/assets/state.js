// Pure navigation state, shared by the browser player and non-browser unit tests.
function createSlideState(stepCounts, initialPage = 0, initialStep = 0) {
  if (!Array.isArray(stepCounts) || !stepCounts.length || stepCounts.some(n => !Number.isSafeInteger(n) || n < 0)) throw new Error('Expected non-negative step counts for at least one slide');
  const counts = [...stepCounts];
  const clamp = (n, min, max) => Math.max(min, Math.min(Number.isSafeInteger(n) ? n : min, max));
  let page = clamp(initialPage, 0, counts.length - 1);
  let step = clamp(initialStep, 0, counts[page]);
  const read = () => ({page, step, steps: counts[page], pages: counts.length});
  const send = action => {
    if (action === 'next') {
      if (step < counts[page]) step++;
      else if (page < counts.length - 1) { page++; step = 0; }
    } else if (action === 'prev') {
      if (step > 0) step--;
      else if (page > 0) { page--; step = counts[page]; }
    } else if (action === 'page-next' && page < counts.length - 1) {
      page++; step = 0;
    } else if (action === 'page-prev' && page > 0) {
      page--; step = 0;
    } else if (action === 'replay') step = 0;
    return read();
  };
  return Object.freeze({read, send});
}
if (typeof module !== 'undefined' && module.exports) module.exports = {createSlideState};
