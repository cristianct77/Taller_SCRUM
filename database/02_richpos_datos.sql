-- =====================================================================
--  RichPOS - Datos iniciales y de prueba (ejecutar después del DDL)
--  Contraseña de todos los usuarios de prueba: Rich2026*
-- =====================================================================
SET NAMES utf8mb4;
USE richpos;

INSERT INTO sede (nombre, direccion, ciudad, telefono) VALUES
 ('Pollería Rich - Principal', 'Local principal', 'Bogotá D.C.', '3000000000');

INSERT INTO parametro (clave, valor, descripcion) VALUES
 ('TEMP_MIN_CORTE_C', '0.0',   'Temperatura mínima aceptada para un corte refrigerado (°C)'),
 ('TEMP_MAX_CORTE_C', '4.0',   'Temperatura máxima aceptada para un corte refrigerado (°C)'),
 ('VALOR_DOMICILIO',  '4000',  'Valor del domicilio en pesos'),
 ('MAX_INTENTOS_LOGIN','2',    'Intentos de autorización antes de terminar');

-- Catálogos de estados (diagramas de estado del documento)
INSERT INTO estado_pedido (codigo, nombre, orden) VALUES
 ('SOLICITADO','Solicitado',1), ('REGISTRADO','Registrado',2), ('CONFIRMADO','Confirmado',3),
 ('EN_PREPARACION','En preparación',4), ('DESPACHADO','Despachado',5), ('ENTREGADO','Entregado',6),
 ('PAGADO','Pagado',7), ('CANCELADO','Cancelado',8);

INSERT INTO estado_orden_compra (codigo, nombre, orden) VALUES
 ('GENERADA','Generada',1), ('EN_REVISION','En revisión',2),
 ('EN_GESTION_ALTERNATIVAS','En gestión de alternativas',3), ('APROBADA','Aprobada',4),
 ('AJUSTADA','Ajustada',5), ('ENVIADA','Enviada',6), ('RECIBIDA','Recibida',7);

INSERT INTO estado_lote (codigo, nombre, orden) VALUES
 ('RECIBIDO','Recibido',1), ('FRESCURA_VERIFICADA','Frescura verificada',2), ('PESADO','Pesado',3),
 ('ALMACENADO','Almacenado',4), ('AGOTADO','Agotado',5), ('DESCARTADO','Descartado',6);

INSERT INTO estado_paquete (codigo, nombre, orden) VALUES
 ('EMPACADO','Empacado',1), ('ROTULADO','Rotulado',2), ('EN_ZONA_DESPACHO','En zona de despacho',3),
 ('ASIGNADO','Asignado',4), ('DESPACHADO','Despachado',5), ('ENTREGADO','Entregado',6),
 ('EN_AJUSTE','En ajuste',7);

INSERT INTO rol (codigo, nombre) VALUES
 ('ADMIN','Administradora'), ('ATENCION_CLIENTE','Atención al Cliente'),
 ('AREA_OPERATIVA','Área Operativa'), ('CONTABILIDAD','Contabilidad y Finanzas'),
 ('DOMICILIARIO','Domiciliario'), ('CLIENTE','Cliente'), ('PROVEEDOR','Proveedor');

SET @h = 'pbkdf2$120000$1Tf+TDlnxcUZ3hNXCUZb7g==$qah+Ajfcdyse0BHcIxy/qi76aHmkj69EGoLMnYVSkmw=';
INSERT INTO usuario (nombre_usuario, nombre_completo, correo, clave_hash, id_rol, id_sede) VALUES
 ('leidy',        'Leidy (Administradora)',      'admin@rich.co',       @h, 1, 1),
 ('atencion',     'Laura Gómez',                 'atencion@rich.co',    @h, 2, 1),
 ('operativa',    'Andrés Pérez',                'operativa@rich.co',   @h, 3, 1),
 ('contabilidad', 'Marta Ruiz',                  'conta@rich.co',       @h, 4, 1),
 ('domiciliario', 'Jhon Suárez',                 'domi@rich.co',        @h, 5, 1),
 ('cliente',      'Carlos Medina',               'carlos@correo.co',    @h, 6, 1),
 ('inactivo',     'Usuario no autorizado',       NULL,                  @h, 2, 1);
UPDATE usuario SET autorizado = FALSE WHERE nombre_usuario = 'inactivo';

INSERT INTO cliente (id_usuario, tipo_persona, tipo_documento, num_documento, nombre, telefono, correo) VALUES
 (6,    'NATURAL',  'CC',  '79845612',    'Carlos Medina',             '3104567890', 'carlos@correo.co'),
 (NULL, 'JURIDICA', 'NIT', '900456123-1', 'Restaurante El Fogón S.A.S.','6017452310', 'compras@elfogon.co'),
 (NULL, 'NATURAL',  'CC',  '52123987',    'Sandra Rojas',              '3125558899', NULL);
INSERT INTO direccion_cliente (id_cliente, direccion, barrio, principal) VALUES
 (1, 'Calle 45 Sur # 23-10', 'Olaya', TRUE),
 (2, 'Cra 30 # 12-45',       'Ricaurte', TRUE),
 (3, 'Calle 1 # 20-15',      'Restrepo', TRUE);

INSERT INTO domiciliario (id_usuario, id_sede, nombre, telefono, placa_vehiculo) VALUES
 (5, 1, 'Jhon Suárez', '3201112233', 'ABC12D');

INSERT INTO proveedor (nit, razon_social, contacto, telefono, correo) VALUES
 ('860001234-5', 'Avícola La Granja S.A.S.', 'Pedro Lara',  '6014440000', 'ventas@lagranja.co'),
 ('900777888-2', 'Distribuidora Pollo Fresco', 'Ana Ríos',  '6013332211', 'pedidos@pollofresco.co');

INSERT INTO categoria_producto (nombre) VALUES ('Pollo entero'), ('Presas'), ('Menudencias');
INSERT INTO producto (codigo, nombre, descripcion, id_categoria, stock_minimo_kg) VALUES
 ('POL-ENT', 'Pollo entero', 'Pollo entero fresco',            1, 20),
 ('POL-PEC', 'Pechuga',      'Pechuga de pollo con hueso',     2, 10),
 ('POL-ALA', 'Alas',         'Alas de pollo',                  2, 8),
 ('POL-PIE', 'Piernas',      'Pierna pernil de pollo',         2, 10),
 ('POL-TRO', 'Trocitos',     'Trocitos de pollo para guiso',   2, 5),
 ('POL-MEN', 'Menudencias',  'Hígado, molleja y corazón',      3, 3);

INSERT INTO medio_pago (nombre) VALUES ('Efectivo'), ('Transferencia');

-- Precios vigentes por kg (datos de prueba, en pesos colombianos)
INSERT INTO precio_producto (id_producto, id_sede, precio_kg, id_usuario) VALUES
 (1, 1, 11000, 1), (2, 1, 16000, 1), (3, 1, 12000, 1),
 (4, 1, 13000, 1), (5, 1, 14000, 1), (6, 1,  8000, 1);

INSERT INTO almacen (id_sede, nombre, refrigerado, temperatura_objetivo_c) VALUES
 (1, 'Cuarto frío', TRUE, 2.0);

-- Stock inicial (lotes almacenados). Alas queda por debajo del mínimo.
INSERT INTO lote (codigo_lote, id_producto, id_almacen, fecha_vencimiento, peso_recibido_kg, peso_disponible_kg, frescura_ok, estado, id_usuario_recibe) VALUES
 ('L-INI-001', 1, 1, DATE_ADD(CURRENT_DATE, INTERVAL 5 DAY), 40, 40, TRUE, 'ALMACENADO', 3),
 ('L-INI-002', 2, 1, DATE_ADD(CURRENT_DATE, INTERVAL 5 DAY), 25, 25, TRUE, 'ALMACENADO', 3),
 ('L-INI-003', 3, 1, DATE_ADD(CURRENT_DATE, INTERVAL 5 DAY),  4,  4, TRUE, 'ALMACENADO', 3),
 ('L-INI-004', 4, 1, DATE_ADD(CURRENT_DATE, INTERVAL 5 DAY), 20, 20, TRUE, 'ALMACENADO', 3),
 ('L-INI-005', 5, 1, DATE_ADD(CURRENT_DATE, INTERVAL 5 DAY), 10, 10, TRUE, 'ALMACENADO', 3);
INSERT INTO movimiento_inventario (id_lote, tipo, cantidad_kg, referencia_tipo, id_usuario)
SELECT id_lote, 'ENTRADA', peso_recibido_kg, 'AJUSTE', 3 FROM lote;

-- Saldo inicial de caja (liquidez)
INSERT INTO movimiento_caja (id_sede, tipo, concepto, valor, referencia_tipo, id_usuario) VALUES
 (1, 'INGRESO', 'Saldo inicial de caja', 1500000, 'SALDO_INICIAL', 4);
