// eslint-disable-next-line import/no-extraneous-dependencies
import { app } from 'electron';
import configureAppIdentity from './appIdentity.js';

configureAppIdentity(app);
