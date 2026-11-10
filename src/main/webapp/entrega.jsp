<% String[] permitidos = {"DOMICILIARIO"}; %>
<%@ include file="/WEB-INF/jspf/encabezado.jspf" %>
<%
    // ----- Interfaz entrega: HU-16 Entregar pedido -----
    try {
        if ("entregar".equals(accion)) {
            String exitosa = Validacion.obligatorio(request.getParameter("exitosa"), "resultado de la entrega");
            ok = Pedido.entregarPedido(Long.parseLong(request.getParameter("id")), "SI".equals(exitosa),
                request.getParameter("recibido"), request.getParameter("motivo"), request.getParameter("pago") != null, idUsuario);
        }
    } catch (IllegalArgumentException e) {
        error = e.getMessage() + " Digite los datos de nuevo.";
    } catch (Exception e) {
        error = "No se pudo completar la operación: " + e.getMessage();
    }
    String filtro = "ADMIN".equals(rol) ? "" : " AND dm.id_usuario = " + idUsuario;
    List<Map<String, Object>> entregas = Consulta.lista(
        "SELECT e.id_entrega, p.codigo, c.nombre, c.telefono, dc.direccion, dc.barrio, p.total, p.estado_pago, mp.nombre AS medio, dm.nombre AS domiciliario, " +
        " (SELECT rotulo FROM paquete k WHERE k.id_pedido = p.id_pedido ORDER BY k.id_paquete DESC LIMIT 1) AS rotulo " +
        "FROM entrega e JOIN pedido p ON p.id_pedido = e.id_pedido JOIN cliente c ON c.id_cliente = p.id_cliente " +
        "JOIN domiciliario dm ON dm.id_domiciliario = e.id_domiciliario LEFT JOIN direccion_cliente dc ON dc.id_direccion = p.id_direccion " +
        "LEFT JOIN medio_pago mp ON mp.id_medio_pago = p.id_medio_pago WHERE e.exitosa IS NULL" + filtro + " ORDER BY e.fecha_asignacion");
%>
<h1>Interfaz entrega</h1>
<%@ include file="/WEB-INF/jspf/mensajes.jspf" %>
<section class="tarjeta">
  <h2>Entregar pedido <small>HU-16</small></h2>
  <% if (entregas.isEmpty()) { %><p class="vacio">No tiene pedidos asignados por entregar.</p><% } %>
  <% for (Map<String, Object> e : entregas) { boolean pendiente = "PENDIENTE".equals(e.get("estado_pago")); %>
    <form method="post" action="entrega.jsp" class="bloque">
      <input type="hidden" name="accion" value="entregar"><input type="hidden" name="id" value="<%= e.get("id_entrega") %>">
      <h3><%= e.get("codigo") %> · <%= Consulta.h(e.get("nombre")) %></h3>
      <p><b>Dirección:</b> <%= Consulta.h(e.get("direccion")) %> (<%= Consulta.h(e.get("barrio")) %>) · <b>Tel:</b> <%= e.get("telefono") %><br>
         <b>Rótulo:</b> <%= Consulta.h(e.get("rotulo")) %><br>
         <b>Total:</b> <%= Consulta.pesos(e.get("total")) %> · <b>Pago:</b> <%= e.get("estado_pago") %> (<%= Consulta.h(e.get("medio")) %>)
         <% if ("ADMIN".equals(rol)) { %> · <b>Domiciliario:</b> <%= Consulta.h(e.get("domiciliario")) %><% } %></p>
      <div class="en-linea">
        <label class="check"><input type="radio" name="exitosa" value="SI" checked> Entrega exitosa</label>
        <input name="recibido" placeholder="Recibido por">
        <% if (pendiente) { %><label class="check"><input type="checkbox" name="pago"> Recibí el pago</label><% } %>
      </div>
      <div class="en-linea">
        <label class="check"><input type="radio" name="exitosa" value="NO"> Entrega no exitosa</label>
        <input name="motivo" placeholder="Motivo (dirección errada, cliente ausente…)">
      </div>
      <button class="boton primario" type="submit">Registrar entrega</button>
    </form>
  <% } %>
</section>
<%@ include file="/WEB-INF/jspf/pie.jspf" %>
