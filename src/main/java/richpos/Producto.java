package richpos;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.SQLException;
import java.time.LocalDate;
import java.util.*;

/** Clase Producto: VerificarDisponibilidad() HU-03 y RecibirLote() HU-31. */
public class Producto {

    /**
     * HU-03 Verificar disponibilidad: compara lo solicitado con el stock. Los productos
     * disponibles siguen a pesar; los no disponibles se cancelan (Cancelar producto).
     * Devuelve un mensaje por producto.
     */
    public static List<String> verificarDisponibilidad(long idPedido, long idUsuario) throws SQLException {
        List<String> mensajes = new ArrayList<>();
        try (Connection c = Conexion.getConexion()) {
            c.setAutoCommit(false);
            try {
                Pedido.exigirEstado(c, idPedido, "REGISTRADO");
                List<Map<String, Object>> detalles = Consulta.lista(c,
                    "SELECT d.id_detalle, d.cantidad_solicitada_kg, p.nombre, COALESCE(s.stock_kg, 0) AS stock_kg " +
                    "  FROM detalle_pedido d JOIN producto p ON p.id_producto = d.id_producto " +
                    "  LEFT JOIN v_stock_producto s ON s.id_producto = d.id_producto AND s.id_sede = ? " +
                    " WHERE d.id_pedido = ? AND d.estado = 'SOLICITADO'", Pedido.SEDE, idPedido);
                if (detalles.isEmpty()) throw new IllegalArgumentException("La disponibilidad de este pedido ya fue verificada.");
                int disponibles = 0;
                for (Map<String, Object> d : detalles) {
                    BigDecimal pedido = Consulta.num(d.get("cantidad_solicitada_kg"));
                    BigDecimal stock = Consulta.num(d.get("stock_kg"));
                    if (stock.compareTo(pedido) >= 0) {
                        Consulta.ejecutar(c, "UPDATE detalle_pedido SET estado = 'DISPONIBLE' WHERE id_detalle = ?", d.get("id_detalle"));
                        mensajes.add(d.get("nombre") + ": disponible (" + pedido + " kg de " + stock + " kg en stock)");
                        disponibles++;
                    } else {
                        Consulta.ejecutar(c, "UPDATE detalle_pedido SET estado = 'CANCELADO' WHERE id_detalle = ?", d.get("id_detalle"));
                        mensajes.add(d.get("nombre") + ": NO disponible (" + pedido + " kg pedidos, " + stock + " kg en stock) - producto cancelado");
                    }
                }
                long activos = ((Number) Consulta.uno(c,
                    "SELECT COUNT(*) n FROM detalle_pedido WHERE id_pedido = ? AND estado <> 'CANCELADO'", idPedido).get("n")).longValue();
                if (activos == 0) {
                    Pedido.cambiarEstado(c, idPedido, "CANCELADO", idUsuario, "Ningún producto disponible");
                    mensajes.add("Ningún producto está disponible: el pedido queda CANCELADO.");
                } else {
                    mensajes.add("Disponibilidad verificada: " + disponibles + " producto(s) para pesar.");
                }
                c.commit();
                return mensajes;
            } catch (SQLException | RuntimeException e) {
                c.rollback();
                throw e;
            }
        }
    }

    /**
     * HU-31 Recibir lote: registra la mercancía de una orden APROBADA. Cada producto con
     * frescura correcta entra al inventario (lote RECIBIDO); si no, el lote queda DESCARTADO.
     * La orden de compra queda RECIBIDA.
     */
    public static int recibirLote(long idOrden, String numeroFactura, String fechaVencimiento,
                                  Map<Long, String> pesosRecibidos, Set<Long> frescuraOk, long idUsuario) throws SQLException {
        Validacion.obligatorio(numeroFactura, "número de factura");
        LocalDate vence;
        try {
            vence = LocalDate.parse(fechaVencimiento);
        } catch (Exception e) {
            throw new IllegalArgumentException("Digite una fecha de vencimiento válida.");
        }
        if (vence.isBefore(LocalDate.now())) throw new IllegalArgumentException("La fecha de vencimiento ya pasó.");
        try (Connection c = Conexion.getConexion()) {
            c.setAutoCommit(false);
            try {
                Map<String, Object> o = Consulta.uno(c, "SELECT * FROM orden_compra WHERE id_orden_compra = ?", idOrden);
                if (o == null || !Arrays.asList("APROBADA", "ENVIADA").contains(o.get("estado")))
                    throw new IllegalArgumentException("Solo se reciben lotes de órdenes aprobadas.");
                List<Map<String, Object>> detalles = Consulta.lista(c,
                    "SELECT id_detalle_oc, id_producto, precio_kg FROM detalle_orden_compra WHERE id_orden_compra = ?", idOrden);
                long idAlmacen = ((Number) Consulta.uno(c,
                    "SELECT id_almacen FROM almacen WHERE id_sede = ? ORDER BY id_almacen LIMIT 1", Pedido.SEDE).get("id_almacen")).longValue();

                BigDecimal pesoTotal = BigDecimal.ZERO, valorTotal = BigDecimal.ZERO;
                Map<Long, BigDecimal> pesos = new HashMap<>();
                for (Map<String, Object> d : detalles) {
                    long idDet = ((Number) d.get("id_detalle_oc")).longValue();
                    BigDecimal peso = Validacion.positivo(pesosRecibidos.getOrDefault(idDet, ""), "peso recibido");
                    pesos.put(idDet, peso);
                    pesoTotal = pesoTotal.add(peso);
                    valorTotal = valorTotal.add(peso.multiply(Consulta.num(d.get("precio_kg"))));
                }
                long idFactura = Consulta.insertar(c,
                    "INSERT INTO factura_proveedor (id_orden_compra, numero_factura, fecha_factura, valor_total, peso_total_kg) VALUES (?, ?, CURRENT_DATE, ?, ?)",
                    idOrden, numeroFactura.trim(), valorTotal, pesoTotal);
                int lotes = 0;
                for (Map<String, Object> d : detalles) {
                    long idDet = ((Number) d.get("id_detalle_oc")).longValue();
                    BigDecimal peso = pesos.get(idDet);
                    boolean fresco = frescuraOk.contains(idDet);
                    String codigo = "L-" + o.get("codigo") + "-" + d.get("id_producto");
                    long idLote = Consulta.insertar(c,
                        "INSERT INTO lote (codigo_lote, id_producto, id_almacen, id_orden_compra, id_factura, fecha_vencimiento, " +
                        " peso_recibido_kg, peso_disponible_kg, frescura_ok, estado, id_usuario_recibe) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                        codigo, d.get("id_producto"), idAlmacen, idOrden, idFactura, java.sql.Date.valueOf(vence),
                        peso, fresco ? peso : BigDecimal.ZERO, fresco, fresco ? "RECIBIDO" : "DESCARTADO", idUsuario);
                    Consulta.ejecutar(c, "UPDATE detalle_orden_compra SET cantidad_recibida_kg = ? WHERE id_detalle_oc = ?", peso, idDet);
                    if (fresco) {
                        Consulta.ejecutar(c,
                            "INSERT INTO movimiento_inventario (id_lote, tipo, cantidad_kg, referencia_tipo, referencia_id, id_usuario) VALUES (?, 'ENTRADA', ?, 'ORDEN_COMPRA', ?, ?)",
                            idLote, peso, idOrden, idUsuario);
                        lotes++;
                    }
                }
                Consulta.ejecutar(c, "UPDATE orden_compra SET estado = 'RECIBIDA', fecha_recepcion = NOW() WHERE id_orden_compra = ?", idOrden);
                OrdenCompra.historial(c, idOrden, (String) o.get("estado"), "RECIBIDA", idUsuario, "Lote recibido con factura " + numeroFactura.trim());
                c.commit();
                return lotes;
            } catch (SQLException | RuntimeException e) {
                c.rollback();
                throw e;
            }
        }
    }

    /** Descuenta del inventario (lotes más próximos a vencer primero) el peso vendido. */
    static void descontarInventario(Connection c, long idProducto, BigDecimal kg, long idPedido, long idUsuario) throws SQLException {
        BigDecimal falta = kg;
        List<Map<String, Object>> lotes = Consulta.lista(c,
            "SELECT id_lote, peso_disponible_kg FROM lote WHERE id_producto = ? AND frescura_ok = TRUE " +
            "AND estado NOT IN ('AGOTADO','DESCARTADO') AND peso_disponible_kg > 0 ORDER BY fecha_vencimiento, id_lote FOR UPDATE", idProducto);
        for (Map<String, Object> l : lotes) {
            if (falta.signum() <= 0) break;
            BigDecimal disp = Consulta.num(l.get("peso_disponible_kg"));
            BigDecimal tomar = disp.min(falta);
            BigDecimal queda = disp.subtract(tomar);
            Consulta.ejecutar(c, "UPDATE lote SET peso_disponible_kg = ?, estado = ? WHERE id_lote = ?",
                queda, queda.signum() == 0 ? "AGOTADO" : "ALMACENADO", l.get("id_lote"));
            Consulta.ejecutar(c,
                "INSERT INTO movimiento_inventario (id_lote, tipo, cantidad_kg, referencia_tipo, referencia_id, id_usuario) VALUES (?, 'SALIDA', ?, 'PEDIDO', ?, ?)",
                l.get("id_lote"), tomar, idPedido, idUsuario);
            falta = falta.subtract(tomar);
        }
        if (falta.signum() > 0) throw new IllegalArgumentException("No hay inventario suficiente para descontar " + kg + " kg.");
    }
}
