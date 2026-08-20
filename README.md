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
| `logos-chat-ui` | logos-co |
| `logos-delivery-demo` | logos-co |
| `logos-delivery-module` | logos-co |
| `logos-libp2p-module` | logos-co |
| `logos-lez-rln-module` | logos-co |
| `logos-rln-module` | logos-co |

### Logos Storage

| Module | Source |
|---|---|
| `logos-storage-module` | logos-co |
| `logos-storage-ui` | logos-co |
| `logos-wallet-module` | logos-co |
| `logos-wallet-ui` | logos-co |

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
