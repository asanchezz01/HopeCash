import 'dotenv/config';

const mysql = {
  client: 'mysql2',
  connection: {
    host: process.env.DB_HOST || 'localhost',
    port: Number(process.env.DB_PORT || 3306),
    user: process.env.DB_USER || 'hopecash',
    password: process.env.DB_PASSWORD || 'hopecash',
    database: process.env.DB_NAME || 'hopecash',
    dateStrings: true,
    decimalNumbers: true,
    charset: 'utf8mb4',
  },
  pool: { min: 2, max: 10 },
  migrations: { directory: './src/db/migrations' },
  seeds: { directory: './src/db/seeds' },
};

export default {
  development: mysql,
  production: mysql,
  test: {
    client: 'better-sqlite3',
    connection: { filename: ':memory:' },
    useNullAsDefault: true,
    migrations: { directory: './src/db/migrations' },
    seeds: { directory: './src/db/seeds' },
    pool: { min: 1, max: 1 },
  },
};
