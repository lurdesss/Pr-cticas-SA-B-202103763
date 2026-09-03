-- Una base de datos por microservicio. Ningun servicio puede leer las
-- tablas de otro: si necesita un dato ajeno, lo pide por la API.
CREATE DATABASE auth_db;
CREATE DATABASE catalogo_db;
CREATE DATABASE inventario_db;
CREATE DATABASE pedidos_db;
CREATE DATABASE resenas_db;
