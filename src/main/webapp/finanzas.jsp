<% String[] permitidos = {"CONTABILIDAD"}; %>
<%@ include file="/WEB-INF/jspf/encabezado.jspf" %>
<%
    // ----- Interfaz inventario y finanzas: HU-26 Aprobar orden -----
    try {
        if ("aprobar".equals(accion)) {
            String r = OrdenCompra.aprobarOrden(Long.parseLong(request.getParameter("id")), request.getParameter("entidad"),
                request.getParameter("monto"), "SI".equals(request.getParameter("viable")), idUsuario);
            if (r.startsWith("Orden aprobada")) ok = r; else error = r;
        }
    } catch (IllegalArgumentException e) {
        error = e.getMessage() + " Digite los datos de nuevo.";
    } catch (Exception e) {
        error = "No se pudo completar la operación: " + e.getMessage();
    }
    BigDecimal liquidez = OrdenCompra.liquidez();
    List<Map<String, Object>> porAprobar = Consulta.lista(
        "SELECT o.id_orden_compra, o.codigo, pv.razon_social, o.valor_total, o.estado, " +
        " (SELECT GROUP_CONCAT(CONCAT(p.nombre,' ',CAST(d.cantidad_kg AS DOUBLE),' kg') SEPARATOR ', ') FROM detalle_orden_compra d JOIN producto p ON p.id_producto = d.id_producto WHERE d.id_orden_compra = o.id_orden_compra) AS productos " +
        "FROM orden_compra o JOIN proveedor pv ON pv.id_proveedor = o.id_proveedor WHERE o.estado IN ('GENERADA','EN_GESTION_ALTERNATIVAS') ORDER BY o.id_orden_compra");
    List<Map<String, Object>> caja = Consulta.lista("SELECT fecha, tipo, concepto, valor FROM movimiento_caja WHERE id_sede = 1 ORDER BY id_movimiento_caja DESC LIMIT 10");
    List<Map<String, Object>> stock = Consulta.lista("SELECT * FROM v_stock_producto WHERE id_sede = 1 ORDER BY nombre");
%>
<h1>Interfaz inventario y finanzas</h1>
<%@ include file="/WEB-INF/jspf/mensajes.jspf" %>
<div class="kpis">
  <div class="kpi"><span>Liquidez disponible</span><strong id="liquidez"><%= Consulta.pesos(liquidez) %></strong></div>
  <div class="kpi"><span>Órdenes por aprobar</span><strong><%= porAprobar.size() %></strong></div>
</div>

<section class="tarjeta">
  <h2>Aprobar orden <small>HU-26</small></h2>
  <% if (porAprobar.isEmpty()) { %><p class="vacio">No hay órdenes por aprobar.</p><% } %>
  <% for (Map<String, Object> o : porAprobar) { boolean alternativa = "EN_GESTION_ALTERNATIVAS".equals(o.get("estado")); %>
    <form method="post" action="finanzas.jsp" class="bloque">
      <input type="hidden" name="accion" value="aprobar"><input type="hidden" name="id" value="<%= o.get("id_orden_compra") %>">
      <h3><%= o.get("codigo") %> · <%= Consulta.h(o.get("razon_social")) %> · <%= Consulta.pesos(o.get("valor_total")) %> <span class="tag <%= o.get("estado") %>"><%= o.get("estado") %></span></h3>
      <p class="suave"><%= Consulta.h(o.get("productos")) %></p>
      <% if (alternativa) { %>
        <p>La liquidez no alcanza. Registre la alternativa de financiamiento:</p>
        <div class="en-linea">
          <input name="entidad" placeholder="Entidad (banco, proveedor, socio)" required>
          <input name="monto" inputmode="decimal" placeholder="Monto" class="corto" required>
          <select name="viable"><option value="SI">Viable</option><option value="NO">No viable</option></select>
          <button class="boton primario" type="submit">Aprobar con financiamiento</button>
        </div>
      <% } else { %>
        <button class="boton primario" type="submit">Revisar liquidez y aprobar</button>
      <% } %>
    </form>
  <% } %>
</section>

<section class="tarjeta">
  <h2>Inventario</h2>
  <table class="grid">
    <thead><tr><th>Producto</th><th>Stock (kg)</th><th>Mínimo (kg)</th></tr></thead>
    <tbody><% for (Map<String, Object> s : stock) { %><tr><td><%= Consulta.h(s.get("nombre")) %></td><td><%= Consulta.kg(s.get("stock_kg")) %></td><td><%= Consulta.kg(s.get("stock_minimo_kg")) %></td></tr><% } %></tbody>
  </table>
</section>

<section class="tarjeta">
  <h2>Últimos movimientos de caja</h2>
  <table class="grid">
    <thead><tr><th>Fecha</th><th>Tipo</th><th>Concepto</th><th>Valor</th></tr></thead>
    <tbody><% for (Map<String, Object> m : caja) { %><tr><td><%= m.get("fecha") %></td><td><%= m.get("tipo") %></td><td><%= Consulta.h(m.get("concepto")) %></td><td><%= Consulta.pesos(m.get("valor")) %></td></tr><% } %></tbody>
  </table>
</section>
<%@ include file="/WEB-INF/jspf/pie.jspf" %>
