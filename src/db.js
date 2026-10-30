const mysql = require('mysql2/promise');
const config = require('./config');

const pool = mysql.createPool({
  host: config.db.host,
  port: config.db.port,
  user: config.db.user,
  password: config.db.password,
  database: config.db.database,
  waitForConnections: true,
  connectionLimit: config.db.connectionLimit,
  queueLimit: 0,
  dateStrings: true,
  charset: 'utf8mb4',
  enableKeepAlive: true,
});

async function ping() {
  await pool.query('SELECT 1');
}

module.exports = { pool, ping };
