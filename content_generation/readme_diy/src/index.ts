import {logger} from './logger';
import {registerServer} from './server';

const server = registerServer();
logger.info('✨ Server is running', {port: server.port});
