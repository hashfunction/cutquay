# Verified unsigned Store package retention

The default qualification identity continues through the existing installation,
consumer workflow, close and ownership-aware cleanup gates. It exports metadata
only. Store identity uses the same gates, then calls `export_store_package.py`.
The exporter creates only `build-evidence/store-upload/Cliptern_1.0.1.0_x64.msix`
and `release-ready.json`. The workflow uploads exactly those two files only when
all preceding steps succeed. Temporary signed copies, certificates and keys are
outside this artifact path.

The final gate checks current checkout/source, workflow run and attempt, native
startup/executable/notices, exact Store identity, installed package ownership,
export/decode/reopen/recipe evidence, normal close, uninstall and empty cleanup
errors/residue. It revalidates the actual Electron archive, ASAR/source, media
pins and complete release inventory; independently verifies the unsigned MSIX;
and rechecks consumed evidence/runtime before and after copying. A failed copy
or final verification removes only its exclusively created export files.
Existing qualification receipts remain historical evidence: the exporter never
changes `workflow_acceptance`, `licenseClearanceClaimed` or `publicRelease`.
The separate readiness receipt binds the retained bytes and input receipt hashes
for Store upload; it does not claim submission, WACK, upgrade or public release.

## Final native-source inputs

The package retains the upstream Electron `LICENSE.electron.txt` and
`LICENSES.chromium.html` unchanged, plus GPLv3 `resources/FFmpeg-LICENSE.txt`.
`resources/NATIVE-SOURCES.txt` explains the separate native runtimes and points
to the canonical source page and fixed source release. The source manifest and
publication record are also normal resource files outside ASAR, verified against
`Release/` source bytes and included in the exact package inventory.

The existing finalized native-source publication remains byte-identical to its
public archive. It retains the historical CutQuay product/source-page fields and
archive names because the native dependencies have not changed. The Cliptern
application and current notice use the new canonical domain. No provisional or
relabeled historical source manifest authorizes export:

- `Release/native-source-manifest.json`: exact bytes of published `source-manifest.json`.
- `Release/native-source-publication.json`: schema version 1; `product: CutQuay`;
  `publication_verified: true`; `source_page: https://cutquay.trieflow.com/source`;
  `release_url: https://github.com/hashfunction/cutquay/releases/tag/native-sources-2026-09-10`;
  UTC `verified_at_utc`; `manifest` with exact public URL, positive byte count and
  SHA256; and four `assets`, each with name, public URL, positive byte count and
  SHA256 matching the source manifest.

The manifest must bind the pinned FFmpeg binary archive/commit and the normal
Electron Windows x64 media configuration. At export time, an unauthenticated
HTTPS fetch of the fixed published manifest must equal the tracked bytes. The
publication record captures the independently verified large source downloads;
the exporter does not download their multi-gigabyte archives again.

Tests use synthetic publication fixtures. Missing production records fail
packaging/source validation and cannot produce an upload artifact. Run the
Python package, source-publication and Store-export tests after dependencies and
artwork are prepared. `test_store_export.py` constructs and verifies real small
MSIX/ASAR/Electron fixtures; only git checkout and network boundaries are replaced.
Actual native Windows Store qualification is required again for every candidate.
