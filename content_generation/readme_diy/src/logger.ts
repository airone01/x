import {createLogger, format, transports} from 'winston';
import {consoleFormat} from 'winston-console-format';

const logger = createLogger({
  format: format.combine(
    format.ms(),
    format.errors({stack: true}),
    format.splat(),
    format.json(),
  ),
  transports: [
    new transports.Console({
      format: format.combine(
        format.colorize({all: true}),
        // Format.padLevels(),
        consoleFormat(),
      ),
    }),
  ],
});

export {logger};
