<%@ page contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" import="java.util.*, richpos.*" %><%
    // Inicio de sesión: Digitar usuario -> Verificar autorización usuario (clase Validacion)
    request.setCharacterEncoding("UTF-8");
    if (session.getAttribute("usuario") != null) { response.sendRedirect("principal.jsp"); return; }
    Integer intentos = (Integer) session.getAttribute("intentos");
    if (intentos == null) intentos = 0;
    String error = null;
    if ("POST".equals(request.getMethod()) && intentos < 2) {
        Map<String, Object> u = Validacion.verificarAutorizacionUsuario(request.getParameter("usuario"), request.getParameter("clave"));
        if (u != null) {
            session.removeAttribute("intentos");
            session.setAttribute("usuario", u);
            response.sendRedirect("principal.jsp");
            return;
        }
        intentos++;
        session.setAttribute("intentos", intentos);
        error = "Usuario no autorizado. Digite de nuevo su usuario y contraseña.";
    }
    boolean terminado = intentos >= 2;
%><!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>RichPOS - Inicio de sesión</title>
  <link rel="stylesheet" href="css/estilos.css">
</head>
<body class="centro">
  <div class="tarjeta login">
    <h1 class="marca grande">Rich<span>POS</span></h1>
    <p class="suave">Sistema de gestión · Pollería "Rich"</p>
    <% if (terminado) { %>
      <div class="msg error">Usuario no autorizado por segunda vez. El proceso terminó.</div>
      <a class="boton" href="salir.jsp">Volver al inicio</a>
    <% } else { %>
      <% if (error != null) { %><div class="msg error"><%= error %></div><% } %>
      <form method="post" action="index.jsp">
        <label>Usuario <input name="usuario" required autofocus></label>
        <label>Contraseña <input name="clave" type="password" required></label>
        <button class="boton primario" type="submit">Ingresar</button>
      </form>
    <% } %>
  </div>
</body>
</html>
