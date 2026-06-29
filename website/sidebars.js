// @ts-check

/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  main: [
    'overview',
    {
      type: 'category',
      label: 'Bootstrap',
      collapsed: false,
      items: ['bootstrap/mothership', 'bootstrap/nodes'],
    },
    {
      type: 'category',
      label: 'Systems',
      collapsed: false,
      items: ['secrets', 'packages', 'terminal'],
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
