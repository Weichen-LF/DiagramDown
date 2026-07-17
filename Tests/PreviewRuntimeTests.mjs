import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repositoryRoot = fileURLToPath(new URL("../", import.meta.url));
const previewDirectory = path.join(repositoryRoot, "Mark/Resources/Preview");
const html = await readFile(path.join(previewDirectory, "preview.html"), "utf8");
const css = await readFile(path.join(previewDirectory, "preview.css"), "utf8");
const javascript = await readFile(path.join(previewDirectory, "preview.js"), "utf8");
const nativeBridge = await readFile(
  path.join(repositoryRoot, "Mark/MarkdownPreviewView.swift"),
  "utf8",
);
const pdfService = await readFile(
  path.join(repositoryRoot, "Mark/PDFExportService.swift"),
  "utf8",
);

test("preview page keeps every runtime dependency local", async () => {
  const assetReferences = [...html.matchAll(/(?:src|href)="([^"]+)"/gu)]
    .map((match) => match[1]);

  assert.deepEqual(assetReferences, [
    "preview.css",
    "markdown-it.min.js",
    "highlight.min.js",
    "mermaid.min.js",
    "preview.js",
  ]);
  assert.ok(assetReferences.every((reference) => !/^https?:/u.test(reference)));

  await Promise.all(assetReferences.map((reference) => (
    access(path.join(previewDirectory, reference))
  )));
});

test("content security policy preserves the offline trust boundary", () => {
  assert.match(html, /default-src 'none'/u);
  assert.match(html, /script-src 'self'/u);
  assert.match(html, /connect-src 'none'/u);
  assert.match(html, /object-src 'none'/u);
  assert.match(html, /base-uri 'none'/u);
});

test("JavaScript and Swift agree on every WebKit message handler", () => {
  const handlers = ["d2", "exportSVG", "previewZoom", "scrollSync"];

  for (const handler of handlers) {
    assert.ok(
      javascript.includes(`messageHandlers?.${handler}`),
      `JavaScript must post to ${handler}`,
    );
    assert.ok(
      nativeBridge.includes(`name: "${handler}"`),
      `Swift must register ${handler}`,
    );
    assert.ok(
      nativeBridge.includes(`case "${handler}"`),
      `Swift must handle ${handler}`,
    );
    assert.ok(
      nativeBridge.includes(`forName: "${handler}"`),
      `Swift must remove ${handler}`,
    );
  }
});

test("preview runtime exports the native entry points", () => {
  for (const entryPoint of [
    "applyD2Error",
    "applyD2Result",
    "beginPDFExport",
    "finishPDFExport",
    "prepareForPDFExport",
    "renderMarkdown",
    "scrollToSourceLine",
  ]) {
    assert.match(
      javascript,
      new RegExp(`window\\.previewRuntime[\\s\\S]*\\b${entryPoint}\\b`, "u"),
    );
  }
});

test("code highlighting is local, explicit, and leaves diagram fences alone", () => {
  assert.match(html, /<script src="highlight\.min\.js"><\/script>/u);
  assert.match(javascript, /highlight\?\.getLanguage\(resolvedLanguage\)/u);
  assert.match(javascript, /ignoreIllegals: true/u);
  assert.match(javascript, /if \(language === "mermaid"\)/u);
  assert.match(javascript, /if \(language === "d2"\)/u);
  assert.match(css, /\.hljs-keyword/u);
});

test("PDF export uses WebKit PDF data instead of WKPrintingView", () => {
  assert.match(nativeBridge, /webView\.pdf\(configuration: configuration\)/u);
  assert.match(pdfService, /CGPDFDocument\(provider\)/u);
  assert.doesNotMatch(nativeBridge, /printOperation\(with:/u);
  assert.match(javascript, /classList\.add\("pdf-exporting"\)/u);
  assert.match(javascript, /classList\.remove\("pdf-exporting"\)/u);
});

test("diagram viewer controls have matching styles and print exclusions", () => {
  for (const className of [
    "diagram-actions",
    "diagram-viewer",
    "diagram-viewer-toolbar",
    "diagram-viewer-viewport",
    "diagram-viewer-canvas",
  ]) {
    assert.ok(javascript.includes(`className = "${className}"`));
    assert.ok(css.includes(`.${className}`));
  }

  assert.match(css, /@media print[\s\S]*\.diagram-actions,[\s\S]*\.diagram-viewer/u);
});

test("all zoom surfaces retain trackpad gesture handling", () => {
  for (const eventName of [
    "gesturestart",
    "gesturechange",
    "gestureend",
    "gesturecancel",
    "wheel",
  ]) {
    assert.ok(javascript.includes(`addEventListener("${eventName}"`));
  }

  assert.match(javascript, /activeDiagramViewer\.applyGestureZoomDelta/u);
  assert.match(javascript, /postPreviewZoomGesture\("delta", scale\)/u);
  assert.match(javascript, /diagramZoomMinimum = 0\.25/u);
  assert.match(javascript, /diagramZoomMaximum = 4/u);
});
