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
| `logos-libp2p-module` | logos-co |
| `logos-storage-module` | logos-co |
| `logos-storage-ui` | logos-co |
| `logos-wallet-module` | logos-co |
| `logos-wallet-ui` | logos-co |

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