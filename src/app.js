const express = require('express');
const cors = require('cors');
const eventosRouter = require('./eventos.routes');
const { ping } = require('./db');
const { errorHandler } = require('./errors');

const app = express();

app.disable('x-powered-by');
app.use(cors());
app.use(express.json({ limit: '100kb' }));

app.get('/', (req, res) => {
  res.status(200).json({
    api: 'API de Agenda',
    version: '1.0.0',
    recursos: {
      eventos: '/eventos',
      salud: '/health',
    },
  });
});

app.get('/health', async (req, res) => {
  try {
    await ping();
    res.status(200).json({ status: 'ok', database: 'ok' });
  } catch (error) {
    console.error('[health] MySQL no disponible:', error.message);
    res.status(503).json({ status: 'error', database: 'unavailable' });
  }
});

app.use('/eventos', eventosRouter);

app.use((req, res) => {
  res.status(404).json({ error: 'Ruta no encontrada' });
});

app.use(errorHandler);

module.exports = app;
