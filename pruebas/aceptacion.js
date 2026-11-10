// Prueba de aceptación de las 10 historias del Sprint 1 (Playwright).
// Uso: node pruebas/aceptacion.js http://localhost:8080/richpos capturas
const { chromium } = require('playwright');
const BASE = process.argv[2] || 'http://localhost:8080/richpos';
const OUT = process.argv[3] || 'capturas';
require('fs').mkdirSync(OUT, { recursive: true });
const res = [];
const check = (id, desc, c) => { res.push({ id, desc, ok: !!c }); console.log(`${c ? 'OK   ' : 'FALLA'} ${id} ${desc}`); };

async function entrar(browser, usuario) {
  const ctx = await browser.newContext({ viewport: { width: 1200, height: 800 }, deviceScaleFactor: 1.25 });
  const page = await ctx.newPage();
  await page.goto(BASE + '/index.jsp');
  await page.fill('input[name=usuario]', usuario);
  await page.fill('input[name=clave]', 'Rich2026*');
  await page.click('button[type=submit]');
  return { ctx, page };
}
const elegir = async (sel, t) => { const v = await sel.evaluate((s, t) => [...s.options].find(o => o.text.includes(t)).value, t); await sel.selectOption(v); };
const foto = (page, n) => page.screenshot({ path: `${OUT}/${n}.png`, fullPage: true });
const texto = async (page, t) => (await page.content()).includes(t);
const enviar = async (page, form) => { await Promise.all([page.waitForNavigation(), form.locator('button[type=submit]').click()]); };

(async () => {
  const browser = await chromium.launch();

  // Autorización de usuario (criterio HU-02): dos intentos fallidos terminan el proceso
  { const ctx = await browser.newContext({ viewport: { width: 1200, height: 800 } }); const p = await ctx.newPage();
    await p.goto(BASE + '/index.jsp'); await foto(p, '00_login');
    for (let i = 0; i < 2; i++) { await p.fill('input[name=usuario]', 'inactivo'); await p.fill('input[name=clave]', 'Rich2026*'); await p.click('button[type=submit]'); if (i === 0) await foto(p, '00_no_autorizado'); }
    check('LOGIN', 'Usuario no autorizado dos veces termina', await texto(p, 'El proceso terminó')); await foto(p, '00_terminado'); await ctx.close(); }

  // HU-01 Solicitar pedido (Cliente)
  let { ctx, page } = await entrar(browser, 'cliente');
  await page.goto(BASE + '/pedidos.jsp');
  await page.click('#form-solicitar button[type=submit]');
  check('HU-01', 'Datos incorrectos: no guarda y pide digitar de nuevo', await texto(page, 'Digite al menos un producto'));
  await foto(page, 'hu01_error');
  const sel = page.locator('#form-solicitar select[name=producto]'), kg = page.locator('#form-solicitar input[name=kg]');
  await elegir(sel.nth(0), 'Pollo entero'); await kg.nth(0).fill('2.5');
  await elegir(sel.nth(1), 'Pechuga'); await kg.nth(1).fill('1.5');
  await elegir(sel.nth(2), 'Alas'); await kg.nth(2).fill('6');
  await page.click('#form-solicitar button[type=submit]');
  check('HU-01', 'Pedido solicitado', await texto(page, 'Pedido solicitado: PED-'));
  await foto(page, 'hu01_ok'); await ctx.close();

  // HU-02 Registrar pedido (Atención al Cliente)
  ({ ctx, page } = await entrar(browser, 'atencion'));
  await page.goto(BASE + '/pedidos.jsp'); await foto(page, 'ui_pedidos');
  await page.locator('form:has(input[value=registrar]) button').first().click();
  check('HU-02', 'Pedido registrado y estado visible', await texto(page, 'Estado del pedido:') && await texto(page, 'REGISTRADO'));
  await foto(page, 'hu02_ok'); await ctx.close();

  // HU-03 Verificar disponibilidad y HU-06 Calcular total (Área Operativa)
  ({ ctx, page } = await entrar(browser, 'operativa'));
  await page.goto(BASE + '/preparacion.jsp');
  await page.locator('form:has(input[value=disponibilidad]) button').first().click();
  check('HU-03', 'Disponibles siguen, no disponibles se cancelan', await texto(page, 'Pollo entero: disponible') && await texto(page, 'Alas: NO disponible'));
  await foto(page, 'hu03_ok');
  const fTotal = page.locator('form:has(input[value=total])').first();
  await fTotal.locator('input[name^=peso_]').nth(0).fill('');
  await enviar(page, fTotal);
  check('HU-06', 'Peso vacío: solicita digitar de nuevo', await texto(page, 'debe ser un número mayor que cero'));
  await foto(page, 'hu06_error');
  const f2 = page.locator('form:has(input[value=total])').first();
  await f2.locator('input[name^=peso_]').nth(0).fill('2.6'); await f2.locator('input[name^=peso_]').nth(1).fill('1.4');
  await enviar(page, f2);
  // 2.6 x 11.000 + 1.4 x 16.000 + domicilio 4.000 = 55.000
  check('HU-06', 'Total = peso x precio vigente + domicilio ($ 55.000)', await texto(page, 'Total calculado y guardado: $ 55.000'));
  await foto(page, 'hu06_ok'); await ctx.close();

  // Confirmar pedido (Atención)
  ({ ctx, page } = await entrar(browser, 'atencion'));
  await page.goto(BASE + '/pedidos.jsp');
  await page.locator('form:has(input[value=confirmar]) button').first().click();
  check('CONF', 'Pedido confirmado', await texto(page, 'Pedido confirmado')); await ctx.close();

  // HU-41 Verificar calidad y temperatura, HU-43 Empacar y sellar (Área Operativa)
  ({ ctx, page } = await entrar(browser, 'operativa'));
  await page.goto(BASE + '/preparacion.jsp');
  let fc = page.locator('form:has(input[value=corte])').first();
  await fc.locator('input[name=especificacion]').fill('Pollo entero despresado en 8'); await fc.locator('input[name=temperatura]').fill('7.5');
  await enviar(page, fc);
  check('HU-41', 'Temperatura 7.5 °C: no conforme, sustituir piezas', await texto(page, 'NO CONFORME'));
  await foto(page, 'hu41_no_conforme');
  fc = page.locator('form:has(input[value=corte])').first();
  await fc.locator('input[name=especificacion]').fill('Pollo entero despresado en 8 (sustituto)'); await fc.locator('input[name=temperatura]').fill('2.0');
  await enviar(page, fc);
  fc = page.locator('form:has(input[value=corte])').first();
  await fc.locator('input[name=especificacion]').fill('Pechuga entera'); await fc.locator('input[name=temperatura]').fill('3');
  await enviar(page, fc);
  check('HU-41', 'Verificación realizada: conforme', await texto(page, 'corte CONFORME'));
  await foto(page, 'hu41_ok');
  const fe = page.locator('form:has(input[value=empacar])').first();
  await enviar(page, fe);
  check('HU-43', 'Sin sellar: solicita digitar de nuevo', await texto(page, 'debe quedar sellado'));
  await foto(page, 'hu43_error');
  const fe2 = page.locator('form:has(input[value=empacar])').first();
  await fe2.locator('input[name=sellado]').check(); await enviar(page, fe2);
  check('HU-43', 'Producto empacado y sellado (Empacado)', await texto(page, 'Producto empacado y sellado'));
  await foto(page, 'hu43_ok');
  await enviar(page, page.locator('form:has(input[value=despachar])').first());
  check('DESP', 'Pedido despachado al domiciliario', await texto(page, 'Pedido despachado')); await ctx.close();

  // HU-16 Entregar pedido (Domiciliario)
  ({ ctx, page } = await entrar(browser, 'domiciliario'));
  await page.goto(BASE + '/entrega.jsp'); await foto(page, 'hu16_antes');
  let fen = page.locator('form:has(input[value=entregar])').first();
  await enviar(page, fen);
  check('HU-16', 'Exitosa sin "recibido por": solicita digitar de nuevo', await texto(page, 'recibido por es obligatorio'));
  fen = page.locator('form:has(input[value=entregar])').first();
  await fen.locator('input[name=recibido]').fill('Carlos Medina'); await fen.locator('input[name=pago]').check();
  await enviar(page, fen);
  check('HU-16', 'Pedido entregado (y pagado)', await texto(page, 'Pedido entregado y pagado'));
  await foto(page, 'hu16_ok'); await ctx.close();

  // HU-23 Generar orden (Área Operativa)
  ({ ctx, page } = await entrar(browser, 'operativa'));
  await page.goto(BASE + '/abastecimiento.jsp');
  const og = async (prov, filas) => {
    const f = page.locator('form:has(input[value=generar])');
    await elegir(f.locator('select[name=proveedor]'), prov);
    for (let i = 0; i < filas.length; i++) {
      await elegir(f.locator('select[name=producto]').nth(i), filas[i][0]);
      await f.locator('input[name=kg]').nth(i).fill(filas[i][1]); await f.locator('input[name=precio]').nth(i).fill(filas[i][2]);
    }
    await enviar(page, f);
  };
  await og('Avícola La Granja S.A.S.', [['Alas', '20', '9000'], ['Menudencias', '10', '5000']]);
  check('HU-23', 'Orden generada (Generada)', await texto(page, 'Orden generada: OC-'));
  await foto(page, 'hu23_ok');
  await og('Distribuidora Pollo Fresco', [['Pollo entero', '200', '9000']]);
  await ctx.close();

  // HU-26 Aprobar orden (Contabilidad y Finanzas)
  ({ ctx, page } = await entrar(browser, 'contabilidad'));
  await page.goto(BASE + '/finanzas.jsp'); await foto(page, 'hu26_antes');
  await enviar(page, page.locator('form:has(input[value=aprobar])').first());
  check('HU-26', 'Liquidez suficiente: orden aprobada', await texto(page, 'Orden aprobada (liquidez suficiente)'));
  await foto(page, 'hu26_ok');
  await enviar(page, page.locator('form:has(input[value=aprobar])').first());
  check('HU-26', 'Liquidez insuficiente: pide alternativa', await texto(page, 'Liquidez insuficiente'));
  await foto(page, 'hu26_liquidez_insuficiente');
  const fa = page.locator('form:has(input[value=aprobar])').first();
  await fa.locator('input[name=entidad]').fill('Banco Agrario'); await fa.locator('input[name=monto]').fill('600000');
  await enviar(page, fa);
  check('HU-26', 'Alternativa viable: orden aprobada', await texto(page, 'Orden aprobada con financiamiento'));
  await foto(page, 'hu26_financiamiento'); await ctx.close();

  // HU-31 Recibir lote (Área Operativa)
  ({ ctx, page } = await entrar(browser, 'operativa'));
  await page.goto(BASE + '/abastecimiento.jsp');
  const fr = page.locator('form:has(input[value=recibir])').first();
  await fr.locator('input[name=factura]').fill('   '); await fr.locator('input[name=vence]').fill('2020-01-01');
  await enviar(page, fr);
  check('HU-31', 'Sin factura: solicita digitar de nuevo', await texto(page, 'número de factura es obligatorio') || await texto(page, 'fecha de vencimiento'));
  const fr2 = page.locator('form:has(input[value=recibir])').first();
  const vence = new Date(Date.now() + 5 * 864e5).toISOString().slice(0, 10);
  await fr2.locator('input[name=factura]').fill('FV-1001'); await fr2.locator('input[name=vence]').fill(vence);
  await enviar(page, fr2);
  check('HU-31', 'Lote recibido y orden Recibida', await texto(page, 'Lote recibido'));
  await foto(page, 'hu31_ok'); await ctx.close();

  await browser.close();
  const f = res.filter(r => !r.ok).length;
  console.log(`\n${res.length - f}/${res.length} verificaciones exitosas`);
  process.exit(f ? 1 : 0);
})();
