# Website

The documentation site for the dotfiles repo, built with
[Docusaurus](https://docusaurus.io/) and published at
<https://joestump.pages.stump.rocks/dotfiles/>.

## Local development

```bash
npm ci
npm start
```

This starts a local dev server and opens a browser window. Most changes are
reflected live without restarting.

## Build

```bash
npm run build
```

Generates static content into the `build/` directory.

## Deployment

Automated via Gitea Actions — `.gitea/workflows/pages.yml` builds and deploys
to Garage Pages (S3-backed) on every push to `main`. No manual deployment step.
