"""Local SPA preview: python tool/serve.py --port 8090 --directory build/web."""
import argparse
import functools
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

class SPAHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        path = self.translate_path(urlparse(self.path).path)
        if not Path(path).is_file() and '.' not in Path(urlparse(self.path).path).name:
            self.path = '/index.html'
        super().do_GET()

    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache')
        super().end_headers()

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8090)
    parser.add_argument('--directory', default='build/web')
    args = parser.parse_args()
    handler = functools.partial(SPAHandler, directory=args.directory)
    print(f'G2G preview: http://localhost:{args.port}', flush=True)
    ThreadingHTTPServer(('127.0.0.1', args.port), handler).serve_forever()
