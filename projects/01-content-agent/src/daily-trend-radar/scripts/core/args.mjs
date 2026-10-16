export function parseArgs(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith("--")) throw new Error(`Unexpected argument: ${token}`);
    const [rawKey, inlineValue] = token.slice(2).split(/=(.*)/s, 2);
    if (["help", "no-dedupe"].includes(rawKey)) {
      result[rawKey] = true;
      continue;
    }
    const value = inlineValue ?? argv[++index];
    if (value == null || value.startsWith("--")) throw new Error(`Missing value for --${rawKey}`);
    result[rawKey] = value;
  }
  return result;
}

export function positiveInteger(value, name, fallback) {
  if (value == null) return fallback;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) throw new Error(`${name} must be a positive integer`);
  return parsed;
}

