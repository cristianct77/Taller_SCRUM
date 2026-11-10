# RichPOS – Módulo 01 (Sprint 1)

Aplicación web en **JSP + MySQL** para la Pollería "Rich".
Módulo 01: *Gestión de pedidos, abastecimiento y preparación de domicilios*, con las 10 historias del Sprint 1.

| HU | Historia | Interfaz | Clase.método |
|----|----------|----------|--------------|
| HU-01 | Solicitar pedido | pedidos.jsp | `Pedido.solicitarPedido()` |
| HU-02 | Registrar pedido | pedidos.jsp | `Pedido.registrarPedido()` |
| HU-03 | Verificar disponibilidad | preparacion.jsp | `Producto.verificarDisponibilidad()` |
| HU-06 | Calcular total | preparacion.jsp | `Pedido.calcularTotal()` |
| HU-41 | Verificar calidad y temperatura | preparacion.jsp | `Corte.verificarCalidadTemperatura()` |
| HU-43 | Empacar y sellar producto | preparacion.jsp | `Paquete.empacarSellarProducto()` |
| HU-16 | Entregar pedido | entrega.jsp | `Pedido.entregarPedido()` |
| HU-23 | Generar orden | abastecimiento.jsp | `OrdenCompra.generarOrden()` |
| HU-26 | Aprobar orden | finanzas.jsp | `OrdenCompra.aprobarOrden()` |
| HU-31 | Recibir lote | abastecimiento.jsp | `Producto.recibirLote()` |

El inicio de sesión usa `Validacion.verificarAutorizacionUsuario()`. Para que el flujo esté completo hay además
tres pasos de apoyo: confirmar pedido con medio de pago, despachar al domiciliario y entregar en el local.

## Estructura (lo más simple posible)

```
database/01_richpos_ddl.sql     DDL de la base de datos (35 tablas, 3 vistas)
database/02_richpos_datos.sql   Datos iniciales y usuarios de prueba
database/er_richpos.png         Diagrama entidad-relación
src/main/java/richpos/          Conexion, Consulta, Validacion, Pedido, Producto, Corte, Paquete, OrdenCompra
src/main/webapp/                index.jsp (login), principal.jsp y las 5 interfaces
pruebas/aceptacion.js           Prueba automática de las 10 HU (Playwright) y capturas/
```

## Cómo ejecutarla

**Requisitos:** JDK 17 o superior, Apache Tomcat **10.1** y MySQL 8 (sirve el de XAMPP o MySQL Workbench).

1. **Base de datos.** Ejecute en MySQL, en este orden, `database/01_richpos_ddl.sql` y `database/02_richpos_datos.sql`.
   Por consola: `mysql -u root -p < database/01_richpos_ddl.sql` y luego el segundo archivo.
2. **Conexión.** Si su MySQL tiene otro usuario o contraseña, cámbielos en `src/main/java/richpos/Conexion.java`.
   Por defecto usa `root` sin contraseña, como en XAMPP.
3. **Compilar y desplegar.** Elija una de estas opciones:
   - **NetBeans o IntelliJ:** abra la carpeta como proyecto Maven y ejecútelo en Tomcat 10.1.
   - **Maven:** ejecute `mvn package` y copie `target/richpos.war` a la carpeta `webapps/` de Tomcat.
   - **Sin Maven:** copie `src/main/webapp` como `webapps/richpos` y compile las clases en `WEB-INF/classes`.
     Además, ponga `mysql-connector-j-8.x.jar` en `WEB-INF/lib`.
4. **Abrir** http://localhost:8080/richpos

## Usuarios de prueba (contraseña `Rich2026*`)

| Usuario | Rol | Interfaces |
|---------|-----|------------|
| `cliente` | Cliente | Pedidos (solicitar) |
| `atencion` | Atención al Cliente | Pedidos (registrar y confirmar) |
| `operativa` | Área Operativa | Preparación, Abastecimiento |
| `contabilidad` | Contabilidad y Finanzas | Inventario y finanzas |
| `domiciliario` | Domiciliario | Entrega |
| `leidy` | Administradora | Todas |
| `inactivo` | No autorizado | Sirve para probar el mensaje de usuario no autorizado |

## Flujo de prueba sugerido

1. **cliente:** solicita un pedido. Por ejemplo, Pollo entero 2,5 kg, Pechuga 1,5 kg y Alas 6 kg (las alas no alcanzan en stock).
2. **atencion:** registra el pedido.
3. **operativa:** verifica la disponibilidad (las alas se cancelan) y luego pesa y calcula el total.
4. **atencion:** confirma el pedido y el medio de pago.
5. **operativa:** verifica la calidad y la temperatura de los cortes (entre 0 y 4 °C), empaca y sella, y despacha.
6. **domiciliario:** registra la entrega y el pago.
7. **operativa:** genera una orden de compra.
8. **contabilidad:** aprueba la orden.
9. **operativa:** recibe el lote.

Prueba automática (opcional, requiere Node.js y Playwright): `node pruebas/aceptacion.js http://localhost:8080/richpos capturas`.
Resultado: 21 de 21 verificaciones correctas.

## Diseño escalable de la base de datos

- **Multi-sede:** pedidos, precios, almacenes, órdenes y caja pertenecen a una sede.
- **Estados en tablas catálogo** en lugar de ENUM. Se agregan estados nuevos sin modificar la estructura.
- **Precios con historial de vigencia.** El pedido guarda el precio con el que se cobró.
- **Inventario por lotes y kardex** (`movimiento_inventario`): descuento FIFO por vencimiento y stock calculado en `v_stock_producto`.
- **Historial de estados** de pedidos y órdenes, más `bitacora` para auditoría.
- **Pagos y caja separados del pedido.** La liquidez se calcula en `v_liquidez`.
- **Parámetros de negocio en tabla:** rango de temperatura, valor del domicilio e intentos de inicio de sesión.
- **Tipos y restricciones:** llaves BIGINT, dinero en DECIMAL(14,2), pesos en DECIMAL(10,3), restricciones CHECK e índices en las llaves foráneas.
