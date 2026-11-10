-- =====================================================================
--  RichPOS - Sistema de Gestión para Pollería "Rich"
--  DDL de la base de datos (MySQL 8.0+)
--
--  Diseño escalable:
--   * Multi-sede: toda operación (pedido, orden, almacén, precio, caja)
--     pertenece a una sede, para crecer a más puntos de venta.
--   * Catálogos de estados en tablas (no ENUM): nuevos estados sin ALTER.
--   * Precios con historial de vigencia por sede.
--   * Inventario por lotes + kardex (movimiento_inventario): trazabilidad
--     FIFO, vencimientos y stock calculado, sin contadores desnormalizados.
--   * Historial de estados de pedido y orden de compra (trazabilidad).
--   * Pagos y movimientos de caja separados del pedido (varios pagos,
--     liquidez calculada).
--   * Llaves BIGINT, dinero DECIMAL(14,2), pesos DECIMAL(10,3),
--     índices en todas las FK y en los campos de búsqueda frecuentes.
--   * Parámetros de negocio en tabla (umbral de temperatura, etc.).
-- =====================================================================

SET NAMES utf8mb4;
DROP DATABASE IF EXISTS richpos;
CREATE DATABASE richpos CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE richpos;

-- ---------------------------------------------------------------------
-- 1. Organización y parámetros
-- ---------------------------------------------------------------------
CREATE TABLE sede (
  id_sede        BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre         VARCHAR(80)  NOT NULL,
  direccion      VARCHAR(150) NOT NULL,
  ciudad         VARCHAR(60)  NOT NULL DEFAULT 'Bogotá D.C.',
  telefono       VARCHAR(20),
  activa         BOOLEAN      NOT NULL DEFAULT TRUE,
  creado_en      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT uk_sede_nombre UNIQUE (nombre)
) ENGINE=InnoDB;

CREATE TABLE parametro (
  clave          VARCHAR(50)  PRIMARY KEY,
  valor          VARCHAR(100) NOT NULL,
  descripcion    VARCHAR(200) NOT NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 2. Seguridad: roles y usuarios (Validación / VerificarAutorizacionUsuario)
-- ---------------------------------------------------------------------
CREATE TABLE rol (
  id_rol         SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  codigo         VARCHAR(30)  NOT NULL,
  nombre         VARCHAR(60)  NOT NULL,
  CONSTRAINT uk_rol_codigo UNIQUE (codigo)
) ENGINE=InnoDB;

CREATE TABLE usuario (
  id_usuario         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre_usuario     VARCHAR(40)  NOT NULL,
  nombre_completo    VARCHAR(100) NOT NULL,
  correo             VARCHAR(120),
  clave_hash         VARCHAR(200) NOT NULL,          -- PBKDF2: iteraciones:sal:hash
  id_rol             SMALLINT UNSIGNED NOT NULL,
  id_sede            BIGINT UNSIGNED NULL,           -- NULL = todas las sedes
  autorizado         BOOLEAN      NOT NULL DEFAULT TRUE,
  intentos_fallidos  TINYINT UNSIGNED NOT NULL DEFAULT 0,
  ultimo_acceso      DATETIME     NULL,
  creado_en          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT uk_usuario_nombre UNIQUE (nombre_usuario),
  CONSTRAINT fk_usuario_rol  FOREIGN KEY (id_rol)  REFERENCES rol(id_rol),
  CONSTRAINT fk_usuario_sede FOREIGN KEY (id_sede) REFERENCES sede(id_sede)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 3. Terceros: clientes, domiciliarios, proveedores
-- ---------------------------------------------------------------------
CREATE TABLE cliente (
  id_cliente      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_usuario      BIGINT UNSIGNED NULL,               -- si el cliente usa el sistema
  tipo_persona    VARCHAR(10)  NOT NULL,
  tipo_documento  VARCHAR(5)   NOT NULL,
  num_documento   VARCHAR(20)  NOT NULL,
  nombre          VARCHAR(120) NOT NULL,
  telefono        VARCHAR(20)  NOT NULL,
  correo          VARCHAR(120),
  creado_en       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT uk_cliente_doc UNIQUE (tipo_documento, num_documento),
  CONSTRAINT uk_cliente_usuario UNIQUE (id_usuario),
  CONSTRAINT ck_cliente_tipo_persona CHECK (tipo_persona IN ('NATURAL','JURIDICA')),
  CONSTRAINT ck_cliente_tipo_doc CHECK (tipo_documento IN ('CC','CE','NIT','PAS')),
  CONSTRAINT fk_cliente_usuario FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario)
) ENGINE=InnoDB;
CREATE INDEX ix_cliente_nombre ON cliente(nombre);
CREATE INDEX ix_cliente_telefono ON cliente(telefono);

CREATE TABLE direccion_cliente (
  id_direccion    BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_cliente      BIGINT UNSIGNED NOT NULL,
  direccion       VARCHAR(150) NOT NULL,
  barrio          VARCHAR(80),
  referencia      VARCHAR(150),
  principal       BOOLEAN      NOT NULL DEFAULT FALSE,
  CONSTRAINT fk_direccion_cliente FOREIGN KEY (id_cliente) REFERENCES cliente(id_cliente) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE domiciliario (
  id_domiciliario BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_usuario      BIGINT UNSIGNED NOT NULL,
  id_sede         BIGINT UNSIGNED NOT NULL,
  nombre          VARCHAR(100) NOT NULL,
  telefono        VARCHAR(20)  NOT NULL,
  placa_vehiculo  VARCHAR(10),
  disponible      BOOLEAN      NOT NULL DEFAULT TRUE,
  activo          BOOLEAN      NOT NULL DEFAULT TRUE,
  CONSTRAINT uk_domiciliario_usuario UNIQUE (id_usuario),
  CONSTRAINT fk_domiciliario_usuario FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario),
  CONSTRAINT fk_domiciliario_sede    FOREIGN KEY (id_sede)    REFERENCES sede(id_sede)
) ENGINE=InnoDB;

CREATE TABLE proveedor (
  id_proveedor    BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_usuario      BIGINT UNSIGNED NULL,
  nit             VARCHAR(20)  NOT NULL,
  razon_social    VARCHAR(120) NOT NULL,
  contacto        VARCHAR(100),
  telefono        VARCHAR(20)  NOT NULL,
  correo          VARCHAR(120),
  activo          BOOLEAN      NOT NULL DEFAULT TRUE,
  CONSTRAINT uk_proveedor_nit UNIQUE (nit),
  CONSTRAINT fk_proveedor_usuario FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 4. Catálogo de productos y precios
-- ---------------------------------------------------------------------
CREATE TABLE categoria_producto (
  id_categoria    SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre          VARCHAR(60) NOT NULL,
  CONSTRAINT uk_categoria_nombre UNIQUE (nombre)
) ENGINE=InnoDB;

CREATE TABLE producto (
  id_producto     BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  codigo          VARCHAR(20)  NOT NULL,
  nombre          VARCHAR(80)  NOT NULL,
  descripcion     VARCHAR(200),
  id_categoria    SMALLINT UNSIGNED NOT NULL,
  unidad_medida   VARCHAR(5)   NOT NULL DEFAULT 'KG',
  perecedero      BOOLEAN      NOT NULL DEFAULT TRUE,
  stock_minimo_kg DECIMAL(10,3) NOT NULL DEFAULT 0,
  activo          BOOLEAN      NOT NULL DEFAULT TRUE,
  CONSTRAINT uk_producto_codigo UNIQUE (codigo),
  CONSTRAINT ck_producto_unidad CHECK (unidad_medida IN ('KG','UND')),
  CONSTRAINT ck_producto_stock_min CHECK (stock_minimo_kg >= 0),
  CONSTRAINT fk_producto_categoria FOREIGN KEY (id_categoria) REFERENCES categoria_producto(id_categoria)
) ENGINE=InnoDB;

-- Precio por kg con historial de vigencia (vigente_hasta NULL = precio actual)
CREATE TABLE precio_producto (
  id_precio       BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_producto     BIGINT UNSIGNED NOT NULL,
  id_sede         BIGINT UNSIGNED NOT NULL,
  precio_kg       DECIMAL(14,2) NOT NULL,
  vigente_desde   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  vigente_hasta   DATETIME      NULL,
  id_usuario      BIGINT UNSIGNED NOT NULL,
  CONSTRAINT ck_precio_positivo CHECK (precio_kg > 0),
  CONSTRAINT fk_precio_producto FOREIGN KEY (id_producto) REFERENCES producto(id_producto),
  CONSTRAINT fk_precio_sede     FOREIGN KEY (id_sede)     REFERENCES sede(id_sede),
  CONSTRAINT fk_precio_usuario  FOREIGN KEY (id_usuario)  REFERENCES usuario(id_usuario)
) ENGINE=InnoDB;
CREATE INDEX ix_precio_vigente ON precio_producto(id_producto, id_sede, vigente_hasta);

-- ---------------------------------------------------------------------
-- 5. Catálogos de estados (diagramas de estado del análisis)
-- ---------------------------------------------------------------------
CREATE TABLE estado_pedido (
  codigo  VARCHAR(30) PRIMARY KEY,
  nombre  VARCHAR(40) NOT NULL,
  orden   TINYINT UNSIGNED NOT NULL
) ENGINE=InnoDB;

CREATE TABLE estado_orden_compra (
  codigo  VARCHAR(30) PRIMARY KEY,
  nombre  VARCHAR(40) NOT NULL,
  orden   TINYINT UNSIGNED NOT NULL
) ENGINE=InnoDB;

CREATE TABLE estado_lote (
  codigo  VARCHAR(30) PRIMARY KEY,
  nombre  VARCHAR(40) NOT NULL,
  orden   TINYINT UNSIGNED NOT NULL
) ENGINE=InnoDB;

CREATE TABLE estado_paquete (
  codigo  VARCHAR(30) PRIMARY KEY,
  nombre  VARCHAR(40) NOT NULL,
  orden   TINYINT UNSIGNED NOT NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 6. Abastecimiento: órdenes de compra, financiamiento y facturas
-- ---------------------------------------------------------------------
CREATE TABLE orden_compra (
  id_orden_compra     BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  codigo              VARCHAR(20)   NOT NULL,
  id_sede             BIGINT UNSIGNED NOT NULL,
  id_proveedor        BIGINT UNSIGNED NOT NULL,
  estado              VARCHAR(30)   NOT NULL DEFAULT 'GENERADA',
  valor_total         DECIMAL(14,2) NOT NULL DEFAULT 0,
  observacion         VARCHAR(250),
  fecha_generacion    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  fecha_aprobacion    DATETIME      NULL,
  fecha_recepcion     DATETIME      NULL,
  id_usuario_genera   BIGINT UNSIGNED NOT NULL,
  id_usuario_aprueba  BIGINT UNSIGNED NULL,
  CONSTRAINT uk_orden_codigo UNIQUE (codigo),
  CONSTRAINT ck_orden_valor CHECK (valor_total >= 0),
  CONSTRAINT fk_orden_sede      FOREIGN KEY (id_sede)            REFERENCES sede(id_sede),
  CONSTRAINT fk_orden_proveedor FOREIGN KEY (id_proveedor)       REFERENCES proveedor(id_proveedor),
  CONSTRAINT fk_orden_estado    FOREIGN KEY (estado)             REFERENCES estado_orden_compra(codigo),
  CONSTRAINT fk_orden_genera    FOREIGN KEY (id_usuario_genera)  REFERENCES usuario(id_usuario),
  CONSTRAINT fk_orden_aprueba   FOREIGN KEY (id_usuario_aprueba) REFERENCES usuario(id_usuario)
) ENGINE=InnoDB;
CREATE INDEX ix_orden_estado ON orden_compra(id_sede, estado, fecha_generacion);

CREATE TABLE detalle_orden_compra (
  id_detalle_oc       BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_orden_compra     BIGINT UNSIGNED NOT NULL,
  id_producto         BIGINT UNSIGNED NOT NULL,
  cantidad_kg         DECIMAL(10,3) NOT NULL,
  precio_kg           DECIMAL(14,2) NOT NULL,
  subtotal            DECIMAL(14,2) AS (ROUND(cantidad_kg * precio_kg, 2)) STORED,
  cantidad_recibida_kg DECIMAL(10,3) NULL,
  CONSTRAINT uk_detalle_oc UNIQUE (id_orden_compra, id_producto),
  CONSTRAINT ck_doc_cantidad CHECK (cantidad_kg > 0),
  CONSTRAINT ck_doc_precio CHECK (precio_kg > 0),
  CONSTRAINT fk_doc_orden    FOREIGN KEY (id_orden_compra) REFERENCES orden_compra(id_orden_compra) ON DELETE CASCADE,
  CONSTRAINT fk_doc_producto FOREIGN KEY (id_producto)     REFERENCES producto(id_producto)
) ENGINE=InnoDB;

CREATE TABLE financiamiento_orden (
  id_financiamiento   BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_orden_compra     BIGINT UNSIGNED NOT NULL,
  entidad             VARCHAR(100)  NOT NULL,
  monto               DECIMAL(14,2) NOT NULL,
  viable              BOOLEAN       NOT NULL,
  fecha               DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  id_usuario          BIGINT UNSIGNED NOT NULL,
  CONSTRAINT ck_fin_monto CHECK (monto >= 0),
  CONSTRAINT fk_fin_orden   FOREIGN KEY (id_orden_compra) REFERENCES orden_compra(id_orden_compra),
  CONSTRAINT fk_fin_usuario FOREIGN KEY (id_usuario)      REFERENCES usuario(id_usuario)
) ENGINE=InnoDB;

CREATE TABLE orden_compra_historial (
  id_historial        BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_orden_compra     BIGINT UNSIGNED NOT NULL,
  estado_anterior     VARCHAR(30) NULL,
  estado_nuevo        VARCHAR(30) NOT NULL,
  id_usuario          BIGINT UNSIGNED NOT NULL,
  fecha               DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  observacion         VARCHAR(250),
  CONSTRAINT fk_och_orden   FOREIGN KEY (id_orden_compra) REFERENCES orden_compra(id_orden_compra),
  CONSTRAINT fk_och_estado  FOREIGN KEY (estado_nuevo)    REFERENCES estado_orden_compra(codigo),
  CONSTRAINT fk_och_usuario FOREIGN KEY (id_usuario)      REFERENCES usuario(id_usuario)
) ENGINE=InnoDB;

CREATE TABLE factura_proveedor (
  id_factura          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_orden_compra     BIGINT UNSIGNED NOT NULL,
  numero_factura      VARCHAR(30)   NOT NULL,
  fecha_factura       DATE          NOT NULL,
  valor_total         DECIMAL(14,2) NOT NULL,
  peso_total_kg       DECIMAL(10,3) NOT NULL,
  archivada           BOOLEAN       NOT NULL DEFAULT FALSE,
  ruta_archivo        VARCHAR(250),
  CONSTRAINT uk_factura UNIQUE (id_orden_compra, numero_factura),
  CONSTRAINT fk_factura_orden FOREIGN KEY (id_orden_compra) REFERENCES orden_compra(id_orden_compra)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 7. Inventario: almacenes, lotes y kardex
-- ---------------------------------------------------------------------
CREATE TABLE almacen (
  id_almacen          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_sede             BIGINT UNSIGNED NOT NULL,
  nombre              VARCHAR(60)  NOT NULL,
  refrigerado         BOOLEAN      NOT NULL DEFAULT TRUE,
  temperatura_objetivo_c DECIMAL(4,1) NULL,
  CONSTRAINT uk_almacen UNIQUE (id_sede, nombre),
  CONSTRAINT fk_almacen_sede FOREIGN KEY (id_sede) REFERENCES sede(id_sede)
) ENGINE=InnoDB;

-- Lote = "Producto" físico recibido del proveedor (diagrama de estado Producto)
CREATE TABLE lote (
  id_lote             BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  codigo_lote         VARCHAR(30)   NOT NULL,
  id_producto         BIGINT UNSIGNED NOT NULL,
  id_almacen          BIGINT UNSIGNED NOT NULL,
  id_orden_compra     BIGINT UNSIGNED NULL,
  id_factura          BIGINT UNSIGNED NULL,
  fecha_recepcion     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  fecha_vencimiento   DATE          NOT NULL,
  peso_recibido_kg    DECIMAL(10,3) NOT NULL,
  peso_disponible_kg  DECIMAL(10,3) NOT NULL,
  frescura_ok         BOOLEAN       NOT NULL,
  estado              VARCHAR(30)   NOT NULL DEFAULT 'RECIBIDO',
  id_usuario_recibe   BIGINT UNSIGNED NOT NULL,
  CONSTRAINT uk_lote_codigo UNIQUE (codigo_lote),
  CONSTRAINT ck_lote_pesos CHECK (peso_recibido_kg > 0 AND peso_disponible_kg >= 0 AND peso_disponible_kg <= peso_recibido_kg),
  CONSTRAINT fk_lote_producto FOREIGN KEY (id_producto)       REFERENCES producto(id_producto),
  CONSTRAINT fk_lote_almacen  FOREIGN KEY (id_almacen)        REFERENCES almacen(id_almacen),
  CONSTRAINT fk_lote_orden    FOREIGN KEY (id_orden_compra)   REFERENCES orden_compra(id_orden_compra),
  CONSTRAINT fk_lote_factura  FOREIGN KEY (id_factura)        REFERENCES factura_proveedor(id_factura),
  CONSTRAINT fk_lote_estado   FOREIGN KEY (estado)            REFERENCES estado_lote(codigo),
  CONSTRAINT fk_lote_usuario  FOREIGN KEY (id_usuario_recibe) REFERENCES usuario(id_usuario)
) ENGINE=InnoDB;
CREATE INDEX ix_lote_fifo ON lote(id_producto, estado, fecha_vencimiento);

CREATE TABLE movimiento_inventario (
  id_movimiento       BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_lote             BIGINT UNSIGNED NOT NULL,
  tipo                VARCHAR(10)   NOT NULL,
  cantidad_kg         DECIMAL(10,3) NOT NULL,
  referencia_tipo     VARCHAR(20)   NOT NULL,   -- ORDEN_COMPRA | PEDIDO | AJUSTE
  referencia_id       BIGINT UNSIGNED NULL,
  id_usuario          BIGINT UNSIGNED NOT NULL,
  fecha               DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT ck_mov_tipo CHECK (tipo IN ('ENTRADA','SALIDA','AJUSTE','MERMA')),
  CONSTRAINT ck_mov_cantidad CHECK (cantidad_kg > 0),
  CONSTRAINT fk_mov_lote    FOREIGN KEY (id_lote)    REFERENCES lote(id_lote),
  CONSTRAINT fk_mov_usuario FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario)
) ENGINE=InnoDB;
CREATE INDEX ix_mov_referencia ON movimiento_inventario(referencia_tipo, referencia_id);
CREATE INDEX ix_mov_fecha ON movimiento_inventario(fecha);

-- ---------------------------------------------------------------------
-- 8. Ventas: pedidos, detalle, pagos
-- ---------------------------------------------------------------------
CREATE TABLE medio_pago (
  id_medio_pago       SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre              VARCHAR(40) NOT NULL,
  activo              BOOLEAN     NOT NULL DEFAULT TRUE,
  CONSTRAINT uk_medio_pago UNIQUE (nombre)
) ENGINE=InnoDB;

CREATE TABLE pedido (
  id_pedido           BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  codigo              VARCHAR(20)   NOT NULL,
  id_sede             BIGINT UNSIGNED NOT NULL,
  id_cliente          BIGINT UNSIGNED NOT NULL,
  id_direccion        BIGINT UNSIGNED NULL,
  canal               VARCHAR(15)   NOT NULL DEFAULT 'MOSTRADOR',
  metodo_entrega      VARCHAR(15)   NOT NULL DEFAULT 'RECOGER',
  id_medio_pago       SMALLINT UNSIGNED NULL,
  estado              VARCHAR(30)   NOT NULL DEFAULT 'SOLICITADO',
  estado_pago         VARCHAR(10)   NOT NULL DEFAULT 'PENDIENTE',
  subtotal            DECIMAL(14,2) NOT NULL DEFAULT 0,
  valor_domicilio     DECIMAL(14,2) NOT NULL DEFAULT 0,
  total               DECIMAL(14,2) NOT NULL DEFAULT 0,
  observaciones       VARCHAR(250),
  fecha_solicitud     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  fecha_registro      DATETIME      NULL,
  id_usuario_registro BIGINT UNSIGNED NULL,
  actualizado_en      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT uk_pedido_codigo UNIQUE (codigo),
  CONSTRAINT ck_pedido_canal CHECK (canal IN ('MOSTRADOR','WHATSAPP','WEB','TELEFONO')),
  CONSTRAINT ck_pedido_entrega CHECK (metodo_entrega IN ('RECOGER','DOMICILIO')),
  CONSTRAINT ck_pedido_estado_pago CHECK (estado_pago IN ('PENDIENTE','PAGADO')),
  CONSTRAINT ck_pedido_valores CHECK (subtotal >= 0 AND valor_domicilio >= 0 AND total >= 0),
  CONSTRAINT fk_pedido_sede      FOREIGN KEY (id_sede)             REFERENCES sede(id_sede),
  CONSTRAINT fk_pedido_cliente   FOREIGN KEY (id_cliente)          REFERENCES cliente(id_cliente),
  CONSTRAINT fk_pedido_direccion FOREIGN KEY (id_direccion)        REFERENCES direccion_cliente(id_direccion),
  CONSTRAINT fk_pedido_medio     FOREIGN KEY (id_medio_pago)       REFERENCES medio_pago(id_medio_pago),
  CONSTRAINT fk_pedido_estado    FOREIGN KEY (estado)              REFERENCES estado_pedido(codigo),
  CONSTRAINT fk_pedido_usuario   FOREIGN KEY (id_usuario_registro) REFERENCES usuario(id_usuario)
) ENGINE=InnoDB;
CREATE INDEX ix_pedido_estado ON pedido(id_sede, estado, fecha_solicitud);
CREATE INDEX ix_pedido_cliente ON pedido(id_cliente, fecha_solicitud);
CREATE INDEX ix_pedido_pago ON pedido(estado_pago);

CREATE TABLE detalle_pedido (
  id_detalle          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_pedido           BIGINT UNSIGNED NOT NULL,
  id_producto         BIGINT UNSIGNED NOT NULL,
  cantidad_solicitada_kg DECIMAL(10,3) NOT NULL,
  peso_real_kg        DECIMAL(10,3) NULL,          -- Pesar producto
  precio_kg           DECIMAL(14,2) NULL,          -- precio vigente congelado al calcular
  subtotal            DECIMAL(14,2) NULL,
  estado              VARCHAR(15)   NOT NULL DEFAULT 'SOLICITADO',
  CONSTRAINT uk_detalle_pedido UNIQUE (id_pedido, id_producto),
  CONSTRAINT ck_dp_cantidad CHECK (cantidad_solicitada_kg > 0),
  CONSTRAINT ck_dp_peso CHECK (peso_real_kg IS NULL OR peso_real_kg > 0),
  CONSTRAINT ck_dp_estado CHECK (estado IN ('SOLICITADO','DISPONIBLE','NO_DISPONIBLE','CANCELADO','PESADO')),
  CONSTRAINT fk_dp_pedido   FOREIGN KEY (id_pedido)   REFERENCES pedido(id_pedido) ON DELETE CASCADE,
  CONSTRAINT fk_dp_producto FOREIGN KEY (id_producto) REFERENCES producto(id_producto)
) ENGINE=InnoDB;

CREATE TABLE pedido_historial (
  id_historial        BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_pedido           BIGINT UNSIGNED NOT NULL,
  estado_anterior     VARCHAR(30) NULL,
  estado_nuevo        VARCHAR(30) NOT NULL,
  id_usuario          BIGINT UNSIGNED NULL,
  fecha               DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  observacion         VARCHAR(250),
  CONSTRAINT fk_ph_pedido  FOREIGN KEY (id_pedido)    REFERENCES pedido(id_pedido) ON DELETE CASCADE,
  CONSTRAINT fk_ph_estado  FOREIGN KEY (estado_nuevo) REFERENCES estado_pedido(codigo),
  CONSTRAINT fk_ph_usuario FOREIGN KEY (id_usuario)   REFERENCES usuario(id_usuario)
) ENGINE=InnoDB;
CREATE INDEX ix_ph_pedido ON pedido_historial(id_pedido, fecha);

CREATE TABLE pago (
  id_pago             BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_pedido           BIGINT UNSIGNED NOT NULL,
  id_medio_pago       SMALLINT UNSIGNED NOT NULL,
  valor               DECIMAL(14,2) NOT NULL,
  referencia          VARCHAR(60),
  recibido_por        VARCHAR(15)   NOT NULL,      -- PUNTO_VENTA | DOMICILIARIO
  fecha               DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  id_usuario          BIGINT UNSIGNED NOT NULL,
  CONSTRAINT ck_pago_valor CHECK (valor > 0),
  CONSTRAINT ck_pago_recibido CHECK (recibido_por IN ('PUNTO_VENTA','DOMICILIARIO')),
  CONSTRAINT fk_pago_pedido  FOREIGN KEY (id_pedido)     REFERENCES pedido(id_pedido),
  CONSTRAINT fk_pago_medio   FOREIGN KEY (id_medio_pago) REFERENCES medio_pago(id_medio_pago),
  CONSTRAINT fk_pago_usuario FOREIGN KEY (id_usuario)    REFERENCES usuario(id_usuario)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 9. Preparación: comanda, cortes y paquetes
-- ---------------------------------------------------------------------
CREATE TABLE comanda (
  id_comanda          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_pedido           BIGINT UNSIGNED NOT NULL,
  fecha               DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  id_usuario          BIGINT UNSIGNED NOT NULL,
  CONSTRAINT uk_comanda_pedido UNIQUE (id_pedido),
  CONSTRAINT fk_comanda_pedido  FOREIGN KEY (id_pedido)  REFERENCES pedido(id_pedido),
  CONSTRAINT fk_comanda_usuario FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario)
) ENGINE=InnoDB;

CREATE TABLE corte (
  id_corte            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_detalle          BIGINT UNSIGNED NOT NULL,
  especificacion_tecnica VARCHAR(120) NOT NULL,
  peso_kg             DECIMAL(10,3) NOT NULL,
  temperatura_c       DECIMAL(4,1)  NOT NULL,
  calidad_ok          BOOLEAN       NOT NULL,
  conforme            BOOLEAN       NOT NULL,
  id_corte_sustituido BIGINT UNSIGNED NULL,       -- Sustituir piezas
  id_usuario          BIGINT UNSIGNED NOT NULL,
  fecha_verificacion  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT ck_corte_peso CHECK (peso_kg > 0),
  CONSTRAINT ck_corte_temp CHECK (temperatura_c BETWEEN -30 AND 40),
  CONSTRAINT fk_corte_detalle   FOREIGN KEY (id_detalle)          REFERENCES detalle_pedido(id_detalle),
  CONSTRAINT fk_corte_sustituye FOREIGN KEY (id_corte_sustituido) REFERENCES corte(id_corte),
  CONSTRAINT fk_corte_usuario   FOREIGN KEY (id_usuario)          REFERENCES usuario(id_usuario)
) ENGINE=InnoDB;

CREATE TABLE paquete (
  id_paquete          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_pedido           BIGINT UNSIGNED NOT NULL,
  tipo_empaque        VARCHAR(10)   NOT NULL,
  peso_total_kg       DECIMAL(10,3) NOT NULL,
  sellado             BOOLEAN       NOT NULL,
  rotulo              VARCHAR(200)  NULL,
  estado              VARCHAR(30)   NOT NULL DEFAULT 'EMPACADO',
  id_usuario          BIGINT UNSIGNED NOT NULL,
  fecha_empaque       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT ck_paquete_tipo CHECK (tipo_empaque IN ('BANDEJA','BOLSA','CAJA')),
  CONSTRAINT ck_paquete_peso CHECK (peso_total_kg > 0),
  CONSTRAINT fk_paquete_pedido  FOREIGN KEY (id_pedido)  REFERENCES pedido(id_pedido),
  CONSTRAINT fk_paquete_estado  FOREIGN KEY (estado)     REFERENCES estado_paquete(codigo),
  CONSTRAINT fk_paquete_usuario FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario)
) ENGINE=InnoDB;

CREATE TABLE paquete_corte (
  id_paquete          BIGINT UNSIGNED NOT NULL,
  id_corte            BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (id_paquete, id_corte),
  CONSTRAINT uk_paquete_corte UNIQUE (id_corte),       -- un corte va en un solo paquete
  CONSTRAINT fk_pc_paquete FOREIGN KEY (id_paquete) REFERENCES paquete(id_paquete) ON DELETE CASCADE,
  CONSTRAINT fk_pc_corte   FOREIGN KEY (id_corte)   REFERENCES corte(id_corte)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 10. Entrega a domicilio
-- ---------------------------------------------------------------------
CREATE TABLE entrega (
  id_entrega          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_pedido           BIGINT UNSIGNED NOT NULL,
  id_domiciliario     BIGINT UNSIGNED NOT NULL,
  fecha_asignacion    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  fecha_entrega       DATETIME     NULL,
  exitosa             BOOLEAN      NULL,          -- NULL = en curso
  recibido_por        VARCHAR(100) NULL,
  motivo_fallo        VARCHAR(200) NULL,
  CONSTRAINT fk_entrega_pedido FOREIGN KEY (id_pedido)       REFERENCES pedido(id_pedido),
  CONSTRAINT fk_entrega_domic  FOREIGN KEY (id_domiciliario) REFERENCES domiciliario(id_domiciliario)
) ENGINE=InnoDB;
CREATE INDEX ix_entrega_domic ON entrega(id_domiciliario, exitosa);

-- ---------------------------------------------------------------------
-- 11. Finanzas: caja (liquidez) y bitácora
-- ---------------------------------------------------------------------
CREATE TABLE movimiento_caja (
  id_movimiento_caja  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_sede             BIGINT UNSIGNED NOT NULL,
  tipo                VARCHAR(8)    NOT NULL,
  concepto            VARCHAR(120)  NOT NULL,
  valor               DECIMAL(14,2) NOT NULL,
  referencia_tipo     VARCHAR(20)   NULL,      -- PAGO | ORDEN_COMPRA | FINANCIAMIENTO | SALDO_INICIAL
  referencia_id       BIGINT UNSIGNED NULL,
  id_usuario          BIGINT UNSIGNED NOT NULL,
  fecha               DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT ck_caja_tipo CHECK (tipo IN ('INGRESO','EGRESO')),
  CONSTRAINT ck_caja_valor CHECK (valor > 0),
  CONSTRAINT fk_caja_sede    FOREIGN KEY (id_sede)    REFERENCES sede(id_sede),
  CONSTRAINT fk_caja_usuario FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario)
) ENGINE=InnoDB;
CREATE INDEX ix_caja_sede_fecha ON movimiento_caja(id_sede, fecha);

CREATE TABLE bitacora (
  id_bitacora         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_usuario          BIGINT UNSIGNED NULL,
  accion              VARCHAR(40)  NOT NULL,
  entidad             VARCHAR(40)  NOT NULL,
  id_entidad          BIGINT UNSIGNED NULL,
  detalle             JSON         NULL,
  ip                  VARCHAR(45)  NULL,
  fecha               DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_bitacora_usuario FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario)
) ENGINE=InnoDB;
CREATE INDEX ix_bitacora_entidad ON bitacora(entidad, id_entidad);

-- ---------------------------------------------------------------------
-- 12. Vistas
-- ---------------------------------------------------------------------
-- Precio vigente por producto y sede
CREATE VIEW v_precio_vigente AS
SELECT pp.id_producto, pp.id_sede, pp.precio_kg, pp.vigente_desde
  FROM precio_producto pp
 WHERE pp.vigente_hasta IS NULL;

-- Stock disponible por producto y sede (lotes frescos, no agotados ni vencidos)
CREATE VIEW v_stock_producto AS
SELECT p.id_producto, p.codigo, p.nombre, a.id_sede,
       COALESCE(SUM(l.peso_disponible_kg), 0) AS stock_kg,
       p.stock_minimo_kg,
       (COALESCE(SUM(l.peso_disponible_kg), 0) < p.stock_minimo_kg) AS bajo_minimo
  FROM producto p
  CROSS JOIN almacen a
  LEFT JOIN lote l
         ON l.id_producto = p.id_producto
        AND l.id_almacen  = a.id_almacen
        AND l.frescura_ok = TRUE
        AND l.estado NOT IN ('AGOTADO','DESCARTADO')
        AND l.fecha_vencimiento >= CURRENT_DATE
 WHERE p.activo = TRUE
 GROUP BY p.id_producto, p.codigo, p.nombre, a.id_sede, p.stock_minimo_kg;

-- Liquidez (saldo de caja) por sede
CREATE VIEW v_liquidez AS
SELECT s.id_sede, s.nombre,
       COALESCE(SUM(CASE WHEN mc.tipo = 'INGRESO' THEN mc.valor ELSE -mc.valor END), 0) AS saldo
  FROM sede s
  LEFT JOIN movimiento_caja mc ON mc.id_sede = s.id_sede
 GROUP BY s.id_sede, s.nombre;
