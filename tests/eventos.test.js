const { test, after } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const app = require('../src/app');
const { pool } = require('../src/db');

const SUFIJO = `${Date.now()}-${Math.floor(Math.random() * 1000)}`;
const PREFIJO = `TEST-API ${SUFIJO}`;
const FECHA_A = '2030-05-15';
const FECHA_B = '2030-05-20';
const FECHA_C = '2030-06-01';

function datosEvento(overrides = {}) {
  return {
    titulo: `${PREFIJO} Dentista`,
    tipo: 'cita',
    fecha: FECHA_A,
    hora: '16:30',
    descripcion: 'Revision general',
    ...overrides,
  };
}

async function crearEvento(overrides = {}) {
  const respuesta = await request(app).post('/eventos').send(datosEvento(overrides));

  assert.equal(respuesta.status, 201, JSON.stringify(respuesta.body));
  assert.equal(typeof respuesta.body.id, 'number');

  return respuesta.body;
}

after(async () => {
  try {
    await pool.query('DELETE FROM eventos WHERE titulo LIKE ?', ['TEST-API %']);
  } finally {
    await pool.end();
  }
});

test('GET / devuelve la informacion basica de la API', async () => {
  const respuesta = await request(app).get('/');

  assert.equal(respuesta.status, 200);
  assert.equal(respuesta.body.api, 'API de Agenda');
  assert.equal(respuesta.body.recursos.eventos, '/eventos');
});

test('GET /health confirma la conexion con MySQL', async () => {
  const respuesta = await request(app).get('/health');

  assert.equal(respuesta.status, 200);
  assert.deepEqual(respuesta.body, { status: 'ok', database: 'ok' });
});

test('POST /eventos crea un evento y devuelve 201 con el id', async () => {
  const datos = datosEvento({ titulo: `${PREFIJO} Dentista` });
  const respuesta = await request(app).post('/eventos').send(datos);

  assert.equal(respuesta.status, 201);
  assert.match(respuesta.headers['content-type'], /application\/json/);
  assert.equal(respuesta.headers.location, `/eventos/${respuesta.body.id}`);
  assert.deepEqual(respuesta.body, {
    id: respuesta.body.id,
    titulo: datos.titulo,
    tipo: 'cita',
    fecha: FECHA_A,
    hora: '16:30',
    descripcion: 'Revision general',
  });

  const consulta = await request(app).get(`/eventos/${respuesta.body.id}`);

  assert.equal(consulta.status, 200);
  assert.deepEqual(consulta.body, respuesta.body);
});

test('GET /eventos devuelve una lista ordenada por fecha y hora', async () => {
  const respuesta = await request(app).get('/eventos');

  assert.equal(respuesta.status, 200);
  assert.ok(Array.isArray(respuesta.body));

  const claves = respuesta.body.map((evento) => `${evento.fecha} ${evento.hora ?? ''}`);

  assert.deepEqual(claves, [...claves].sort());
});

test('GET /eventos?fecha= busca por fecha y ordena por hora', async () => {
  const tarde = await crearEvento({
    titulo: `${PREFIJO} Tarde`,
    fecha: FECHA_B,
    hora: '17:00',
  });
  const manana = await crearEvento({
    titulo: `${PREFIJO} Manana`,
    fecha: FECHA_B,
    hora: '08:00',
  });

  const respuesta = await request(app).get('/eventos').query({ fecha: FECHA_B });

  assert.equal(respuesta.status, 200);
  assert.ok(Array.isArray(respuesta.body));
  assert.ok(respuesta.body.every((evento) => evento.fecha === FECHA_B));

  const ids = respuesta.body.map((evento) => evento.id);
  assert.ok(ids.includes(tarde.id));
  assert.ok(ids.includes(manana.id));

  const horas = respuesta.body.map((evento) => evento.hora);
  assert.deepEqual(horas, [...horas].sort());
});

test('GET /eventos?fecha= devuelve lista vacia si no hay eventos', async () => {
  const respuesta = await request(app).get('/eventos').query({ fecha: '2031-12-31' });

  assert.equal(respuesta.status, 200);
  assert.deepEqual(respuesta.body, []);
});

test('GET /eventos?titulo= busca de forma parcial y sin distinguir mayusculas', async () => {
  const evento = await crearEvento({
    titulo: `${PREFIJO} Odontologo`,
    fecha: FECHA_C,
    hora: '10:15',
  });

  const busqueda = `test-api ${SUFIJO} odont`;
  const respuesta = await request(app).get('/eventos').query({ titulo: busqueda });

  assert.equal(respuesta.status, 200);

  const encontrado = respuesta.body.find((item) => item.id === evento.id);

  assert.ok(encontrado, 'El evento debe aparecer en la busqueda por titulo');
  assert.equal(encontrado.fecha, FECHA_C);
});

test('GET /eventos combina los filtros de fecha y titulo', async () => {
  const objetivo = await crearEvento({
    titulo: `${PREFIJO} Combinado`,
    fecha: '2030-07-01',
    hora: '11:00',
  });
  await crearEvento({
    titulo: `${PREFIJO} Combinado`,
    fecha: '2030-07-02',
    hora: '11:00',
  });

  const respuesta = await request(app)
    .get('/eventos')
    .query({ fecha: '2030-07-01', titulo: `test-api ${SUFIJO} combinado` });

  assert.equal(respuesta.status, 200);
  assert.equal(respuesta.body.length, 1);
  assert.equal(respuesta.body[0].id, objetivo.id);
});

test('GET /eventos/:id consulta un evento y devuelve 404 si no existe', async () => {
  const evento = await crearEvento();
  const respuesta = await request(app).get(`/eventos/${evento.id}`);

  assert.equal(respuesta.status, 200);
  assert.deepEqual(respuesta.body, evento);

  const noExiste = await request(app).get('/eventos/2147483000');

  assert.equal(noExiste.status, 404);
  assert.equal(noExiste.body.error, 'No existe un evento con el id 2147483000');
});

test('GET /eventos/:id rechaza un id invalido con 400', async () => {
  for (const id of ['abc', '0', '-1', '1.5']) {
    const respuesta = await request(app).get(`/eventos/${id}`);

    assert.equal(respuesta.status, 400);
    assert.equal(typeof respuesta.body.error, 'string');
  }
});

test('PUT /eventos/:id actualiza todos los campos', async () => {
  const evento = await crearEvento({ titulo: `${PREFIJO} Para editar` });
  const cambios = {
    titulo: `${PREFIJO} Editado`,
    tipo: 'evento',
    fecha: '2030-08-09',
    hora: '07:05',
    descripcion: 'Cita reprogramada',
  };

  const respuesta = await request(app).put(`/eventos/${evento.id}`).send(cambios);

  assert.equal(respuesta.status, 200);
  assert.deepEqual(respuesta.body, { id: evento.id, ...cambios });

  const sinHora = {
    titulo: `${PREFIJO} Editado sin hora`,
    tipo: 'cita',
    fecha: '2030-08-10',
    hora: null,
    descripcion: null,
  };

  const segunda = await request(app).put(`/eventos/${evento.id}`).send(sinHora);

  assert.equal(segunda.status, 200);
  assert.equal(segunda.body.hora, null);
  assert.equal(segunda.body.descripcion, null);

  const consulta = await request(app).get(`/eventos/${evento.id}`);

  assert.deepEqual(consulta.body, segunda.body);
});

test('PUT /eventos/:id valida los datos antes de actualizar', async () => {
  const evento = await crearEvento({ titulo: `${PREFIJO} Edicion invalida` });
  const respuesta = await request(app)
    .put(`/eventos/${evento.id}`)
    .send({ titulo: '   ', tipo: 'cita', fecha: FECHA_A });

  assert.equal(respuesta.status, 400);
  assert.equal(typeof respuesta.body.error, 'string');

  const consulta = await request(app).get(`/eventos/${evento.id}`);

  assert.equal(consulta.body.titulo, evento.titulo);
});

test('PUT /eventos/:id devuelve 404 si el id no existe', async () => {
  const respuesta = await request(app).put('/eventos/2147483000').send(datosEvento());

  assert.equal(respuesta.status, 404);
  assert.equal(typeof respuesta.body.error, 'string');
});

test('DELETE /eventos/:id elimina y devuelve 204', async () => {
  const evento = await crearEvento({ titulo: `${PREFIJO} Para borrar` });
  const respuesta = await request(app).delete(`/eventos/${evento.id}`);

  assert.equal(respuesta.status, 204);
  assert.equal(respuesta.text, '');

  const consulta = await request(app).get(`/eventos/${evento.id}`);
  assert.equal(consulta.status, 404);

  const otraVez = await request(app).delete(`/eventos/${evento.id}`);
  assert.equal(otraVez.status, 404);
});

test('POST /eventos valida los datos obligatorios y los formatos', async (t) => {
  const casos = [
    ['sin cuerpo', undefined],
    ['sin titulo', { tipo: 'cita', fecha: FECHA_A }],
    ['titulo vacio', { titulo: '   ', tipo: 'cita', fecha: FECHA_A }],
    ['titulo demasiado largo', { titulo: 'x'.repeat(101), tipo: 'cita', fecha: FECHA_A }],
    ['sin tipo', { titulo: 'Evento', fecha: FECHA_A }],
    ['tipo invalido', { titulo: 'Evento', tipo: 'reunion', fecha: FECHA_A }],
    ['sin fecha', { titulo: 'Evento', tipo: 'evento' }],
    ['fecha con formato invalido', { titulo: 'Evento', tipo: 'evento', fecha: '15-05-2030' }],
    ['fecha inexistente', { titulo: 'Evento', tipo: 'evento', fecha: '2030-02-30' }],
    ['hora con formato invalido', { titulo: 'Evento', tipo: 'evento', fecha: FECHA_A, hora: '9:00' }],
    ['hora fuera de rango', { titulo: 'Evento', tipo: 'evento', fecha: FECHA_A, hora: '25:00' }],
    ['descripcion no es texto', { titulo: 'Evento', tipo: 'evento', fecha: FECHA_A, descripcion: 42 }],
  ];

  for (const [nombre, datos] of casos) {
    await t.test(nombre, async () => {
      const peticion = request(app).post('/eventos');
      const respuesta = datos === undefined ? await peticion : await peticion.send(datos);

      assert.equal(respuesta.status, 400);
      assert.equal(typeof respuesta.body.error, 'string');
    });
  }
});

test('POST /eventos rechaza un JSON mal formado con 400', async () => {
  const respuesta = await request(app)
    .post('/eventos')
    .set('Content-Type', 'application/json')
    .send('{"titulo":');

  assert.equal(respuesta.status, 400);
  assert.equal(typeof respuesta.body.error, 'string');
});

test('GET /eventos?fecha= rechaza fechas invalidas con 400', async () => {
  for (const fecha of ['2030-02-30', '30-02-2030', '2030-13-01', '']) {
    const respuesta = await request(app).get('/eventos').query({ fecha });

    assert.equal(respuesta.status, 400);
    assert.equal(typeof respuesta.body.error, 'string');
  }
});
