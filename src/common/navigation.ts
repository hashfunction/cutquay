// eslint-disable-next-line import/prefer-default-export
export function canOpenExternal(url: string) {
  try { return ['https:', 'http:', 'mailto:'].includes(new URL(url).protocol); } catch { return false; }
}
