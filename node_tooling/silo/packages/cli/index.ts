import {exit} from 'node:process';
import meow from 'meow';
import {initProject} from './tui.js';
import {
  blue, blurple, bold, gray, orange, pink,
} from './lib.js';
import {version} from './config.js';

const helps = {
  main: `${blurple('Silo')} is an universal project bootstrapper. ${gray(`(${version})`)}

${blue('Usage:')} ${bold('silo <command> [...flags] [...args]')}

${blue('Commands:')}
  ${pink('init')}  ${gray('myproject')}  Initializes a project`,
  init: `${blue('Usage:')} ${bold('silo init [project name] [...flags] [...args]')}

${blue('Examples:')}
  ${pink('silo init')}
  ${pink('silo init')} ${orange('myproject')}`,
} as const;

const cli = meow({
  importMeta: import.meta,
});

switch (cli.input.at(0)) {
  case 'init': {
    await initProject(cli.input.at(1));
    break;
  }

  case undefined: {
    console.log(helps.main);
    exit(1);
    break;
  }

  default: {
    console.log(helps.init);
    exit(1);
    break;
  }
}
