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
let activeD2ConfigurationID = "default";
let activeAppearance = "system";
let activeMarkdownTheme = "diagramDown";
let activeMermaidLightTheme = "default";
let activeMermaidDarkTheme = "dark";
let mermaidQueue = Promise.resolve();
const d2Sources = new Map();
let pendingD2BlockIDs = new Set();
const d2SVGCache = new Map();
const maximumD2SVGCacheBytes = 32 * 1024 * 1024;
let d2SVGCacheBytes = 0;
let latestD2CacheKeys = [];
let lastSuccessfulD2CacheKeys = [];
let previewScrollAnimationFrame = 0;
let previewScrollMessageFrame = 0;
let suppressPreviewScrollMessages = false;
let activeDiagramViewer = null;
let trackpadGestureActive = false;
let trackpadGestureTarget = "preview";

const diagramZoomMinimum = 0.25;
const diagramZoomMaximum = 4;
const diagramZoomStep = 0.25;

function configureMermaid() {
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: "strict",
    theme: effectiveDarkMode()
      ? activeMermaidDarkTheme
      : activeMermaidLightTheme,
    flowchart: {
      htmlLabels: false,
    },
  });
}

function effectiveDarkMode() {
  if (activeAppearance === "dark") {
    return true;
  }
  if (activeAppearance === "light") {
    return false;
  }
  return colorScheme.matches;
}

function supportedValue(value, supported, fallback) {
  const normalized = String(value);
  return supported.has(normalized) ? normalized : fallback;
}

function applyPreviewConfiguration(
  d2ConfigurationID,
  appearance,
  markdownTheme,
  mermaidLightTheme,
  mermaidDarkTheme,
) {
  activeD2ConfigurationID = String(d2ConfigurationID);
  activeAppearance = supportedValue(
    appearance,
    new Set(["system", "light", "dark"]),
    "system",
  );
  activeMarkdownTheme = supportedValue(
    markdownTheme,
    new Set(["diagramDown", "github", "paper"]),
    "diagramDown",
  );
  const mermaidThemes = new Set(["default", "neutral", "forest", "dark", "base"]);
  activeMermaidLightTheme = supportedValue(
    mermaidLightTheme,
    mermaidThemes,
    "default",
  );
  activeMermaidDarkTheme = supportedValue(
    mermaidDarkTheme,
    mermaidThemes,
    "dark",
  );

  document.documentElement.dataset.appearance = activeAppearance;
  document.documentElement.dataset.markdownTheme = activeMarkdownTheme;
  configureMermaid();
}

configureMermaid();

markdown.core.ruler.push("source_line_anchors", (state) => {
  for (const token of state.tokens) {
    if (token.block && Array.isArray(token.map)) {
      token.attrSet("data-source-line", String(token.map[0] + 1));
    }
  }
});

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
  const sourceLine = Array.isArray(token.map) ? token.map[0] + 1 : 1;

  if (language === "mermaid") {
    const blockID = stableBlockID(env, "mermaid", token.content);
    env.mermaidBlocks.push({
      id: blockID,
      source: token.content,
    });

    return `<div id="${blockID}-container" class="diagram mermaid-diagram" data-block-id="${blockID}" data-source-line="${sourceLine}" aria-label="Mermaid diagram"><div class="diagram-pending">Rendering Mermaid…</div></div>`;
  }

  if (language === "d2") {
    const blockID = stableBlockID(env, "d2", token.content);
    env.d2Blocks.push({
      id: blockID,
      source: token.content,
    });

    return `<div id="${blockID}-container" class="diagram d2-diagram" data-block-id="${blockID}" data-source-line="${sourceLine}" aria-label="D2 diagram"><div class="diagram-pending">Rendering D2…</div></div>`;
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

function diagramDisplayName(kind) {
  return kind === "d2" ? "D2" : "Mermaid";
}

function postSVGExport(container, blockID, kind) {
  const currentSVG = container.querySelector("svg");
  const handler = window.webkit?.messageHandlers?.exportSVG;
  if (!currentSVG || !handler) {
    return;
  }

  const exportedSVG = currentSVG.cloneNode(true);
  if (!exportedSVG.hasAttribute("xmlns")) {
    exportedSVG.setAttribute("xmlns", "http://www.w3.org/2000/svg");
  }

  handler.postMessage({
    blockID,
    kind,
    sourceLine: Number.parseInt(container.dataset.sourceLine || "1", 10),
    svg: new XMLSerializer().serializeToString(exportedSVG),
  });
}

function diagramIntrinsicSize(svg) {
  const bounds = svg.getBoundingClientRect();
  const viewBox = svg.viewBox?.baseVal;
  const attributeWidth = Number.parseFloat(svg.getAttribute("width") || "");
  const attributeHeight = Number.parseFloat(svg.getAttribute("height") || "");
  const width = viewBox?.width > 0
    ? viewBox.width
    : (attributeWidth > 0 ? attributeWidth : bounds.width);
  const height = viewBox?.height > 0
    ? viewBox.height
    : (attributeHeight > 0 ? attributeHeight : bounds.height);

  return {
    width: Math.min(Math.max(width || 1, 1), 20000),
    height: Math.min(Math.max(height || 1, 1), 20000),
  };
}

function closeDiagramViewer() {
  activeDiagramViewer?.close();
}

function openDiagramViewer(container, kind, returnFocus) {
  const sourceSVG = container.querySelector("svg");
  if (!sourceSVG) {
    return;
  }

  closeDiagramViewer();

  const displayName = diagramDisplayName(kind);
  const size = diagramIntrinsicSize(sourceSVG);
  const overlay = document.createElement("div");
  overlay.className = "diagram-viewer";
  overlay.setAttribute("role", "dialog");
  overlay.setAttribute("aria-modal", "true");
  overlay.setAttribute("aria-label", `${displayName} diagram preview`);

  const toolbar = document.createElement("div");
  toolbar.className = "diagram-viewer-toolbar";

  const title = document.createElement("strong");
  title.className = "diagram-viewer-title";
  title.textContent = `${displayName} Diagram`;

  const controls = document.createElement("div");
  controls.className = "diagram-viewer-controls";

  const makeButton = (label, titleText, action, className = "") => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `diagram-viewer-button ${className}`.trim();
    button.textContent = label;
    button.title = titleText;
    button.setAttribute("aria-label", titleText);
    button.addEventListener("click", action);
    return button;
  };

  const viewport = document.createElement("div");
  viewport.className = "diagram-viewer-viewport";

  const canvas = document.createElement("div");
  canvas.className = "diagram-viewer-canvas";

  const viewerSVG = sourceSVG.cloneNode(true);
  viewerSVG.style.maxWidth = "none";
  viewerSVG.style.margin = "0";
  viewerSVG.style.flex = "none";
  viewerSVG.setAttribute("aria-label", `${displayName} diagram`);
  canvas.appendChild(viewerSVG);
  viewport.appendChild(canvas);

  let zoom = 1;
  let gestureStartZoom = zoom;
  let usingFitZoom = true;
  let zoomOutButton = null;
  let zoomInButton = null;

  const zoomValue = document.createElement("button");
  zoomValue.type = "button";
  zoomValue.className = "diagram-viewer-zoom-value";
  zoomValue.title = "Show diagram at actual size";
  zoomValue.setAttribute("aria-label", "Show diagram at actual size");

  const applyZoom = (nextZoom, fit = false) => {
    const previousCanvasWidth = Number.parseFloat(canvas.style.width)
      || viewport.clientWidth;
    const previousCanvasHeight = Number.parseFloat(canvas.style.height)
      || viewport.clientHeight;
    const horizontalCenterRatio = previousCanvasWidth > 0
      ? (viewport.scrollLeft + viewport.clientWidth / 2) / previousCanvasWidth
      : 0.5;
    const verticalCenterRatio = previousCanvasHeight > 0
      ? (viewport.scrollTop + viewport.clientHeight / 2) / previousCanvasHeight
      : 0.5;

    zoom = Math.min(Math.max(nextZoom, diagramZoomMinimum), diagramZoomMaximum);
    usingFitZoom = fit;
    const width = Math.max(size.width * zoom, 1);
    const height = Math.max(size.height * zoom, 1);
    const canvasWidth = Math.max(width + 64, viewport.clientWidth);
    const canvasHeight = Math.max(height + 64, viewport.clientHeight);

    viewerSVG.style.width = `${width}px`;
    viewerSVG.style.height = `${height}px`;
    canvas.style.width = `${canvasWidth}px`;
    canvas.style.height = `${canvasHeight}px`;
    zoomValue.textContent = `${Math.round(zoom * 100)}%`;
    if (zoomOutButton) {
      zoomOutButton.disabled = zoom <= diagramZoomMinimum;
    }
    if (zoomInButton) {
      zoomInButton.disabled = zoom >= diagramZoomMaximum;
    }

    requestAnimationFrame(() => {
      viewport.scrollLeft = Math.max(
        (fit ? 0.5 : horizontalCenterRatio) * canvasWidth - viewport.clientWidth / 2,
        0,
      );
      viewport.scrollTop = Math.max(
        (fit ? 0.5 : verticalCenterRatio) * canvasHeight - viewport.clientHeight / 2,
        0,
      );
    });
  };

  const fitDiagram = () => {
    const availableWidth = Math.max(viewport.clientWidth - 64, 1);
    const availableHeight = Math.max(viewport.clientHeight - 64, 1);
    applyZoom(
      Math.min(availableWidth / size.width, availableHeight / size.height),
      true,
    );
  };

  const close = () => {
    if (!overlay.isConnected) {
      return;
    }
    window.removeEventListener("keydown", handleKeyDown);
    window.removeEventListener("resize", handleResize);
    overlay.remove();
    document.documentElement.classList.remove("diagram-viewer-open");
    activeDiagramViewer = null;
    returnFocus?.focus();
  };

  const handleKeyDown = (event) => {
    if (event.key === "Escape") {
      event.preventDefault();
      close();
      return;
    }

    if (["+", "="].includes(event.key)) {
      event.preventDefault();
      applyZoom(zoom + diagramZoomStep);
    } else if (event.key === "-") {
      event.preventDefault();
      applyZoom(zoom - diagramZoomStep);
    } else if (event.key === "0") {
      event.preventDefault();
      applyZoom(1);
    } else if (event.key.toLowerCase() === "f") {
      event.preventDefault();
      fitDiagram();
    }
  };

  const handleResize = () => {
    if (usingFitZoom) {
      fitDiagram();
    } else {
      applyZoom(zoom);
    }
  };

  const beginGestureZoom = () => {
    gestureStartZoom = zoom;
  };

  const changeGestureZoom = (scale) => {
    if (Number.isFinite(scale)) {
      applyZoom(gestureStartZoom * scale);
    }
  };

  const applyGestureZoomDelta = (scale) => {
    if (Number.isFinite(scale)) {
      applyZoom(zoom * scale);
    }
  };

  const fitButton = makeButton("Fit", "Fit diagram to window", fitDiagram);
  zoomOutButton = makeButton("−", "Zoom out diagram", () => {
    applyZoom(zoom - diagramZoomStep);
  });
  zoomValue.addEventListener("click", () => applyZoom(1));
  zoomInButton = makeButton("+", "Zoom in diagram", () => {
    applyZoom(zoom + diagramZoomStep);
  });
  const closeButton = makeButton("Close", "Close diagram preview", close, "close");

  controls.append(fitButton, zoomOutButton, zoomValue, zoomInButton, closeButton);
  toolbar.append(title, controls);
  overlay.append(toolbar, viewport);
  overlay.addEventListener("click", (event) => {
    if (event.target === overlay) {
      close();
    }
  });

  document.documentElement.classList.add("diagram-viewer-open");
  document.body.appendChild(overlay);
  window.addEventListener("keydown", handleKeyDown);
  window.addEventListener("resize", handleResize);
  activeDiagramViewer = {
    applyGestureZoomDelta,
    beginGestureZoom,
    changeGestureZoom,
    close,
  };

  requestAnimationFrame(() => {
    fitDiagram();
    closeButton.focus();
  });
}

function installDiagramControls(container, blockID, kind) {
  const svg = container.querySelector("svg");
  if (!svg) {
    return;
  }

  const displayName = diagramDisplayName(kind);
  const actions = document.createElement("div");
  actions.className = "diagram-actions";

  const previewButton = document.createElement("button");
  previewButton.type = "button";
  previewButton.className = "diagram-action-button diagram-preview-button";
  previewButton.textContent = "Open Preview";
  previewButton.title = `Open ${displayName} diagram preview`;
  previewButton.setAttribute("aria-label", previewButton.title);
  previewButton.addEventListener("click", (event) => {
    event.preventDefault();
    event.stopPropagation();
    openDiagramViewer(container, kind, previewButton);
  });

  const exportButton = document.createElement("button");
  exportButton.type = "button";
  exportButton.className = "diagram-action-button diagram-export-button";
  exportButton.textContent = "Export SVG";
  exportButton.title = `Export ${displayName} diagram as SVG`;
  exportButton.setAttribute("aria-label", exportButton.title);
  exportButton.addEventListener("click", (event) => {
    event.preventDefault();
    event.stopPropagation();
    postSVGExport(container, blockID, kind);
  });

  actions.append(previewButton, exportButton);
  container.appendChild(actions);
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
      installDiagramControls(container, block.id, "mermaid");
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
      pendingD2BlockIDs.delete(block.id);
    }
    return;
  }

  handler.postMessage({
    blocks,
    revision,
  });
}

function d2CacheKey(blockID) {
  return `${activeD2ConfigurationID}\0${blockID}`;
}

function cachedD2SVG(cacheKey) {
  const entry = d2SVGCache.get(cacheKey);
  if (!entry) {
    return null;
  }

  d2SVGCache.delete(cacheKey);
  d2SVGCache.set(cacheKey, entry);
  return entry.svg;
}

function removeD2SVG(cacheKey) {
  const removed = d2SVGCache.get(cacheKey);
  if (!removed) {
    return;
  }

  d2SVGCache.delete(cacheKey);
  d2SVGCacheBytes -= removed.cost;
}

function storeD2SVG(cacheKey, svg) {
  const cost = new TextEncoder().encode(svg).byteLength;
  if (cost > maximumD2SVGCacheBytes) {
    return;
  }

  const previous = d2SVGCache.get(cacheKey);
  if (previous) {
    removeD2SVG(cacheKey);
  }

  d2SVGCache.set(cacheKey, { cost, svg });
  d2SVGCacheBytes += cost;

  while (d2SVGCacheBytes > maximumD2SVGCacheBytes) {
    const oldestCacheKey = d2SVGCache.keys().next().value;
    removeD2SVG(oldestCacheKey);
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

function showD2SVG(container, svg, blockID = null) {
  container.replaceChildren(sanitizedSVG(svg));
  if (blockID) {
    installDiagramControls(container, blockID, "d2");
  }
}

function restoreD2Blocks(blocks, revision) {
  const pendingBlocks = [];
  d2Sources.clear();

  for (const [index, block] of blocks.entries()) {
    d2Sources.set(block.id, block.source);

    const container = document.getElementById(`${block.id}-container`);
    const cacheKey = d2CacheKey(block.id);
    const exactSVG = cachedD2SVG(cacheKey);
    if (container && exactSVG) {
      try {
        showD2SVG(container, exactSVG, block.id);
        lastSuccessfulD2CacheKeys[index] = cacheKey;
        continue;
      } catch {
        removeD2SVG(cacheKey);
      }
    }

    const previousCacheKey = lastSuccessfulD2CacheKeys[index];
    const previousSVG = previousCacheKey
      ? cachedD2SVG(previousCacheKey)
      : null;
    if (container && previousSVG) {
      try {
        showD2SVG(container, previousSVG);
      } catch {
        removeD2SVG(previousCacheKey);
        // Leave the pending view visible if the previous SVG cannot be restored.
      }
    }

    pendingBlocks.push(block);
  }

  latestD2CacheKeys = blocks.map((block) => d2CacheKey(block.id));
  lastSuccessfulD2CacheKeys.length = blocks.length;
  pendingD2BlockIDs = new Set(pendingBlocks.map((block) => block.id));
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
    showD2SVG(container, svg, blockID);
    const cacheKey = d2CacheKey(blockID);
    storeD2SVG(cacheKey, svg);
    const blockIndex = latestD2CacheKeys.indexOf(cacheKey);
    if (blockIndex >= 0) {
      lastSuccessfulD2CacheKeys[blockIndex] = cacheKey;
    }
  } catch (error) {
    showD2Error(container, d2Sources.get(blockID) || "", errorMessage(error));
  }
  pendingD2BlockIDs.delete(blockID);
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
  pendingD2BlockIDs.delete(blockID);
  return true;
}

function waitForAnimationFrame() {
  return new Promise((resolve) => requestAnimationFrame(resolve));
}

async function prepareForPDFExport() {
  closeDiagramViewer();
  await mermaidQueue.catch(() => undefined);

  const deadline = Date.now() + 7000;
  while (pendingD2BlockIDs.size > 0 && Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 50));
  }

  await document.fonts?.ready;
  await waitForAnimationFrame();
  await waitForAnimationFrame();

  const pendingCount = Math.max(
    pendingD2BlockIDs.size,
    preview.querySelectorAll(".diagram-pending").length,
  );
  return {
    ready: pendingCount === 0,
    message: pendingCount === 0
      ? ""
      : `${pendingCount} diagram${pendingCount === 1 ? " is" : "s are"} still rendering. Try exporting again.`,
  };
}

function restoreScrollRatio(scroller, ratio) {
  suppressPreviewScrollMessages = true;
  requestAnimationFrame(() => {
    const nextMaximum = Math.max(
      scroller.scrollHeight - scroller.clientHeight,
      0,
    );
    scroller.scrollTop = ratio * nextMaximum;
    requestAnimationFrame(() => {
      if (previewScrollAnimationFrame === 0) {
        suppressPreviewScrollMessages = false;
      }
    });
  });
}

function sourceAnchors() {
  const scroller = document.scrollingElement;
  return [...preview.querySelectorAll("[data-source-line]")]
    .map((element) => ({
      element,
      sourceLine: Number.parseInt(element.dataset.sourceLine, 10),
      top: element.getBoundingClientRect().top + scroller.scrollTop,
    }))
    .filter((anchor) => Number.isFinite(anchor.sourceLine));
}

function cancelPreviewScrollAnimation() {
  if (previewScrollAnimationFrame !== 0) {
    cancelAnimationFrame(previewScrollAnimationFrame);
    previewScrollAnimationFrame = 0;
  }
  suppressPreviewScrollMessages = false;
}

function animatePreviewScroll(targetTop) {
  if (previewScrollAnimationFrame !== 0) {
    cancelAnimationFrame(previewScrollAnimationFrame);
  }

  suppressPreviewScrollMessages = true;
  const step = () => {
    const scroller = document.scrollingElement;
    const distance = targetTop - scroller.scrollTop;
    if (Math.abs(distance) < 0.75) {
      scroller.scrollTop = targetTop;
      previewScrollAnimationFrame = 0;
      requestAnimationFrame(() => {
        if (previewScrollAnimationFrame === 0) {
          suppressPreviewScrollMessages = false;
        }
      });
      return;
    }

    scroller.scrollTop += distance * 0.34;
    previewScrollAnimationFrame = requestAnimationFrame(step);
  };

  previewScrollAnimationFrame = requestAnimationFrame(step);
}

function scrollToSourceLine(sourceLine, progress) {
  const scroller = document.scrollingElement;
  const maximumScroll = Math.max(
    scroller.scrollHeight - scroller.clientHeight,
    0,
  );
  const fallbackTop = Math.min(Math.max(progress, 0), 1) * maximumScroll;
  const anchors = sourceAnchors();

  let targetTop = fallbackTop;
  if (anchors.length > 0) {
    let before = anchors[0];
    let after = anchors[anchors.length - 1];

    for (const anchor of anchors) {
      if (anchor.sourceLine <= sourceLine) {
        before = anchor;
      }
      if (anchor.sourceLine >= sourceLine) {
        after = anchor;
        break;
      }
    }

    const beforeTop = before.top;
    const afterTop = after.top;
    if (after.sourceLine > before.sourceLine) {
      const lineFraction = (sourceLine - before.sourceLine)
        / (after.sourceLine - before.sourceLine);
      targetTop = beforeTop + (afterTop - beforeTop) * lineFraction;
    } else if (sourceLine < anchors[0].sourceLine
               || sourceLine > anchors[anchors.length - 1].sourceLine) {
      targetTop = fallbackTop;
    } else {
      targetTop = beforeTop;
    }
  }

  animatePreviewScroll(Math.min(Math.max(targetTop, 0), maximumScroll));
  return anchors.length > 0;
}

function previewScrollPosition() {
  const scroller = document.scrollingElement;
  const maximumScroll = Math.max(
    scroller.scrollHeight - scroller.clientHeight,
    0,
  );
  const progress = maximumScroll > 0 ? scroller.scrollTop / maximumScroll : 0;
  const anchors = sourceAnchors();
  if (anchors.length === 0) {
    return { progress, sourceLine: 1, usesProgressFallback: true };
  }

  const viewportTop = scroller.scrollTop;
  if (viewportTop <= anchors[0].top) {
    return {
      progress,
      sourceLine: anchors[0].sourceLine,
      usesProgressFallback: false,
    };
  }

  for (let index = 1; index < anchors.length; index += 1) {
    const before = anchors[index - 1];
    const after = anchors[index];
    if (viewportTop <= after.top && after.top > before.top) {
      const positionFraction = (viewportTop - before.top) / (after.top - before.top);
      return {
        progress,
        sourceLine: before.sourceLine
          + (after.sourceLine - before.sourceLine) * positionFraction,
        usesProgressFallback: false,
      };
    }
  }

  return {
    progress,
    sourceLine: anchors[anchors.length - 1].sourceLine,
    usesProgressFallback: true,
  };
}

function postPreviewScrollPosition() {
  const handler = window.webkit?.messageHandlers?.scrollSync;
  if (!handler) {
    return;
  }

  handler.postMessage({
    kind: "previewScroll",
    ...previewScrollPosition(),
  });
}

async function renderMarkdown(
  source,
  revision,
  d2ConfigurationID = "default",
  appearance = "system",
  markdownTheme = "diagramDown",
  mermaidLightTheme = "default",
  mermaidDarkTheme = "dark",
) {
  closeDiagramViewer();
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
  applyPreviewConfiguration(
    d2ConfigurationID,
    appearance,
    markdownTheme,
    mermaidLightTheme,
    mermaidDarkTheme,
  );

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
  if (activeAppearance !== "system") {
    return;
  }
  void renderMarkdown(
    latestSource,
    latestRevision,
    activeD2ConfigurationID,
    activeAppearance,
    activeMarkdownTheme,
    activeMermaidLightTheme,
    activeMermaidDarkTheme,
  );
});

preview.addEventListener("click", (event) => {
  if (!(event.target instanceof Element) || event.target.closest("a, button")) {
    return;
  }

  const anchor = event.target.closest("[data-source-line]");
  const sourceLine = Number.parseInt(anchor?.dataset.sourceLine || "", 10);
  if (!Number.isFinite(sourceLine)) {
    return;
  }

  window.webkit?.messageHandlers?.scrollSync?.postMessage({
    kind: "selection",
    sourceLine,
  });
});

function postPreviewZoomGesture(phase, scale = 1) {
  window.webkit?.messageHandlers?.previewZoom?.postMessage({ phase, scale });
}

function handleGestureStart(event) {
  event.preventDefault();
  cancelPreviewScrollAnimation();
  trackpadGestureActive = true;
  trackpadGestureTarget = activeDiagramViewer ? "diagram" : "preview";

  if (trackpadGestureTarget === "diagram") {
    activeDiagramViewer?.beginGestureZoom();
  } else {
    postPreviewZoomGesture("start");
  }
}

function handleGestureChange(event) {
  event.preventDefault();
  const scale = Number(event.scale);
  if (!Number.isFinite(scale)) {
    return;
  }

  if (trackpadGestureTarget === "diagram") {
    activeDiagramViewer?.changeGestureZoom(scale);
  } else {
    postPreviewZoomGesture("change", scale);
  }
}

function handleGestureEnd(event) {
  event.preventDefault();
  if (trackpadGestureTarget === "preview") {
    postPreviewZoomGesture("end");
  }
  trackpadGestureActive = false;
  trackpadGestureTarget = "preview";
}

function handleWheel(event) {
  cancelPreviewScrollAnimation();
  if (!event.ctrlKey) {
    return;
  }

  event.preventDefault();
  if (trackpadGestureActive) {
    return;
  }

  const scale = Math.min(Math.max(Math.exp(-event.deltaY * 0.01), 0.85), 1.15);
  if (activeDiagramViewer) {
    activeDiagramViewer.applyGestureZoomDelta(scale);
  } else {
    postPreviewZoomGesture("delta", scale);
  }
}

window.addEventListener("gesturestart", handleGestureStart, { passive: false });
window.addEventListener("gesturechange", handleGestureChange, { passive: false });
window.addEventListener("gestureend", handleGestureEnd, { passive: false });
window.addEventListener("gesturecancel", handleGestureEnd, { passive: false });
window.addEventListener("wheel", handleWheel, { passive: false });
window.addEventListener("pointerdown", cancelPreviewScrollAnimation, { passive: true });
window.addEventListener("scroll", () => {
  if (suppressPreviewScrollMessages || previewScrollMessageFrame !== 0) {
    return;
  }

  previewScrollMessageFrame = requestAnimationFrame(() => {
    previewScrollMessageFrame = 0;
    if (!suppressPreviewScrollMessages) {
      postPreviewScrollPosition();
    }
  });
}, { passive: true });

window.previewRuntime = Object.freeze({
  applyD2Error,
  applyD2Result,
  prepareForPDFExport,
  renderMarkdown,
  scrollToSourceLine,
});
