<%@ page contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" isErrorPage="true" %><!DOCTYPE html>
<html lang="es"><head><meta charset="UTF-8"><title>RichPOS - Error</title><link rel="stylesheet" href="css/estilos.css"></head>
<body class="centro"><div class="tarjeta login">
  <h1 class="marca grande">Rich<span>POS</span></h1>
  <div class="msg error">Ocurrió un error. Verifique que la base de datos MySQL esté encendida y la configuración de Conexion.java.</div>
  <p class="suave"><%= exception != null ? richpos.Consulta.h(exception.getMessage()) : "" %></p>
  <a class="boton" href="principal.jsp">Volver</a>
</div></body></html>
