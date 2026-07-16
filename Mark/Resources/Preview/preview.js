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

markdown.renderer.rules.fence = (tokens, index, options, env, self) => {
  const token = tokens[index];
  const language = token.info.trim().split(/\s+/u, 1)[0].toLowerCase();

  if (language !== "mermaid") {
    return defaultFenceRenderer(tokens, index, options, env, self);
  }

  const blockIndex = env.mermaidBlocks.length;
  const blockID = `mermaid-${env.revision}-${blockIndex}`;
  env.mermaidBlocks.push({
    id: blockID,
    source: token.content,
  });

  return `<div id="${blockID}-container" class="diagram mermaid-diagram" data-block-id="${blockID}" aria-label="Mermaid diagram"><div class="diagram-pending">Rendering Mermaid…</div></div>`;
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
  renderMarkdown,
});
