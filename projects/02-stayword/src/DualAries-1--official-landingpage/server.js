const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 8888;
const HOST = '0.0.0.0';
const root = __dirname;

const mimeTypes = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.webp': 'image/webp',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml'
};

const server = http.createServer((req, res) => {
  try {
    let rawUrl = req.url.split('?')[0];
    let safeUrl = decodeURIComponent(rawUrl);
    let target = safeUrl === '/' ? 'index.html' : safeUrl.replace(/^\//, '');
    let filePath = path.join(root, target);

    if (fs.existsSync(filePath) && fs.statSync(filePath).isDirectory()) {
      filePath = path.join(filePath, 'index.html');
    }

    const ext = path.extname(filePath).toLowerCase();
    const contentType = mimeTypes[ext] || 'application/octet-stream';

    fs.readFile(filePath, (err, content) => {
      if (err) {
        res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
        res.end('404 Not Found: ' + req.url);
      } else {
        res.writeHead(200, { 'Content-Type': contentType });
        res.end(content);
      }
    });
  } catch (e) {
    res.writeHead(500);
    res.end('Server Error');
  }
});

server.listen(PORT, HOST, () => {
  console.log(`Server running at http://127.0.0.1:${PORT}/ and http://localhost:${PORT}/`);
});
