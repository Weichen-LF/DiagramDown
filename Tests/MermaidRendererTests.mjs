import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const testsDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(testsDirectory, "..");
const rendererDirectory = path.join(
  repositoryRoot,
  "Mark/Resources/MermaidRenderer",
);
const html = await readFile(path.join(rendererDirectory, "renderer.html"), "utf8");
const javascript = await readFile(
  path.join(rendererDirectory, "renderer.js"),
  "utf8",
);

test("hidden Mermaid renderer keeps all runtime dependencies local", () => {
  assert.match(html, /<script src="mermaid\.min\.js"><\/script>/);
  assert.match(html, /<script src="renderer\.js"><\/script>/);
  assert.doesNotMatch(html, /https?:\/\//i);
  assert.doesNotMatch(javascript, /\b(fetch|XMLHttpRequest|WebSocket)\b/);
});

test("hidden Mermaid renderer has a network-denying content security policy", () => {
  assert.match(html, /default-src 'none'/);
  assert.match(html, /script-src 'self'/);
  assert.match(html, /connect-src 'none'/);
  assert.match(html, /object-src 'none'/);
  assert.match(html, /base-uri 'none'/);
  assert.match(html, /form-action 'none'/);
});

test("renderer exposes only the argument-driven Mermaid SVG API", () => {
  assert.match(javascript, /window\.mermaidRuntime = Object\.freeze/);
  assert.match(javascript, /async render\(source, requestID, theme, appearance\)/);
  assert.match(javascript, /securityLevel: "strict"/);
  assert.match(javascript, /suppressErrorRendering: true/);
  assert.doesNotMatch(javascript, /window\.webkit|messageHandlers/);
  assert.doesNotMatch(javascript, /innerHTML\s*=/);
});

test("renderer constrains themes and sanitizes Mermaid DOM identifiers", () => {
  assert.match(
    javascript,
    /new Set\(\["default", "neutral", "forest", "dark", "base"\]\)/,
  );
  assert.match(javascript, /replace\(\/\[\^a-zA-Z0-9_-\]\/g, ""\)/);
  assert.match(javascript, /DOMParser\(\)\.parseFromString\(svg, "image\/svg\+xml"\)/);
});
