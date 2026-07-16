const preview = document.getElementById("preview");
const colorScheme = window.matchMedia("(prefers-color-scheme: dark)");
const mermaid = window.mermaid;
const markdown = window.markdownit({
  breaks: false,
  html: false,
  linkify: true,
  typographer: false,
});
const defaultFenceRenderer = markdown.renderer.rules.fence;

let latestRevision = 0;
let latestSource = "";
let mermaidQueue = Promise.resolve();
const d2Sources = new Map();
const d2SVGCache = new Map();
const maximumD2SVGCacheBytes = 32 * 1024 * 1024;
let d2SVGCacheBytes = 0;
let latestD2BlockIDs = [];
let lastSuccessfulD2BlockIDs = [];

function configureMermaid() {
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: "strict",
    theme: colorScheme.matches ? "dark" : "default",
    flowchart: {
      htmlLabels: false,
    },
  });
}

configureMermaid();

function sourceFingerprint(language, source) {
  const value = `${language}\0${source}`;
  let first = 0x811c9dc5;
  let second = 0x9e3779b9;

  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    first = Math.imul(first ^ code, 0x01000193);
    second = Math.imul(second ^ code, 0x85ebca6b);
  }

  return [first, second]
    .map((valuePart) => (valuePart >>> 0).toString(16).padStart(8, "0"))
    .join("");
}

function stableBlockID(environment, language, source) {
  const fingerprint = sourceFingerprint(language, source);
  const occurrenceKey = `${language}-${fingerprint}`;
  const occurrence = environment.blockOccurrences.get(occurrenceKey) || 0;
  environment.blockOccurrences.set(occurrenceKey, occurrence + 1);
  return `${language}-${fingerprint}-${occurrence}`;
}

markdown.renderer.rules.fence = (tokens, index, options, env, self) => {
  const token = tokens[index];
  const language = token.info.trim().split(/\s+/u, 1)[0].toLowerCase();

  if (language === "mermaid") {
    const blockID = stableBlockID(env, "mermaid", token.content);
    env.mermaidBlocks.push({
      id: blockID,
      source: token.content,
    });

    return `<div id="${blockID}-container" class="diagram mermaid-diagram" data-block-id="${blockID}" aria-label="Mermaid diagram"><div class="diagram-pending">Rendering Mermaid…</div></div>`;
  }

  if (language === "d2") {
    const blockID = stableBlockID(env, "d2", token.content);
    env.d2Blocks.push({
      id: blockID,
      source: token.content,
    });

    return `<div id="${blockID}-container" class="diagram d2-diagram" data-block-id="${blockID}" aria-label="D2 diagram"><div class="diagram-pending">Rendering D2…</div></div>`;
  }

  return defaultFenceRenderer(tokens, index, options, env, self);
};

function errorMessage(error) {
  if (error instanceof Error && error.message) {
    return error.message;
  }

  return String(error || "Unknown Mermaid error");
}

function showMermaidError(container, source, error) {
  const errorView = document.createElement("div");
  errorView.className = "diagram-error";

  const title = document.createElement("strong");
  title.textContent = "Mermaid rendering failed";

  const message = document.createElement("pre");
  message.className = "diagram-error-message";
  message.textContent = errorMessage(error);

  const sourceDisclosure = document.createElement("details");
  const sourceSummary = document.createElement("summary");
  const sourceCode = document.createElement("pre");
  sourceSummary.textContent = "Show source";
  sourceCode.textContent = source;
  sourceDisclosure.append(sourceSummary, sourceCode);

  errorView.append(title, message, sourceDisclosure);
  container.replaceChildren(errorView);
}

async function renderMermaidBlocks(blocks, revision) {
  for (const block of blocks) {
    if (revision !== latestRevision) {
      return;
    }

    const container = document.getElementById(`${block.id}-container`);
    if (!container) {
      continue;
    }

    try {
      const result = await mermaid.render(block.id, block.source);
      if (revision !== latestRevision || !container.isConnected) {
        continue;
      }

      container.innerHTML = result.svg;
      result.bindFunctions?.(container);
    } catch (error) {
      if (revision === latestRevision && container.isConnected) {
        showMermaidError(container, block.source, error);
      }
    } finally {
      document.getElementById(`d${block.id}`)?.remove();
    }
  }
}

function requestD2Blocks(blocks, revision) {
  if (blocks.length === 0) {
    return;
  }

  const handler = window.webkit?.messageHandlers?.d2;
  if (!handler) {
    for (const block of blocks) {
      const container = document.getElementById(`${block.id}-container`);
      if (container) {
        showD2Error(container, block.source, "The native D2 renderer is unavailable.");
      }
    }
    return;
  }

  handler.postMessage({
    blocks,
    revision,
  });
}

function cachedD2SVG(blockID) {
  const entry = d2SVGCache.get(blockID);
  if (!entry) {
    return null;
  }

  d2SVGCache.delete(blockID);
  d2SVGCache.set(blockID, entry);
  return entry.svg;
}

function removeD2SVG(blockID) {
  const removed = d2SVGCache.get(blockID);
  if (!removed) {
    return;
  }

  d2SVGCache.delete(blockID);
  d2SVGCacheBytes -= removed.cost;
}

function storeD2SVG(blockID, svg) {
  const cost = new TextEncoder().encode(svg).byteLength;
  if (cost > maximumD2SVGCacheBytes) {
    return;
  }

  const previous = d2SVGCache.get(blockID);
  if (previous) {
    removeD2SVG(blockID);
  }

  d2SVGCache.set(blockID, { cost, svg });
  d2SVGCacheBytes += cost;

  while (d2SVGCacheBytes > maximumD2SVGCacheBytes) {
    const oldestBlockID = d2SVGCache.keys().next().value;
    removeD2SVG(oldestBlockID);
  }
}

function sanitizedSVG(source) {
  const parsed = new DOMParser().parseFromString(source, "image/svg+xml");
  const root = parsed.documentElement;
  if (parsed.querySelector("parsererror") || root.localName.toLowerCase() !== "svg") {
    throw new Error("D2 returned invalid SVG markup.");
  }

  const blockedElements = new Set([
    "audio",
    "embed",
    "foreignobject",
    "iframe",
    "object",
    "script",
    "video",
  ]);
  const elements = [root, ...root.querySelectorAll("*")];

  for (const element of elements) {
    if (blockedElements.has(element.localName.toLowerCase())) {
      element.remove();
      continue;
    }

    for (const attribute of [...element.attributes]) {
      const attributeName = attribute.localName.toLowerCase();
      const attributeValue = attribute.value.trim();
      const normalizedValue = attributeValue.toLowerCase();

      if (attributeName.startsWith("on")) {
        element.removeAttributeNode(attribute);
        continue;
      }

      if (attributeName === "href") {
        const isLink = element.localName.toLowerCase() === "a";
        const allowedLink = isLink && /^(https?:|mailto:|#)/u.test(normalizedValue);
        const allowedResource = /^(data:image\/|#)/u.test(normalizedValue);
        if (!allowedLink && !allowedResource) {
          element.removeAttributeNode(attribute);
        }
        continue;
      }

      if (attributeName === "style"
          && /url\(\s*["']?(?!#|data:image\/)/iu.test(attributeValue)) {
        element.removeAttributeNode(attribute);
      }
    }
  }

  return document.importNode(root, true);
}

function showD2Error(container, source, message) {
  const errorView = document.createElement("div");
  errorView.className = "diagram-error";

  const title = document.createElement("strong");
  title.textContent = "D2 rendering failed";

  const errorMessageView = document.createElement("pre");
  errorMessageView.className = "diagram-error-message";
  errorMessageView.textContent = message || "Unknown D2 error";

  const sourceDisclosure = document.createElement("details");
  const sourceSummary = document.createElement("summary");
  const sourceCode = document.createElement("pre");
  sourceSummary.textContent = "Show source";
  sourceCode.textContent = source;
  sourceDisclosure.append(sourceSummary, sourceCode);

  errorView.append(title, errorMessageView, sourceDisclosure);
  container.replaceChildren(errorView);
}

function showD2SVG(container, svg) {
  container.replaceChildren(sanitizedSVG(svg));
}

function restoreD2Blocks(blocks, revision) {
  const pendingBlocks = [];
  d2Sources.clear();

  for (const [index, block] of blocks.entries()) {
    d2Sources.set(block.id, block.source);

    const container = document.getElementById(`${block.id}-container`);
    const exactSVG = cachedD2SVG(block.id);
    if (container && exactSVG) {
      try {
        showD2SVG(container, exactSVG);
        continue;
      } catch {
        removeD2SVG(block.id);
      }
    }

    const previousBlockID = lastSuccessfulD2BlockIDs[index];
    const previousSVG = previousBlockID
      ? cachedD2SVG(previousBlockID)
      : null;
    if (container && previousSVG) {
      try {
        showD2SVG(container, previousSVG);
      } catch {
        removeD2SVG(previousBlockID);
        // Leave the pending view visible if the previous SVG cannot be restored.
      }
    }

    pendingBlocks.push(block);
  }

  latestD2BlockIDs = blocks.map((block) => block.id);
  lastSuccessfulD2BlockIDs.length = blocks.length;
  requestD2Blocks(pendingBlocks, revision);
}

function applyD2Result(blockID, revision, svg) {
  if (revision !== latestRevision) {
    return false;
  }

  const container = document.getElementById(`${blockID}-container`);
  if (!container) {
    return false;
  }

  try {
    showD2SVG(container, svg);
    storeD2SVG(blockID, svg);
    const blockIndex = latestD2BlockIDs.indexOf(blockID);
    if (blockIndex >= 0) {
      lastSuccessfulD2BlockIDs[blockIndex] = blockID;
    }
  } catch (error) {
    showD2Error(container, d2Sources.get(blockID) || "", errorMessage(error));
  }
  return true;
}

function applyD2Error(blockID, revision, message) {
  if (revision !== latestRevision) {
    return false;
  }

  const container = document.getElementById(`${blockID}-container`);
  if (!container) {
    return false;
  }

  showD2Error(container, d2Sources.get(blockID) || "", message);
  return true;
}

function restoreScrollRatio(scroller, ratio) {
  requestAnimationFrame(() => {
    const nextMaximum = Math.max(
      scroller.scrollHeight - scroller.clientHeight,
      0,
    );
    scroller.scrollTop = ratio * nextMaximum;
  });
}

async function renderMarkdown(source, revision) {
  const scroller = document.scrollingElement;
  const previousMaximum = Math.max(
    scroller.scrollHeight - scroller.clientHeight,
    0,
  );
  const scrollRatio = previousMaximum > 0
    ? scroller.scrollTop / previousMaximum
    : 0;
  const environment = {
    blockOccurrences: new Map(),
    d2Blocks: [],
    mermaidBlocks: [],
    revision,
  };

  latestRevision = revision;
  latestSource = source;

  if (source.trim().length === 0) {
    preview.replaceChildren();
    const emptyState = document.createElement("p");
    emptyState.className = "preview-empty";
    emptyState.textContent = "Start writing to see a preview.";
    preview.appendChild(emptyState);
  } else {
    preview.innerHTML = markdown.render(source, environment);
  }

  preview.dataset.revision = String(revision);
  restoreD2Blocks(environment.d2Blocks, revision);

  mermaidQueue = mermaidQueue
    .catch(() => undefined)
    .then(() => renderMermaidBlocks(environment.mermaidBlocks, revision));
  await mermaidQueue;

  if (revision === latestRevision) {
    restoreScrollRatio(scroller, scrollRatio);
  }

  return revision;
}

colorScheme.addEventListener("change", () => {
  configureMermaid();
  void renderMarkdown(latestSource, latestRevision);
});

window.previewRuntime = Object.freeze({
  applyD2Error,
  applyD2Result,
  renderMarkdown,
});
