#!/usr/bin/env python3
"""Publish only aggregated 24h merchant interest; never export visitor records."""
import datetime
import json
import pathlib
import subprocess
import urllib.request

CONFIG = pathlib.Path('/opt/umami/collection-heat.json')
SQL = """
WITH interest AS (
 SELECT d.string_value AS id, count(DISTINCT e.session_id)::integer AS clicks
 FROM website_event e JOIN event_data d ON d.website_event_id=e.event_id
 WHERE e.website_id='89ee5fce-9013-4146-a0bd-32e85e49cf15'
 AND e.hostname='pricemapai.com' AND e.created_at>now()-interval '24 hours'
 AND e.event_name IN ('purchase_link_click','merchant_shop_click','api_provider_click','api_station_detail_open')
 AND d.data_key='source_id' AND d.string_value IS NOT NULL
 GROUP BY d.string_value ORDER BY clicks DESC,d.string_value LIMIT 1000
)
SELECT coalesce(json_agg(interest),'[]'::json) FROM interest;
"""

def main():
    result = subprocess.run(['docker', 'compose', '--project-directory', '/opt/umami',
                             'exec', '-T', 'db', 'psql', '-U', 'umami', '-d', 'umami',
                             '-v', 'ON_ERROR_STOP=1', '-Atc', SQL],
                            capture_output=True, text=True, check=True, timeout=30)
    sources = json.loads(result.stdout)
    report = {'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'sources': sources}
    if not CONFIG.exists():
        print(json.dumps({'dry_run': True, 'sources': len(sources), 'top': sources[:10]}, ensure_ascii=False))
        return
    config = json.loads(CONFIG.read_text())
    endpoint = config['endpoint']
    if not endpoint.startswith('https://') or not endpoint.endswith(('/heat', '/api/collection-heat')):
        raise ValueError('Invalid heat endpoint')
    request = urllib.request.Request(endpoint, data=json.dumps(report).encode(), method='POST',
              headers={'Content-Type': 'application/json', 'User-Agent': 'PriceMapAI-Collection-Heat/1.0', 'X-Heat-Token': config['token']})
    with urllib.request.urlopen(request, timeout=30) as response:
        print(json.dumps({'sent': len(sources), 'response': json.load(response)}))

if __name__ == '__main__':
    main()
