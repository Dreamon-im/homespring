# iPhone Home Screen

## What it is

A Claude Code skill for organizing the home screen of an iPhone connected over USB or Wi-Fi: moving apps, creating folders, cleaning up offloaded apps, and backing up and restoring layouts.

It consists of a Swift CLI and a Claude Code skill, and does not include or call any other home-screen organizing implementation.

## Division of work

- **`skill/SKILL.md`**: the parts that need judgment. How to categorize, when to list candidates for the user to confirm first, and showing the user the diff before running anything.
- **`iconctl/` (Swift CLI)**: every deterministic operation. Reading and writing the phone, resolving IDs, generating plans, diffs, backups and validation.
- Transport: libimobiledevice, linked statically into release builds (`scripts/build-deps.sh`). Grid metrics are read, and layouts read and written, directly through SpringBoard's plist service.

## Goals

- One plan and one write, instead of running each move separately.
- Check whether the phone's state changed before writing, so manual changes made on the phone are never overwritten.
- Keep backups in a fixed location (`~/Library/Application Support/homespring/`) as plists that preserve the original field types.

## Target users

Myself: a phone with hundreds of apps, a home screen that needs regular tidying, and the wish to just ask Claude in natural language.

## Dependencies

- Running: macOS 13 or later, Apple silicon or Intel; nothing else to install
- Building: Xcode with Swift 6, `brew install pkgconf`; dev builds also use `brew install libimobiledevice`
- iPhone connected by USB, or with Wi-Fi sync turned on in Finder and on the same Wi-Fi as the Mac; unlocked, and trusting this Mac
