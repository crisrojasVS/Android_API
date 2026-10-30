const path = require('node:path');

require('dotenv').config({
  path: path.join(__dirname, '..', '.env'),
  quiet: true,
});

function enteroPositivo(nombre, valorPorDefecto) {
  const valor = process.env[nombre] ?? String(valorPorDefecto);
  const numero = Number(valor);

  if (!Number.isInteger(numero) || numero <= 0) {
    throw new Error(`La variable de entorno ${nombre} debe ser un numero entero positivo`);
  }

  return numero;
}

const config = {
  port: enteroPositivo('PORT', 3000),
  host: process.env.HOST || '0.0.0.0',
  db: {
    host: process.env.DB_HOST || '127.0.0.1',
    port: enteroPositivo('DB_PORT', 3306),
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD ?? '',
    database: process.env.DB_NAME || 'agenda',
    connectionLimit: enteroPositivo('DB_CONNECTION_LIMIT', 10),
  },
};

module.exports = config;
