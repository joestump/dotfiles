// @ts-check

/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  main: [
    'overview',
    {
      type: 'category',
      label: 'Install',
      collapsed: false,
      items: ['install/mothership', 'install/nodes'],
    },
    {
      type: 'category',
      label: 'Systems',
      collapsed: false,
      items: ['secrets', 'packages', 'terminal'],
    },
    {
      type: 'category',
      label: 'Zsh Plugins',
      collapsed: true,
      link: {type: 'doc', id: 'zsh-plugins/index'},
      items: [
        {
          type: 'category',
          label: 'Git & Forges',
          collapsed: true,
          items: ['zsh-plugins/git', 'zsh-plugins/git-auto-fetch', 'zsh-plugins/gh', 'zsh-plugins/shlink'],
        },
        {
          type: 'category',
          label: 'Containers & Cloud',
          collapsed: true,
          items: [
            'zsh-plugins/docker',
            'zsh-plugins/docker-compose',
            'zsh-plugins/aws',
            'zsh-plugins/terraform',
            'zsh-plugins/kubectl',
            'zsh-plugins/kubectx',
            'zsh-plugins/helm',
          ],
        },
        {
          type: 'category',
          label: 'Languages & Packages',
          collapsed: true,
          items: [
            'zsh-plugins/brew',
            'zsh-plugins/macos',
            'zsh-plugins/python',
            'zsh-plugins/pip',
            'zsh-plugins/virtualenv',
            'zsh-plugins/npm',
          ],
        },
        {
          type: 'category',
          label: 'Navigation & Files',
          collapsed: true,
          items: [
            'zsh-plugins/zoxide',
            'zsh-plugins/eza',
            'zsh-plugins/dirhistory',
            'zsh-plugins/copypath',
            'zsh-plugins/copyfile',
            'zsh-plugins/extract',
          ],
        },
        {
          type: 'category',
          label: 'History & Typing',
          collapsed: true,
          items: [
            'zsh-plugins/zsh-autosuggestions',
            'zsh-plugins/history-substring-search',
            'zsh-plugins/fzf',
            'zsh-plugins/sudo',
            'zsh-plugins/alias-finder',
            'zsh-plugins/zsh-ai',
          ],
        },
        {
          type: 'category',
          label: 'Data & Display',
          collapsed: true,
          items: [
            'zsh-plugins/jsontools',
            'zsh-plugins/urltools',
            'zsh-plugins/zsh-syntax-highlighting',
            'zsh-plugins/colored-man-pages',
            'zsh-plugins/colorize',
          ],
        },
      ],
    },
    {
      type: 'category',
      label: 'Claude',
      collapsed: false,
      link: {type: 'doc', id: 'claude/index'},
      items: ['claude/mcp', 'claude/plugins', 'claude/signal'],
    },
    'maintenance',
    'architecture',
  ],
};

export default sidebars;
