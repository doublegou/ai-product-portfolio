"""Serve the built product with archived public data, on localhost only.
No collection, credentials, database, analytics, or production writes.
"""
import argparse
import json
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit

HERE = Path(__file__).resolve().parent
FIXTURES = HERE / 'fixtures/public-snapshot-20261017'
MANIFEST = json.loads((FIXTURES / 'latest.json').read_text())
DATA = {'/data/latest.json': FIXTURES / 'latest.json'}
for kind in ('offers', 'transit'):
    for url in MANIFEST[kind]['pages']:
        DATA[url] = FIXTURES / Path(url).name


class Preview(SimpleHTTPRequestHandler):
    def send_head(self):
        url = unquote(urlsplit(self.path).path)
        if url in DATA:
            target = DATA[url]
        elif url.startswith(('/data/', '/api/', '/admin')):
            self.send_error(404, 'Not available in archived preview')
            return None
        else:
            base = Path(self.directory).resolve()
            target = (base / url.lstrip('/')).resolve()
            if not target.is_relative_to(base):
                self.send_error(403)
                return None
            if not target.is_file():
                if Path(url).suffix:
                    self.send_error(404)
                    return None
                target = base / 'index.html'
        stream = target.open('rb')
        self.send_response(200)
        self.send_header('Content-Type', 'application/gzip' if target.suffix == '.gz' else self.guess_type(str(target)))
        # Raw gzip bytes: the production loader explicitly decompresses the stream.
        self.send_header('Content-Length', str(target.stat().st_size))
        self.send_header('Cache-Control', 'no-store')
        # Keep the preview local; external merchant links still open on explicit clicks.
        self.send_header('Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'self'")
        self.end_headers()
        return stream


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=4184)
    parser.add_argument('--dist', type=Path, default=HERE.parent / 'src/pricemapai-web-production/dist')
    args = parser.parse_args()
    if not (args.dist / 'index.html').is_file():
        parser.error('Build the product first: npm run build')
    print(f'Archived read-only preview: http://127.0.0.1:{args.port} (2026-10-17 data; real clock)', flush=True)
    server = ThreadingHTTPServer(('127.0.0.1', args.port), partial(Preview, directory=str(args.dist.resolve())))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
