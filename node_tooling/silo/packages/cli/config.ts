import {readFile} from 'node:fs/promises';
import Configstore from 'configstore';
import {z} from 'zod';

const {name, version} = JSON.parse(await readFile('./package.json', 'utf8')) as {name: string; version: string};

// Create a Configstore instance.
const config = new Configstore(name, {version});

const hasAlreadyRun: () => boolean = () => {
  const hasAlreadyRunAny = config.get('hasAlreadyRun'); // eslint-disable-line @typescript-eslint/no-unsafe-assignment

  const {success, data: hasAlreadyRun} = z.boolean().safeParse(hasAlreadyRunAny);

  return success && hasAlreadyRun;
};

export {version, hasAlreadyRun};
