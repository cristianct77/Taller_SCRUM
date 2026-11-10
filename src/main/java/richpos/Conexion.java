package richpos;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;

/** Conexión a la base de datos MySQL "richpos". Cambie USUARIO y CLAVE según su instalación. */
public class Conexion {

    private static final String DRIVER  = valor("DB_DRIVER", "com.mysql.cj.jdbc.Driver");
    private static final String URL     = valor("DB_URL",
            "jdbc:mysql://localhost:3306/richpos?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=America/Bogota");
    private static final String USUARIO = valor("DB_USER", "root");
    private static final String CLAVE   = valor("DB_PASS", "");

    public static Connection getConexion() throws SQLException {
        try {
            Class.forName(DRIVER);
        } catch (ClassNotFoundException e) {
            throw new SQLException("No se encontró el conector JDBC: " + DRIVER, e);
        }
        return DriverManager.getConnection(URL, USUARIO, CLAVE);
    }

    /** Permite sobrescribir la configuración con variables de entorno. */
    private static String valor(String variable, String porDefecto) {
        String v = System.getenv(variable);
        return (v == null || v.isEmpty()) ? porDefecto : v;
    }
}
