package richpos;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.SQLException;
import java.util.List;
import java.util.Map;

/** Clase Paquete: EmpacarSellarProducto() HU-43 y despacho del pedido. */
public class Paquete {

    /**
     * HU-43 Empacar y sellar producto: empaca los cortes conformes del pedido en un paquete
     * (estado EMPACADO), lo rotula y descuenta el inventario. Devuelve el id del paquete.
     */
    public static long empacarSellarProducto(long idPedido, String tipoEmpaque, boolean sellado, long idUsuario) throws SQLException {
        if (!"BANDEJA".equals(tipoEmpaque) && !"BOLSA".equals(tipoEmpaque) && !"CAJA".equals(tipoEmpaque))
            throw new IllegalArgumentException("Seleccione el tipo de empaque.");
        if (!sellado) throw new IllegalArgumentException("El producto debe quedar sellado para empacarlo.");
        try (Connection c = Conexion.getConexion()) {
            c.setAutoCommit(false);
            try {
                Map<String, Object> p = Pedido.exigirEstado(c, idPedido, "EN_PREPARACION");
                // cada producto pesado debe tener al menos un corte conforme sin empacar
                List<Map<String, Object>> faltan = Consulta.lista(c,
                    "SELECT pr.nombre FROM detalle_pedido d JOIN producto pr ON pr.id_producto = d.id_producto " +
                    " WHERE d.id_pedido = ? AND d.estado = 'PESADO' AND NOT EXISTS (" +
                    "   SELECT 1 FROM corte k WHERE k.id_detalle = d.id_detalle AND k.conforme = TRUE)", idPedido);
                if (!faltan.isEmpty())
                    throw new IllegalArgumentException("Falta verificar un corte conforme de: " + faltan.get(0).get("nombre"));
                List<Map<String, Object>> cortes = Consulta.lista(c,
                    "SELECT k.id_corte, k.peso_kg FROM corte k JOIN detalle_pedido d ON d.id_detalle = k.id_detalle " +
                    " WHERE d.id_pedido = ? AND k.conforme = TRUE " +
                    "   AND NOT EXISTS (SELECT 1 FROM paquete_corte pc WHERE pc.id_corte = k.id_corte)", idPedido);
                if (cortes.isEmpty()) throw new IllegalArgumentException("No hay cortes conformes pendientes por empacar.");
                BigDecimal peso = BigDecimal.ZERO;
                for (Map<String, Object> k : cortes) peso = peso.add(Consulta.num(k.get("peso_kg")));

                Map<String, Object> cli = Consulta.uno(c,
                    "SELECT cl.nombre, cl.telefono, dc.direccion FROM pedido pe JOIN cliente cl ON cl.id_cliente = pe.id_cliente " +
                    "LEFT JOIN direccion_cliente dc ON dc.id_direccion = pe.id_direccion WHERE pe.id_pedido = ?", idPedido);
                String rotulo = p.get("codigo") + " | " + cli.get("nombre") + " | " + cli.get("telefono")
                        + (cli.get("direccion") != null ? " | " + cli.get("direccion") : " | Recoge en el local");
                long idPaquete = Consulta.insertar(c,
                    "INSERT INTO paquete (id_pedido, tipo_empaque, peso_total_kg, sellado, rotulo, estado, id_usuario) VALUES (?, ?, ?, TRUE, ?, 'EMPACADO', ?)",
                    idPedido, tipoEmpaque, peso, rotulo, idUsuario);
                for (Map<String, Object> k : cortes)
                    Consulta.ejecutar(c, "INSERT INTO paquete_corte (id_paquete, id_corte) VALUES (?, ?)", idPaquete, k.get("id_corte"));

                // salida de inventario por el peso real vendido de cada producto (solo la primera vez)
                boolean yaDescontado = Consulta.uno(c,
                    "SELECT 1 FROM movimiento_inventario WHERE referencia_tipo = 'PEDIDO' AND referencia_id = ? LIMIT 1", idPedido) != null;
                if (!yaDescontado) {
                    for (Map<String, Object> d : Consulta.lista(c,
                            "SELECT id_producto, peso_real_kg FROM detalle_pedido WHERE id_pedido = ? AND estado = 'PESADO'", idPedido)) {
                        Producto.descontarInventario(c, ((Number) d.get("id_producto")).longValue(),
                            Consulta.num(d.get("peso_real_kg")), idPedido, idUsuario);
                    }
                }
                c.commit();
                return idPaquete;
            } catch (SQLException | RuntimeException e) {
                c.rollback();
                throw e;
            }
        }
    }

    /**
     * Despachar: si el pedido es a domicilio se asigna al domiciliario (paquete DESPACHADO);
     * si el cliente recoge en el local, se entrega en el punto de venta.
     */
    public static String despachar(long idPedido, Long idDomiciliario, long idUsuario) throws SQLException {
        try (Connection c = Conexion.getConexion()) {
            c.setAutoCommit(false);
            try {
                Map<String, Object> p = Pedido.exigirEstado(c, idPedido, "EN_PREPARACION");
                if (Consulta.uno(c, "SELECT 1 FROM paquete WHERE id_pedido = ? AND estado IN ('EMPACADO','EN_AJUSTE')", idPedido) == null)
                    throw new IllegalArgumentException("Primero empaque y selle el producto.");
                String r;
                if ("DOMICILIO".equals(p.get("metodo_entrega"))) {
                    if (idDomiciliario == null) throw new IllegalArgumentException("Seleccione el domiciliario.");
                    Consulta.ejecutar(c, "INSERT INTO entrega (id_pedido, id_domiciliario) VALUES (?, ?)", idPedido, idDomiciliario);
                    Consulta.ejecutar(c, "UPDATE paquete SET estado = 'DESPACHADO' WHERE id_pedido = ? AND estado IN ('EMPACADO','EN_AJUSTE')", idPedido);
                    Pedido.cambiarEstado(c, idPedido, "DESPACHADO", idUsuario, "Asignado al domiciliario");
                    r = "Pedido despachado al domiciliario";
                } else {
                    Consulta.ejecutar(c, "UPDATE paquete SET estado = 'ENTREGADO' WHERE id_pedido = ? AND estado IN ('EMPACADO','EN_AJUSTE')", idPedido);
                    Pedido.cambiarEstado(c, idPedido, "DESPACHADO", idUsuario, "Listo en mostrador");
                    Pedido.cambiarEstado(c, idPedido, "ENTREGADO", idUsuario, "Entregado en el punto de venta");
                    if ("PENDIENTE".equals(p.get("estado_pago"))) {
                        Pedido.registrarPago(c, idPedido, p.get("id_medio_pago"), Consulta.num(p.get("total")), "PUNTO_VENTA", idUsuario);
                        Pedido.cambiarEstado(c, idPedido, "PAGADO", idUsuario, "Pago en el punto de venta");
                    }
                    r = "Pedido entregado y pagado en el punto de venta";
                }
                c.commit();
                return r;
            } catch (SQLException | RuntimeException e) {
                c.rollback();
                throw e;
            }
        }
    }
}
