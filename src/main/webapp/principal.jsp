<% String[] permitidos = {"CLIENTE", "ATENCION_CLIENTE", "AREA_OPERATIVA", "CONTABILIDAD", "DOMICILIARIO"}; %>
<%@ include file="/WEB-INF/jspf/encabezado.jspf" %>
<h1>Interfaz principal</h1>
<p class="suave">Seleccione la interfaz con la que va a trabajar.</p>
<div class="menu">
  <% if ("ADMIN".equals(rol) || "CLIENTE".equals(rol) || "ATENCION_CLIENTE".equals(rol)) { %>
  <a class="tarjeta opcion" href="pedidos.jsp"><b>Interfaz pedidos</b><span>Solicitar pedido · Registrar pedido</span></a>
  <% } if ("ADMIN".equals(rol) || "AREA_OPERATIVA".equals(rol)) { %>
  <a class="tarjeta opcion" href="preparacion.jsp"><b>Interfaz preparación</b><span>Verificar disponibilidad · Calcular total · Verificar calidad y temperatura · Empacar y sellar</span></a>
  <% } if ("ADMIN".equals(rol) || "DOMICILIARIO".equals(rol)) { %>
  <a class="tarjeta opcion" href="entrega.jsp"><b>Interfaz entrega</b><span>Entregar pedido</span></a>
  <% } if ("ADMIN".equals(rol) || "AREA_OPERATIVA".equals(rol)) { %>
  <a class="tarjeta opcion" href="abastecimiento.jsp"><b>Interfaz abastecimiento</b><span>Generar orden · Recibir lote</span></a>
  <% } if ("ADMIN".equals(rol) || "CONTABILIDAD".equals(rol)) { %>
  <a class="tarjeta opcion" href="finanzas.jsp"><b>Interfaz inventario y finanzas</b><span>Aprobar orden · Inventario</span></a>
  <% } %>
</div>
<%@ include file="/WEB-INF/jspf/pie.jspf" %>
