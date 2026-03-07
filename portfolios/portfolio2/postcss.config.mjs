import {join} from 'node:path';

export const plugins = {
  tailwindcss: {
    config: join(import.meta.dirname, 'tailwind.config.js'),
  },
  autoprefixer: {},
};
