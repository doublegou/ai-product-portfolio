const PRODUCTION_HOST = 'seedxdream.com';
const WWW_HOST = 'www.seedxdream.com';

export async function middleware(context) {
  const { request, next, redirect } = context;
  const url = new URL(request.url);

  if (url.hostname === WWW_HOST) {
    url.hostname = PRODUCTION_HOST;
    return redirect(url.toString(), 301);
  }

  const response = await next();
  if (url.hostname === PRODUCTION_HOST) return response;

  const headers = new Headers(response.headers);
  headers.set('X-Robots-Tag', 'noindex, nofollow, noarchive');

  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

export const config = {
  matcher: ['/:path*'],
};
