import {logger} from './logger';
import {badgen} from './badgen';
import {parseUrl, type Command} from './url-parser';

export function registerServer() {
  return Bun.serve({
    fetch(request, server) {
      const {label, message, color} = parseUrl(request);

      logger.verbose('Badge request', {label});
      const badge = badgen({
        status: message ?? label,
        label: message == undefined ? undefined : label,
        color,
      });
      return new Response(badge, {
        headers: {
          'Content-Type': 'image/svg+xml',
        },
      });
    },
  });
}
