export function unpackSourceResult(result) {
  if (Array.isArray(result)) return { items: result, warnings: [] };
  if (result && Array.isArray(result.items)) {
    return {
      items: result.items,
      warnings: Array.isArray(result.warnings) ? result.warnings.filter(Boolean) : [],
    };
  }
  throw new Error("source returned an invalid result");
}

