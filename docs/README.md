# Documentation

This directory is the root of the DNSDeck Mintlify site. Run from the repository
root:

```sh
npm ci
npm run docs:dev
npm run docs:check
```

The preview opens at http://localhost:4187. In Mintlify, connect
avgeek-oss/DNSDeck, use main as the production branch, and set the documentation
directory to /docs. No deployment service or database is needed for DNSDeck.

Keep this site focused on the native app: installation, building, provider
setup, and security. Update App Store availability when the restored app has
actually been approved and made available.
