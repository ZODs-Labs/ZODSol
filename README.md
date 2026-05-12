# ZODSol

Lightweight, fast and secure Solana wallet bar for macOS.

> [!IMPORTANT]
> **Coming soon.** ZODSol is in active development and not yet ready for general use. Public builds, signed releases and full docs will land here once the first milestone ships.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 6.2 toolchain (to build from source)
- A [Helius](https://helius.dev) API key

## Build from source

```bash
swift build
./Scripts/run.sh
```

## Local Signing

For repeated local or Homebrew-style builds, create a stable local code-signing
identity once:

```bash
make setup-signing
```

Then package normally:

```bash
make package
```

Using the same local signing identity keeps macOS Keychain trust stable across
rebuilds, so API keys and wallet credentials do not need to be re-entered after
every package build. Without this setup, packaging falls back to ad-hoc signing,
which can make each build look like a different app to Keychain.

## Xcode Run

The auto-generated SwiftPM `ZODSol` scheme launches an unsigned command-line
binary, which is the wrong context for credentialed app testing. The
`ZODSol Signed App` scheme does the right thing: each Run quits any live
ZODSol, packages a debug `ZODSol.app`, signs it with the stable local
identity, and launches the signed bundle so Keychain items persist across
rebuilds.

One command bootstraps everything (signing identity, scheme generation, and
opens Xcode):

```bash
make xcode
```

Select `ZODSol Signed App` from the scheme picker, then press Run (`⌘R`).

If you move the repo to a different path on disk, re-run `make setup-xcode`
to regenerate the scheme's absolute paths.

Pre-action output (signing, packaging, codesign verification) is mirrored to
`.build/xcode-preaction.log`. If Run fails with a generic Xcode error, run
`tail -n 80 .build/xcode-preaction.log` to see the real cause.
