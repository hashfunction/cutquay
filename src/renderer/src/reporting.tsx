import i18n from 'i18next';
import { Trans } from 'react-i18next';

import CopyClipboardButton from './components/CopyClipboardButton';
import { isStoreBuild, isMasBuild, isWindowsStoreBuild, isExecaError, appVersion, appPath } from './util';
import getSwal from './swal';
import { supportUrl } from '../../common/constants';
import mainApi from './mainApi';

const remote = window.require('@electron/remote');
const { platform, arch } = remote.require('./index.js');


// This cannot be a radix dialog, because it needs to be called even if the React tree is broken.
// eslint-disable-next-line import/prefer-default-export
export function openSendReportDialog({ err, message, state }: {
  err?: unknown | undefined,
  message?: string,
  state?: unknown,
}) {
  const reportInstructions = (
    <p>Describe what happened on the <button type="button" onClick={() => mainApi.openExternal(supportUrl)}>Cliptern support page</button>. The diagnostic text below stays local until you copy and share it.</p>
  );

  const errorText = (() => {
    if (err == null) return 'No error occurred.';
    return err instanceof Error ? err.stack : String(err);
  })();

  const jsonReport = JSON.stringify({
    err: isExecaError(err) && {
      code: err.code,
      isTerminated: err.isTerminated,
      failed: err.failed,
      timedOut: err.timedOut,
      isCanceled: err.isCanceled,
      exitCode: err.exitCode,
      signal: err.signal,
      signalDescription: err.signalDescription,
    },

    state,

    appPath,
    platform,
    arch,
    version: appVersion,
    isWindowsStoreBuild,
    isMasBuild,
  }, null, 2);

  const lines = [
    ...(message != null ? [message] : []),
    errorText,
    '',
    'App state:',
    jsonReport,
  ];

  const text = lines.join('\n');

  getSwal().ReactSwal.fire({
    showCloseButton: true,
    title: i18n.t('Send problem report'),
    showConfirmButton: false,
    html: (
      <div style={{ textAlign: 'left', overflow: 'auto', maxHeight: 300, overflowY: 'auto' }}>
        {reportInstructions}

        <p style={{ marginBottom: 0 }}><Trans>Include the following text:</Trans> <CopyClipboardButton text={text} /></p>

        {!isStoreBuild && <p style={{ marginTop: '.2em', fontSize: '.8em', opacity: 0.7 }}><Trans>You might want to redact any sensitive information like paths.</Trans></p>}

        <div style={{ fontWeight: 600, fontSize: '.75em', fontFamily: 'monospace', whiteSpace: 'pre-wrap', color: 'var(--gray-11)', backgroundColor: 'var(--gray-3)', padding: '.3em' }} contentEditable suppressContentEditableWarning>
          {text}
        </div>
      </div>
    ),
  });
}
