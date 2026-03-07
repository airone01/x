import c from 'chalk';

enum Color {
  YELLOW = '#ffbe0b',
  ORANGE = '#fb5607',
  PINK = '#ff006e',
  BLURPLE = '#8338ec',
  BLUE = '#3a86ff',
}
const blurple = (input: string) => c.hex(Color.BLURPLE).bold(input);
const blue = (input: string) => c.hex(Color.BLUE).bold(input);
const pink = (input: string) => c.hex(Color.PINK).bold(input);
const orange = (input: string) => c.hex(Color.ORANGE).bold(input);
const gray = (input: string) => c.gray(input);
const bold = (input: string) => c.bold(input);

enum DirectoryType {
  CLASSIC,
}

enum NodePackageManager {
  NPM,
  YARN,
  PNPM,
  BUN,
  NOTHING,
}

export {
  Color, blue, blurple, bold, gray, orange, pink, DirectoryType, NodePackageManager,
};
