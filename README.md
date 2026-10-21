# SufflixLinkr

A native macOS app for managing **default "Open with" associations** — which application
opens which file type. Instead of digging through Finder's *Get Info → Open with → Change All*
one extension at a time, SufflixLinkr gives you a single, searchable overview of every file
type on your Mac and lets you reassign handlers in bulk.

> **Requirements:** macOS 26 (Tahoe) or later, Apple Silicon.

## Features

- **File Types view** — browse ~250 known file types grouped into categories (Programming,
  Data / DevOps, Office & Docs, Images, Media, Archives, 3D / CAD, System, Other). Search by
  extension, UTI, or handler name. See and change the default app per type.
- **Applications view** — pick an app and toggle, in bulk, every file type it should own.
  Toggling a type off hands it to the next available handler.
- **New-app detection** — when you install a new app, SufflixLinkr notices the file types it
  can handle and offers to make it the default in one click.
- **Import / Export `.slinkr`** — save your handler setup to a portable `.slinkr` file and
  re-apply it later or on another Mac (double-click a `.slinkr` in Finder to import).

## Download & install

1. Grab the latest `SufflixLinkr-x.y.zip` from the [Releases](../../releases) page and unzip it.
2. Move `SufflixLinkr.app` to `/Applications`.
3. **First launch:** the app is ad-hoc signed (not notarized), so macOS Gatekeeper will block a
   normal double-click. Instead **right-click the app → Open**, then confirm **Open** in the
   dialog. You only need to do this once.

   If it's already quarantined, you can also clear it from Terminal:
   ```sh
   xattr -dr com.apple.quarantine /Applications/SufflixLinkr.app
   ```

## Build from source

```sh
git clone https://github.com/ProfessorEngineergit/SufflixLinkr.git
cd SufflixLinkr
open SufflixLinkr.xcodeproj   # then Product ▸ Run in Xcode 26+
```

Or from the command line:

```sh
xcodebuild -project SufflixLinkr.xcodeproj -scheme SufflixLinkr -configuration Release build
```

## How it works

SufflixLinkr is a SwiftUI app built directly on the LaunchServices C API
(`LSCopyDefaultRoleHandlerForContentType` / `LSSetDefaultRoleHandlerForContentType`) to read
and set default handlers, and on Spotlight (`NSMetadataQuery`) to discover installed apps.

Because changing system-wide file associations requires access outside a sandbox container,
the app runs **without the App Sandbox** (Hardened Runtime stays on). It never phones home and
stores no data beyond the `.slinkr` files you export yourself.

### The `.slinkr` format

A `.slinkr` file is a small, human-readable CSV of your **user overrides** only:

```
# SufflixLinkrExportVersion: 1
# ExportDate: 2026-07-02T…
uti,extensions,category,bundleIdentifier,appNameHint,userOverride
public.python-script,py,Programming,com.microsoft.VSCode,Visual Studio Code,true
```

On import, each row's `bundleIdentifier` is resolved to the installed app and set as the default
handler for that UTI. Rows whose app isn't installed are reported as skipped.

## License

[MIT](LICENSE) © 2026 Bahrian Novotny

## Development and AI assistance

The default-branch history includes contributions explicitly attributed to Claude ([example](https://github.com/ProfessorEngineergit/SufflixLinkr/commit/8dec0f711745deac2f8ecf2bc31c3a04dffda1d5)). This documents AI involvement in those contributions; it does not establish the origin of every line or independent validation. Existing author, co-author and session records are retained.
