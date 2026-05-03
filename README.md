# Paste History

A native macOS menu bar app that records the last 20 clipboard items and lets you put any saved item back on the clipboard.

## Supported Clipboard Items

- Text, including multiline text
- Images, persisted as PNG files under Application Support
- Finder-copied files, videos, documents, and folders as file URLs

## Shortcut

The global shortcut defaults to `Command + Shift + V`.

Open `Settings...` from the menu bar item to remap it. Click the shortcut field, then press the new key combination.

## Build

```sh
swift build
```

## Build The App Bundle

```sh
scripts/build-app.sh
```

The app bundle is created at:

```text
build/Paste History.app
```

## Run

```sh
open "build/Paste History.app"
```

The app runs as an accessory app, so it appears only in the macOS menu bar.
