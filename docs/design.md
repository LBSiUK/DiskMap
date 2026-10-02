# Design

## Features

- Native Liquid Glass design
- Treemap of any drive or folder
- Fast background scanning
- Size list sorted biggest first
- Show in Finder, Quick Look and Copy Path
- Move to Trash or delete permanently
- Saves your last scan
- Checks for updates and installs them for you

## What it does

Disk Map is a native macOS file storage overview application that lets you clean up from the same window. It scans a drive or folder and shows it as a treemap, where every folder is a box sized by how much space it uses, and you can zoom into any folder.

## How it works

- **Scanning** runs in the background so the window never freezes. It stays on one drive, doesn't follow shortcuts, counts hard-linked files once, and skips folders it isn't allowed to read instead of getting stuck.
- **Memory** stays low by keeping every folder but only listing files over 1 MB on their own. Smaller files in each folder are grouped into one box.
- **The treemap** shows a few levels at once and is drawn in one go, so it stays smooth even with tens of thousands of boxes.
- **The last scan** is saved, so the app opens straight to your previous results.

## The window

- A sidebar with your main drive, your home folder and any folder you pick.
- The treemap in the middle, with Back, Up and the current path in the toolbar.
- A list on the right showing what's in the current folder, biggest first.
- A bar showing used and free space.

## Actions

Right-click any box or list item to:

- Show it in Finder
- Quick Look it (or press Space)
- Copy its path
- Move it to the Trash
- Delete it permanently

Both deleting options ask first, and permanent delete makes it clear it can't be undone. The app won't let you remove the drive itself, system folders or your home folder. After you delete something the map updates straight away without a rescan.

## Updates

When the app opens it asks GitHub for the latest release. If there's a newer version, a banner offers to install it: the app downloads the DMG, checks it's really Disk Map, swaps itself in and reopens. You can turn the check off in Settings, or check by hand from the Disk Map menu.

## Permissions

The app works without Full Disk Access, but macOS hides some folders. If access is missing, a banner explains this and opens the right page in System Settings.

## Requirements

- macOS 26 or later
- Not sandboxed, as it needs to read the whole drive and delete files

## Not yet

- Notarised builds
- Menu bar item
- Search
