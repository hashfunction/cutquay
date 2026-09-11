import { z } from 'zod';

// eslint-disable-next-line no-control-regex
const recipeName = z.string().trim().min(1).max(80).refine((s) => !/[\u0000-\u001F/\\]/u.test(s) && !s.includes('..'), 'Use a plain recipe name');
const template = z.string().min(1).max(4096).refine((s) => !s.includes('\0'), 'Invalid filename template');

export const exportRecipeSchema = z.object({
  version: z.literal(1),
  id: z.string().min(1).max(100),
  name: recipeName,
  exportMode: z.enum(['separate', 'merge', 'merge+separate', 'segments_to_chapters']),
  outFormat: z.string().regex(/^[a-z0-9_]+$/u).max(80),
  keyframeCut: z.boolean(),
  preserveMetadata: z.enum(['default', 'nonglobal', 'none']),
  preserveChapters: z.boolean(),
  movFastStart: z.boolean(),
  avoidNegativeTs: z.enum(['make_zero', 'auto', 'make_non_negative', 'disabled']),
  autoExportExtraStreams: z.boolean(),
  enableOverwriteOutput: z.boolean(),
  cutFileTemplate: template,
  cutMergedFileTemplate: template,
});

export type ExportRecipeV1 = z.infer<typeof exportRecipeSchema>;
export type ExportRecipeSettings = Omit<ExportRecipeV1, 'version' | 'id' | 'name'>;
export type ResolvedExportRecipe = Readonly<ExportRecipeV1>;

export function parseExportRecipes(value: unknown): ExportRecipeV1[] {
  if (value === undefined) return [];
  const recipes = z.array(exportRecipeSchema).max(100).parse(value);
  if (new Set(recipes.map((r) => r.id)).size !== recipes.length || new Set(recipes.map((r) => r.name.toLowerCase())).size !== recipes.length) {
    throw new Error('Recipe names and IDs must be unique');
  }
  return recipes;
}

export function resolveExportRecipe(recipe: ExportRecipeV1): ResolvedExportRecipe {
  return Object.freeze(exportRecipeSchema.parse(recipe));
}

export function recipeSettings(recipe: ExportRecipeV1) {
  const parsed = resolveExportRecipe(recipe);
  return {
    ...parsed,
    autoMerge: parsed.exportMode === 'merge' || parsed.exportMode === 'merge+separate',
    autoDeleteMergedSegments: parsed.exportMode === 'merge',
    segmentsToChaptersOnly: parsed.exportMode === 'segments_to_chapters',
  };
}

export function updateRecipes(recipes: ExportRecipeV1[], action:
  | { type: 'save', recipe: ExportRecipeV1 }
  | { type: 'rename', id: string, name: string }
  | { type: 'delete', id: string }) {
  switch (action.type) {
    case 'save': { return parseExportRecipes([...recipes, action.recipe]);
    }
    case 'rename': { return parseExportRecipes(recipes.map((r) => (r.id === action.id ? { ...r, name: action.name } : r)));
    }
    case 'delete': { return parseExportRecipes(recipes.filter((r) => r.id !== action.id));
    }
    default: { throw new Error('Unknown recipe action');
    }
  }
}
