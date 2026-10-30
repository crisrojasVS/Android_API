const { HttpError } = require('./errors');

const TIPOS_VALIDOS = new Set(['cita', 'evento']);
const REGEX_FECHA = /^(\d{4})-(\d{2})-(\d{2})$/;
const REGEX_HORA = /^([01]\d|2[0-3]):[0-5]\d$/;
const MAX_TITULO = 100;
const MAX_DESCRIPCION = 255;
const MAX_ID_MYSQL = 2147483647;

function esFechaValida(fecha) {
  const coincidencia = REGEX_FECHA.exec(fecha);

  if (!coincidencia) {
    return false;
  }

  const anio = Number(coincidencia[1]);
  const mes = Number(coincidencia[2]);
  const dia = Number(coincidencia[3]);

  if (anio < 1000 || anio > 9999 || mes < 1 || mes > 12 || dia < 1 || dia > 31) {
    return false;
  }

  const fechaUtc = new Date(Date.UTC(anio, mes - 1, dia));

  return (
    fechaUtc.getUTCFullYear() === anio &&
    fechaUtc.getUTCMonth() === mes - 1 &&
    fechaUtc.getUTCDate() === dia
  );
}

function esHoraValida(hora) {
  return REGEX_HORA.test(hora);
}

function validarEvento(body) {
  if (body === undefined || body === null || typeof body !== 'object' || Array.isArray(body)) {
    throw new HttpError(400, 'El cuerpo de la petición debe ser un objeto JSON');
  }

  const { titulo, tipo, fecha, hora, descripcion } = body;

  if (typeof titulo !== 'string' || titulo.trim() === '') {
    throw new HttpError(400, "El campo 'titulo' es obligatorio y no puede estar vacío");
  }

  const tituloLimpio = titulo.trim();

  if (tituloLimpio.length > MAX_TITULO) {
    throw new HttpError(400, `El campo 'titulo' no puede superar los ${MAX_TITULO} caracteres`);
  }

  if (typeof tipo !== 'string' || !TIPOS_VALIDOS.has(tipo.trim())) {
    throw new HttpError(400, "El campo 'tipo' es obligatorio y solo acepta 'cita' o 'evento'");
  }

  const tipoLimpio = tipo.trim();

  if (typeof fecha !== 'string' || !esFechaValida(fecha)) {
    throw new HttpError(400, "El campo 'fecha' debe tener el formato AAAA-MM-DD y ser una fecha válida");
  }

  let horaLimpia = null;

  if (hora !== undefined && hora !== null) {
    if (typeof hora !== 'string' || !esHoraValida(hora)) {
      throw new HttpError(400, "El campo 'hora' debe tener el formato HH:mm");
    }

    horaLimpia = hora;
  }

  let descripcionLimpia = null;

  if (descripcion !== undefined && descripcion !== null) {
    if (typeof descripcion !== 'string') {
      throw new HttpError(400, "El campo 'descripcion' debe ser un texto");
    }

    const descripcionRecortada = descripcion.trim();

    if (descripcionRecortada.length > MAX_DESCRIPCION) {
      throw new HttpError(
        400,
        `El campo 'descripcion' no puede superar los ${MAX_DESCRIPCION} caracteres`
      );
    }

    descripcionLimpia = descripcionRecortada === '' ? null : descripcionRecortada;
  }

  return {
    titulo: tituloLimpio,
    tipo: tipoLimpio,
    fecha,
    hora: horaLimpia,
    descripcion: descripcionLimpia,
  };
}

function validarFiltros(query) {
  const filtros = {};

  if (query.fecha !== undefined) {
    if (typeof query.fecha !== 'string' || !esFechaValida(query.fecha)) {
      throw new HttpError(
        400,
        "El parámetro 'fecha' debe tener el formato AAAA-MM-DD y ser una fecha válida"
      );
    }

    filtros.fecha = query.fecha;
  }

  if (query.titulo !== undefined) {
    if (typeof query.titulo !== 'string') {
      throw new HttpError(400, "El parámetro 'titulo' debe ser un texto");
    }

    const titulo = query.titulo.trim();

    if (titulo !== '') {
      filtros.titulo = titulo;
    }
  }

  return filtros;
}

function validarId(valor) {
  if (typeof valor !== 'string' || !/^[1-9]\d*$/.test(valor)) {
    throw new HttpError(400, 'El id debe ser un número entero positivo');
  }

  const id = Number(valor);

  if (!Number.isSafeInteger(id) || id > MAX_ID_MYSQL) {
    throw new HttpError(400, 'El id debe ser un número entero positivo');
  }

  return id;
}

module.exports = {
  validarEvento,
  validarFiltros,
  validarId,
};
