# Cliptern

Cliptern by Trieflow LLC provides local lossless video/audio segment editing, merge and audio extraction, with named export recipes and a JSON report for each run.

- Product: https://cliptern.trieflow.com
- Privacy: https://cliptern.trieflow.com/privacy
- Support: https://cliptern.trieflow.com/support

Based on LosslessCut v3.69.0 (`260603cad0180dc5d6c8eeebba1476b703703b6c`), © Mikael Finstad and contributors. Cliptern modifications and original icon © 2026 Trieflow LLC. GPL-2.0-only; see LICENSE and NOTICE. Complete corresponding source and build materials must accompany distribution.

In Export options, choose a recipe or name and save the current settings. Applying a recipe leaves the controls and keyframe/codec warnings open for review. Track selection remains explicit. Requested cutpoints are not a guarantee of frame-accurate output.

Exports write to unique staging files. With overwrite disabled, publication refuses an existing destination atomically. With overwrite enabled, a completed output replaces the destination. Failed/cancelled exports preserve sources and previous outputs. A skipped segment stops automatic merging. Reports distinguish created, skipped, deleted after merge, failed, cancelled and unattempted outputs; they include requested ranges, effective settings, command arguments, verified sizes and warnings. Reports contain local filenames and stay on your computer until you share them.

Cliptern 1.0.1 retains the established `CutQuay` user-data directory, Chromium
session directory, Windows application IDs, and `config.json` recipe/preferences
format. Explicit `--user-data-dir`, `--config-dir`, and portable neighboring
configuration continue to work. Existing `.llc` projects remain readable. New
local export reports use `.cliptern-report.json`; existing reports are unchanged.

## Build and verify

Use Node 22 or newer, Corepack and Yarn 4.11.0:

```sh
yarn install --immutable
yarn tsc
yarn lint
yarn test run
yarn build
yarn check-licenses
yarn generate-licenses
```

Run actual-media integration tests with `CUTQUAY_TEST_FFMPEG_DIR` pointing to a directory containing ffmpeg and ffprobe. The fixture creates its own H.264/PCM media. Without this variable the native media tests are explicitly skipped.

On Windows x64 with 7-Zip on PATH:

```powershell
yarn download-ffmpeg-win32-x64
$env:CUTQUAY_TEST_FFMPEG_DIR = (Resolve-Path ffmpeg/win32-x64/lib).Path
yarn test run
yarn pack-win-dir
.\dist\win-unpacked\Cliptern.exe
```

The downloader verifies an exact dated FFmpeg archive and every bundled executable/DLL hash before copying files. Electron 42.11.3 is a patched supported branch, not the latest major; recheck support/security at release.

The Windows workflow builds and qualifies both the disposable and assigned Store
identities through the same real import/trim/export/recipe/reopen workflow, exact
binary/module checks and owned normal close/uninstall. The assigned identity
remains `1659hashfunction.CutQuay`, publisher
`CN=B6A2631A-FD32-45CC-AE12-82466975F528`, application ID `CutQuay`; package
version is 1.0.1.0. Successful Store qualification then retains exactly
`Cliptern_1.0.1.0_x64.msix` and `release-ready.json` as unsigned upload inputs.
See `script/msix/STORE-UPLOAD.md` for current-source/runtime/consumer/source gates.
The legacy `pack-win-store` helper still requires a reviewed external config;
the supported qualification and unsigned upload path is the Windows workflow.

No Windows runtime, Store package validation, submission or release is claimed by this source build. Uncommon codecs, disk full, read-only/Unicode Windows paths, cancellation, large media and install/upgrade/uninstall are required Windows gates. The upstream Electron renderer still uses Node integration and @electron/remote; remote promotion, online map loading and upstream update services have been removed. A broader IPC migration is outside this change.

The workflow invokes committed Yarn 4.11.0. Exact native source manifests, archive
names and the previously published source release remain unchanged by branding.
Current source/download information is at https://cliptern.trieflow.com/source.
The screenshot workflow preserves its historical CutQuay package binding and
refuses capture until a newly qualified Cliptern package is reviewed and pinned.
A fresh renamed Windows run and actual screenshots remain required.
