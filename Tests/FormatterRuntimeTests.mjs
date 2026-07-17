import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const repositoryRoot = fileURLToPath(new URL("../", import.meta.url));
const formatterDirectory = path.join(repositoryRoot, "Mark/Resources/Formatter");

async function loadRuntime() {
  const context = vm.createContext({ console, setTimeout, clearTimeout });
  context.globalThis = context;
  context.self = context;
  context.window = context;

  for (const fileName of [
    "prettier.js",
    "markdown.js",
    "babel.js",
    "estree.js",
    "typescript.js",
    "html.js",
    "postcss.js",
    "yaml.js",
    "formatter.js",
  ]) {
    const source = await readFile(path.join(formatterDirectory, fileName), "utf8");
    vm.runInContext(source, context, { filename: fileName });
  }
  return context.formatterRuntime;
}

test("bundled Prettier formats Markdown and embedded code offline", async () => {
  const runtime = await loadRuntime();
  const source = "#  Heading\n\n```json\n{\"name\":\"DiagramDown\",\"ok\":true}\n```\n";
  const formatted = await runtime.formatMarkdown(source);

  assert.match(formatted, /^# Heading/mu);
  assert.match(formatted, /\{ "name": "DiagramDown", "ok": true \}/u);
});

test("Prettier leaves Mermaid diagram source unchanged", async () => {
  const runtime = await loadRuntime();
  const diagram = "graph TD\nA-->B";
  const formatted = await runtime.formatMarkdown(`\`\`\`mermaid\n${diagram}\n\`\`\`\n`);
  assert.ok(formatted.includes(diagram));
});
