package richpos;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.SQLException;
import java.util.Map;

/** Clase Corte: VerificarCalidadTemperatura() HU-41. */
public class Corte {

    /**
     * HU-41 Verificar calidad y temperatura: guarda la verificación del corte y devuelve true si
     * es conforme (calidad aprobada y temperatura dentro del rango configurado).
     * Si no es conforme, se deben sustituir las piezas y registrar un nuevo corte.
     */
    public static boolean verificarCalidadTemperatura(long idDetalle, String especificacion, String pesoTexto,
                                                      String temperaturaTexto, boolean calidadOk, Long idCorteSustituido,
                                                      long idUsuario) throws SQLException {
        Validacion.obligatorio(especificacion, "especificación del corte");
        BigDecimal peso = Validacion.positivo(pesoTexto, "peso del corte (kg)");
        BigDecimal temp = Validacion.numero(temperaturaTexto, "temperatura (°C)");
        if (temp.compareTo(new BigDecimal("-30")) < 0 || temp.compareTo(new BigDecimal("40")) > 0)
            throw new IllegalArgumentException("La temperatura debe estar entre -30 y 40 °C.");

        try (Connection c = Conexion.getConexion()) {
            c.setAutoCommit(false);
            try {
                Map<String, Object> d = Consulta.uno(c,
                    "SELECT d.id_pedido, d.estado FROM detalle_pedido d WHERE d.id_detalle = ?", idDetalle);
                if (d == null || !"PESADO".equals(d.get("estado")))
                    throw new IllegalArgumentException("El producto no está pesado o no existe.");
                long idPedido = ((Number) d.get("id_pedido")).longValue();
                Map<String, Object> p = Pedido.exigirEstado(c, idPedido, "CONFIRMADO", "EN_PREPARACION");
                if ("CONFIRMADO".equals(p.get("estado"))) {        // Preparar pedido: se genera la comanda
                    Consulta.ejecutar(c, "INSERT INTO comanda (id_pedido, id_usuario) VALUES (?, ?)", idPedido, idUsuario);
                    Pedido.cambiarEstado(c, idPedido, "EN_PREPARACION", idUsuario, "Comanda recibida, inicia la preparación");
                }
                BigDecimal min = new BigDecimal(Pedido.parametro(c, "TEMP_MIN_CORTE_C"));
                BigDecimal max = new BigDecimal(Pedido.parametro(c, "TEMP_MAX_CORTE_C"));
                boolean conforme = calidadOk && temp.compareTo(min) >= 0 && temp.compareTo(max) <= 0;
                Consulta.insertar(c,
                    "INSERT INTO corte (id_detalle, especificacion_tecnica, peso_kg, temperatura_c, calidad_ok, conforme, id_corte_sustituido, id_usuario) " +
                    "VALUES (?, ?, ?, ?, ?, ?, ?, ?)", idDetalle, especificacion.trim(), peso, temp, calidadOk, conforme, idCorteSustituido, idUsuario);
                c.commit();
                return conforme;
            } catch (SQLException | RuntimeException e) {
                c.rollback();
                throw e;
            }
        }
    }
}
