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
      items: ['secrets', 'packages', 'claude', 'terminal'],
    },
    'maintenance',
    'architecture',
  ],
};

export default sidebars;
