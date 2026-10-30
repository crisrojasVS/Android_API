const app = require('./app');
const config = require('./config');
const { pool, ping } = require('./db');

async function iniciar() {
  try {
    await ping();
    console.log(
      `Conexion a MySQL OK (${config.db.host}:${config.db.port}/${config.db.database})`
    );
  } catch (error) {
    console.error('No se pudo conectar a MySQL:', error.message);
    console.error('Revisa las variables DB_* del archivo .env y que el servicio MySQL este activo.');
    process.exit(1);
  }

  const servidor = app.listen(config.port, config.host, () => {
    console.log(`API de Agenda escuchando en http://${config.host}:${config.port}`);
    console.log(`Prueba rapida: http://localhost:${config.port}/eventos`);
  });

  let cerrando = false;

  function cerrar(senal) {
    if (cerrando) {
      return;
    }

    cerrando = true;
    console.log(`\n${senal} recibido, cerrando la API...`);

    servidor.close(async () => {
      try {
        await pool.end();
      } catch (error) {
        console.error('Error al cerrar MySQL:', error.message);
      }

      process.exit(0);
    });

    setTimeout(() => process.exit(1), 5000).unref();
  }

  process.on('SIGINT', () => cerrar('SIGINT'));
  process.on('SIGTERM', () => cerrar('SIGTERM'));
}

iniciar();
