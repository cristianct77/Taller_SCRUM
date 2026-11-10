package richpos;

import java.math.BigDecimal;
import java.sql.*;
import java.text.NumberFormat;
import java.util.*;

/** Utilidades JDBC sencillas para consultar y ejecutar sentencias. */
public class Consulta {

    /** Ejecuta un SELECT y devuelve las filas como lista de mapas (columna -> valor). */
    public static List<Map<String, Object>> lista(String sql, Object... parametros) throws SQLException {
        try (Connection c = Conexion.getConexion()) {
            return lista(c, sql, parametros);
        }
    }

    public static List<Map<String, Object>> lista(Connection c, String sql, Object... parametros) throws SQLException {
        List<Map<String, Object>> filas = new ArrayList<>();
        try (PreparedStatement ps = preparar(c, sql, parametros); ResultSet rs = ps.executeQuery()) {
            ResultSetMetaData md = rs.getMetaData();
            while (rs.next()) {
                Map<String, Object> fila = new LinkedHashMap<>();
                for (int i = 1; i <= md.getColumnCount(); i++) {
                    fila.put(md.getColumnLabel(i), rs.getObject(i));
                }
                filas.add(fila);
            }
        }
        return filas;
    }

    /** Devuelve la primera fila o null. */
    public static Map<String, Object> uno(Connection c, String sql, Object... parametros) throws SQLException {
        List<Map<String, Object>> l = lista(c, sql, parametros);
        return l.isEmpty() ? null : l.get(0);
    }

    public static Map<String, Object> uno(String sql, Object... parametros) throws SQLException {
        try (Connection c = Conexion.getConexion()) {
            return uno(c, sql, parametros);
        }
    }

    /** Ejecuta INSERT/UPDATE/DELETE y devuelve las filas afectadas. */
    public static int ejecutar(Connection c, String sql, Object... parametros) throws SQLException {
        try (PreparedStatement ps = preparar(c, sql, parametros)) {
            return ps.executeUpdate();
        }
    }

    /** Ejecuta un INSERT y devuelve la llave generada. */
    public static long insertar(Connection c, String sql, Object... parametros) throws SQLException {
        try (PreparedStatement ps = c.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {
            for (int i = 0; i < parametros.length; i++) ps.setObject(i + 1, parametros[i]);
            ps.executeUpdate();
            try (ResultSet rs = ps.getGeneratedKeys()) {
                rs.next();
                return rs.getLong(1);
            }
        }
    }

    private static PreparedStatement preparar(Connection c, String sql, Object... parametros) throws SQLException {
        PreparedStatement ps = c.prepareStatement(sql);
        for (int i = 0; i < parametros.length; i++) ps.setObject(i + 1, parametros[i]);
        return ps;
    }

    /** Convierte un valor numérico de la base de datos a BigDecimal. */
    public static BigDecimal num(Object v) {
        if (v == null) return BigDecimal.ZERO;
        return (v instanceof BigDecimal) ? (BigDecimal) v : new BigDecimal(v.toString());
    }

    /** Formato de pesos colombianos: $ 12.500 */
    public static String pesos(Object v) {
        NumberFormat f = NumberFormat.getIntegerInstance(new Locale("es", "CO"));
        return "$ " + f.format(num(v));
    }

    /** Muestra kilos sin ceros sobrantes: 4.000 -> 4, 37.400 -> 37.4 */
    public static String kg(Object v) {
        if (v == null) return "";
        BigDecimal b = num(v).stripTrailingZeros();
        return b.scale() < 0 ? b.setScale(0).toPlainString() : b.toPlainString();
    }

    /** Escapa texto para mostrarlo en HTML. */
    public static String h(Object v) {
        if (v == null) return "";
        return v.toString().replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;");
    }
}
