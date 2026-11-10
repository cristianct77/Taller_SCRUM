package richpos;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.Connection;
import java.sql.SQLException;
import java.util.*;

/**
 * Clase Pedido: SolicitarPedido() HU-01, RegistrarPedido() HU-02, CalcularTotal() HU-06,
 * EntregarPedido() HU-16. Incluye ConfirmarPedido() para pasar el pedido a preparación.
 */
public class Pedido {

    public static final long SEDE = 1;

    /** HU-01 Solicitar pedido: guarda el pedido en estado SOLICITADO y devuelve su código. */
    public static String solicitarPedido(long idCliente, String metodoEntrega, String observaciones,
                                         String[] productos, String[] cantidades) throws SQLException {
        if (!"RECOGER".equals(metodoEntrega) && !"DOMICILIO".equals(metodoEntrega))
            throw new IllegalArgumentException("Seleccione el método de entrega.");
        Map<Long, BigDecimal> lineas = new LinkedHashMap<>();
        for (int i = 0; productos != null && i < productos.length; i++) {
            if (productos[i] == null || productos[i].isBlank()) continue;
            long idProducto = Long.parseLong(productos[i]);
            BigDecimal kg = Validacion.positivo(cantidades[i], "cantidad (kg)");
            if (lineas.containsKey(idProducto)) throw new IllegalArgumentException("Un producto está repetido en el pedido.");
            lineas.put(idProducto, kg);
        }
        if (lineas.isEmpty()) throw new IllegalArgumentException("Digite al menos un producto con su cantidad en kg.");

        try (Connection c = Conexion.getConexion()) {
            c.setAutoCommit(false);
            try {
                if (Consulta.uno(c, "SELECT id_cliente FROM cliente WHERE id_cliente = ?", idCliente) == null)
                    throw new IllegalArgumentException("El cliente no existe.");
                Object idDireccion = null;
                if ("DOMICILIO".equals(metodoEntrega)) {
                    Map<String, Object> d = Consulta.uno(c,
                        "SELECT id_direccion FROM direccion_cliente WHERE id_cliente = ? ORDER BY principal DESC LIMIT 1", idCliente);
                    if (d == null) throw new IllegalArgumentException("El cliente no tiene dirección para el domicilio.");
                    idDireccion = d.get("id_direccion");
                }
                long id = Consulta.insertar(c,
                    "INSERT INTO pedido (codigo, id_sede, id_cliente, id_direccion, canal, metodo_entrega, observaciones) " +
                    "VALUES (?, ?, ?, ?, 'WEB', ?, ?)", "T" + System.nanoTime(), SEDE, idCliente, idDireccion, metodoEntrega, observaciones);
                String codigo = String.format("PED-%05d", id);
                Consulta.ejecutar(c, "UPDATE pedido SET codigo = ? WHERE id_pedido = ?", codigo, id);
                for (Map.Entry<Long, BigDecimal> l : lineas.entrySet()) {
                    Consulta.ejecutar(c, "INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad_solicitada_kg) VALUES (?, ?, ?)",
                        id, l.getKey(), l.getValue());
                }
                historial(c, id, null, "SOLICITADO", null, "Pedido solicitado");
                c.commit();
                return codigo;
            } catch (SQLException | RuntimeException e) {
                c.rollback();
                throw e;
            }
        }
    }

    /** HU-02 Registrar pedido: pasa un pedido SOLICITADO a REGISTRADO. */
    public static void registrarPedido(long idPedido, long idUsuario) throws SQLException {
        try (Connection c = Conexion.getConexion()) {
            exigirEstado(c, idPedido, "SOLICITADO");
            Consulta.ejecutar(c, "UPDATE pedido SET fecha_registro = NOW(), id_usuario_registro = ? WHERE id_pedido = ?", idUsuario, idPedido);
            cambiarEstado(c, idPedido, "REGISTRADO", idUsuario, "Pedido registrado por Atención al Cliente");
        }
    }

    /**
     * HU-06 Calcular total: con el peso real (kg) de cada producto disponible, multiplica por el
     * precio vigente, guarda subtotales y total, y lo devuelve.
     */
    public static BigDecimal calcularTotal(long idPedido, Map<Long, String> pesosPorDetalle, long idUsuario) throws SQLException {
        try (Connection c = Conexion.getConexion()) {
            c.setAutoCommit(false);
            try {
                Map<String, Object> p = exigirEstado(c, idPedido, "REGISTRADO");
                List<Map<String, Object>> detalles = Consulta.lista(c,
                    "SELECT d.id_detalle, d.id_producto, d.estado, pr.nombre, v.precio_kg " +
                    "  FROM detalle_pedido d JOIN producto pr ON pr.id_producto = d.id_producto " +
                    "  LEFT JOIN v_precio_vigente v ON v.id_producto = d.id_producto AND v.id_sede = ? " +
                    " WHERE d.id_pedido = ?", SEDE, idPedido);
                BigDecimal subtotal = BigDecimal.ZERO;
                int lineas = 0;
                for (Map<String, Object> d : detalles) {
                    String estado = (String) d.get("estado");
                    if ("SOLICITADO".equals(estado))
                        throw new IllegalArgumentException("Primero verifique la disponibilidad de todos los productos.");
                    if (!"DISPONIBLE".equals(estado) && !"PESADO".equals(estado)) continue;
                    long idDetalle = ((Number) d.get("id_detalle")).longValue();
                    BigDecimal peso = Validacion.positivo(pesosPorDetalle.getOrDefault(idDetalle, ""), "peso de " + d.get("nombre"));
                    if (d.get("precio_kg") == null) throw new IllegalArgumentException("El producto " + d.get("nombre") + " no tiene precio vigente.");
                    BigDecimal precio = Consulta.num(d.get("precio_kg"));
                    BigDecimal valor = peso.multiply(precio).setScale(0, RoundingMode.HALF_UP);
                    Consulta.ejecutar(c, "UPDATE detalle_pedido SET peso_real_kg = ?, precio_kg = ?, subtotal = ?, estado = 'PESADO' WHERE id_detalle = ?",
                        peso, precio, valor, idDetalle);
                    subtotal = subtotal.add(valor);
                    lineas++;
                }
                if (lineas == 0) throw new IllegalArgumentException("El pedido no tiene productos disponibles para pesar.");
                BigDecimal domicilio = "DOMICILIO".equals(p.get("metodo_entrega"))
                        ? new BigDecimal(parametro(c, "VALOR_DOMICILIO")) : BigDecimal.ZERO;
                BigDecimal total = subtotal.add(domicilio);
                Consulta.ejecutar(c, "UPDATE pedido SET subtotal = ?, valor_domicilio = ?, total = ? WHERE id_pedido = ?",
                    subtotal, domicilio, total, idPedido);
                c.commit();
                return total;
            } catch (SQLException | RuntimeException e) {
                c.rollback();
                throw e;
            }
        }
    }

    /** Confirmar pedido (paso previo a la preparación): fija el medio de pago acordado. */
    public static void confirmarPedido(long idPedido, int idMedioPago, long idUsuario) throws SQLException {
        try (Connection c = Conexion.getConexion()) {
            Map<String, Object> p = exigirEstado(c, idPedido, "REGISTRADO");
            if (Consulta.num(p.get("total")).signum() <= 0)
                throw new IllegalArgumentException("Calcule el total del pedido antes de confirmarlo.");
            Consulta.ejecutar(c, "UPDATE pedido SET id_medio_pago = ? WHERE id_pedido = ?", idMedioPago, idPedido);
            cambiarEstado(c, idPedido, "CONFIRMADO", idUsuario, "Pedido confirmado con el cliente");
        }
    }

    /**
     * HU-16 Entregar pedido: si la entrega es exitosa el pedido queda ENTREGADO (y PAGADO si se
     * recibe el pago); si no, vuelve a EN_PREPARACION y el paquete queda EN_AJUSTE.
     */
    public static String entregarPedido(long idEntrega, boolean exitosa, String recibidoPor, String motivo,
                                        boolean pagoRecibido, long idUsuario) throws SQLException {
        try (Connection c = Conexion.getConexion()) {
            c.setAutoCommit(false);
            try {
                Map<String, Object> e = Consulta.uno(c,
                    "SELECT e.id_pedido, e.exitosa, p.estado, p.estado_pago, p.total, p.id_medio_pago FROM entrega e " +
                    "JOIN pedido p ON p.id_pedido = e.id_pedido WHERE e.id_entrega = ?", idEntrega);
                if (e == null || e.get("exitosa") != null) throw new IllegalArgumentException("La entrega no existe o ya fue registrada.");
                long idPedido = ((Number) e.get("id_pedido")).longValue();
                if (!"DESPACHADO".equals(e.get("estado"))) throw new IllegalArgumentException("El pedido no está despachado.");
                String resultado;
                if (exitosa) {
                    Validacion.obligatorio(recibidoPor, "recibido por");
                    Consulta.ejecutar(c, "UPDATE entrega SET exitosa = TRUE, fecha_entrega = NOW(), recibido_por = ? WHERE id_entrega = ?",
                        recibidoPor.trim(), idEntrega);
                    Consulta.ejecutar(c, "UPDATE paquete SET estado = 'ENTREGADO' WHERE id_pedido = ? AND estado = 'DESPACHADO'", idPedido);
                    cambiarEstado(c, idPedido, "ENTREGADO", idUsuario, "Entregado a " + recibidoPor.trim());
                    resultado = "Pedido entregado";
                    if (pagoRecibido && "PENDIENTE".equals(e.get("estado_pago"))) {
                        registrarPago(c, idPedido, e.get("id_medio_pago"), Consulta.num(e.get("total")), "DOMICILIARIO", idUsuario);
                        cambiarEstado(c, idPedido, "PAGADO", idUsuario, "Pago recibido en la entrega");
                        resultado = "Pedido entregado y pagado";
                    }
                } else {
                    Validacion.obligatorio(motivo, "motivo de la entrega no exitosa");
                    Consulta.ejecutar(c, "UPDATE entrega SET exitosa = FALSE, fecha_entrega = NOW(), motivo_fallo = ? WHERE id_entrega = ?",
                        motivo.trim(), idEntrega);
                    Consulta.ejecutar(c, "UPDATE paquete SET estado = 'EN_AJUSTE' WHERE id_pedido = ? AND estado = 'DESPACHADO'", idPedido);
                    cambiarEstado(c, idPedido, "EN_PREPARACION", idUsuario, "Entrega no exitosa: " + motivo.trim());
                    resultado = "Entrega no exitosa: el pedido vuelve a preparación para ajuste";
                }
                c.commit();
                return resultado;
            } catch (SQLException | RuntimeException ex) {
                c.rollback();
                throw ex;
            }
        }
    }

    // ------------------------------------------------------------------ apoyo

    static void registrarPago(Connection c, long idPedido, Object idMedioPago, BigDecimal valor, String recibidoPor, long idUsuario) throws SQLException {
        long idPago = Consulta.insertar(c,
            "INSERT INTO pago (id_pedido, id_medio_pago, valor, recibido_por, id_usuario) VALUES (?, ?, ?, ?, ?)",
            idPedido, idMedioPago == null ? 1 : idMedioPago, valor, recibidoPor, idUsuario);
        Consulta.ejecutar(c, "UPDATE pedido SET estado_pago = 'PAGADO' WHERE id_pedido = ?", idPedido);
        Consulta.ejecutar(c,
            "INSERT INTO movimiento_caja (id_sede, tipo, concepto, valor, referencia_tipo, referencia_id, id_usuario) " +
            "VALUES (?, 'INGRESO', 'Pago de pedido', ?, 'PAGO', ?, ?)", SEDE, valor, idPago, idUsuario);
    }

    static Map<String, Object> exigirEstado(Connection c, long idPedido, String... estados) throws SQLException {
        Map<String, Object> p = Consulta.uno(c, "SELECT * FROM pedido WHERE id_pedido = ?", idPedido);
        if (p == null) throw new IllegalArgumentException("El pedido no existe.");
        if (!Arrays.asList(estados).contains(p.get("estado")))
            throw new IllegalArgumentException("El pedido " + p.get("codigo") + " está en estado " + p.get("estado")
                    + "; se esperaba " + String.join(" o ", estados) + ".");
        return p;
    }

    static void cambiarEstado(Connection c, long idPedido, String nuevo, Long idUsuario, String observacion) throws SQLException {
        Map<String, Object> p = Consulta.uno(c, "SELECT estado FROM pedido WHERE id_pedido = ?", idPedido);
        Consulta.ejecutar(c, "UPDATE pedido SET estado = ? WHERE id_pedido = ?", nuevo, idPedido);
        historial(c, idPedido, (String) p.get("estado"), nuevo, idUsuario, observacion);
    }

    static void historial(Connection c, long idPedido, String anterior, String nuevo, Long idUsuario, String obs) throws SQLException {
        Consulta.ejecutar(c, "INSERT INTO pedido_historial (id_pedido, estado_anterior, estado_nuevo, id_usuario, observacion) VALUES (?, ?, ?, ?, ?)",
            idPedido, anterior, nuevo, idUsuario, obs);
    }

    static String parametro(Connection c, String clave) throws SQLException {
        return (String) Consulta.uno(c, "SELECT valor FROM parametro WHERE clave = ?", clave).get("valor");
    }
}
