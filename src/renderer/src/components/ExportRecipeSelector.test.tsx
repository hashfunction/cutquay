// @vitest-environment jsdom
import { useState } from 'react';
import { afterEach, expect, it, vi } from 'vitest';
import { cleanup, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import ExportRecipeSelector from './ExportRecipeSelector';
import { recipe } from '../../../common/exportRecipe.fixture';
import type { ExportRecipeV1 } from '../../../common/exportRecipe';

afterEach(cleanup);
function Harness() {
  const [recipes, setRecipes] = useState<ExportRecipeV1[]>([recipe]);
  const [current, setCurrent] = useState<ExportRecipeV1>({ ...recipe, outFormat: 'mp4' });
  return (
    <section aria-label="Export options">
      <ExportRecipeSelector recipes={recipes} currentSettings={current} onChange={setRecipes} onApply={(value) => setCurrent(value)} />
      <output aria-label="Output format">{current.outFormat}</output>
      <p>Cutpoints may be inaccurate.</p>
      <button type="button">Export</button>
    </section>
  );
}
it('applies a recipe and retains the separate export action and cutpoint warning', async () => {
  render(<Harness />);
  await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Recipe' }), 'podcast');
  expect(screen.getByLabelText('Output format').textContent).toBe('matroska');
  expect(screen.getByText('Cutpoints may be inaccurate.')).toBeTruthy();
  expect(screen.getByRole('button', { name: 'Export' })).toBeTruthy();
});
it('rejects duplicates without modifying saved recipes and supports rename and delete', async () => {
  render(<Harness />);
  await userEvent.type(screen.getByRole('textbox', { name: 'Name' }), 'Podcast clip');
  await userEvent.click(screen.getByRole('button', { name: 'Save current' }));
  expect(screen.getByRole('alert').textContent).toContain('unique');
  expect(screen.getAllByRole('option')).toHaveLength(2);
  await userEvent.selectOptions(screen.getByRole('combobox'), 'podcast');
  await userEvent.clear(screen.getByRole('textbox'));
  await userEvent.type(screen.getByRole('textbox'), 'Voice');
  await userEvent.click(screen.getByRole('button', { name: 'Rename' }));
  expect(screen.getByRole('option', { name: 'Voice' })).toBeTruthy();
  await userEvent.click(screen.getByRole('button', { name: 'Delete' }));
  expect(screen.getAllByRole('option')).toHaveLength(1);
});

it('disables all recipe changes after a load failure and offers explicit retry', async () => {
  const onChange = vi.fn();
  const retry = vi.fn();
  render(<ExportRecipeSelector recipes={[recipe]} currentSettings={recipe} onChange={onChange} onApply={vi.fn()} loadError="Restore your config.json backup, then retry loading." onRetryLoad={retry} />);
  for (const name of ['Save current', 'Rename', 'Delete']) await userEvent.click(screen.getByRole('button', { name }));
  await userEvent.type(screen.getByRole('textbox'), 'New name');
  expect((screen.getByRole('textbox') as HTMLInputElement).value).toBe('');
  expect(onChange).not.toHaveBeenCalled();
  expect(screen.getByRole('alert').textContent).toContain('config.json');
  await userEvent.click(screen.getByRole('button', { name: 'Retry loading' }));
  expect(retry).toHaveBeenCalledOnce();
});
