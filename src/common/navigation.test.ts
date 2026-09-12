// eslint-disable-next-line import/no-extraneous-dependencies
import { expect, it } from 'vitest';
import { canOpenExternal } from './navigation.ts';

it('only allows explicit web and email destinations outside the privileged renderer', () => {
  expect(canOpenExternal('https://cliptern.trieflow.com/support')).toBe(true);
  expect(canOpenExternal('http://localhost:3000')).toBe(true);
  // eslint-disable-next-line no-script-url
  for (const url of ['file:///tmp/script.html', 'javascript:alert(1)', 'data:text/html,x', 'shell:AppsFolder', 'not a url']) expect(canOpenExternal(url)).toBe(false);
});
