import { build } from "esbuild";
import { readFile, writeFile, readdir, mkdir } from "node:fs/promises";
import path from "node:path";

/**
 * Bundles the app into ONE self-contained HTML file.
 *
 * Everything is inlined — JS, CSS and both webfonts as data URIs — so the
 * result opens from disk, needs no server, and makes zero network requests.
 * Used for shareable previews; `npm run dev` remains the real app.
 *
 *   npm run build && npm run preview   →   preview/dist/meguri-preview.html
 *
 * The CSS is lifted straight from the Next production build, so the preview
 * and the app render identically.
 */

const ROOT = process.cwd();
const OUT_DIR = path.join(ROOT, "preview", "dist");

/* ------------------------------------------------------------------ */
/* 1. Bundle the app                                                   */
/* ------------------------------------------------------------------ */

const result = await build({
  entryPoints: [path.join(ROOT, "preview", "entry.tsx")],
  bundle: true,
  minify: true,
  format: "iife",
  platform: "browser",
  target: ["es2020"],
  jsx: "automatic",
  tsconfig: path.join(ROOT, "tsconfig.json"),
  write: false,
  legalComments: "none",
  alias: {
    "next/navigation": path.join(ROOT, "preview", "next-shim.tsx"),
    "next/link": path.join(ROOT, "preview", "link-shim.tsx"),
  },
  define: {
    "process.env.NODE_ENV": '"production"',
    "process.env.NEXT_PUBLIC_MAPS_EMBED_KEY": "undefined",
  },
});

const js = result.outputFiles[0].text;

/* ------------------------------------------------------------------ */
/* 2. Reuse the compiled CSS, inlining the fonts                        */
/* ------------------------------------------------------------------ */

/* Next has moved this directory between releases, so walk the whole tree. */
async function findCss(dir) {
  const entries = await readdir(dir, { withFileTypes: true }).catch(() => []);
  const found = [];
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) found.push(...(await findCss(full)));
    else if (entry.name.endsWith(".css")) found.push(full);
  }
  return found;
}

const cssFiles = await findCss(path.join(ROOT, ".next", "static", "css"));
if (cssFiles.length === 0) {
  throw new Error("No compiled CSS found — run `npm run build` first.");
}

let css = "";
for (const file of cssFiles.sort()) {
  css += await readFile(file, "utf8");
}

/* Swap every /_next/static/media/*.woff2 reference for a data URI. */
const mediaDir = path.join(ROOT, ".next", "static", "media");
const fontRefs = [...new Set([...css.matchAll(/\/_next\/static\/media\/([\w.-]+\.woff2)/g)].map((m) => m[1]))];

let inlinedFonts = 0;
for (const fontFile of fontRefs) {
  try {
    const buf = await readFile(path.join(mediaDir, fontFile));
    const dataUri = `data:font/woff2;base64,${buf.toString("base64")}`;
    css = css.replaceAll(`/_next/static/media/${fontFile}`, dataUri);
    inlinedFonts++;
  } catch {
    /* Missing font: the CSS fallback stack takes over. */
  }
}

/* The real app sets these via next/font; the preview declares them directly. */
css = `:root{--font-inter:'Inter';--font-display:'Instrument Serif';}\n${css}`;

/* ------------------------------------------------------------------ */
/* 3. Emit one file                                                     */
/* ------------------------------------------------------------------ */

const html = `<title>Meguri — find what's on in Japan</title>
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
<meta name="theme-color" content="#16130f" />
<style>${css}</style>
<div id="root"></div>
<script>${js}</script>`;

await mkdir(OUT_DIR, { recursive: true });
const outPath = path.join(OUT_DIR, "meguri-preview.html");
await writeFile(outPath, html, "utf8");

const kb = (Buffer.byteLength(html) / 1024).toFixed(0);
console.log(`✓ ${outPath}`);
console.log(`  ${kb} KB · ${inlinedFonts} fonts inlined · 0 external requests`);
