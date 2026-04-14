// Shared highlight.js instance — core build with all languages emitted by
// language_class/1 in file_helpers.ex. Full build ships 384 langs (~1MB);
// core + these 19 langs is ~200KB — still ~80% smaller.
//
// Languages: markdown, json, elixir, bash, yaml, toml(=ini), javascript,
//   typescript, html(=xml), css, python, ruby, go, rust, java, c, cpp, sql, xml
//
// Both markdown.js, hooks/highlight.js, and NotesTab.svelte import getHljs()
// from here so Vite bundles one shared syntax chunk with no duplication.

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
      { default: javascript },
      { default: typescript },
      { default: xml },
      { default: css },
      { default: python },
      { default: ruby },
      { default: go },
      { default: rust },
      { default: java },
      { default: c },
      { default: cpp },
      { default: sql },
    ] = await Promise.all([
      import('highlight.js/lib/core'),
      import('highlight.js/lib/languages/markdown'),
      import('highlight.js/lib/languages/json'),
      import('highlight.js/lib/languages/elixir'),
      import('highlight.js/lib/languages/bash'),
      import('highlight.js/lib/languages/yaml'),
      import('highlight.js/lib/languages/ini'),
      import('highlight.js/lib/languages/javascript'),
      import('highlight.js/lib/languages/typescript'),
      import('highlight.js/lib/languages/xml'),
      import('highlight.js/lib/languages/css'),
      import('highlight.js/lib/languages/python'),
      import('highlight.js/lib/languages/ruby'),
      import('highlight.js/lib/languages/go'),
      import('highlight.js/lib/languages/rust'),
      import('highlight.js/lib/languages/java'),
      import('highlight.js/lib/languages/c'),
      import('highlight.js/lib/languages/cpp'),
      import('highlight.js/lib/languages/sql'),
    ]);

    hljs.registerLanguage('markdown', markdown);
    hljs.registerLanguage('json', json);
    hljs.registerLanguage('elixir', elixir);
    hljs.registerLanguage('bash', bash);
    hljs.registerLanguage('shell', bash);     // alias
    hljs.registerLanguage('yaml', yaml);
    hljs.registerLanguage('toml', ini);       // no hljs toml grammar; ini is closest
    hljs.registerLanguage('ini', ini);
    hljs.registerLanguage('javascript', javascript);
    hljs.registerLanguage('js', javascript);  // alias
    hljs.registerLanguage('typescript', typescript);
    hljs.registerLanguage('ts', typescript);  // alias
    hljs.registerLanguage('xml', xml);
    hljs.registerLanguage('html', xml);       // xml grammar handles html
    hljs.registerLanguage('css', css);
    hljs.registerLanguage('python', python);
    hljs.registerLanguage('ruby', ruby);
    hljs.registerLanguage('go', go);
    hljs.registerLanguage('rust', rust);
    hljs.registerLanguage('java', java);
    hljs.registerLanguage('c', c);
    hljs.registerLanguage('cpp', cpp);
    hljs.registerLanguage('sql', sql);
    hljs.registerLanguage('plaintext', () => ({ name: 'Plaintext', aliases: ['text', 'txt'] }));

    _hljs = hljs;
  }
  return _hljs;
}
