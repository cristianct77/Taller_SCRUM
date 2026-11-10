package richpos;

import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.PBEKeySpec;
import java.math.BigDecimal;
import java.security.MessageDigest;
import java.sql.Connection;
import java.sql.SQLException;
import java.util.Base64;
import java.util.Map;

/** Clase Validación: verificación de usuarios y de datos digitados. */
public class Validacion {

    /**
     * VerificarAutorizacionUsuario(): devuelve los datos del usuario si el nombre y la
     * clave son correctos y el usuario está autorizado; en otro caso devuelve null.
     */
    public static Map<String, Object> verificarAutorizacionUsuario(String usuario, String clave) throws SQLException {
        if (usuario == null || clave == null || usuario.isBlank() || clave.isBlank()) return null;
        try (Connection c = Conexion.getConexion()) {
            Map<String, Object> u = Consulta.uno(c,
                "SELECT u.id_usuario, u.nombre_usuario, u.nombre_completo, u.clave_hash, u.autorizado, " +
                "       u.id_sede, r.codigo AS rol, r.nombre AS rol_nombre " +
                "  FROM usuario u JOIN rol r ON r.id_rol = u.id_rol WHERE u.nombre_usuario = ?", usuario.trim());
            if (u == null) return null;
            boolean claveOk = claveCorrecta(clave, (String) u.get("clave_hash"));
            boolean autorizado = Boolean.TRUE.equals(u.get("autorizado")) || "1".equals(String.valueOf(u.get("autorizado")));
            if (!claveOk || !autorizado) {
                Consulta.ejecutar(c, "UPDATE usuario SET intentos_fallidos = intentos_fallidos + 1 WHERE id_usuario = ?", u.get("id_usuario"));
                return null;
            }
            Consulta.ejecutar(c, "UPDATE usuario SET intentos_fallidos = 0, ultimo_acceso = NOW() WHERE id_usuario = ?", u.get("id_usuario"));
            u.remove("clave_hash");
            return u;
        }
    }

    /** Compara la clave con el hash guardado (formato pbkdf2$iteraciones$sal$hash). */
    static boolean claveCorrecta(String clave, String guardado) {
        try {
            String[] p = guardado.split("\\$");
            int iteraciones = Integer.parseInt(p[1]);
            byte[] sal = Base64.getDecoder().decode(p[2]);
            byte[] esperado = Base64.getDecoder().decode(p[3]);
            PBEKeySpec spec = new PBEKeySpec(clave.toCharArray(), sal, iteraciones, esperado.length * 8);
            byte[] calculado = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).getEncoded();
            return MessageDigest.isEqual(esperado, calculado);
        } catch (Exception e) {
            return false;
        }
    }

    /** Convierte un texto a número positivo; lanza un error de validación si no lo es. */
    public static BigDecimal positivo(String texto, String campo) {
        try {
            BigDecimal v = new BigDecimal(texto.trim().replace(",", "."));
            if (v.signum() <= 0) throw new NumberFormatException();
            return v;
        } catch (Exception e) {
            throw new IllegalArgumentException("El campo " + campo + " debe ser un número mayor que cero.");
        }
    }

    public static BigDecimal numero(String texto, String campo) {
        try {
            return new BigDecimal(texto.trim().replace(",", "."));
        } catch (Exception e) {
            throw new IllegalArgumentException("El campo " + campo + " debe ser numérico.");
        }
    }

    public static String obligatorio(String texto, String campo) {
        if (texto == null || texto.isBlank()) throw new IllegalArgumentException("El campo " + campo + " es obligatorio.");
        return texto.trim();
    }
}
