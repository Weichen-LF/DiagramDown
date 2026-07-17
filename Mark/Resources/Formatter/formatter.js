const plugins = [
  prettierPlugins.markdown,
  prettierPlugins.babel,
  prettierPlugins.estree,
  prettierPlugins.typescript,
  prettierPlugins.html,
  prettierPlugins.postcss,
  prettierPlugins.yaml,
];

async function formatMarkdown(source) {
  return prettier.format(String(source), {
    parser: "markdown",
    plugins,
    proseWrap: "preserve",
    tabWidth: 2,
    useTabs: false,
    embeddedLanguageFormatting: "auto",
  });
}

window.formatterRuntime = Object.freeze({ formatMarkdown });
