import { join } from 'node:path';
import { appName } from './common.js';

interface IdentityApp {
  getPath: (name: 'appData') => string,
  setPath: (name: 'userData' | 'sessionData', value: string) => void,
  setName: (value: string) => void,
  setAppUserModelId: (value: string) => void,
  commandLine: { hasSwitch: (name: string) => boolean },
}

export default function configureAppIdentity(app: IdentityApp, platform = process.platform) {
  // Set before logger/config/session imports. The rename must not move existing data.
  // Explicit browser profiles are retained, including qualification's owned directories.
  if (!app.commandLine.hasSwitch('user-data-dir')) {
    const profile = join(app.getPath('appData'), 'CutQuay');
    app.setPath('userData', profile);
    app.setPath('sessionData', profile);
  }
  app.setName(appName);
  if (platform === 'win32') app.setAppUserModelId('CutQuay');
}
