# Cliptern MSIX identity and installation qualification

Implements `docs/plans/cutquay-msix-qualification.md` in the parent project, extending approved Task 4. Product baseline: `c7998d88706cd6cf1bcbbdd4d79f67ca528b46d5`. This changes packaging/qualification only; it does not open the existing production Store license gate or change dependencies.

## Explicit Store identity mode

`script/qualifyWindowsMsix.ps1` defaults to `-IdentityMode qualification`. The
additional `-IdentityMode store` selects only the reserved identity
`1659hashfunction.CutQuay`, publisher
`CN=B6A2631A-FD32-45CC-AE12-82466975F528`, and PublisherDisplayName `hashfunction`.
Both modes use version `1.0.1.0`, x64, application ID `CutQuay`, executable
`Cliptern.exe`, and Windows.Desktop. Arbitrary identities and mode spellings are
rejected. The Python builder exposes the same selection as `--identity-mode`;
manifest, container and unpacked verification all require the explicit mode.

The installer independently checks its fixed identity tuple against both the
typed package record and the actual unsigned manifest before signing. The record
source must match the current Windows run. A preexisting registration with the
selected package name, at any version or architecture, prevents installation.
The temporary certificate uses the selected publisher but confers no production
signing or submission approval. Exact package/process ownership, installed media,
the real import/trim/recipe/export/reopen workflow, normal close and uninstall
remain mandatory in both modes.

Windows runs Store identity qualification only after the disposable identity
step succeeds. Store metadata is separate: `msix-store-package-record.json` and
`msix-store-install/` under `build-evidence`. The unsigned Store-mode output is
named `Cliptern.Store_1.0.1.0_x64.msix` and remains in the runner's temporary tree.
The current Store-upload gate in `STORE-UPLOAD.md` retains exactly the verified
unsigned Cliptern package and readiness receipt after all checks pass. Signed
copies, media and certificates are excluded; qualification artifacts contain
metadata/screenshots only.

Package records state `identityMode`, `qualificationIdentityOnly`, and
`storeIdentityUsed`. Installer evidence states the selected `identity_mode` and
sets `store_identity_used` only after the exact Store registration is owned.
`publicRelease`/`public_release` and license-clearance flags remain false even
when Store identity qualification passes. Dependency corresponding-source
obligations, WACK, upgrade and Store submission remain separate gates.

## Exact scope and inputs

- Fixed disposable identity: `Trieflow.CutQuay.Qualification`, publisher `CN=CutQuay-CI-Qualification`, version `1.0.1.0`, x64, AUMID application `CutQuay`, root executable `Cliptern.exe`. Exactly one full-trust application and `runFullTrust`; no protocols, associations or COM declarations.
- Existing native build runs first, with immutable Yarn 4.11.0, Electron 42.11.3 and electron-builder 26.15.3 from the unchanged lock. The baseline startup receipt binds source SHA, executable SHA, exact unpacked title and generated dependency-notice SHA. Its source must be clean before building.
- `prepare-electron-input.cjs` uses the locked `@electron/get` and official version-specific Electron release/checksum URLs. It independently verifies the retained ZIP against that release's exact checksum. This is an exact version plus upstream checksum acquisition, not a hard-coded archive digest; the actual digest, checksum-file digest, URL and all runtime file hashes become immutable package evidence. No mirror can evade the official checksum comparison.
- `inspect-asar.cjs` uses locked `@electron/asar` to inspect the actual archive without executing app code. It rejects links/unsafe entries, verifies application metadata, entry/renderer bytes and six embedded notices against build/source inputs, records every ASAR entry and unpacked file, and regenerates the original SVG with the actual Sharp settings to verify the provided PNG.
- The complete `dist/win-unpacked` file set is inventoried. Electron archive members must match exactly, except the documented builder transformations: renamed/resource-edited `electron.exe` becomes the separately native-startup-bound `Cliptern.exe`; `LICENSE` becomes `LICENSE.electron.txt`; `version` and `resources/default_app.asar` are builder-removed. All Electron runtime DLL/data/locale/notice bytes are checked against the exact archive.
- The verifier requires the exact approved set of nine `bin/` media paths independently of the pin. All nine selected `Release/ffmpeg-build.json` FFmpeg/FFprobe/native DLL rows, their sizes/hashes, external FFmpeg notice and complete application locale tree must match. Any other staged file is rejected, including an unlisted native executable. ASAR contents/dependencies remain bound by the actual archive and source/lock hashes; this is not a corresponding-source license audit.
- `licenses.txt` is deliberately generated by the existing native build. If generation changes that tracked file, it is the only permitted dirty path and must equal the same-source native receipt. Every other source change is rejected. Its actual generated bytes and SHA are recorded inside the package's application input evidence.

## Packaging and installation gates

`msix_qualification.py` stages only into new directories and revalidates release/source/artwork inputs after copying. It rejects links/reparse points, unsafe Windows names, case/Unicode/file-directory aliases, changed/missing inputs and unexpected files. Manifest and artwork are qualification-owned; semantic XML validation verifies the exact identity/capabilities/resources/application.

Only SDK `10.0.26100.0/x64/MakeAppx.exe` is accepted. Its bytes are recorded/rechecked around semantic `pack /v /h SHA256` and `unpack /v`; `/nv` and replacement are not used. Independent ZIP validation decodes OPC URI names exactly once, rejects malformed UTF-8/percent sequences, escaped hierarchy separators and decoded aliases/unsafe paths, then checks every payload hash and manifest semantics. SDK-unpacked payloads and final copied unsigned MSIX hashes are independently compared.

The installer refuses an existing matching registration. It signs a separate temporary copy with an ephemeral nonexportable CurrentUser My private key, trusts only its public certificate in LocalMachine TrustedPeople, verifies the exact signature/SDK tool bytes, and retains the unchanged unsigned hash. It verifies exact installed publisher/version/architecture and every installed payload byte.

Installed startup uses the package-family AUMID through `IApplicationActivationManager`. The broker PID must report the exact package full name through the actual two-call `GetPackageFullName` API and load the exact installed main executable. Main and discovered Electron child processes are bound to retained process handles, installed executable path, actual package identity and creation time after this install; no name-only cleanup is allowed. Loaded modules for the retained live Electron processes must come from verified package payloads or Windows. Discovery is a bounded snapshot, not a claim of exhaustive tracing of every transient process/module.

The exact installed title is **Cliptern**, while unpacked title is **Cliptern 1.0.1**. Existing `src/renderer/src/util.ts` uses the app name without a version when `process.windowsStore` is true; Electron documents that it is true for **any MSIX package** ([Electron process documentation](https://www.electronjs.org/docs/latest/api/process)). The prior unpacked run `34576772812` does not establish an installed title or package identity.

A direct installed diagnostic startup captures stderr, checks actual package identity, rejects fatal/JavaScript error diagnostics, and closes normally before broker startup. Broker startup checks visible UI bounds, accessible elements/controls where exposed, error surfaces, a mandatory screenshot and stable main window. Missing accessible controls are explicitly `startup_limited`; no workflow or accessibility acceptance is inferred. Installed `resources/ffmpeg.exe` and `resources/ffprobe.exe` each run `-version` and `-buildconf`, with bounded waits, before/after executable hashes and exact pinned version/configuration comparisons. Version invocations do not establish media workflows.

Normal close requires main and retained children to exit; uninstall must remove the exact captured registration. Ownership is established only after our Add-AppxPackage returns successfully and one registration with the exact expected identity and architecture is observed. Both normal uninstall and failure cleanup use only its captured PackageFullName. After a failed/partial Add or ambiguous observation, residual registrations are preserved and reported as a cleanup failure. Evidence retains the preflight full names, Add completion, ownership marker, captured full name and remaining full names. All process/package/trust/private-key/temp-copy cleanup operations run independently. Native stdout is sent to the host log, keeping exactly one structured result. Primary, all cleanup and final unsigned-hash errors survive in exclusive-write JSON; missing/changed unsigned bytes fail qualification. If JSON cannot be written, the combined original errors are included in the thrown failure and previous bytes are preserved.

## Local evidence (macOS, no desktop/UI use)

Executed against this implementation on 2026-09-11:

- `python3 script/msix/test_msix_qualification.py`: **31 tests, 30 passed, 1 Windows-only junction skip**. Real temporary ASAR/ZIP/XML/PNG/files and a real temporary Git checkout; checksum/runtime/media/notice/source/artwork mutation, input replacement during copy, source SHA/notice-receipt binding, unsafe/OPC/alias names, SDK adapter command semantics, unpacked hash failures and no-overwrite output checks. Initial tests failed against the unadapted reference (wrong identity/executable and missing Cut runtime boundary).
- PowerShell **7.6.6**, run through the absolute FileQuay `.tools/powershell-7.6.6/pwsh`, `-NoLogo -NoProfile -File script/msix/test_qualify_msix_install.ps1`: core success/failure/cleanup/preflight scenarios, noisy native outputs, path-boundary checks, exclusive JSON writing, and actual activation/GetPackageFullName interop type compilation. Removing `Out-Host` in a temporary copy made the noisy-output regression fail; actual helper passes.
- Same host, `script/msix/test_registration_ownership.ps1`: **nine real Install/normal-Uninstall/cleanup/evidence flow scenarios pass**, replacing only Appx commands and unrelated OS operations. A registration with the exact expected x64 identity appearing during failed Add is preserved; ambiguous/wrong-architecture/unobservable post-Add registration is preserved; exact-owned normal/failure cleanup, foreign residue and failed removal are checked.
- Same host, `script/msix/test_msix_evidence.ps1`: **five actual outer-reporting scenarios pass**, including missing/changed unsigned package, changed package after otherwise successful core, unchanged success and exclusive-write failure preserving prior bytes and original errors. Only Windows operations are substituted.
- Same host, `script/msix/test_installed_media.ps1`: **four actual native FFmpeg/FFprobe calls pass**, then a mismatched configuration and changed expected executable hash are rejected. Uses owned copies of local **FFmpeg 9.0.1** on macOS; Windows CI uses the existing pinned Windows binaries. This validates the process/API boundary, not MSIX install or the pinned Windows runtime on macOS.
- `CUTQUAY_TEST_FFMPEG_DIR=/opt/homebrew/bin node .yarn/releases/yarn-4.11.0.cjs test run`: **113/113 existing tests pass**, 16 files, including real local media integration. Without that environment the suite has 104 pass/9 expected native-media skips; the enabled run is the reported full check.
- `node .yarn/releases/yarn-4.11.0.cjs lint`: exit 0, with existing upstream JSX `TSSatisfiesExpression` analysis notices. TypeScript, PowerShell parser, Node syntax and `git diff --check` are included in final handoff verification.

Tests use SDK/Windows adapters only where the actual OS is unavailable. ZIP fixtures do not claim MakeAppx semantic acceptance, and locally compiled P/Invoke declarations do not claim successful Win32 invocation.

## CI and remaining gates

`.github/workflows/windows.yml` runs the unchanged native feature/build sequence, then `script/qualifyWindowsMsix.ps1` with pinned Python setup and SDK. It uploads only explicitly selected JSON/XML/text/log/PNG metadata. MSIX, native binaries, Electron ZIPs, public/private certificates and personal profiles stay in the disposable private runner; no binary artifacts are uploaded.

Independent review and an actual Windows run at the final source/snapshot SHA are still required. Temporary installation/broker acceptance, the final Store binary's normal installation/startup, interactive export/overwrite/cancel/permissions, upgrades, accessibility/DPI, WACK, corresponding source/license closure, Store identity, production signing/submission and publication remain **unverified/false**. No Windows package result is claimed by this handoff.

Helper provenance: adapted from PixelQuay's MIT pipeline through `a34074751992eb81441cf1e562107b3a84f1957b`, plus its coordinator's subsequent stdout-isolation correction. `PIPELINE-MIT.txt` and the retained `RETICLEQUAY-MIT.txt` accompany these source helpers. Application/native component licenses remain unchanged.

## Bounded independent-review repairs

The review of `4f8e8ef4648fb6a2a0930b72db9e4af88c959c97` found two P2 defects. Before repair, new real-ASAR tests accepted a two-executable-only pin/payload and a nine-row pin substituting ffplay for avcodec; both now fail. The suite additionally removes each of the nine rows and its actual payload while rebuilding the embedded ASAR pin, and rejects duplicate/malformed membership. The valid fixture itself now models all nine approved filenames. Sizes and hashes continue to come from the unchanged committed FFmpeg pin.

The new registration adapter regression first ran against the existing real Install/cleanup closures and reproduced deletion of a registration that appeared independently during a failed Add. It now preserves that exact-x64 registration and reports the original Add failure plus residue. Seven additional ambiguity/cleanup cases and the normal uninstall path are exercised without invoking Windows APIs on macOS. These repairs change qualification gates only; application behavior, dependency versions, FFmpeg bytes, Store/publication status, and all unrun Windows/device acceptance claims remain unchanged.

### Windows ASAR lookup separator repair

Actual Windows34601925925 passed the existing native feature/build/startup step, then15 packaging test cases failed before any MSIX construction because nested `out/main/index.js` lookups could not resolve. The locked @electron/asar Filesystem splits parent directories using native `path.sep`; portable inventory names must be normalized at its extractFile boundary. inspect-asar.cjs now passes path.normalize(relative), while inventory/source keys remain portable and link handling stays disabled. Root exercised the real locked Filesystem under path.win32: both nested portable lookups failed, both one-level paths resolved, and allfour normalized lookups resolved.31 local Python methods pass (oneWindowsjunctionskip). ExactWindows retry is still required; no package installation success is claimed.

## Installed-media package context repair (2026-09-11)

The authoritative failure is [Windows run 34602897912](https://github.com/hashfunction/cutquay/actions/runs/34602897912), public source `3e937360d623eeea3552089787fd08600fc99fac`, corresponding local source `1ff67838b12b884c02a74059818e73072ff1bf02`. Its native build/startup and all 113 application tests passed. MSIX pack, unpack, signature verification, exact registration, and installed payload hashes passed. The first installed `resources/ffmpeg.exe -version` launch failed with **Access is denied**, before media, direct installed stderr, broker activation, or GUI qualification. The external PowerShell process had no package identity for that unmanifested helper. Cleanup additionally attempted to kill the allocated but unstarted `Process`, producing **No process is associated with this object**. Exact owned registration cleanup still completed (`residual_package_full_names=[]`), and the unsigned package hash remained unchanged; normal uninstall qualification did not run and remains false.

Downloaded metadata artifact ID `10265586118` has ZIP SHA256 `07595847c731fe18559a4b7ff206440ec09295a1fe73d27b4e81eb6e485a123d`. Its `msix-install/installation-qualification.json` SHA256 is `a78116284f367c6caa966255ba6b201e6259fee1f4606f38d9c79fc7b0f11ad9`. Investigation files are local under `/tmp/cutquay-msix-34602897912`; the immutable run/artifact references above are the remote evidence.

`VerifyInstalledMedia` now uses Microsoft's documented [Invoke-CommandInDesktopPackage](https://learn.microsoft.com/en-us/powershell/module/appx/invoke-commandindesktoppackage?view=windowsserver2025-ps) diagnostic launcher with the exact installed family/application ID and `-PreventBreakaway`. Microsoft documents the package token/identity and retention of the child process tree's package context. This launches only a diagnostic PowerShell worker, using the exact current runner path and fixed encoded script. It does not add that shell to the product payload or count its modules as product modules. The installed main executable remains manifest-declared and its separate direct stderr and broker checks are unchanged.

The worker runs the same four installed FFmpeg/FFprobe version/buildconf probes with all prior installed byte/hash, version, complete configuration, timeout and exit-code checks. Its input and result are bound to the same SHA256 and per-invocation nonce. It verifies its actual package full name, publishes an atomic ready receipt and waits for authorization. The parent retains a live process handle and checks its creation time, exact executable path and actual `GetPackageFullName` before claiming cleanup ownership or authorizing media work. Unverified workers receive no authorization and are preserved by parent cleanup. Final results also require the matching worker receipt and observed zero exit. Primary and cleanup failures remain separate in `media-worker-result.json` and both propagate to failed qualification. Timeout cleanup uses only the already verified worker handle; existing exact registration/certificate cleanup continues independently. Handshake, authorization, result and final worker identity/exit evidence are covered by existing metadata-only artifact globs. Failed native `Process.Start` now disposes its local object before publishing ownership to cleanup.

RED/GREEN evidence:

- Real invalid native-image `Process.Start` test was RED on `1ff67838`: `Failed Process.Start retained an unstarted process for cleanup.` It now passes while preserving the original start error.
- The new actual subprocess worker test was RED before implementation because `Invoke-InstalledMediaInPackage` did not exist. Seven worker scenarios are now GREEN: clean success; four real native FFmpeg/FFprobe calls in a separate process; original media failure; simultaneous media/cleanup failure; wrong actual package identity; wrong actual executable; and timeout. Wrong-identity/executable and timeout scenarios execute the real outer `StopOwnedProcess` closure: unverified processes survive, the verified timed-out worker exits. Only Windows package launching/identity APIs are substituted locally; no simulated Windows installation success is claimed.
- Existing 31 Python package methods: 30 passed, one Windows-only junction case skipped on macOS. Existing PowerShell suites: six orchestration, nine actual registration ownership, five reporting scenarios passed. Existing native media test: four actual FFmpeg/FFprobe invocations, incompatible configuration and changed executable rejected (local FFmpeg 9.0.1).
- All 113 application tests passed with `CUTQUAY_TEST_FFMPEG_DIR=/opt/homebrew/bin node .yarn/releases/yarn-4.11.0.cjs test run` (16 files, Vitest 4.1.11).
- PowerShell 7.6.6 parsed all nine `script/**/*.ps1` files and compiled the embedded activation/package-identity C# types. `git diff --check` passed. No native/app source, dependencies, manifest, capability, source-inventory, broker identity, module confinement, exact title, screenshot or uninstall gates were changed.

Re-run on a fresh disposable Windows runner after native qualification with `pwsh -NoProfile -File script/qualifyWindowsMsix.ps1`. It now executes `test_media_failed_start.ps1` and `test_package_media.ps1` before packaging. Local focused command: `pwsh -NoProfile -File script/msix/test_package_media.ps1`. The actual Windows package-context launcher, installed media, direct stderr, broker/UI, normal close and uninstall remain **unqualified until that exact committed CI run succeeds**. This diagnostic does not qualify CutQuay export behavior inside MSIX. Existing FFmpeg GPLv3 corresponding-source, Store identity/submission, workflow acceptance, upgrade and WACK gates remain open; no product release claim follows from these local results.

## Worker result-publication review repair (2026-09-11)

Independent review of `9f29d84d8f04ec5427724cb049d6b61411a84d6f` reproduced a reporting defect with `/private/tmp/cutquay-worker-reporting-review.ps1`: distinct media and `Kill` failures followed by a preexisting `media-worker-result.json` surfaced only the final `File.Move` collision. The old result bytes were preserved, but the earlier errors were lost. The exact independent probe was rerun RED before this repair and GREEN afterward; the worker now throws the media, cleanup and publication failures together.

Final result publication is guarded. On failure, a separate exclusive, atomic diagnostic receipt is written beside the parent's unique input (`media-worker-input.json.reporting-failure.json`), independently of the output/result directory. It retains the original fields plus `reporting_error`; it never replaces an existing result or fallback file. The actual parent verifies the fallback nonce/input SHA256 and propagates all three errors before attempting to parse a stale or missing result. Its existing outer qualification reporting therefore preserves the combined diagnostic in `installation-qualification.json`. A fallback publication failure is itself appended to the worker's thrown error instead of replacing the original failures. No diagnostic path grants process/package ownership or qualification success.

The lasting real-subprocess `worker-reporting-error` regression is part of `test_package_media.ps1`. Before the fix, the parent lost the media/cleanup errors to a JSON parse failure of the preserved old result; afterward it observes all three original errors, validates the independent fallback contents, and verifies the old bytes are unchanged. Input and output directories are now separate in all worker fixtures, matching the real launcher. All eight worker scenarios pass, including actual native media calls and process ownership cleanup. The existing failed-native-start, native media/hash/configuration, six orchestration, nine registration and five reporting checks pass; all 31 Python package methods pass subject to the unchanged one Windows-junction skip on macOS. PowerShell parsing/embedded C# compilation and `git diff --check` pass. Product/native/build inputs are unchanged; the earlier 113 application test result is not presented as a new run for this reporting-only repair. Actual Windows package-context and installed GUI qualification remain pending.

The same bounded commit repairs a test-only Windows portability failure confirmed in [run 34605285054](https://github.com/hashfunction/cutquay/actions/runs/34605285054) at the preceding `9f29d84` source. `Get-Command python -CommandType Application` returned both `C:\hostedtoolcache\windows\Python\3.12.10\x64\python.exe` and `C:\Users\runneradmin\AppData\Local\Microsoft\WindowsApps\python.exe`. The wrong-executable fixture concatenated both into one `ProcessStartInfo` filename and failed before reaching its intended identity assertion. `/tmp/cutquay-multiple-python-review.ps1` reproduced that actual two-result boundary locally: RED attempted the joined real/alias path; GREEN runs the interpreter to obtain one absolute `sys.executable`, checks its exit status and single output, and then launches that actual foreign executable. All eight worker scenarios pass under the two-result reproduction; exact foreign executable rejection and preservation remain required. The Windows run had passed the first five worker cases but did not reach the package-context installation qualification. This fixture correction makes no product/runtime provenance claim.
