<% String[] permitidos = {"AREA_OPERATIVA"}; %>
<%@ include file="/WEB-INF/jspf/encabezado.jspf" %>
<%
    // ----- Interfaz preparación: HU-03, HU-06, HU-41, HU-43 y despacho -----
    List<String> detalleMensajes = new ArrayList<>();
    try {
        if ("disponibilidad".equals(accion)) {
            detalleMensajes = Producto.verificarDisponibilidad(Long.parseLong(request.getParameter("id")), idUsuario);
            ok = "Disponibilidad verificada.";
        } else if ("total".equals(accion)) {
            long id = Long.parseLong(request.getParameter("id"));
            Map<Long, String> pesos = new HashMap<>();
            for (String nombre : Collections.list(request.getParameterNames()))
                if (nombre.startsWith("peso_")) pesos.put(Long.parseLong(nombre.substring(5)), request.getParameter(nombre));
            BigDecimal total = Pedido.calcularTotal(id, pesos, idUsuario);
            ok = "Total calculado y guardado: " + Consulta.pesos(total);
        } else if ("corte".equals(accion)) {
            String sust = request.getParameter("sustituye");
            boolean conforme = Corte.verificarCalidadTemperatura(Long.parseLong(request.getParameter("detalle")),
                request.getParameter("especificacion"), request.getParameter("peso"), request.getParameter("temperatura"),
                request.getParameter("calidad") != null, (sust == null || sust.isBlank()) ? null : Long.parseLong(sust), idUsuario);
            if (conforme) ok = "Verificación realizada: corte CONFORME. Puede empacar y sellar.";
            else error = "Verificación realizada: corte NO CONFORME. Sustituya las piezas y digite el nuevo corte.";
        } else if ("empacar".equals(accion)) {
            long idPaquete = Paquete.empacarSellarProducto(Long.parseLong(request.getParameter("id")),
                request.getParameter("tipo"), request.getParameter("sellado") != null, idUsuario);
            ok = "Producto empacado y sellado (paquete #" + idPaquete + ", estado Empacado).";
        } else if ("despachar".equals(accion)) {
            String dom = request.getParameter("domiciliario");
            ok = Paquete.despachar(Long.parseLong(request.getParameter("id")),
                (dom == null || dom.isBlank()) ? null : Long.parseLong(dom), idUsuario);
        }
    } catch (IllegalArgumentException e) {
        error = e.getMessage() + " Digite los datos de nuevo.";
    } catch (Exception e) {
        error = "No se pudo completar la operación: " + e.getMessage();
    }

    String detSql = "SELECT d.id_detalle, pr.nombre, d.cantidad_solicitada_kg, d.peso_real_kg, d.estado, d.subtotal, v.precio_kg " +
                    "FROM detalle_pedido d JOIN producto pr ON pr.id_producto = d.id_producto " +
                    "LEFT JOIN v_precio_vigente v ON v.id_producto = d.id_producto AND v.id_sede = 1 WHERE d.id_pedido = ? ORDER BY d.id_detalle";
    List<Map<String, Object>> porVerificar = Consulta.lista(
        "SELECT p.id_pedido, p.codigo, c.nombre FROM pedido p JOIN cliente c ON c.id_cliente = p.id_cliente WHERE p.estado = 'REGISTRADO' " +
        "AND EXISTS (SELECT 1 FROM detalle_pedido d WHERE d.id_pedido = p.id_pedido AND d.estado = 'SOLICITADO') ORDER BY p.id_pedido");
    List<Map<String, Object>> porPesar = Consulta.lista(
        "SELECT p.id_pedido, p.codigo, c.nombre, p.metodo_entrega FROM pedido p JOIN cliente c ON c.id_cliente = p.id_cliente WHERE p.estado = 'REGISTRADO' AND p.total = 0 " +
        "AND NOT EXISTS (SELECT 1 FROM detalle_pedido d WHERE d.id_pedido = p.id_pedido AND d.estado = 'SOLICITADO') ORDER BY p.id_pedido");
    List<Map<String, Object>> enPreparacion = Consulta.lista(
        "SELECT p.id_pedido, p.codigo, c.nombre, p.estado, p.metodo_entrega, " +
        " (SELECT COUNT(*) FROM paquete k WHERE k.id_pedido = p.id_pedido AND k.estado IN ('EMPACADO','EN_AJUSTE')) AS paquetes " +
        "FROM pedido p JOIN cliente c ON c.id_cliente = p.id_cliente WHERE p.estado IN ('CONFIRMADO','EN_PREPARACION') ORDER BY p.id_pedido");
    List<Map<String, Object>> domiciliarios = Consulta.lista("SELECT id_domiciliario, nombre FROM domiciliario WHERE activo AND disponible");
%>
<h1>Interfaz preparación</h1>
<%@ include file="/WEB-INF/jspf/mensajes.jspf" %>
<% if (!detalleMensajes.isEmpty()) { %><ul class="lista-msg"><% for (String m : detalleMensajes) { %><li><%= Consulta.h(m) %></li><% } %></ul><% } %>

<section class="tarjeta">
  <h2>Verificar disponibilidad <small>HU-03</small></h2>
  <% if (porVerificar.isEmpty()) { %><p class="vacio">No hay pedidos registrados pendientes de verificar.</p><% } else { %>
  <table class="grid">
    <thead><tr><th>Pedido</th><th>Cliente</th><th>Productos solicitados</th><th></th></tr></thead>
    <tbody>
    <% for (Map<String, Object> p : porVerificar) { %>
      <tr><td><%= p.get("codigo") %></td><td><%= Consulta.h(p.get("nombre")) %></td>
        <td><% for (Map<String, Object> d : Consulta.lista(detSql, p.get("id_pedido"))) { %><%= Consulta.h(d.get("nombre")) %> <%= Consulta.kg(d.get("cantidad_solicitada_kg")) %> kg<br><% } %></td>
        <td><form method="post" action="preparacion.jsp"><input type="hidden" name="accion" value="disponibilidad"><input type="hidden" name="id" value="<%= p.get("id_pedido") %>"><button class="boton" type="submit">Verificar disponibilidad</button></form></td></tr>
    <% } %>
    </tbody>
  </table>
  <% } %>
</section>

<section class="tarjeta">
  <h2>Pesar producto y calcular total <small>HU-06</small></h2>
  <% if (porPesar.isEmpty()) { %><p class="vacio">No hay pedidos con disponibilidad verificada por pesar.</p><% } %>
  <% for (Map<String, Object> p : porPesar) { %>
    <form method="post" action="preparacion.jsp" class="bloque">
      <input type="hidden" name="accion" value="total"><input type="hidden" name="id" value="<%= p.get("id_pedido") %>">
      <h3><%= p.get("codigo") %> · <%= Consulta.h(p.get("nombre")) %> <small><%= p.get("metodo_entrega") %></small></h3>
      <table class="grid">
        <thead><tr><th>Producto</th><th>Solicitado</th><th>Estado</th><th>Precio vigente</th><th>Peso real (kg)</th></tr></thead>
        <tbody>
        <% for (Map<String, Object> d : Consulta.lista(detSql, p.get("id_pedido"))) { boolean disp = "DISPONIBLE".equals(d.get("estado")); %>
          <tr><td><%= Consulta.h(d.get("nombre")) %></td><td><%= Consulta.kg(d.get("cantidad_solicitada_kg")) %> kg</td><td><%= d.get("estado") %></td><td><%= Consulta.pesos(d.get("precio_kg")) %>/kg</td>
            <td><% if (disp) { %><input name="peso_<%= d.get("id_detalle") %>" inputmode="decimal" value="<%= Consulta.kg(d.get("cantidad_solicitada_kg")) %>"><% } else { %>—<% } %></td></tr>
        <% } %>
        </tbody>
      </table>
      <button class="boton primario" type="submit">Calcular total</button>
    </form>
  <% } %>
</section>

<section class="tarjeta">
  <h2>Verificar calidad y temperatura <small>HU-41</small> · Empacar y sellar <small>HU-43</small></h2>
  <p class="suave">Rango de temperatura aceptado: 0 a 4 °C. Un corte no conforme se sustituye y se vuelve a digitar.</p>
  <% if (enPreparacion.isEmpty()) { %><p class="vacio">No hay pedidos confirmados o en preparación.</p><% } %>
  <% for (Map<String, Object> p : enPreparacion) { boolean todosConformes = true; %>
    <div class="bloque">
      <h3><%= p.get("codigo") %> · <%= Consulta.h(p.get("nombre")) %> <span class="tag <%= p.get("estado") %>"><%= p.get("estado") %></span> <small><%= p.get("metodo_entrega") %></small></h3>
      <% for (Map<String, Object> d : Consulta.lista(detSql, p.get("id_pedido"))) {
           if (!"PESADO".equals(d.get("estado"))) continue;
           List<Map<String, Object>> cortes = Consulta.lista(
             "SELECT k.id_corte, k.especificacion_tecnica, k.peso_kg, k.temperatura_c, k.calidad_ok, k.conforme, " +
             " EXISTS(SELECT 1 FROM paquete_corte pc WHERE pc.id_corte = k.id_corte) AS empacado FROM corte k WHERE k.id_detalle = ? ORDER BY k.id_corte", d.get("id_detalle"));
           boolean conforme = false; Object ultimoNoConforme = null;
           for (Map<String, Object> k : cortes) { if (Boolean.TRUE.equals(k.get("conforme")) || "1".equals(String.valueOf(k.get("conforme")))) conforme = true; else ultimoNoConforme = k.get("id_corte"); }
           if (!conforme) todosConformes = false;
      %>
        <div class="sub">
          <b><%= Consulta.h(d.get("nombre")) %></b> · peso <%= Consulta.kg(d.get("peso_real_kg")) %> kg
          <% for (Map<String, Object> k : cortes) { boolean kc = Boolean.TRUE.equals(k.get("conforme")) || "1".equals(String.valueOf(k.get("conforme"))); %>
            <div class="corte">Corte #<%= k.get("id_corte") %>: <%= Consulta.h(k.get("especificacion_tecnica")) %>, <%= Consulta.kg(k.get("peso_kg")) %> kg, <%= k.get("temperatura_c") %> °C →
              <span class="tag <%= kc ? "CONFORME" : "NO_CONFORME" %>"><%= kc ? "Conforme" : "No conforme" %></span></div>
          <% } %>
          <% if (!conforme) { %>
          <form method="post" action="preparacion.jsp" class="en-linea">
            <input type="hidden" name="accion" value="corte"><input type="hidden" name="detalle" value="<%= d.get("id_detalle") %>">
            <% if (ultimoNoConforme != null) { %><input type="hidden" name="sustituye" value="<%= ultimoNoConforme %>"><span class="suave">Sustituir piezas:</span><% } %>
            <input name="especificacion" placeholder="Especificación del corte" required>
            <input name="peso" inputmode="decimal" placeholder="Peso kg" value="<%= Consulta.kg(d.get("peso_real_kg")) %>" class="corto">
            <input name="temperatura" inputmode="decimal" placeholder="°C" class="corto">
            <label class="check"><input type="checkbox" name="calidad" checked> Calidad OK</label>
            <button class="boton" type="submit">Verificar</button>
          </form>
          <% } %>
        </div>
      <% } %>
      <% if (todosConformes && ((Number) p.get("paquetes")).intValue() == 0 && "EN_PREPARACION".equals(p.get("estado"))) { %>
        <form method="post" action="preparacion.jsp" class="en-linea fondo">
          <input type="hidden" name="accion" value="empacar"><input type="hidden" name="id" value="<%= p.get("id_pedido") %>">
          <b>Empacar y sellar:</b>
          <select name="tipo"><option value="BANDEJA">Bandeja</option><option value="BOLSA">Bolsa</option><option value="CAJA">Caja</option></select>
          <label class="check"><input type="checkbox" name="sellado"> Sellado</label>
          <button class="boton primario" type="submit">Empacar y sellar</button>
        </form>
      <% } %>
      <% if (((Number) p.get("paquetes")).intValue() > 0) { %>
        <form method="post" action="preparacion.jsp" class="en-linea fondo">
          <input type="hidden" name="accion" value="despachar"><input type="hidden" name="id" value="<%= p.get("id_pedido") %>">
          <% if ("DOMICILIO".equals(p.get("metodo_entrega"))) { %>
            <b>Asignar domiciliario:</b>
            <select name="domiciliario"><% for (Map<String, Object> m : domiciliarios) { %><option value="<%= m.get("id_domiciliario") %>"><%= Consulta.h(m.get("nombre")) %></option><% } %></select>
            <button class="boton" type="submit">Despachar pedido</button>
          <% } else { %>
            <button class="boton" type="submit">Entregar en el local</button>
          <% } %>
        </form>
      <% } %>
    </div>
  <% } %>
</section>
<%@ include file="/WEB-INF/jspf/pie.jspf" %>
