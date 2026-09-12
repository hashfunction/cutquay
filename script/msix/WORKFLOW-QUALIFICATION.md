# Installed Cliptern trim/export qualification

Cliptern 1.0.1 retains this consumer flow with renamed executable/title/report
expectations. The historical implementation and Windows observations below keep
their original identities; a fresh renamed Windows run is required.

This extends the approved Task 4 Windows acceptance with a focused consumer UI
workflow. The application source and packaged payload are unchanged. The existing
normal diagnostic and broker startup/close remain required before this test.

The new operation uses the same exact owned temporary registration. Its existing
handle/identity-authorized package-context media worker generates an eight-second
160x90 H.264/AAC fixture, using only the installed, package-hash-verified FFmpeg.
A separately broker-activated consumer session uses Electron's documented
loopback DevTools switch and the app's existing isolated config-directory option.
The parent binds the loopback listener to the observed broker PID; the CDP client
also requires that PID from SystemInfo and exactly the installed renderer URL.
No application test flag, replacement renderer, IPC invocation, React state hook,
HTTP action API, or fixture recipe injection is used.

CDP dispatches actual file-drag, mouse, key and text input events to existing
controls. It imports the fixture, enters 2s/5s trim boundaries, opens Export
options, turns off the current default overwrite setting through its visible switch,
saves an originally named recipe, applies that recipe and clicks the
real Export control. It requires the visible success dialog and the actual
consumer export report, output bytes and persisted recipe configuration. A
second normally closed/reopened broker session imports that output, verifies its
media element, reloads/applies the saved recipe and observes restored controls.
The installed FFprobe independently checks codecs, geometry and duration, and
installed FFmpeg decodes every output audio/video stream with errors fatal.

Each invocation uses fresh owned work/profile/evidence directories and bounded
waits. Input bytes, helper/source/package identity, exact commands, UI snapshots,
export report, output hashes and probe results are retained as metadata only.
Generated media, profiles and executables are not artifact-upload paths. Primary,
cleanup and report-publication failures remain failures; only retained owned
process handles may be terminated. Module snapshots are repeated after workflow
sessions. They do not claim exhaustive tracing of transient media processes.

This is automation of the unmodified installed consumer app, with disclosed
qualification command-line switches. It qualifies only the stated import,
recipe-save/apply, keyframe-aligned trim/export and reopen path. Cancel, overwrite,
unusual codecs/filesystems, non-keyframe accuracy, upgrades, accessibility/DPI,
WACK, Store identity, all corresponding-source/license and binary distribution
gates remain separate. Actual Windows execution is pending until the committed
source is run by the coordinator.

Primary protocol references:
- https://www.electronjs.org/docs/latest/api/command-line-switches
- https://chromedevtools.github.io/devtools-protocol/tot/Input/
- https://chromedevtools.github.io/devtools-protocol/tot/SystemInfo/

## Short-lived native process observation repair

Windows run `34637266629`, source `401aadad3d27252d5ad679b51e5afc3c5073ef87`,
failed in the required real media fixture before installation: the production
`Invoke-WorkflowNative` queried `MainModule.FileName` after FFprobe could exit.
Its module list was gone, yielding the missing `FileName` property error.
The regression forces each actual native command to finish before image
observation and reproduces that same failure against the preceding source.

The subsequent source `2dd4a29ac004c1f6f17616eef4f4f736511b7c7b` used
`QueryFullProcessImageNameW` through the original retained `SafeProcessHandle`.
Windows run `34640478541` then failed in `workflow-generate`, also before actual
installation: the native image query itself failed after a short-lived command.
Keeping the original handle did not establish that every post-exit query would
succeed. That failed run retained only the earlier startup/test/media-runtime
metadata, not installed workflow acceptance.

For these synchronous media commands, the execution contract is now the exact
preverified executable passed to `ProcessStartInfo`, successful `Process.Start`
with its original handle retained, actual output/exit and unchanged executable
and media DLL hashes after execution. The native helper is compiled before
launch. Image and package queries still use that original handle; a returned
foreign image or package remains fatal, including after exit. A query exception
is fatal while the same process is observed running. Only after observing exit
with `WaitForExit(0)` may its failed query be recorded as
`unavailable_after_observed_exit`, with a null observed value, actual exception
type/message and native error code. There is no PID reopen or requested-path
fallback. An invalid retained handle still fails.

Receipts distinguish `launch_executable_path` from nullable
`process_image_path`, and distinguish expected parent package context from
nullable child `package_full_name`. Each `process_identity` observation records
its status and error. The parent worker is independently verified in its package
context and launched with `PreventBreakaway`; this does not fabricate an
unavailable child observation. The broker's persistent consumer UI process,
module, ownership and cleanup requirements are unchanged.

The updated real media fixture generates, probes and decodes actual H.264/AAC,
forces all three commands to exit before the image query, rejects wrong package
and wrong path without success receipts, and exercises the actual C#
invalid-handle rejection. It also invokes real FFprobe with an adapted post-exit
query failure and checks its output/exit and persisted null/error fields. Eight
separate real subprocess cases cover observed identities, one or both unavailable
queries, returned mismatches after exit and image/package failures while alive,
including retention of the same open handle. On macOS the unavailable Windows
image API is adapted; the fixture package-identity adapter is explicit on both
platforms. The Windows test uses the production image API after termination.
Nine real worker scenarios, the owned-process/foreign-process fixture, six
installation orchestration scenarios and the actual failed-start fixture also
passed locally with PowerShell 7.6.6 and Homebrew FFmpeg 9.0.1. Actual Windows
observation results and installed workflow acceptance still require a fresh
native run; local adapters establish neither fact.

Primary Windows API/lifetime references:
- https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-queryfullprocessimagenamew
- https://learn.microsoft.com/en-us/windows/win32/procthread/terminating-a-process
- https://learn.microsoft.com/en-us/windows/win32/api/appmodel/nf-appmodel-getpackagefullname

The first API queries an image name from an authorized process handle. Windows
retains the process object while handles remain open, although its executable
code and module list have been removed at termination. These references explain
the API choice, without guaranteeing post-exit query availability. The required
Windows regression retains its actual observed or unavailable result.

## Local verification and execution handoff

Run the focused checks from the committed source root:

```sh
node --test script/msix/testWorkflowUi.mjs
pwsh -NoLogo -NoProfile -File script/msix/test_workflow_media.ps1
pwsh -NoLogo -NoProfile -File script/msix/test_media_identity.ps1
pwsh -NoLogo -NoProfile -File script/msix/test_workflow_ownership.ps1
pwsh -NoLogo -NoProfile -File script/msix/test_package_media.ps1
```

The native runner executes these before building the MSIX. Existing installation
orchestration now requires `QualifyExportWorkflow` after ordinary close and before
normal uninstall. A failure skips normal acceptance and still runs all owned
cleanup. The installed helper continues to record broad `workflow_acceptance`
as false; the narrower `export_workflow_tested` and `consumer_export_workflow`
are set only from the completed operation. Those are pending native execution.

Local checks on macOS (without desktop/app interaction): seven Node boundary,
real DOM locator and CDP transport tests passed; real fixed-command media tests
built the H.264/AAC input and probed/fully decoded a native three-second fixture;
existing source bytes and changed-output hashes were preserved/rejected as
specified. The CDP and DOM tests do not claim actual Windows input delivery.
The expanded nine subprocess-worker scenarios include actual fixture generation
through the real handshake/authorization/result path, plus native versions,
identity rejection, timeout and combined operation/cleanup/publication failures.
Package launch/identity are explicit fixture adapters. The unavailable Windows
image query is adapted only locally; Windows uses its real retained-handle API.
Listener tests reject absent, foreign-PID and broad-address listeners; a real
owned driver process is terminated while a separate foreign process survives.
Existing 113 feature tests passed, as did 31 Python package tests with the one
Windows-only junction skip, existing registration/reporting/native helper tests,
TypeScript, lint and PowerShell parsing/C# interop compilation. Existing upstream
JSX lint-analysis notices remain unchanged.

The first boundary tests were RED because the new media/UI helpers did not
exist. Adding the new required operation to the real core-order test was RED
before integration; it is GREEN with the failure-plus-cleanup assertion. Local
logs are retained under ignored `build-evidence/workflow-*`. A real Windows run
at the final commit must establish broker arguments/DevTools availability,
actual input delivery, save/apply/trim/export/reopen and normal lifecycle. No
result from the prior startup-only run establishes these new facts.
# Fresh-profile view selection

Run 34643457961 successfully loaded the eight-second fixture through the
installed consumer UI, then correctly failed because simple view hides the
manual trim fields. The external driver now checks the rendered start-time
field and, when absent, clicks the visible **Toggle advanced view** control.
It still requires exposed, enabled trim fields before entering the requested
2–5 second range. This changes only test navigation and leaves source defaults
unchanged. The normal toggle may save its view preference; the driver does not
edit configuration files directly.

Run 34645294742 completed the installed consumer import, 2–5 second trim,
saved-recipe application and actual export. Its 156,675-byte output was then
reopened at 3.029333 seconds. The next test step failed because an untouched
full-file segment uses the existing button title **Export**, while the driver
expected **Export selection**. `useSegments` deliberately excludes the initial
full-file segment from the cut list, and `ExportButton` derives its title from
that list. The reopen step now selects the exact visible **Export** button.
The trim phase keeps its selection-specific selector and all report/media
checks. Persisted recipe reapplication after restart still requires a fresh
Windows result.
