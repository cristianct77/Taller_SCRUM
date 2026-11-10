<% String[] permitidos = {"AREA_OPERATIVA"}; %>
<%@ include file="/WEB-INF/jspf/encabezado.jspf" %>
<%
    // ----- Interfaz abastecimiento: HU-23 Generar orden, HU-31 Recibir lote -----
    try {
        if ("generar".equals(accion)) {
            String codigo = OrdenCompra.generarOrden(Long.parseLong(Validacion.obligatorio(request.getParameter("proveedor"), "proveedor")),
                request.getParameterValues("producto"), request.getParameterValues("kg"), request.getParameterValues("precio"),
                request.getParameter("observacion"), idUsuario);
            ok = "Orden generada: " + codigo + " (estado Generada).";
        } else if ("recibir".equals(accion)) {
            long id = Long.parseLong(request.getParameter("id"));
            Map<Long, String> pesos = new HashMap<>();
            Set<Long> frescos = new HashSet<>();
            for (String nombre : Collections.list(request.getParameterNames())) {
                if (nombre.startsWith("peso_")) pesos.put(Long.parseLong(nombre.substring(5)), request.getParameter(nombre));
                if (nombre.startsWith("fresco_")) frescos.add(Long.parseLong(nombre.substring(7)));
            }
            int lotes = Producto.recibirLote(id, request.getParameter("factura"), request.getParameter("vence"), pesos, frescos, idUsuario);
            ok = "Lote recibido: " + lotes + " producto(s) ingresaron al inventario. La orden queda Recibida.";
        }
    } catch (IllegalArgumentException e) {
        error = e.getMessage() + " Digite los datos de nuevo.";
    } catch (Exception e) {
        error = "No se pudo completar la operación: " + e.getMessage();
    }
    List<Map<String, Object>> stock = Consulta.lista("SELECT * FROM v_stock_producto WHERE id_sede = 1 ORDER BY bajo_minimo DESC, nombre");
    List<Map<String, Object>> productos = Consulta.lista("SELECT id_producto, nombre FROM producto WHERE activo ORDER BY nombre");
    List<Map<String, Object>> proveedores = Consulta.lista("SELECT id_proveedor, razon_social FROM proveedor WHERE activo ORDER BY razon_social");
    List<Map<String, Object>> aprobadas = Consulta.lista(
        "SELECT o.id_orden_compra, o.codigo, pv.razon_social, o.valor_total FROM orden_compra o JOIN proveedor pv ON pv.id_proveedor = o.id_proveedor " +
        "WHERE o.estado IN ('APROBADA','ENVIADA') ORDER BY o.id_orden_compra");
    List<Map<String, Object>> ordenes = Consulta.lista(
        "SELECT o.codigo, pv.razon_social, o.estado, o.valor_total, o.fecha_generacion FROM orden_compra o JOIN proveedor pv ON pv.id_proveedor = o.id_proveedor ORDER BY o.id_orden_compra DESC LIMIT 15");
%>
<h1>Interfaz abastecimiento</h1>
<%@ include file="/WEB-INF/jspf/mensajes.jspf" %>

<section class="tarjeta">
  <h2>Existencias</h2>
  <table class="grid">
    <thead><tr><th>Producto</th><th>Stock (kg)</th><th>Mínimo (kg)</th><th></th></tr></thead>
    <tbody>
    <% for (Map<String, Object> s : stock) { boolean bajo = "1".equals(String.valueOf(s.get("bajo_minimo"))) || Boolean.TRUE.equals(s.get("bajo_minimo")); %>
      <tr><td><%= Consulta.h(s.get("nombre")) %></td><td><%= Consulta.kg(s.get("stock_kg")) %></td><td><%= Consulta.kg(s.get("stock_minimo_kg")) %></td>
        <td><% if (bajo) { %><span class="tag NO_CONFORME">Faltante</span><% } %></td></tr>
    <% } %>
    </tbody>
  </table>
</section>

<section class="tarjeta">
  <h2>Generar orden <small>HU-23</small></h2>
  <form method="post" action="abastecimiento.jsp">
    <input type="hidden" name="accion" value="generar">
    <label>Proveedor
      <select name="proveedor" required><option value="">Seleccione…</option>
        <% for (Map<String, Object> pv : proveedores) { %><option value="<%= pv.get("id_proveedor") %>"><%= Consulta.h(pv.get("razon_social")) %></option><% } %>
      </select>
    </label>
    <table class="grid">
      <thead><tr><th>Producto</th><th>Cantidad (kg)</th><th>Precio por kg</th></tr></thead>
      <tbody>
      <% for (int i = 0; i < 4; i++) { %>
        <tr><td><select name="producto"><option value="">—</option>
              <% for (Map<String, Object> p : productos) { %><option value="<%= p.get("id_producto") %>"><%= Consulta.h(p.get("nombre")) %></option><% } %></select></td>
            <td><input name="kg" inputmode="decimal"></td><td><input name="precio" inputmode="decimal"></td></tr>
      <% } %>
      </tbody>
    </table>
    <label>Observación <input name="observacion" maxlength="250"></label>
    <button class="boton primario" type="submit">Generar orden</button>
  </form>
</section>

<section class="tarjeta">
  <h2>Recibir lote <small>HU-31</small></h2>
  <% if (aprobadas.isEmpty()) { %><p class="vacio">No hay órdenes aprobadas por recibir.</p><% } %>
  <% for (Map<String, Object> o : aprobadas) { %>
    <form method="post" action="abastecimiento.jsp" class="bloque">
      <input type="hidden" name="accion" value="recibir"><input type="hidden" name="id" value="<%= o.get("id_orden_compra") %>">
      <h3><%= o.get("codigo") %> · <%= Consulta.h(o.get("razon_social")) %> · <%= Consulta.pesos(o.get("valor_total")) %></h3>
      <div class="fila">
        <label>Número de factura <input name="factura" required></label>
        <label>Fecha de vencimiento <input name="vence" type="date" required></label>
      </div>
      <table class="grid">
        <thead><tr><th>Producto</th><th>Pedido (kg)</th><th>Peso recibido (kg)</th><th>Frescura</th></tr></thead>
        <tbody>
        <% for (Map<String, Object> d : Consulta.lista("SELECT d.id_detalle_oc, p.nombre, d.cantidad_kg FROM detalle_orden_compra d JOIN producto p ON p.id_producto = d.id_producto WHERE d.id_orden_compra = ?", o.get("id_orden_compra"))) { %>
          <tr><td><%= Consulta.h(d.get("nombre")) %></td><td><%= Consulta.kg(d.get("cantidad_kg")) %></td>
            <td><input name="peso_<%= d.get("id_detalle_oc") %>" inputmode="decimal" value="<%= Consulta.kg(d.get("cantidad_kg")) %>"></td>
            <td><label class="check"><input type="checkbox" name="fresco_<%= d.get("id_detalle_oc") %>" checked> Fresco</label></td></tr>
        <% } %>
        </tbody>
      </table>
      <button class="boton primario" type="submit">Recibir lote</button>
    </form>
  <% } %>
</section>

<section class="tarjeta">
  <h2>Órdenes de compra</h2>
  <table class="grid">
    <thead><tr><th>Orden</th><th>Proveedor</th><th>Estado</th><th>Valor</th><th>Fecha</th></tr></thead>
    <tbody>
    <% for (Map<String, Object> o : ordenes) { %>
      <tr><td><%= o.get("codigo") %></td><td><%= Consulta.h(o.get("razon_social")) %></td><td><span class="tag <%= o.get("estado") %>"><%= o.get("estado") %></span></td>
        <td><%= Consulta.pesos(o.get("valor_total")) %></td><td><%= o.get("fecha_generacion") %></td></tr>
    <% } %>
    </tbody>
  </table>
</section>
<%@ include file="/WEB-INF/jspf/pie.jspf" %>
