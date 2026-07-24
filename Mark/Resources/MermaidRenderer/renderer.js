"use strict";

(() => {
  const allowedThemes = new Set(["default", "neutral", "forest", "dark", "base"]);

  function dimensions(svg) {
    const document = new DOMParser().parseFromString(svg, "image/svg+xml");
    const root = document.documentElement;
    const viewBox = (root.getAttribute("viewBox") || "")
      .trim()
      .split(/[\s,]+/)
      .map(Number);
    if (viewBox.length === 4 && viewBox.every(Number.isFinite)) {
      return { width: viewBox[2], height: viewBox[3] };
    }
    const width = Number.parseFloat(root.getAttribute("width") || "800");
    const height = Number.parseFloat(root.getAttribute("height") || "600");
    return {
      width: Number.isFinite(width) ? width : 800,
      height: Number.isFinite(height) ? height : 600,
    };
  }

  window.mermaidRuntime = Object.freeze({
    async render(source, requestID, theme, appearance) {
      const selectedTheme = allowedThemes.has(theme) ? theme : "default";
      mermaid.initialize({
        startOnLoad: false,
        securityLevel: "strict",
        htmlLabels: false,
        theme: selectedTheme,
        darkMode: appearance === "dark",
        suppressErrorRendering: true,
      });

      const safeRequestID = String(requestID).replace(/[^a-zA-Z0-9_-]/g, "");
      const result = await mermaid.render(`diagramdown-${safeRequestID}`, source);
      const size = dimensions(result.svg);
      return {
        requestID,
        svg: result.svg,
        width: size.width,
        height: size.height,
      };
    },
  });
})();
