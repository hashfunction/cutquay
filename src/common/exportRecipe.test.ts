// eslint-disable-next-line import/no-extraneous-dependencies
import { describe, expect, it } from 'vitest';
import { parseExportRecipes, resolveExportRecipe, updateRecipes, recipeSettings } from './exportRecipe.ts';

import { recipe } from './exportRecipe.fixture.ts';

describe('export recipes', () => {
  it('migrates absent storage and rejects malformed persisted data', () => {
    expect(parseExportRecipes(undefined)).toEqual([]);
    for (const change of [{ version: 2 }, { name: '../x' }, { name: ' ' }, { exportMode: 'erase' }, { outFormat: '-y file' }, { enableOverwriteOutput: 'yes' }]) {
      expect(() => parseExportRecipes([{ ...recipe, ...change }])).toThrow();
    }
  });
  it('rejects duplicate IDs and case-insensitive names after trimming', () => {
    expect(() => parseExportRecipes([recipe, { ...recipe, id: 'other', name: ' podcast clip ' }])).toThrow();
    expect(() => parseExportRecipes([recipe, { ...recipe, name: 'Other' }])).toThrow();
  });
  it('freezes a detached effective snapshot including overwrite policy', () => {
    const mutable = { ...recipe };
    const snapshot = resolveExportRecipe(mutable);
    mutable.name = 'changed';
    mutable.enableOverwriteOutput = true;
    expect(snapshot.name).toBe('Podcast clip');
    expect(snapshot.enableOverwriteOutput).toBe(false);
    expect(Object.isFrozen(snapshot)).toBe(true);
  });
  it('renames and deletes by ID without corrupting other recipes', () => {
    const saved = updateRecipes([], { type: 'save', recipe });
    const renamed = updateRecipes(saved, { type: 'rename', id: 'podcast', name: '  Voice  ' });
    expect(renamed[0]?.name).toBe('Voice');
    expect(saved[0]?.name).toBe('Podcast clip');
    expect(updateRecipes(renamed, { type: 'delete', id: 'podcast' })).toEqual([]);
  });
  it('maps all four actual export modes to the existing controls', () => {
    expect(recipeSettings({ ...recipe, exportMode: 'merge' })).toMatchObject({ autoMerge: true, autoDeleteMergedSegments: true, segmentsToChaptersOnly: false });
    expect(recipeSettings({ ...recipe, exportMode: 'merge+separate' })).toMatchObject({ autoMerge: true, autoDeleteMergedSegments: false, segmentsToChaptersOnly: false });
    expect(recipeSettings({ ...recipe, exportMode: 'separate' })).toMatchObject({ autoMerge: false, segmentsToChaptersOnly: false });
    expect(recipeSettings({ ...recipe, exportMode: 'segments_to_chapters' })).toMatchObject({ autoMerge: false, segmentsToChaptersOnly: true });
  });
});
