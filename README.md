# Disk Map

A small Mac app that shows what's filling up your disk, in the spirit of WizTree.

It scans a drive or folder and draws every folder as a box sized by how much space it takes up. Click a box to zoom in, right-click it to show it in Finder, Quick Look it, or get rid of it.

## Status

Early days, but it works. Download the latest `.dmg` from [Releases](https://github.com/LBSiUK/DiskMap/releases), open it and drag Disk Map into Applications. The app checks for new versions when it opens and can update itself (you can turn this off in Settings).

The design is written up in [`docs/design.md`](docs/design.md).

## Building it yourself

```
brew install xcodegen
./build.sh
```

That builds the app and copies it to `/Applications`. To sign it with your own certificate, see the note at the top of `Config/Base.xcconfig`.

## Requirements

- macOS 26 or later
- Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you want to build it yourself

## A note on permissions

macOS hides some folders from apps unless they have Full Disk Access. Disk Map works without it, but the numbers will be more complete if you turn it on in System Settings → Privacy & Security → Full Disk Access.

## Credits

Copyright © 2026 LBSi UK / Leon Brahams

https://github.com/LBSiUK/DiskMap
