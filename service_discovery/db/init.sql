CREATE TABLE saludos (
    id SERIAL PRIMARY KEY,
    mensaje VARCHAR(255) NOT NULL
);

INSERT INTO saludos (mensaje) VALUES
('¡Hola! Espero que tengas un excelente día.'),
('¡Hola desde la arquitectura de tres capas!'),
('¡Saludos desde PostgreSQL!'),
('¡Bienvenido al laboratorio de virtualización!'),
('¡Tu solicitud viajó por varias máquinas virtuales!'),
('¡Todo funciona correctamente!'),
('¡Saludos desde el backend!'),
('¡La base de datos respondió correctamente!'),
('¡Excelente! Acabas de consultar una aplicación distribuida.'),
('¡Bienvenido a la infraestructura virtualizada!');