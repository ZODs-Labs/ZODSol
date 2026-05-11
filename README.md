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

The generated SwiftPM `ZODSol` scheme runs an unsigned command-line product, so
it is not the right path for credentialed app testing. Create the local signed
app scheme once:

```bash
make setup-xcode
```

Then open `Package.swift` in Xcode, select `ZODSol Signed App`, and press Run.
That scheme packages a debug `ZODSol.app`, signs it with the stable local
identity, and launches the signed bundle so Keychain items persist across
rebuilds.
