/* eslint-disable import/prefer-default-export, no-template-curly-in-string */
export const recipe = {
  version: 1 as const,
  id: 'podcast',
  name: 'Podcast clip',
  exportMode: 'merge' as const,
  outFormat: 'matroska',
  keyframeCut: true,
  preserveMetadata: 'default' as const,
  preserveChapters: true,
  movFastStart: true,
  avoidNegativeTs: 'make_non_negative' as const,
  autoExportExtraStreams: false,
  enableOverwriteOutput: false,
  cutFileTemplate: '${FILENAME}-${SEG_NUM}${EXT}',
  cutMergedFileTemplate: '${FILENAME}-merged${EXT}',
};
