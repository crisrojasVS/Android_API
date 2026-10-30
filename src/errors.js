class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.name = 'HttpError';
    this.status = status;
  }
}

function errorHandler(error, req, res, next) {
  if (res.headersSent) {
    return next(error);
  }

  if (error instanceof HttpError) {
    return res.status(error.status).json({ error: error.message });
  }

  if (error.type === 'entity.parse.failed') {
    return res.status(400).json({ error: 'El cuerpo de la petición debe ser JSON válido' });
  }

  if (error.type === 'entity.too.large') {
    return res.status(413).json({ error: 'El cuerpo de la petición es demasiado grande' });
  }

  if (
    error.code === 'ER_TRUNCATED_WRONG_VALUE' ||
    error.code === 'WARN_DATA_TRUNCATED' ||
    error.code === 'ER_WARN_DATA_OUT_OF_RANGE'
  ) {
    return res.status(400).json({ error: 'Datos inválidos' });
  }

  console.error('[error]', error);
  return res.status(500).json({ error: 'Error interno del servidor' });
}

module.exports = { HttpError, errorHandler };
