const fs = require('node:fs');
const path = require('node:path');
const mysql = require('mysql2/promise');
const config = require('../src/config');

const RUTA_SQL = path.join(__dirname, '..', 'database', 'agenda.sql');

function dividirSentencias(sql) {
  return sql
    .split(/\r?\n/)
    .filter((linea) => !linea.trim().startsWith('--'))
    .join('\n')
    .split(';')
    .map((sentencia) => sentencia.trim())
    .filter(Boolean);
}

async function main() {
  if (!fs.existsSync(RUTA_SQL)) {
    throw new Error(`No se encontro el archivo SQL en ${RUTA_SQL}`);
  }

  const sentencias = dividirSentencias(fs.readFileSync(RUTA_SQL, 'utf8'));
  const conexion = await mysql.createConnection({
    host: config.db.host,
    port: config.db.port,
    user: config.db.user,
    password: config.db.password,
  });

  try {
    console.log(`Inicializando base de datos en ${config.db.host}:${config.db.port}...`);

    for (const sentencia of sentencias) {
      const resumen = sentencia.replace(/\s+/g, ' ').slice(0, 100);

      if (/^INSERT\s+INTO\s+eventos/i.test(sentencia)) {
        const [filas] = await conexion.query('SELECT COUNT(*) AS total FROM agenda.eventos');

        if (Number(filas[0].total) > 0) {
          console.log('Datos de prueba: se omiten porque la tabla ya tiene eventos.');
          continue;
        }
      }

      try {
        await conexion.query(sentencia);
        console.log(`OK: ${resumen}`);
      } catch (error) {
        if (error.code === 'ER_DUP_KEYNAME') {
          console.log(`OK (el indice ya existia): ${resumen}`);
          continue;
        }

        throw error;
      }
    }

    console.log('Base de datos lista.');
  } finally {
    await conexion.end();
  }
}

main().catch((error) => {
  console.error('No se pudo inicializar la base de datos:', error.message);
  process.exit(1);
});
