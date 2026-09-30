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

### Logos Blockchain

| Module | Source |
|---|---|
| `lez-explorer-ui` | logos-blockchain |
| `lez-indexer-module` | logos-blockchain |
| `logos-amm-module` | logos-blockchain |
| `logos-amm-ui-module` | logos-blockchain |
| `logos-blockchain-module` | logos-blockchain |
| `logos-blockchain-ui` | logos-blockchain |
| `logos-execution-zone-module` | logos-blockchain |
| `logos-execution-zone-wallet-ui` | logos-blockchain |

### Logos Messaging

| Module | Source |
|---|---|
| `logos-chat-module` | logos-co |
| `logos-chat-module-mix` | logos-co (`feat/logos-testnetv02-mix`) |
| `logos-chat-ui` | logos-co |
| `logos-chat-ui-mix` | logos-co (`feat/logos-testnetv02-mix`) |
| `logos-delivery-demo` | logos-co |
| `logos-delivery-module` | logos-co |
| `logos-libp2p-module` | logos-co |

### Logos Storage

| Module | Source |
|---|---|
| `logos-storage-module` | logos-co |
| `logos-storage-ui` | logos-co |

### EVM Wallet

| Module | Source |
|---|---|
| `logos-eth-rpc-ui` | logos-co |
| `logos-eth-wallet-backend` | logos-co |
| `logos-eth-wallet-ui` | logos-co |
| `logos-evm-assets-module` | logos-co |
| `logos-evm-eth-rpc-module` | logos-co |
| `logos-evm-fee-module` | logos-co |
| `logos-evm-keystore-cli` | logos-co |
| `logos-evm-keystore-module` | logos-co |
| `logos-evm-keystore-ui` | logos-co |
| `logos-evm-signer-cli` | logos-co |
| `logos-evm-signer-ui` | logos-co |
| `logos-evm-token-list-module` | logos-co |
| `logos-evm-tx-sender-module` | logos-co |
| `logos-evm-uniswap-module` | logos-co |
| `logos-token-list-ui` | logos-co |
| `logos-uniswap-backend` | logos-co |
| `logos-uniswap-ui` | logos-co |
| `logos-verified-proxy-module` | logos-co |
| `logos-verified-proxy-ui` | logos-co |

### Monero Wallet

| Module | Source |
|---|---|
| `logos-monero-node-module` | logos-co |
| `logos-monero-wallet-backend` | logos-co |
| `logos-monero-wallet-cli` | logos-co |
| `logos-monero-wallet-core-module` | logos-co |
| `logos-monero-wallet-ui` | logos-co |
| `logos-monerod-module` | logos-co |
| `logos-monerod-ui` | logos-co |

### Others

| Module | Source |
|---|---|
| `logos-accounts-ui` | logos-co |
| `logos-json-rpc-bridge` | logos-co |
| `openmetrics-module` | logos-co |

## Releasing a module

Open a PR to `master` that bumps your submodule commit **and** the version
in your module's `metadata.json`, then merge it. That's the whole procedure,
 there is no button to press and no tag to push.

On every merge to `master` the Jenkins release pipeline:

1. Compares each module's `metadata.json` version against the published
   GitHub releases and picks up whatever isn't released yet. It does not
   diff which submodules changed, so **the `metadata.json` version bump is
   the release trigger**. Bumping the submodule commit alone releases
   nothing (which also means you can merge submodule updates without
   releasing, by holding the version bump).
2. Builds the module on `linux-amd64`, `linux-arm64` and `darwin-arm64`
   (`nix build .#lgx-portable` per platform).
3. Merges the per-platform packages into a single `.lgx` and signs it with
   the official Logos release key.
4. Publishes the `<name>-v<version>` GitHub release with two assets: the
   signed `.lgx` and a `sidecar.json` describing it.

The catalog index then updates itself: the `rebuild-index.yml` workflow
rebuilds `index.json` from all published releases whenever a release is
published, and on a 6-hourly schedule as a catch-up. Within a few minutes
of the merge the new version is visible in Basecamp.

Published versions are **immutable**: the pipeline skips anything already
fully released, so changing a module's content without bumping its version
ships nothing.

## Unpublishing a module or version

Removal stays on GitHub Actions: run the **Unpublish module / version**
workflow from the Actions tab. It deletes the matching release(s) and
optionally their git tags, then rebuilds the index so clients stop being
offered the removed package(s). Always run it once with `dry_run: true`
first to see exactly what matches. The rolling `index` release itself is
guarded against deletion.

**Unpublishing alone is not permanent.** The Jenkins pipeline re-publishes
any version that `metadata.json` still declares so on the next merge to
`master` it will rebuild, re-sign and re-release what you just removed.
Pair every unpublish with a PR that bumps (or removes) the module's
`metadata.json` version.

## Official Logos signing key

Modules published by Logos from this repository are signed with the
following Ed25519 key. A valid signature from this key means the
package was built and published by the Logos release pipeline.

**Publisher DID:** `did:jwk:eyJjcnYiOiJFZDI1NTE5Iiwia3R5IjoiT0tQIiwieCI6IlpUdEIzaU9FYVZDWFVLUWw0Sm9sR3V1MkhMb19iOUhSQ2V2RjRINm81aUkifQ`

**Public key :** `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGU7Qd4jhGlQl1CkJeCaJRrrthy6P2/R0QnrxeB+qOYi logos-release`

### Verifying a package

```sh
lgx verify <package>.lgx
```

`lgx verify` prints the signer DID; confirm it matches the DID above.
Packages from this catalog signed by any other DID, or unsigned, were
not published by Logos.

The private key is held offline and in the Logos release
infrastructure only. If this key is ever rotated, this section and
all current package versions will be updated in the same change.
