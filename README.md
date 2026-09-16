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
| `lez-explorer-ui` | logos-blockchain |
| `lez-indexer-module` | logos-blockchain |
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
| `logos-json-rpc-bridge` | logos-co |
| `logos-libp2p-module` | logos-co |
| `logos-storage-module` | logos-co |
| `logos-storage-ui` | logos-co |
| `logos-wallet-module` | logos-co |
| `logos-wallet-ui` | logos-co |

## Runners and the Nix cache

Releases read the Logos Nix cache (`cache.nix.logos.co`) and push what they
build to it. This works because the repo is provisioned for the cache: it
has the `ATTIC_ENDPOINT` variable, the `ATTIC_TOKEN_CI` secret, and a
`public-cache` environment (branch `main`) holding `ATTIC_TOKEN_PUBLIC`.
Runs from `main` push to the public cache.

Every job runs on GitHub-hosted runners unless these repository variables
say otherwise:

- `RELEASE_BUILD_RUNNERS` moves the build legs, per variant.
- `RELEASE_RUNNER` moves every other job.

To put the builds on the enterprise self-hosted runners:

```bash
gh variable set RELEASE_BUILD_RUNNERS --repo logos-co/logos-modules-release --body '{"linux-amd64": ["self-hosted", "Linux", "X64"], "windows-x86_64": ["self-hosted", "Linux", "X64"], "darwin-arm64": ["self-hosted", "macOS", "ARM64"]}'
```

`linux-arm64` has no self-hosted runner and stays on `ubuntu-24.04-arm`.
The value format is described in the
[base repo's README](https://github.com/logos-co/logos-modules-release-base#runners-and-the-nix-cache).
