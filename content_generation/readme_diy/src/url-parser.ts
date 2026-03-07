import levenshtein from 'fast-levenshtein';
import colorNameList from 'color-name-list';
import {logger} from './logger';

const colorsMap = Object.fromEntries(colorNameList
  .map(({name, hex}) => [name.toLowerCase(), hex]));
const transformColor = (color: string) => colorsMap[color].slice(1);
const nearest = (search: string) => {
  let bestColor = '#b86fc2';
  let minDistribution = 100;
  const searchL = search.toLowerCase();

  for (const color in colorsMap) {
    const distribution = levenshtein.get(color, searchL);
    if (distribution == 0) {
      return transformColor(color);
    }

    if (distribution < minDistribution) {
      bestColor = color;
      minDistribution = distribution;
    }
  }

  return (transformColor(bestColor));
};

export function parseUrl(request) {
  const url = new URL(request.url);
  // For later: search params here
  const {searchParams} = url;
  const basicCommand = getBasicCommand(url);
  const {label, message, color} = getCommand(basicCommand);
  let finalColor: string | undefined = color;
  if (color === undefined) {
    finalColor = 'b86fc2';
  }

  if (color != undefined && color[0] !== '#') {
    finalColor = nearest(color);
  }

  return {label, message, color: finalColor};
}

export type Command = {
  label: string;
  message?: string;
  color?: string;
};

function getCommand(basic: string): Command {
  const [label, message, color] = handleDashes(basic);

  return {label, message, color};
}

function getBasicCommand(url: URL): string {
  const array = url.pathname.split('/');
  return handleUnderscores(array.at(-1));
}

function handleDashes(string_: string): string[] {
  const withPlaceholder = string_.replaceAll('--', '█'); // Using a special character as placeholder
  const splits = withPlaceholder.split('-');
  return splits.map(element => element.replaceAll('█', '-'));
}

function handleUnderscores(string_: string): string {
  return string_
    .replaceAll(/([^_])(_)([^_])/gm, '$1 $3')
    .replaceAll(/%20/gm, ' ')
    .replaceAll(/__/gm, '_');
}
