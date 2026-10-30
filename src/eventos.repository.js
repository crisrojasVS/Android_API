const { pool } = require('./db');

const CAMPOS = `
  id,
  titulo,
  tipo,
  DATE_FORMAT(fecha, '%Y-%m-%d') AS fecha,
  TIME_FORMAT(hora, '%H:%i') AS hora,
  descripcion
`;

function escaparLike(texto) {
  return texto.replace(/[!%_]/g, '!$&');
}

async function listar({ fecha, titulo } = {}) {
  const condiciones = [];
  const parametros = [];

  if (fecha) {
    condiciones.push('fecha = ?');
    parametros.push(fecha);
  }

  if (titulo) {
    condiciones.push("LOWER(titulo) LIKE LOWER(?) ESCAPE '!'");
    parametros.push(`%${escaparLike(titulo)}%`);
  }

  const where = condiciones.length > 0 ? ` WHERE ${condiciones.join(' AND ')}` : '';
  const sql = `SELECT ${CAMPOS} FROM eventos${where} ORDER BY fecha ASC, hora ASC, id ASC`;
  const [filas] = await pool.execute(sql, parametros);

  return filas;
}

async function obtenerPorId(id) {
  const [filas] = await pool.execute(`SELECT ${CAMPOS} FROM eventos WHERE id = ?`, [id]);

  return filas[0] ?? null;
}

async function crear(evento) {
  const [resultado] = await pool.execute(
    'INSERT INTO eventos (titulo, tipo, fecha, hora, descripcion) VALUES (?, ?, ?, ?, ?)',
    [evento.titulo, evento.tipo, evento.fecha, evento.hora, evento.descripcion]
  );

  return obtenerPorId(resultado.insertId);
}

async function actualizar(id, evento) {
  await pool.execute(
    'UPDATE eventos SET titulo = ?, tipo = ?, fecha = ?, hora = ?, descripcion = ? WHERE id = ?',
    [evento.titulo, evento.tipo, evento.fecha, evento.hora, evento.descripcion, id]
  );

  return obtenerPorId(id);
}

async function eliminar(id) {
  const [resultado] = await pool.execute('DELETE FROM eventos WHERE id = ?', [id]);

  return resultado.affectedRows > 0;
}

module.exports = {
  listar,
  obtenerPorId,
  crear,
  actualizar,
  eliminar,
};
