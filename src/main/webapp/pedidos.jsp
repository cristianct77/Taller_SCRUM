<% String[] permitidos = {"CLIENTE", "ATENCION_CLIENTE"}; %>
<%@ include file="/WEB-INF/jspf/encabezado.jspf" %>
<%
    // ----- Interfaz pedidos: HU-01 Solicitar pedido, HU-02 Registrar pedido -----
    boolean esCliente = "CLIENTE".equals(rol);
    Long idClienteSesion = null;
    if (esCliente) {
        Map<String, Object> cli = Consulta.uno("SELECT id_cliente FROM cliente WHERE id_usuario = ?", idUsuario);
        if (cli != null) idClienteSesion = ((Number) cli.get("id_cliente")).longValue();
    }
    String estadoMostrado = null;
    try {
        if ("solicitar".equals(accion)) {
            long idCliente = esCliente ? idClienteSesion : Long.parseLong(Validacion.obligatorio(request.getParameter("cliente"), "cliente"));
            String codigo = Pedido.solicitarPedido(idCliente, request.getParameter("entrega"), request.getParameter("observaciones"),
                    request.getParameterValues("producto"), request.getParameterValues("kg"));
            ok = "Pedido solicitado: " + codigo + " (estado Solicitado).";
        } else if ("registrar".equals(accion) && !esCliente) {
            long id = Long.parseLong(request.getParameter("id"));
            Pedido.registrarPedido(id, idUsuario);
            Map<String, Object> p = Consulta.uno("SELECT codigo, estado FROM pedido WHERE id_pedido = ?", id);
            ok = "Pedido " + p.get("codigo") + " registrado.";
            estadoMostrado = (String) p.get("estado");
        } else if ("confirmar".equals(accion) && !esCliente) {
            Pedido.confirmarPedido(Long.parseLong(request.getParameter("id")), Integer.parseInt(request.getParameter("medio")), idUsuario);
            ok = "Pedido confirmado: pasa a preparación.";
        }
    } catch (IllegalArgumentException e) {
        error = e.getMessage() + " Digite los datos de nuevo.";
    } catch (Exception e) {
        error = "No se pudo completar la operación: " + e.getMessage();
    }
    List<Map<String, Object>> productos = Consulta.lista(
        "SELECT p.id_producto, p.nombre, v.precio_kg FROM producto p JOIN v_precio_vigente v ON v.id_producto = p.id_producto AND v.id_sede = 1 WHERE p.activo ORDER BY p.nombre");
    List<Map<String, Object>> clientes = Consulta.lista("SELECT id_cliente, nombre, num_documento FROM cliente ORDER BY nombre");
%>
<h1>Interfaz pedidos</h1>
<%@ include file="/WEB-INF/jspf/mensajes.jspf" %>
<% if (estadoMostrado != null) { %><div class="estado-grande">Estado del pedido: <span class="tag <%= estadoMostrado %>"><%= estadoMostrado %></span></div><% } %>

<section class="tarjeta">
  <h2>Solicitar pedido <small>HU-01</small></h2>
  <% if (esCliente && idClienteSesion == null) { %>
    <div class="msg error">Su usuario no está asociado a un cliente.</div>
  <% } else { %>
  <form method="post" action="pedidos.jsp" id="form-solicitar">
    <input type="hidden" name="accion" value="solicitar">
    <div class="fila">
      <% if (!esCliente) { %>
      <label>Cliente
        <select name="cliente" required>
          <option value="">Seleccione…</option>
          <% for (Map<String, Object> c : clientes) { %><option value="<%= c.get("id_cliente") %>"><%= Consulta.h(c.get("nombre")) %> (<%= c.get("num_documento") %>)</option><% } %>
        </select>
      </label>
      <% } %>
      <label>Método de entrega
        <select name="entrega"><option value="DOMICILIO">Domicilio</option><option value="RECOGER">Recoger en el local</option></select>
      </label>
    </div>
    <table class="grid">
      <thead><tr><th>Producto</th><th>Cantidad (kg)</th></tr></thead>
      <tbody>
      <% for (int i = 0; i < 4; i++) { %>
        <tr>
          <td><select name="producto"><option value="">—</option>
            <% for (Map<String, Object> p : productos) { %><option value="<%= p.get("id_producto") %>"><%= Consulta.h(p.get("nombre")) %> · <%= Consulta.pesos(p.get("precio_kg")) %>/kg</option><% } %>
          </select></td>
          <td><input name="kg" inputmode="decimal" placeholder="0.0"></td>
        </tr>
      <% } %>
      </tbody>
    </table>
    <label>Observaciones <input name="observaciones" maxlength="250"></label>
    <button class="boton primario" type="submit">Solicitar pedido</button>
  </form>
  <% } %>
</section>

<% if (!esCliente) {
     List<Map<String, Object>> solicitados = Consulta.lista(
        "SELECT p.id_pedido, p.codigo, c.nombre, p.metodo_entrega, p.fecha_solicitud, " +
        " (SELECT GROUP_CONCAT(CONCAT(pr.nombre,' ',CAST(d.cantidad_solicitada_kg AS DOUBLE),' kg') SEPARATOR ', ') FROM detalle_pedido d JOIN producto pr ON pr.id_producto=d.id_producto WHERE d.id_pedido=p.id_pedido) AS productos " +
        "FROM pedido p JOIN cliente c ON c.id_cliente = p.id_cliente WHERE p.estado = 'SOLICITADO' ORDER BY p.fecha_solicitud");
     List<Map<String, Object>> porConfirmar = Consulta.lista(
        "SELECT p.id_pedido, p.codigo, c.nombre, p.total FROM pedido p JOIN cliente c ON c.id_cliente = p.id_cliente " +
        "WHERE p.estado = 'REGISTRADO' AND p.total > 0 ORDER BY p.id_pedido");
     List<Map<String, Object>> medios = Consulta.lista("SELECT id_medio_pago, nombre FROM medio_pago WHERE activo");
%>
<section class="tarjeta">
  <h2>Registrar pedido <small>HU-02</small></h2>
  <% if (solicitados.isEmpty()) { %><p class="vacio">No hay pedidos solicitados por registrar.</p><% } else { %>
  <table class="grid">
    <thead><tr><th>Pedido</th><th>Cliente</th><th>Productos</th><th>Entrega</th><th></th></tr></thead>
    <tbody>
    <% for (Map<String, Object> p : solicitados) { %>
      <tr><td><%= p.get("codigo") %></td><td><%= Consulta.h(p.get("nombre")) %></td><td><%= Consulta.h(p.get("productos")) %></td><td><%= p.get("metodo_entrega") %></td>
        <td><form method="post" action="pedidos.jsp"><input type="hidden" name="accion" value="registrar"><input type="hidden" name="id" value="<%= p.get("id_pedido") %>"><button class="boton" type="submit">Registrar</button></form></td></tr>
    <% } %>
    </tbody>
  </table>
  <% } %>
</section>

<section class="tarjeta">
  <h2>Confirmar pedido y medio de pago</h2>
  <% if (porConfirmar.isEmpty()) { %><p class="vacio">No hay pedidos con total calculado por confirmar.</p><% } else { %>
  <table class="grid">
    <thead><tr><th>Pedido</th><th>Cliente</th><th>Total</th><th>Medio de pago</th></tr></thead>
    <tbody>
    <% for (Map<String, Object> p : porConfirmar) { %>
      <tr><td><%= p.get("codigo") %></td><td><%= Consulta.h(p.get("nombre")) %></td><td><%= Consulta.pesos(p.get("total")) %></td>
        <td><form method="post" action="pedidos.jsp" class="en-linea"><input type="hidden" name="accion" value="confirmar"><input type="hidden" name="id" value="<%= p.get("id_pedido") %>">
          <select name="medio"><% for (Map<String, Object> m : medios) { %><option value="<%= m.get("id_medio_pago") %>"><%= m.get("nombre") %></option><% } %></select>
          <button class="boton" type="submit">Confirmar</button></form></td></tr>
    <% } %>
    </tbody>
  </table>
  <% } %>
</section>
<% } %>

<%
    List<Map<String, Object>> pedidos = esCliente
        ? Consulta.lista("SELECT p.codigo, c.nombre, p.estado, p.estado_pago, p.total, p.fecha_solicitud FROM pedido p JOIN cliente c ON c.id_cliente = p.id_cliente WHERE p.id_cliente = ? ORDER BY p.id_pedido DESC LIMIT 20", idClienteSesion)
        : Consulta.lista("SELECT p.codigo, c.nombre, p.estado, p.estado_pago, p.total, p.fecha_solicitud FROM pedido p JOIN cliente c ON c.id_cliente = p.id_cliente ORDER BY p.id_pedido DESC LIMIT 20");
%>
<section class="tarjeta">
  <h2><%= esCliente ? "Mis pedidos" : "Últimos pedidos" %></h2>
  <% if (pedidos.isEmpty()) { %><p class="vacio">Sin pedidos.</p><% } else { %>
  <table class="grid">
    <thead><tr><th>Pedido</th><th>Cliente</th><th>Estado</th><th>Pago</th><th>Total</th><th>Fecha</th></tr></thead>
    <tbody>
    <% for (Map<String, Object> p : pedidos) { %>
      <tr><td><%= p.get("codigo") %></td><td><%= Consulta.h(p.get("nombre")) %></td><td><span class="tag <%= p.get("estado") %>"><%= p.get("estado") %></span></td>
        <td><%= p.get("estado_pago") %></td><td><%= Consulta.pesos(p.get("total")) %></td><td><%= p.get("fecha_solicitud") %></td></tr>
    <% } %>
    </tbody>
  </table>
  <% } %>
</section>
<%@ include file="/WEB-INF/jspf/pie.jspf" %>
