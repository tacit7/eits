// Shared highlight.js instance — core build with only the languages this app uses.
// Full highlight.js ships 384 languages (~1MB minified). Core + 6 langs is ~60KB.
//
// Languages used (from language_class/1 in config_browser.ex, files.ex, config.ex):
//   markdown, json, elixir, bash, yaml, toml (no hljs toml grammar — ini is the closest).
//
// Both markdown.js and hooks/highlight.js import from here, so Vite bundles
// one shared chunk with no duplication.

let _hljs = null;

export async function getHljs() {
  if (!_hljs) {
    const [
      { default: hljs },
      { default: markdown },
      { default: json },
      { default: elixir },
      { default: bash },
      { default: yaml },
      { default: ini },
    ] = await Promise.all([
      import('highlight.js/lib/core'),
      import('highlight.js/lib/languages/markdown'),
      import('highlight.js/lib/languages/json'),
      import('highlight.js/lib/languages/elixir'),
      import('highlight.js/lib/languages/bash'),
      import('highlight.js/lib/languages/yaml'),
      import('highlight.js/lib/languages/ini'),
    ]);

    hljs.registerLanguage('markdown', markdown);
    hljs.registerLanguage('json', json);
    hljs.registerLanguage('elixir', elixir);
    hljs.registerLanguage('bash', bash);
    hljs.registerLanguage('shell', bash); // alias
    hljs.registerLanguage('yaml', yaml);
    hljs.registerLanguage('toml', ini);   // closest hljs grammar for toml
    hljs.registerLanguage('ini', ini);
    hljs.registerLanguage('plaintext', (hljs) => ({ name: 'Plaintext', aliases: ['text', 'txt'] }));

    _hljs = hljs;
  }
  return _hljs;
}
