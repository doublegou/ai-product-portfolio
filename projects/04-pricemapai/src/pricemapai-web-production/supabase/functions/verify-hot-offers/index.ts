import { timingSafeEqual } from 'node:crypto';
import { verifyHotOffers } from '../../../worker/hot-verification.ts';

Deno.serve(async (request: Request) => {
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const token = Deno.env.get('CRAWLER_TOKEN') ?? '';
  const expected = new TextEncoder().encode(token);
  const actual = new TextEncoder().encode(request.headers.get('X-Crawler-Token') ?? '');
  if (!key || !token || actual.length !== expected.length || !timingSafeEqual(actual, expected))
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  if (request.method !== 'POST') return new Response(null, { status: 405 });
  try {
    const results = await verifyHotOffers({ SUPABASE_URL: Deno.env.get('SUPABASE_URL')!, SUPABASE_SERVICE_ROLE_KEY: key });
    console.log(JSON.stringify({ trigger: 'hot-offer-verification', sources: results.length, failed: results.filter(r => r.status === 'failed').length }));
    return Response.json({ results });
  } catch (error) {
    console.error(error);
    return Response.json({ error: 'Verification failed' }, { status: 500 });
  }
});
