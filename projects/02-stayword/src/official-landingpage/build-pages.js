const fs = require('fs');
const path = require('path');

const contentDir = '/Users/rivendell/Workspace/WebWork/seedxdream-website/website-content';
const outBaseDir = '/Users/rivendell/Workspace/WebWork/seedxdream-website/seedxdream-landingpage/products/stayword';

const filesToBuild = [
  'features/local-transcription.md',
  'features/ai-summary.md',
  'features/recording-library.md',
  'use-cases/meeting-recording.md',
  'use-cases/lecture-recording.md',
  'use-cases/interview-recording.md',
  'guides/iphone-recording-to-text.md',
  'guides/long-recording.md',
  'compare/local-vs-cloud-transcription.md',
  'help/does-stayword-upload-audio.md'
];

function parseFrontmatter(md) {
  const match = md.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n([\s\S]*)$/);
  if (!match) return { meta: {}, content: md };
  const metaStr = match[1];
  const content = match[2];
  const meta = {};
  metaStr.split('\n').forEach(line => {
    const colonIdx = line.indexOf(':');
    if (colonIdx > -1) {
      const key = line.slice(0, colonIdx).trim();
      let val = line.slice(colonIdx + 1).trim();
      if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
        val = val.slice(1, -1);
      }
      meta[key] = val;
    }
  });
  return { meta, content };
}

function mdToHtml(md) {
  // Normalize date review phrases
  md = md.replace(/截至\s*2026\s*年\s*8\s*月\s*13\s*日复核的/g, '');
  md = md.replace(/以下说明按当前版本于\s*2026\s*年\s*8\s*月\s*13\s*日复核[。，]/g, '');
  md = md.replace(/产品事实最后复核于\s*2026\s*年\s*8\s*月\s*13\s*日[。，]/g, '');

  const lines = md.split('\n');
  let html = [];
  let inTable = false;
  let tableRows = [];
  let inUl = false;
  let inOl = false;
  let inBlockquote = false;
  let bqLines = [];

  function flushTable() {
    if (!inTable) return;
    if (tableRows.length > 0) {
      let res = '<div class="table-responsive"><table class="apple-table">\n';
      // First row is header
      const headerCols = tableRows[0];
      res += '  <thead><tr>' + headerCols.map(c => `<th>${formatInline(c)}</th>`).join('') + '</tr></thead>\n';
      res += '  <tbody>\n';
      for (let i = 1; i < tableRows.length; i++) {
        res += '    <tr>' + tableRows[i].map(c => `<td>${formatInline(c)}</td>`).join('') + '</tr>\n';
      }
      res += '  </tbody>\n</table></div>\n';
      html.push(res);
    }
    inTable = false;
    tableRows = [];
  }

  function flushList() {
    if (inUl) { html.push('</ul>\n'); inUl = false; }
    if (inOl) { html.push('</ol>\n'); inOl = false; }
  }

  function flushBlockquote() {
    if (!inBlockquote) return;
    html.push(`<blockquote class="apple-quote">\n<p>${formatInline(bqLines.join(' '))}</p>\n</blockquote>\n`);
    inBlockquote = false;
    bqLines = [];
  }

  function formatInline(str) {
    if (!str) return '';
    return str
      .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
      .replace(/\[(.*?)\]\((.*?)\)/g, (m, text, href) => {
        // adjust root absolute links to relative
        let relHref = href;
        if (relHref.startsWith('/products/stayword/features/on-device-privacy')) {
          relHref = '../../';
        } else if (relHref.startsWith('/products/stayword/')) {
          relHref = relHref.replace('/products/stayword/', '../../');
        }
        return `<a href="${relHref}">${text}</a>`;
      });
  }

  for (let i = 0; i < lines.length; i++) {
    const rawLine = lines[i];
    const trimmed = rawLine.trim();

    // Table line
    if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
      flushList();
      flushBlockquote();
      const cells = trimmed.slice(1, -1).split('|').map(c => c.trim());
      // check separator line
      if (cells.every(c => /^:?-+:?$/.test(c))) {
        // separator, skip
      } else {
        inTable = true;
        tableRows.push(cells);
      }
      continue;
    } else {
      flushTable();
    }

    // Blockquote
    if (trimmed.startsWith('>')) {
      flushList();
      inBlockquote = true;
      bqLines.push(trimmed.replace(/^>\s*/, ''));
      continue;
    } else {
      flushBlockquote();
    }

    // Empty line
    if (!trimmed) {
      flushList();
      continue;
    }

    // Filter out redundant CTA footer lines like "[了解言灵] · [查看xxx]"
    if (trimmed.startsWith('[了解言灵]')) {
      continue;
    }

    // Headings
    if (trimmed.startsWith('# ')) {
      // Top heading handled separately in article header
      continue;
    }
    if (trimmed.startsWith('## ')) {
      flushList();
      html.push(`<h2>${formatInline(trimmed.slice(3))}</h2>\n`);
      continue;
    }
    if (trimmed.startsWith('### ')) {
      flushList();
      html.push(`<h3>${formatInline(trimmed.slice(4))}</h3>\n`);
      continue;
    }

    // Unordered list
    if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
      if (inOl) flushList();
      if (!inUl) { inUl = true; html.push('<ul>\n'); }
      html.push(`  <li>${formatInline(trimmed.slice(2))}</li>\n`);
      continue;
    }

    // Ordered list
    const olMatch = trimmed.match(/^(\d+)\.\s+(.*)$/);
    if (olMatch) {
      if (inUl) flushList();
      if (!inOl) { inOl = true; html.push('<ol>\n'); }
      html.push(`  <li>${formatInline(olMatch[2])}</li>\n`);
      continue;
    }

    // Standard paragraph
    flushList();
    html.push(`<p>${formatInline(trimmed)}</p>\n`);
  }

  flushTable();
  flushBlockquote();
  flushList();

  return html.join('');
}

function buildPage(relFile) {
  const srcPath = path.join(contentDir, relFile);
  if (!fs.existsSync(srcPath)) {
    console.warn(`File not found: ${srcPath}`);
    return;
  }

  const raw = fs.readFileSync(srcPath, 'utf8');
  const { meta, content } = parseFrontmatter(raw);

  const title = meta.title || 'StayWord | 北京种梦智能科技有限公司';
  const description = meta.description || '';
  const h1 = meta.h1 || meta.title || 'StayWord';
  
  let slug = meta.slug || '';
  if (slug.startsWith('/products/stayword/')) {
    slug = slug.replace('/products/stayword/', '');
  }
  slug = slug.replace(/^\//, '').replace(/\/$/, '');

  const targetDir = path.join(outBaseDir, slug);
  fs.mkdirSync(targetDir, { recursive: true });

  const bodyHtml = mdToHtml(content);

  // Calculate relative depth for styles and nav links
  // slug is e.g. "features/local-transcription" -> depth 2 -> styles is "../../../../styles.css"
  const depth = slug ? slug.split('/').length + 2 : 2;
  const rootRel = '../'.repeat(depth);
  const staywordRel = '../'.repeat(slug.split('/').length);

  const htmlDoc = `<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta name="description" content="${description.replace(/"/g, '&quot;')}" />
    <title>${title} | 北京种梦智能科技有限公司</title>
    <link rel="stylesheet" href="${rootRel}styles.css?v=20260817-v2" />
  </head>
  <body class="product-detail-page">
    <a class="skip-link" href="#main">跳到主要内容</a>

    <header class="site-header" aria-label="主导航">
      <nav class="nav">
        <a class="brand" href="${rootRel}#top" aria-label="北京种梦智能科技有限公司首页">
          <span class="brand-logo-window" aria-hidden="true">
            <img class="brand-logo" src="${rootRel}assets/brand/zhongmeng-logo.webp" width="1672" height="941" alt="" />
          </span>
          <span class="brand-copy" aria-hidden="true">
            <span class="brand-company">北京种梦智能科技有限公司</span>
            <span class="brand-company-en">DualariesAI</span>
          </span>
        </a>
        <div class="nav-links" aria-label="页面导航">
          <a href="${rootRel}#top">首页</a>
          <a href="${staywordRel}">StayWord</a>
          <a href="${rootRel}#products">产品</a>
          <a href="${rootRel}#why">关于我们</a>
          <a href="${rootRel}#contact">联系我们</a>
        </div>
      </nav>
    </header>

    <main id="main">
      <article class="legal-article-shell">
        <header class="legal-header">
          <h1>${h1}</h1>
        </header>

        <div class="legal-content">
          ${bodyHtml}
        </div>

        <nav class="legal-nav-footer" style="margin-top: 48px; padding-top: 24px; border-top: 1px solid var(--line); display: flex; gap: 16px; justify-content: center;">
          <a class="button button-primary" href="${staywordRel}">返回 StayWord</a>
          <a class="button button-secondary" href="${rootRel}#products">全部产品</a>
        </nav>
      </article>
    </main>

    <footer class="site-footer">
      <p>
        <span>© 2026 北京种梦智能科技有限公司</span>
        <span>All rights reserved.</span>
        <span>京ICP备2026027922号-4</span>
      </p>
    </footer>

    <script src="${rootRel}script.js?v=20260817"></script>
  </body>
</html>
`;

  const outFilePath = path.join(targetDir, 'index.html');
  fs.writeFileSync(outFilePath, htmlDoc, 'utf8');
  console.log(`Generated: ${outFilePath}`);
}

filesToBuild.forEach(buildPage);
require('./scripts/apply-seo-metadata');
console.log('All pages built successfully!');
