# Cliptern source rename verification

Date: 2026-09-12. Base: `9b1716fa191fa623062bd3d9c26aa1de239651ae`.

The current application, translations, executable, portable/package names, UI
titles, generated own notices and current documentation now use Cliptern. The
application version is 1.0.1; MSIX is 1.0.1.0. Current product links use
`https://cliptern.trieflow.com`. The repository remains
`https://github.com/hashfunction/cutquay`; upstream attribution remains in NOTICE.

The assigned Store name `1659hashfunction.CutQuay`, publisher
`CN=B6A2631A-FD32-45CC-AE12-82466975F528`, publisher display name `hashfunction`,
application ID `CutQuay`, and existing `com.trieflow.cutquay` builder identifiers
are unchanged. Disposable qualification identity and ownership helpers retain
their existing identifiers. Both independent package inspectors and installer
now require the actual `Cliptern.exe` and current version/display name. Existing
rejection tests include old executable/display names and selected-mode confusion.

## Existing user data

Changing Electron productName otherwise changes its default profile. An early
bootstrap retains `appData/CutQuay` for both userData and sessionData before the
logger, configuration and session imports. The built main bundle confirms the
bootstrap call precedes the first userData-dependent logger. The visible app name
is Cliptern, with the old Windows notification application ID retained. Explicit
`--user-data-dir`, existing `--config-dir`, portable configuration and `.llc`
project behavior remain unchanged. This ordering follows Electron's documented
[profile path behavior](https://www.electronjs.org/docs/latest/api/app).

Three production-boundary tests check the default profile, explicit isolated
profile, and persistence using the actual installed electron-store module. The
last seeds a valid pre-rename export recipe, verifies loading does not rewrite
the existing bytes, saves another recipe, reopens the store, and confirms a
custom config directory does not replace the default data. Only the Electron
platform boundary is adapted. The initial missing-bootstrap case failed before
implementation; the final tests pass.

## Qualification and screenshot evidence

The main Windows workflow retains the full installed media/import/trim/recipe/
export/reopen checks, process/package/module ownership, normal close, uninstall,
certificate removal and residual-cleanup gates. Its Store artifact remains
success-only, containing exactly the unsigned MSIX and release-ready receipt.
Changing display names does not establish Windows acceptance or release approval.

The screenshot-only workflow retains its historical exact package and receipt
binding: source `bd28e72559ee8c06cc320e8c02b82ddb79ef353d`, run `34671595408`,
`CutQuay_1.0.0.0_x64.msix`, 260378673 bytes, SHA-256
`bfaed1c545107b948e9e240b5041f197548bf8b83179c12c70f27b1d262b40b3`.
That old evidence has not been relabeled as Cliptern. New preflight rejects this
binding before filesystem output, download, install or capture. Preparation and
capture each enforce it. Tests prove refusal before side effects. Root must
independently review a freshly qualified Cliptern package, receipt, source/run,
artifact IDs and hashes before updating the locked capture inputs. The actual
display-mode helper and unedited-capture rules are unchanged. No new native
screenshots or renamed Windows package were produced locally.

Running the actual repository lint also exposed previously unlinted marketing
JavaScript. Formatting and explicit browser globals were corrected without
disabling lint checks or changing the UI/ownership/pixel gates; both production
marketing helper tests pass.

## Native source and attribution

The exact finalized native-source manifest and publication JSON, FFmpeg pin,
source-publication validator, application GPL license and FFmpeg license remain
byte-for-byte identical to the base. The historical public archive names, URLs,
source-page/product fields and original qualification history are preserved.
The real publication validator still accepts the four exact source archives.
No native-source or binary closure was changed by this rename.

The actual license generator was rerun. All 531 third-party license blocks are
byte-for-byte identical to the previous generated blocks, including duplicate
package-name blocks (compared as a multiset), although the generator reordered
some blocks. The own product entry and the appended current native-source notice
were updated. Upstream license whitespace was preserved. Consequently plain
`git diff --check` reports inherited whitespace in moved generated license text;
`git diff --check -- . ':!licenses.txt'` is clean. Yarn likewise reordered the
renamed workspace block; dependency versions did not change.

## Local verification

No downloads were needed. Local runtime: Node 25.2.1, Yarn 4.11.0, Python 3.10;
the existing Windows Node pin remains unchanged. PowerShell 7.6.6 was run from
`/Users/hashfunction/workspace/project_app_factory/microsoft-store/apps/filequay/source/.tools/powershell-7.6.6/pwsh`.

- Offline immutable install: passed (`YARN_ENABLE_NETWORK=0`, skip-build mode).
- TypeScript, repository lint, application build, license check and actual
  license generation: passed. Lint prints an existing jsx-ast-utils
  TSSatisfiesExpression diagnostic but exits zero with no lint errors.
- Application tests with `CUTQUAY_TEST_FFMPEG_DIR=/opt/homebrew/bin`: 116 passed
  across 17 files, including real host FFmpeg integration; no skipped tests.
- MSIX/source/export Python suite: 57 tests, 56 passed and one existing
  Windows-only junction test skipped on macOS.
- All 14 MSIX/marketing PowerShell fixture scripts: passed.
- Combined MSIX/marketing Node helpers: 9 passed.
- Marketing Python fixtures: 8 passed.
- All translation JSON parses, with no old-brand keys or values.
- Exact native-source publication validation and source byte comparison: passed.

Detailed local logs are retained in `/private/tmp/cliptern-*.log`, including
`cliptern-app-tests.log`, `cliptern-helper-tests.log`, `cliptern-msix-tests.log`,
`cliptern-lint.log`, `cliptern-tsc.log`, `cliptern-build.log`,
`cliptern-immutable-install.log`, `cliptern-license-check.log`, and
`cliptern-notices.log`. Full application and Python/Node suites were also rerun
after the final recipe-fixture change.

Only the test adapter file created during this task was removed. The two
pre-existing untracked `.capture-parameters-128feb6a15ee4a3aac52c593ed1a01e1.ps1`
and `.capture-parameters-ea32cf6452374ae38723a79501740d45.ps1` remain untouched
and are excluded from the commit. No parent release state, website, Store
submission or public branch was changed. Independent root review and a fresh
actual Windows qualification remain required.
