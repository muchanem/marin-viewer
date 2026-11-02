# Build system

No Xcode project, no `xcodebuild`, no XcodeGen. `swift build` compiles; a shell
script bundles and signs; `make` orchestrates. Xcode is only a toolchain
provider (`swift`, `codesign`, `notarytool`, `stapler`).

Bundled builds explicitly select SwiftPM's `swiftbuild` backend for both the
compile and `--show-bin-path` calls. This matches the successful Swift 6.4 build
on ELSTON and also works with Swift 6.3.3. The older toolchain defaults to the
native backend, which emits flat resource bundles and a `Bundle.module`
accessor that does not search an app's `Contents/Resources`; the packaging
script requires the macOS bundles and app-aware accessor emitted by Swift Build.
Compile-only checks and tests can still use the toolchain's default backend.

## The pieces

- **`Package.swift`** — one `executableTarget` (`Radiology`) + one `testTarget`.
  Swift 6 language mode, Swift 6.2+ tools. It depends on the Tree-sitter C
  runtime, the official Swift wrapper, and eight grammars (Swift, Rust, Go,
  Python, JavaScript, TypeScript, TSX, Kotlin); `Package.resolved` pins the
  graph, and the grammar packages are pinned to exact versions.
  A small `GrammarScanners` C target carries the two external scanners whose
  upstream manifests fail to compile them — see
  `Sources/GrammarScanners/PROVENANCE.md`.
  Tree-sitter queries ship as SwiftPM resources of the `Radiology` target
  (`Sources/Radiology/Queries`), loaded through `Bundle.module`. `build.sh`
  copies every `*.bundle` from the build directory into
  `Contents/Resources` and then fails the build if the query resources are
  missing, because without them every file would silently fall back to plain
  text. `Radiology --verify-resources` re-checks the assembled app from a
  minimal environment.
  `Sources/Radiology/IndexingScripts` also ships in that resource bundle:
  Kotlin's Gradle attachment, runner, and managed-tool installer. Packaged
  verification checks all three scripts as well as the eight grammars.
  Compiler tools are installed separately under Application Support.
  See plans/kotlin-semantic-indexing.md.
- **`build.sh`** — `swift build` → assemble `build/Marin Viewer.app` (Info.plist
  with `__SHORT_VERSION__`/`__BUILD_VERSION__` substituted, `PkgInfo`, any
  dependency `*.bundle`s copied into `Contents/Resources`, the icon) → codesign.
  Falls back to ad-hoc signing (`-`) when no real identity is available, so
  `make run` always works on a bare machine.
- **`Makefile`** — the front door. `make help` lists everything.
- **`Resources/Info.plist`** — bundle metadata. Version strings are
  placeholders filled at build time. It is the one place that names the
  bundle: `CFBundleName` gives `build/Marin Viewer.app` and `CFBundleExecutable`
  gives `Contents/MacOS/Marin Viewer`, and `build.sh` reads both from it. The
  SwiftPM target, module and product stay `Radiology` (see "App identity" below).
- **`Resources/marin-viewer-logo.svg`** — the supplied logo, and the app icon's
  source. The logo is a circle, which macOS 26 and later shrink onto a grey
  squircle plate, so `scripts/make-icon.swift` lays it out on Apple's 1024-point
  icon grid: an 824-point continuous-corner squircle with a cream rim in place
  of the ring, the disc's dark blue as its face, and the boat inside, with the
  standard drop shadow. `rsvg-convert` (Homebrew `librsvg`; `make deps` checks
  for it) renders the logo afresh at each of the ten sizes; NSImage is not used
  because CoreSVG drops the logo's glow filter. `iconutil` packages the PNGs as
  `build/AppIcon.icns`, which `build.sh` copies into
  `Contents/Resources/AppIcon.icns`. Both the SVG and the script are Make
  dependencies, so changing either regenerates the icon on the next build.
  Upstream's `RADIO.png` stays in the tree, unused, to keep merges small.
- **`Radiology/Radiology.entitlements`** — empty entitlements for the local build. App Sandbox is off because the product launches Git and ripgrep to read selected repositories. An App Store sandbox/distribution strategy is not implemented.

## Permissions & capabilities

OS capabilities work in this no-Xcode, ad-hoc-signed bundle — you just have to
add the keys by hand, because there's no Xcode "Signing & Capabilities" tab
doing it for you:

- **Usage prompts** need the matching `NS…UsageDescription` string in
  `Resources/Info.plist`. CoreLocation, for example, prompts and returns a fix
  with `NSLocationUsageDescription` (+ `NSLocationWhenInUseUsageDescription`)
  present — ad-hoc signing and the hand-assembled `.app` are not a barrier.
- **The sandbox decides the entitlement.** With the App Sandbox **off**, a
  usage-description string is enough. With it **on**, also add the matching
  `com.apple.security.*` entitlement (e.g.
  `com.apple.security.personal-information.location`).
- **Always design the denied path.** A permission the user declines should
  route to a sensible default, not a dead feature — e.g. a one-shot location
  request that yields `nil` falls back to a configured location.

## App identity

The app a user sees is **Marin Viewer**: `build/Marin Viewer.app`, executable
`Contents/MacOS/Marin Viewer` (what Activity Monitor and `pgrep` show), the
app menu (About, Hide and Quit Marin Viewer), the About panel, the reader
window's title when no repository is attached, the Help text, and the
messages that name the app (search without ripgrep, indexer installation).
The icon comes from `Resources/marin-viewer-logo.svg` (see above).

`Radiology` stays where only developers see it, so merges from tqbf/radiology
stay small: the SwiftPM package, target, module and product
(`Sources/Radiology`, `Tests/RadiologyTests`, `RadiologyApp`, the
`Radiology_Radiology.bundle` resource bundle), `Radiology/Radiology.entitlements`,
the `RadiologyRipgrepPath` Info.plist key, code comments that credit upstream's
reader, the indexing scripts' `radiology.*` Gradle properties and scratch file
names, and the on-disk state directories below.

The bundle id is **`com.muchanem.marin-viewer`** (was `org.sockpuppet.radiology`),
so the fork never shares preferences, LaunchServices registration or privacy
grants with a real Radiology install. What is keyed by what:

| State | Keyed by | Where |
|---|---|---|
| Window frame, sidebar split widths, last session, recent repositories, Hide Tests, Source Files Only, bookmarks, code paths, indexing personality choice, Context pane layout, open-panel state | bundle id | `UserDefaults.standard` → `~/Library/Preferences/com.muchanem.marin-viewer.plist` |
| Code windows' readers | fixed suite | `org.marin.viewer.code-windows` |
| Index cache, PR worktrees | app name, literal path | `~/Library/Caches/Radiology/repositories` |
| Managed indexer tools, indexing personalities, criticality overrides | app name, literal path | `~/Library/Application Support/Radiology/{tools,IndexingPersonalities,overrides}` |
| Viewer state, wordbase | `--viewer-*` arguments | the repository checkout |

The literal `Radiology/` paths are kept on purpose: they hold 100 MB of index
cache and installed indexers that would otherwise be rebuilt, and the code is
upstream's. A real Radiology install would share them; its formats are the
same code. The app is not sandboxed, so there is no container keyed by the id.

Changing the id dropped what the old id's defaults held: the window frame,
sidebar widths, the last session and the recent repositories list (plus any
bookmarks, code paths or filter toggles, which were unset on Mark's machine).
The app starts cleanly without them. To carry them over, quit the app and run
`defaults export org.sockpuppet.radiology - | defaults import com.muchanem.marin-viewer -`.

Icon Composer's `.icon` format also builds from the command line with Xcode
27.2 (`xcrun actool --app-icon AppIcon --compile <dir> … AppIcon.icon` writes
`Assets.car`, a fallback `AppIcon.icns` and `CFBundleIconName`, after
`xcodebuild -runFirstLaunch`). It is not used yet: actool rasterises SVG layers
with CoreSVG, which drops the logo's glow, so the layers would have to be
pre-rendered PNGs or the glow redrawn with Icon Composer's own effects. The
`.icns` is accepted by macOS 27 as a full squircle (no grey plate).

## Everyday targets

| Target        | What it does                                              |
|---------------|----------------------------------------------------------|
| `make check`  | `swift build` only — fast compile gate for CI/agents      |
| `make test`   | `swift test` (swift-testing)                              |
| `make run`    | build the `.app`, ad-hoc sign, `open` it                 |
| `make` / build| `build/Marin Viewer.app` (debug)                              |
| `make icon`   | regenerate `build/AppIcon.icns` from the logo SVG         |
| `make clean`  | remove `build/ .build/ dist/`                            |

## Versioning

`make` resolves the version in this order: a `VERSION=` override → an exact
`vX.Y.Z` git tag at HEAD → the `VERSION` file. `make print-version` shows what
resolved and from where.

## Release pipeline (`make dist`)

Requires an exact `vX.Y.Z` tag at HEAD and a Developer ID signing identity.
The chain is deliberately ordered:

```
clean → release → sign → zip-notary → notarize → staple → zip-release → checksum → verify-release
```

The two-zip dance is intentional: Apple's notary service takes a zip; stapling
writes the ticket back into the `.app`; the zip you actually ship must be made
**after** stapling. One-time credential setup:

```sh
make notary-setup TEAM_ID=XXXXXXXXXX APPLE_ID=you@example.com
```

`make github-release` uploads the release zip + `.sha256` to a GitHub release.

## CI gate

The minimum a change must pass: `make check && make test`. The minimum a *UI*
change must pass: also `make run` and look at it — see `SWIFTUI-RULES.md` §9.

## External tools and Finder launch

Git is located through PATH and standard macOS locations. ripgrep is located through PATH, Homebrew/cargo locations, or the build-time installation recorded by `build.sh` in the built Info.plist's RadiologyRipgrepPath key. That key is a local-build convenience; rebuilding on another machine records its local installation. Missing ripgrep only disables text search. No shell expands user queries or filenames.

The workspace was originally copied with invalid `.build` entries and missing script executable bits. The old generated cache was moved to `/tmp/radiology-template-build-20261002`, a fresh build cache was created, and build/rename scripts were made executable. The root initially had no Git history; after the documentation handoff, the user authorized initializing Git and publishing to [tqbf/radiology](https://github.com/tqbf/radiology). The inherited local nested repo copy is not the active build root and is excluded from version control.
