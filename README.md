# logos-modules-release

Canonical Logos module catalog. Hosts the official curated set of Logos
modules as submodules and publishes them via the
[`logos-modules-release-action`](https://github.com/logos-co/logos-modules-release-action)
reusable workflows.

This repo replaces the legacy `logos-modules` (single-bundle releases)
with one GitHub release per module-version. Clients (`lgpd`, the Logos
`package_downloader` module, the package-manager UI) discover the repo
by fetching `logos-repo.json` from the default branch root.

## Module set

| Module | Source |
|---|---|
| `logos-accounts-module` | logos-co |
| `logos-accounts-ui` | logos-co |
| `logos-blockchain-module` | logos-blockchain |
| `logos-blockchain-ui` | logos-blockchain |
| `logos-chat-module` | logos-co |
| `logos-chat-module-mix` | logos-co (`feat/logos-testnetv02-mix`) |
| `logos-chat-ui` | logos-co |
| `logos-chat-ui-mix` | logos-co (`feat/logos-testnetv02-mix`) |
| `logos-delivery-module` | logos-co |
| `logos-execution-zone-module` | logos-blockchain |
| `logos-execution-zone-wallet-ui` | logos-blockchain |
| `logos-libp2p-module` | logos-co |
| `logos-storage-module` | logos-co |
| `logos-storage-ui` | logos-co |
| `logos-wallet-module` | logos-co |
| `logos-wallet-ui` | logos-co |
