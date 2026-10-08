# DNSDeck website and documentation

This directory is the Mintlify site root. `index.mdx` is the product homepage;
the guides live under `docs/` and use Mintlify's native navigation and search.

From the repository root, with Node.js 24 or newer:

```sh
npm ci
npm run docs:dev
npm run docs:check
```

Preview the site at http://localhost:4187. `docs:check` checks shared-layout
drift, validates Mintlify pages, and checks internal links.
Mintlify's local search requires `mint login`; page navigation works without it.

## Site structure

- `site.json`: branding, navigation categories, header, footer, and redirects.
- `index.mdx`: product homepage, composed from Avgeek OSS Docs components.
- `docs/`: using the app, provider support, personal builds, and data privacy.
- `assets/`: DNSDeck artwork. Do not publish screenshots with real account data.
- `style.css`: product-specific logo sizing; shared layout stays in the kit.

The shared layout is pinned to a public source archive in `package.json`.
No registry token is required. After changing `site.json`, run
`npm run docs:sync`. Commit the generated `docs.json`, `oss-docs.css`,
`oss-docs.js`, `snippets/oss/`, and `.oss-docs.json`; do not edit them directly.
Mintlify hosting can use these checked-in files without installing npm packages.

Connect `avgeek-oss/dnsdeck` in Mintlify with `main` as the production branch
and `/docs` as the documentation directory. Configure `dnsdeck.app` as the
production domain when publishing; `site.json` already uses it as the canonical
origin. An App Store download link should only be added once the app is
available there.

[Repository](../README.md)
