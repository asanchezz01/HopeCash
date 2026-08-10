import knex from 'knex';
import knexConfig from '../../knexfile.js';
import { config } from '../config.js';

export const db = knex(knexConfig[config.env] || knexConfig.development);
