// @vitest-environment jsdom
import { afterEach, beforeAll, beforeEach, expect, it, vi } from 'vitest';
import { act, cleanup, renderHook } from '@testing-library/react';
import { recipe } from '../../../common/exportRecipe.fixture';

vi.mock('../swal', () => ({ errorToast: vi.fn() }));
vi.mock('../isDev', () => ({ default: false }));

let persisted: unknown;
let readFails = false;
let writeFails = false;
let useUserSettingsRoot: (typeof import('./useUserSettingsRoot'))['default'];
const configStore = {
  get: (key: string) => {
    if (key !== 'exportRecipes') return undefined;
    if (readFails) throw new Error('Unable to read saved recipes');
    return persisted;
  },
  set: (key: string, value: unknown) => {
    if (key !== 'exportRecipes') return;
    if (writeFails) throw new Error('Unable to save recipes');
    persisted = value;
  },
};
beforeAll(async () => {
  Object.assign(window, { require: () => ({
    systemPreferences: { getAnimationSettings: () => ({ prefersReducedMotion: false }) },
    require: () => ({ configStore }),
  }) });
  ({ default: useUserSettingsRoot } = await import('./useUserSettingsRoot'));
});
beforeEach(() => { persisted = undefined; readFails = false; writeFails = false; });
afterEach(cleanup);

it('preserves failed-load data after every ordinary mutation, including updater callbacks', () => {
  const original = [recipe, null];
  persisted = original;
  const { result } = renderHook(() => useUserSettingsRoot());
  expect(persisted).toEqual(original);
  expect(result.current.settings.exportRecipes).toEqual([]);
  act(() => result.current.setExportRecipes([{ ...recipe, id: 'new', name: 'New recipe' }]));
  expect(persisted).toEqual(original);
  act(() => result.current.retryExportRecipesLoad());
  expect(result.current.exportRecipesLoadError).toBeTruthy();
  act(() => result.current.setExportRecipes(() => []));
  expect(persisted).toEqual(original);
});

it('keeps failed reads locked until an explicit successful retry, then permits normal saves', () => {
  persisted = [recipe];
  readFails = true;
  const { result } = renderHook(() => useUserSettingsRoot());
  expect(result.current.exportRecipesLoadError).toBeTruthy();
  act(() => result.current.setExportRecipes([]));
  expect(persisted).toEqual([recipe]);
  act(() => result.current.retryExportRecipesLoad());
  expect(result.current.exportRecipesLoadError).toBeTruthy();
  readFails = false;
  act(() => result.current.retryExportRecipesLoad());
  expect(result.current.exportRecipesLoadError).toBeUndefined();
  expect(result.current.settings.exportRecipes).toEqual([recipe]);
  act(() => result.current.setExportRecipes((previous) => [...previous, { ...recipe, id: 'new', name: 'New' }]));
  expect(persisted).toEqual([recipe, { ...recipe, id: 'new', name: 'New' }]);
});

it('distinguishes absent settings from failed loads and retains valid data after write failures', () => {
  const { result } = renderHook(() => useUserSettingsRoot());
  expect(result.current.exportRecipesLoadError).toBeUndefined();
  act(() => result.current.setExportRecipes([recipe]));
  expect(persisted).toEqual([recipe]);
  writeFails = true;
  act(() => result.current.setExportRecipes([]));
  expect(persisted).toEqual([recipe]);
  expect(result.current.settings.exportRecipes).toEqual([recipe]);
});
