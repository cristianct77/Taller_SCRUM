package richpos;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.SQLException;
import java.util.*;

/** Clase OrdenCompra: GenerarOrden() HU-23 y AprobarOrden() HU-26. */
public class OrdenCompra {

    /** HU-23 Generar orden: crea la orden de compra en estado GENERADA y devuelve su código. */
    public static String generarOrden(long idProveedor, String[] productos, String[] cantidades, String[] precios,
                                      String observacion, long idUsuario) throws SQLException {
        Map<Long, BigDecimal[]> lineas = new LinkedHashMap<>();
        for (int i = 0; productos != null && i < productos.length; i++) {
            if (productos[i] == null || productos[i].isBlank()) continue;
            long idProducto = Long.parseLong(productos[i]);
            if (lineas.containsKey(idProducto)) throw new IllegalArgumentException("Un producto está repetido en la orden.");
            lineas.put(idProducto, new BigDecimal[]{
                Validacion.positivo(cantidades[i], "cantidad (kg)"), Validacion.positivo(precios[i], "precio por kg")});
        }
        if (lineas.isEmpty()) throw new IllegalArgumentException("Agregue al menos un producto a la orden.");
        try (Connection c = Conexion.getConexion()) {
            c.setAutoCommit(false);
            try {
                if (Consulta.uno(c, "SELECT 1 FROM proveedor WHERE id_proveedor = ? AND activo = TRUE", idProveedor) == null)
                    throw new IllegalArgumentException("Seleccione un proveedor válido.");
                long id = Consulta.insertar(c,
                    "INSERT INTO orden_compra (codigo, id_sede, id_proveedor, observacion, id_usuario_genera) VALUES (?, ?, ?, ?, ?)",
                    "T" + System.nanoTime(), Pedido.SEDE, idProveedor, observacion, idUsuario);
                String codigo = String.format("OC-%05d", id);
                for (Map.Entry<Long, BigDecimal[]> l : lineas.entrySet())
                    Consulta.ejecutar(c, "INSERT INTO detalle_orden_compra (id_orden_compra, id_producto, cantidad_kg, precio_kg) VALUES (?, ?, ?, ?)",
                        id, l.getKey(), l.getValue()[0], l.getValue()[1]);
                Consulta.ejecutar(c,
                    "UPDATE orden_compra SET codigo = ?, valor_total = (SELECT SUM(subtotal) FROM detalle_orden_compra WHERE id_orden_compra = ?) WHERE id_orden_compra = ?",
                    codigo, id, id);
                historial(c, id, null, "GENERADA", idUsuario, "Orden generada");
                c.commit();
                return codigo;
            } catch (SQLException | RuntimeException e) {
                c.rollback();
                throw e;
            }
        }
    }

    /**
     * HU-26 Aprobar orden: revisa la liquidez. Si alcanza, la orden queda APROBADA. Si no alcanza
     * y no se ha digitado una alternativa, queda EN_GESTION_ALTERNATIVAS. Con una alternativa de
     * financiamiento viable que cubra la diferencia se aprueba; si no es viable queda AJUSTADA.
     */
    public static String aprobarOrden(long idOrden, String entidad, String montoTexto, boolean viable, long idUsuario) throws SQLException {
        try (Connection c = Conexion.getConexion()) {
            c.setAutoCommit(false);
            try {
                Map<String, Object> o = Consulta.uno(c, "SELECT * FROM orden_compra WHERE id_orden_compra = ? FOR UPDATE", idOrden);
                if (o == null) throw new IllegalArgumentException("La orden no existe.");
                String estado = (String) o.get("estado");
                if (!"GENERADA".equals(estado) && !"EN_GESTION_ALTERNATIVAS".equals(estado))
                    throw new IllegalArgumentException("La orden " + o.get("codigo") + " ya fue revisada (estado " + estado + ").");
                if ("GENERADA".equals(estado)) {
                    cambiarEstado(c, idOrden, "EN_REVISION", idUsuario, "Revisar liquidez");
                }
                BigDecimal valor = Consulta.num(o.get("valor_total"));
                BigDecimal saldo = liquidez(c);
                String resultado;
                if (saldo.compareTo(valor) >= 0) {
                    aprobar(c, o, idUsuario, "Liquidez suficiente");
                    resultado = "Orden aprobada (liquidez suficiente)";
                } else if (entidad == null || entidad.isBlank()) {
                    cambiarEstado(c, idOrden, "EN_GESTION_ALTERNATIVAS", idUsuario, "Liquidez insuficiente");
                    resultado = "Liquidez insuficiente (" + Consulta.pesos(saldo) + "). Registre una alternativa de financiamiento.";
                } else {
                    BigDecimal monto = Validacion.positivo(montoTexto, "monto del financiamiento");
                    Consulta.insertar(c, "INSERT INTO financiamiento_orden (id_orden_compra, entidad, monto, viable, id_usuario) VALUES (?, ?, ?, ?, ?)",
                        idOrden, entidad.trim(), monto, viable, idUsuario);
                    if (viable && saldo.add(monto).compareTo(valor) >= 0) {
                        Consulta.ejecutar(c,
                            "INSERT INTO movimiento_caja (id_sede, tipo, concepto, valor, referencia_tipo, referencia_id, id_usuario) VALUES (?, 'INGRESO', ?, ?, 'FINANCIAMIENTO', ?, ?)",
                            Pedido.SEDE, "Financiamiento " + entidad.trim(), monto, idOrden, idUsuario);
                        aprobar(c, o, idUsuario, "Aprobada con financiamiento de " + entidad.trim());
                        resultado = "Orden aprobada con financiamiento";
                    } else {
                        cambiarEstado(c, idOrden, "AJUSTADA", idUsuario, "Alternativa no viable: pedido ajustado");
                        resultado = "Alternativa no viable: la orden queda AJUSTADA y no se aprueba";
                    }
                }
                c.commit();
                return resultado;
            } catch (SQLException | RuntimeException e) {
                c.rollback();
                throw e;
            }
        }
    }

    public static BigDecimal liquidez() throws SQLException {
        try (Connection c = Conexion.getConexion()) {
            return liquidez(c);
        }
    }

    static BigDecimal liquidez(Connection c) throws SQLException {
        return Consulta.num(Consulta.uno(c, "SELECT saldo FROM v_liquidez WHERE id_sede = ?", Pedido.SEDE).get("saldo"));
    }

    private static void aprobar(Connection c, Map<String, Object> o, long idUsuario, String obs) throws SQLException {
        long id = ((Number) o.get("id_orden_compra")).longValue();
        Consulta.ejecutar(c, "UPDATE orden_compra SET fecha_aprobacion = NOW(), id_usuario_aprueba = ? WHERE id_orden_compra = ?", idUsuario, id);
        Consulta.ejecutar(c,
            "INSERT INTO movimiento_caja (id_sede, tipo, concepto, valor, referencia_tipo, referencia_id, id_usuario) VALUES (?, 'EGRESO', ?, ?, 'ORDEN_COMPRA', ?, ?)",
            Pedido.SEDE, "Pago orden " + o.get("codigo"), o.get("valor_total"), id, idUsuario);
        cambiarEstado(c, id, "APROBADA", idUsuario, obs);
    }

    static void cambiarEstado(Connection c, long idOrden, String nuevo, long idUsuario, String obs) throws SQLException {
        String anterior = (String) Consulta.uno(c, "SELECT estado FROM orden_compra WHERE id_orden_compra = ?", idOrden).get("estado");
        Consulta.ejecutar(c, "UPDATE orden_compra SET estado = ? WHERE id_orden_compra = ?", nuevo, idOrden);
        historial(c, idOrden, anterior, nuevo, idUsuario, obs);
    }

    static void historial(Connection c, long idOrden, String anterior, String nuevo, long idUsuario, String obs) throws SQLException {
        Consulta.ejecutar(c, "INSERT INTO orden_compra_historial (id_orden_compra, estado_anterior, estado_nuevo, id_usuario, observacion) VALUES (?, ?, ?, ?, ?)",
            idOrden, anterior, nuevo, idUsuario, obs);
    }
}
