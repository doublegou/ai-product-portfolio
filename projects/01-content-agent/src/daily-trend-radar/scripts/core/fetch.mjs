const DEFAULT_USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
  "(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 daily-trend-radar/0.1.0";

export class HttpError extends Error {
  constructor(url, status, statusText) {
    super(`HTTP ${status} ${statusText}: ${url}`);
    this.name = "HttpError";
    this.status = status;
    this.url = url;
  }
}

const delay = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

export async function fetchResponse(url, options = {}) {
  const {
    timeoutMs = 10_000,
    retries = 2,
    headers = {},
    ...requestOptions
  } = options;

  let lastError;
  for (let attempt = 0; attempt <= retries; attempt += 1) {
    try {
      const response = await fetch(url, {
        ...requestOptions,
        headers: {
          "user-agent": DEFAULT_USER_AGENT,
          accept: "*/*",
          ...headers,
        },
        signal: AbortSignal.timeout(timeoutMs),
      });

      if (!response.ok) {
        const error = new HttpError(url, response.status, response.statusText);
        if ([401, 403, 429].includes(response.status) || attempt === retries) throw error;
        lastError = error;
      } else {
        return response;
      }
    } catch (error) {
      lastError = error;
      if (error instanceof HttpError && [401, 403, 429].includes(error.status)) throw error;
      if (attempt === retries) throw error;
    }

    await delay(300 * 2 ** attempt);
  }

  throw lastError;
}

export async function fetchText(url, options = {}) {
  return (await fetchResponse(url, options)).text();
}

export async function fetchJson(url, options = {}) {
  return (await fetchResponse(url, options)).json();
}

