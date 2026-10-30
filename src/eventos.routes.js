const express = require('express');
const {
  listar,
  obtenerPorId,
  crear,
  actualizar,
  eliminar,
} = require('./eventos.repository');
const { validarEvento, validarFiltros, validarId } = require('./eventos.validators');
const { HttpError } = require('./errors');

const router = express.Router();

router.get('/', async (req, res) => {
  const filtros = validarFiltros(req.query);
  const eventos = await listar(filtros);

  res.status(200).json(eventos);
});

router.post('/', async (req, res) => {
  const datos = validarEvento(req.body);
  const evento = await crear(datos);

  res.status(201).location(`/eventos/${evento.id}`).json(evento);
});

router.get('/:id', async (req, res) => {
  const id = validarId(req.params.id);
  const evento = await obtenerPorId(id);

  if (!evento) {
    throw new HttpError(404, `No existe un evento con el id ${id}`);
  }

  res.status(200).json(evento);
});

router.put('/:id', async (req, res) => {
  const id = validarId(req.params.id);
  const datos = validarEvento(req.body);
  const evento = await actualizar(id, datos);

  if (!evento) {
    throw new HttpError(404, `No existe un evento con el id ${id}`);
  }

  res.status(200).json(evento);
});

router.delete('/:id', async (req, res) => {
  const id = validarId(req.params.id);
  const eliminado = await eliminar(id);

  if (!eliminado) {
    throw new HttpError(404, `No existe un evento con el id ${id}`);
  }

  res.status(204).end();
});

module.exports = router;
