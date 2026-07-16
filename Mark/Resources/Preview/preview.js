(() => {
  "use strict";

  const preview = document.getElementById("preview");
  const markdown = window.markdownit({
    breaks: false,
    html: false,
    linkify: true,
    typographer: false,
  });

  function renderMarkdown(source, revision) {
    const scroller = document.scrollingElement;
    const previousMaximum = Math.max(
      scroller.scrollHeight - scroller.clientHeight,
      0,
    );
    const scrollRatio = previousMaximum > 0
      ? scroller.scrollTop / previousMaximum
      : 0;

    if (source.trim().length === 0) {
      preview.replaceChildren();
      const emptyState = document.createElement("p");
      emptyState.className = "preview-empty";
      emptyState.textContent = "Start writing to see a preview.";
      preview.appendChild(emptyState);
    } else {
      preview.innerHTML = markdown.render(source);
    }

    preview.dataset.revision = String(revision);

    requestAnimationFrame(() => {
      const nextMaximum = Math.max(
        scroller.scrollHeight - scroller.clientHeight,
        0,
      );
      scroller.scrollTop = scrollRatio * nextMaximum;
    });

    return revision;
  }

  window.previewRuntime = Object.freeze({
    renderMarkdown,
  });
})();
