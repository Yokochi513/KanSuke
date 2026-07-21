// docs/api.md を静的な HTML 1 枚にして dist/ へ出す（Cloudflare Pages 用）。
//
// 仕様の正本はあくまで docs/api.md で、このスクリプトは体裁を付けるだけ。
// ドキュメントを直すときは Markdown 側を直す。

import {mkdir, readFile, writeFile} from "node:fs/promises";
import {dirname, join} from "node:path";
import {fileURLToPath} from "node:url";

import MarkdownIt from "markdown-it";

const here = dirname(fileURLToPath(import.meta.url));
const source = join(here, "..", "docs", "api.md");
const outDir = join(here, "dist");

const md = new MarkdownIt({html: false, linkify: true, typographer: false});

const STYLE = `
:root {
  color-scheme: light dark;
  --bg: #ffffff;
  --fg: #1c1b1f;
  --muted: #5f5b66;
  --border: #e3e0e8;
  --surface: #f6f4f9;
  --accent: #4f46e5;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #131218;
    --fg: #e7e2ee;
    --muted: #a8a2b3;
    --border: #302c39;
    --surface: #1c1a23;
    --accent: #a5b4fc;
  }
}
* { box-sizing: border-box; }
body {
  margin: 0;
  padding: 3rem 1.25rem 6rem;
  background: var(--bg);
  color: var(--fg);
  font-family: "Hiragino Sans", "Noto Sans JP", system-ui, sans-serif;
  line-height: 1.85;
  -webkit-text-size-adjust: 100%;
}
main { max-width: 46rem; margin: 0 auto; }
h1, h2, h3 { line-height: 1.4; font-weight: 700; }
h1 { font-size: 1.9rem; margin: 0 0 2rem; }
h2 {
  font-size: 1.35rem;
  margin: 3.5rem 0 1rem;
  padding-bottom: 0.4rem;
  border-bottom: 1px solid var(--border);
}
h3 { font-size: 1.1rem; margin: 2.25rem 0 0.75rem; }
h4 { font-size: 1rem; margin: 1.75rem 0 0.5rem; }
p, ul, ol { margin: 0 0 1rem; }
li { margin-bottom: 0.35rem; }
a { color: var(--accent); text-decoration: none; }
a:hover { text-decoration: underline; }
code {
  font-family: ui-monospace, "SFMono-Regular", Menlo, Consolas, monospace;
  font-size: 0.875em;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 4px;
  padding: 0.1em 0.35em;
  word-break: break-word;
}
pre {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 1rem;
  overflow-x: auto;
}
pre code { background: none; border: none; padding: 0; font-size: 0.85rem; }
.table-scroll { overflow-x: auto; margin: 0 0 1.25rem; }
table { border-collapse: collapse; width: 100%; font-size: 0.9rem; }
th, td {
  border: 1px solid var(--border);
  padding: 0.55rem 0.7rem;
  text-align: left;
  vertical-align: top;
}
th { background: var(--surface); font-weight: 600; white-space: nowrap; }
blockquote {
  margin: 0 0 1rem;
  padding: 0.25rem 0 0.25rem 1rem;
  border-left: 3px solid var(--border);
  color: var(--muted);
}
hr { border: none; border-top: 1px solid var(--border); margin: 2.5rem 0; }
footer {
  max-width: 46rem;
  margin: 4rem auto 0;
  padding-top: 1.5rem;
  border-top: 1px solid var(--border);
  color: var(--muted);
  font-size: 0.85rem;
}
`;

/**
 * 横に長い表がページ全体を横スクロールさせないよう、各 table を
 * スクロール用の div で包む。
 *
 * @param {string} html レンダリング済み HTML。
 * @return {string}
 */
function wrapTables(html) {
  return html.replace(
    /<table>[\s\S]*?<\/table>/g,
    (table) => `<div class="table-scroll">${table}</div>`,
  );
}

const markdown = await readFile(source, "utf8");
const body = wrapTables(md.render(markdown));

const html = `<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>KanSuke API v1</title>
<meta name="description" content="KanSuke 外部向け読み取り専用 REST API v1 の仕様">
<meta name="color-scheme" content="light dark">
<style>${STYLE}</style>
</head>
<body>
<main>
${body}
</main>
<footer>
KanSuke — 家庭内専用スケジュール共有アプリ /
<a href="https://github.com/Yokochi513/KanSuke">GitHub</a>
</footer>
</body>
</html>
`;

await mkdir(outDir, {recursive: true});
await writeFile(join(outDir, "index.html"), html, "utf8");
console.log(`built: ${join(outDir, "index.html")}`);
