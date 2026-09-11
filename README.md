# CutQuay

CutQuay by Trieflow LLC provides local lossless video/audio segment editing, merge and audio extraction, with named export recipes and a JSON report for each run.

- Product: https://cutquay.trieflow.com
- Privacy: https://cutquay.trieflow.com/privacy
- Support: https://cutquay.trieflow.com/support

Based on LosslessCut v3.69.0 (`260603cad0180dc5d6c8eeebba1476b703703b6c`), © Mikael Finstad and contributors. CutQuay modifications and original icon © 2026 Trieflow LLC. GPL-2.0-only; see LICENSE and NOTICE. Complete corresponding source and build materials must accompany distribution.

In Export options, choose a recipe or name and save the current settings. Applying a recipe leaves the controls and keyframe/codec warnings open for review. Track selection remains explicit. Requested cutpoints are not a guarantee of frame-accurate output.

Exports write to unique staging files. With overwrite disabled, publication refuses an existing destination atomically. With overwrite enabled, a completed output replaces the destination. Failed/cancelled exports preserve sources and previous outputs. A skipped segment stops automatic merging. Reports distinguish created, skipped, deleted after merge, failed, cancelled and unattempted outputs; they include requested ranges, effective settings, command arguments, verified sizes and warnings. Reports contain local filenames and stay on your computer until you share them.

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
.\dist\win-unpacked\CutQuay.exe
```

The downloader verifies an exact dated FFmpeg archive and every bundled executable/DLL hash before copying files. Electron 42.11.3 is a patched supported branch, not the latest major; recheck support/security at release.

Store packaging additionally requires a reviewed JSON config containing Trieflow's own `appx.identityName`, `publisher`, `applicationId`, and `publisherDisplayName`. Set `CUTQUAY_STORE_CONFIG` and run `yarn pack-win-store`. No upstream Store/signing identity is supplied. `check-release-licenses` intentionally blocks until actual Windows media execution and complete corresponding-source evidence are recorded in `Release/ffmpeg-build.json`.

No Windows runtime, Store package validation, submission or release is claimed by this source build. Uncommon codecs, disk full, read-only/Unicode Windows paths, cancellation, large media and install/upgrade/uninstall are required Windows gates. The upstream Electron renderer still uses Node integration and @electron/remote; remote promotion, online map loading and upstream update services have been removed. A broader IPC migration is outside this change.

The public Windows qualification workflow invokes the committed Yarn4.11.0 file, builds a native application directory and exercises generated media. Downloadable CI artifacts contain metadata only until native corresponding-source clearance; no Store release is implied.
