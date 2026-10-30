-- =====================================================
-- Base de datos: agenda (citas y eventos)
-- Motor: MySQL
-- =====================================================

-- 1. Crear la base de datos y usarla
CREATE DATABASE IF NOT EXISTS agenda;
USE agenda;

-- 2. Tabla de eventos (una cita y un evento son lo mismo, el campo "tipo" los distingue)
CREATE TABLE IF NOT EXISTS eventos (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    titulo      VARCHAR(100) NOT NULL,
    tipo        ENUM('cita', 'evento') NOT NULL,
    fecha       DATE NOT NULL,
    hora        TIME NULL,
    descripcion VARCHAR(255) NULL
);

-- 3. Indice para que la busqueda por fecha sea rapida
CREATE INDEX idx_eventos_fecha ON eventos (fecha);

-- 4. Datos de prueba
INSERT INTO eventos (titulo, tipo, fecha, hora, descripcion) VALUES
('Dentista',          'cita',   '2026-11-05', '16:30:00', 'Revision general'),
('Examen de Moviles', 'evento', '2026-11-12', '09:00:00', NULL),
('Junta de equipo',   'evento', '2026-11-12', '12:00:00', 'Avance del proyecto'),
('Cita con el doctor','cita',   '2026-11-20', NULL,       NULL);

-- =====================================================
-- Consultas que usara la API (una por endpoint)
-- =====================================================

-- POST /eventos          -> crear
-- INSERT INTO eventos (titulo, tipo, fecha, hora, descripcion)
-- VALUES ('Dentista', 'cita', '2026-11-05', '16:30:00', 'Revision general');

-- GET /eventos           -> listar todos
-- SELECT * FROM eventos ORDER BY fecha, hora;

-- GET /eventos?fecha=... -> buscar por fecha
-- SELECT * FROM eventos WHERE fecha = '2026-11-12' ORDER BY hora;

-- GET /eventos?titulo=... -> buscar por titulo (parcial)
-- SELECT * FROM eventos WHERE titulo LIKE '%dent%' ORDER BY fecha, hora;

-- GET /eventos/{id}      -> consultar uno
-- SELECT * FROM eventos WHERE id = 1;

-- PUT /eventos/{id}      -> editar
-- UPDATE eventos
-- SET titulo = 'Dentista', tipo = 'cita', fecha = '2026-11-07', hora = '10:00:00', descripcion = 'Cita reprogramada'
-- WHERE id = 1;

-- DELETE /eventos/{id}   -> eliminar
-- DELETE FROM eventos WHERE id = 1;
