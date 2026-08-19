// @ts-check
import {themes as prismThemes} from 'prism-react-renderer';

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'StumpCloud Dotfiles',
  tagline: 'chezmoi // Oh My Zsh // OpenBao — one command, any machine.',
  favicon: 'img/favicon.svg',

  // Published to TWO hosts from one source: Gitea Pages (canonical) and the
  // GitHub Pages mirror. Only the host differs — the GitHub workflow sets
  // SITE_URL; the default keeps local `npm start` and the Gitea build canonical.
  url: process.env.SITE_URL || 'https://joestump.pages.stump.rocks',
  baseUrl: '/dotfiles/',

  organizationName: 'joestump',
  projectName: 'dotfiles',
  onBrokenLinks: 'throw',
  onBrokenAnchors: 'throw',
  markdown: {mermaid: true, hooks: {onBrokenMarkdownLinks: 'warn'}},
  themes: ['@docusaurus/theme-mermaid'],

  future: {v4: true},

  i18n: {defaultLocale: 'en', locales: ['en']},

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          routeBasePath: 'docs',
          sidebarPath: './sidebars.js',
          editUrl: 'https://gitea.stump.rocks/joestump/dotfiles/_edit/main/website/',
        },
        blog: false,
        theme: {customCss: './src/css/custom.css'},
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      colorMode: {defaultMode: 'dark', disableSwitch: true, respectPrefersColorScheme: false},
      mermaid: {theme: {light: 'dark', dark: 'dark'}},
      navbar: {
        title: 'DOTFILES',
        items: [
          {type: 'docSidebar', sidebarId: 'main', position: 'left', label: 'Docs'},
          {to: '/docs/install/mothership', label: 'Install', position: 'left'},
          {to: '/docs/commands', label: 'Commands', position: 'left'},
          {to: '/docs/claude/harness', label: 'Agents', position: 'left'},
          {href: 'https://gitea.stump.rocks/joestump/dotfiles', label: 'Gitea', position: 'right'},
        ],
      },
      footer: {
        style: 'dark',
        links: [
          {
            title: 'Start here',
            items: [
              {label: 'Overview', to: '/docs/overview'},
              {label: 'The Hub (macOS)', to: '/docs/install/mothership'},
              {label: 'Spokes (Linux)', to: '/docs/install/nodes'},
              {label: 'Command reference', to: '/docs/commands'},
              {label: 'Editing', to: '/docs/workflow'},
            ],
          },
          {
            title: 'Systems',
            items: [
              {label: 'Secrets', to: '/docs/secrets'},
              {label: 'Packages', to: '/docs/packages'},
              {label: 'Services & schedules', to: '/docs/services'},
              {label: 'Terminal', to: '/docs/terminal'},
            ],
          },
          {
            title: 'AI & Agents',
            items: [
              {label: 'Harness', to: '/docs/claude/harness'},
              {label: 'Crush', to: '/docs/claude/crush'},
              {label: 'MCP servers', to: '/docs/claude/mcp'},
              {label: 'Agent rules', to: '/docs/claude/agents'},
            ],
          },
          {
            title: 'Source',
            items: [
              {label: 'Gitea repo', href: 'https://gitea.stump.rocks/joestump/dotfiles'},
              {label: 'GitHub mirror', href: 'https://github.com/joestump/dotfiles'},
              {label: 'OpenBao', href: 'https://vault.stump.rocks'},
            ],
          },
        ],
        copyright: `// ${new Date().getFullYear()} STUMPCLOUD — transmitted over the wire.`,
      },
      prism: {
        theme: prismThemes.vsDark,
        darkTheme: prismThemes.vsDark,
        additionalLanguages: ['bash', 'toml', 'json', 'ini', 'docker'],
      },
    }),
};

export default config;
