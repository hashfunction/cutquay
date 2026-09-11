import { useState } from 'react';
import { updateRecipes, type ExportRecipeV1, type ExportRecipeSettings } from '../../../common/exportRecipe';

export default function ExportRecipeSelector({ recipes, currentSettings, onApply, onChange, loadError, onRetryLoad }: {
  loadError?: string | undefined, onRetryLoad?: () => void,
  recipes: ExportRecipeV1[], currentSettings: ExportRecipeSettings,
  onApply: (recipe: ExportRecipeV1) => void, onChange: (updatedRecipes: ExportRecipeV1[]) => void,
}) {
  const [selectedId, setSelectedId] = useState('');
  const [name, setName] = useState('');
  const [error, setError] = useState('');
  const selected = recipes.find((r) => r.id === selectedId);
  function change(action: Parameters<typeof updateRecipes>[1]) {
    if (loadError) return;
    try { onChange(updateRecipes(recipes, action)); setError(''); } catch (err) { setError(err instanceof Error ? err.message : String(err)); }
  }
  return (
    <fieldset style={{ margin: '0 0 16px', padding: 14, border: '1px solid var(--gray-7)', borderRadius: 8 }}>
      <legend>Export recipes</legend>
      {loadError && <div role="alert"><p>{loadError}</p><button type="button" onClick={onRetryLoad}>Retry loading</button></div>}
      <fieldset disabled={Boolean(loadError)} style={{ border: 0, padding: 0, margin: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
          <label htmlFor="export-recipe">Recipe
            <select
              id="export-recipe"
              value={selectedId}
              onChange={(event) => {
                setSelectedId(event.target.value);
                const recipe = recipes.find((r) => r.id === event.target.value);
                if (recipe) { onApply(recipe); setName(recipe.name); }
              }}
            >
              <option value="">Current settings</option>
              {recipes.map((recipe) => <option key={recipe.id} value={recipe.id}>{recipe.name}</option>)}
            </select>
          </label>
          <label htmlFor="export-recipe-name">Name
            <input id="export-recipe-name" value={name} maxLength={80} onChange={(event) => setName(event.target.value)} />
          </label>
          <button type="button" onClick={() => change({ type: 'save', recipe: { ...currentSettings, version: 1, id: globalThis.crypto.randomUUID(), name } })}>Save current</button>
          <button type="button" disabled={!selected} onClick={() => change({ type: 'rename', id: selectedId, name })}>Rename</button>
          <button type="button" disabled={!selected} onClick={() => { change({ type: 'delete', id: selectedId }); setSelectedId(''); }}>Delete</button>
        </div>
      </fieldset>
      <p style={{ fontSize: '.85em', marginBottom: 0 }}>Recipes update the controls below. Review the format, tracks and cutpoint warnings before exporting. Each run saves a local JSON report beside its output.</p>
      {currentSettings.enableOverwriteOutput && <p role="alert" style={{ color: 'var(--orange-11)' }}>Overwrite is enabled. Existing output files will be replaced only after a new export completes.</p>}
      {error && <p role="alert">{error}</p>}
    </fieldset>
  );
}
