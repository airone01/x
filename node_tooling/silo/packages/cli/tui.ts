import {
  input, search, select, Separator,
} from '@inquirer/prompts';
import typeglide from 'typeglide';
import {DirectoryType, NodePackageManager} from './lib.js';
import {hasAlreadyRun} from './config.js';

const motdList = [
  'Hi. Let\'s set up your new side project!',
  'I heard astro is cool, wanna check it out?',
];

const directoryTypes: Array<{
  name: string;
  value: DirectoryType;
  description: string;
}> = [
  {
    name: 'Single project',
    value: DirectoryType.CLASSIC,
    description: 'Default and recommended choice.',
  },
];

const npms: Array<{
  name: string;
  value: NodePackageManager;
  description: string;
} | Separator> = [
  {
    name: 'npm',
    value: NodePackageManager.NPM,
    description: 'The classic. Default choice.',
  },
  new Separator(),
  {
    name: 'yarn',
    value: NodePackageManager.YARN,
    description: 'Uses a different lockfile format.',
  },
  {
    name: 'pnpm',
    value: NodePackageManager.PNPM,
    description: 'Very fast.',
  },
  {
    name: 'bun',
    value: NodePackageManager.BUN,
    description: 'The fastest.',
  },
];

const initProject = async (initialName?: string) => {
  // Typewriter intro
  await typeglide({
    strings: [motdList[Math.floor(Math.random() * motdList.length)]],
    backspace: false,
    typeSpeed: 30,
  });
  console.log('');

  const has = hasAlreadyRun();
  if (!has) {
    console.log('Hey! This seem to be your first time running silo. Care to fill out some of these details?\n');

    const favoriteNpm = await select({
      message: 'What is usually your Node/JS/TS package manager of choice? We will autocomplete with this.',
      choices: npms,
    });
  }

  const projectName = await input({
    message: 'Name of your project',
    default: initialName,
  });
  const directoryType = await search({
    message: 'Type of your project/folder hierarchy',
    source: () => directoryTypes,
  });
};

export {initProject};
