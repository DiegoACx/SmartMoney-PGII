# Fase 6 – Guía de etiquetado de INTENCIONES del asistente

Este documento define las **6 intenciones** que el clasificador debe reconocer en los mensajes
que un usuario le escribe al asistente de SmartMoney, y da los criterios para etiquetar cada
frase sin ambigüedad. La idea es que dos personas etiquetando por separado lleguen al mismo
resultado; donde no coincidan, se resuelve en conjunto (ver `resolucion_desacuerdos.csv`).

> Importante: el clasificador mira **sólo el mensaje**. Las etiquetas describen *qué quiere el
> usuario con ese mensaje*, no lo que la app haría después.

---

## 1. `consultar_datos` — leer datos ya registrados

El usuario pide **leer** información que ya está en la app. La respuesta se puede construir con
sumas, totales, listas, promedios, el progreso de una meta o una comparación entre periodos.
No hay hipótesis ni cálculo de escenarios: se muestra lo que ya existe.

**Señales típicas:** "cuánto gasté…", "cuánto llevo…", "dame el total…", "muéstrame…",
"cómo voy con la meta…", "en qué se me fue la plata…", "compárame este mes con el anterior",
"cuál fue mi gasto más alto…".

**Ejemplos**
- "cuanto gaste en comida esta semana"
- "como voy con la meta del viaje"
- "dame el total de transporte del mes pasado"
- "cuanto he ahorrado este año"
- "en que categoria gaste mas este mes"

**Casos frontera**
- "cuanto tengo que ahorrar al mes para la meta" → **no** es leer un dato (no existe aún):
  es `simular_escenario` porque pide un cálculo con sus datos.
- "muestrame mis ultimos movimientos" → `consultar_datos` (sólo lista).
- "cuanto gaste en comida y cuanto deberia gastar" → mezcla leer + juicio; si pide un número
  nuevo → `simular_escenario`; si pide opinión sin cálculo → `pedir_consejo`. Aquí hay cálculo
  implícito del "debería" → `pedir_consejo` si no da una fórmula concreta, `simular_escenario`
  si explícitamente pide calcularlo.

---

## 2. `simular_escenario` — hipótesis o capacidad que requiere cálculo

El usuario plantea un **escenario hipotético** o pregunta por su **capacidad** de hacer algo.
Para responder hay que usar **sus datos + un cálculo** (proyección, tiempo, cuota, comparación).

**Señales típicas:** "me alcanza para…", "si ahorro X…", "en cuánto tiempo…", "puedo pagar una
cuota de…", "cuánto me sobra si…", "si dejo de gastar en…".

**Ejemplos**
- "me alcanza para un cdt si tengo 500 mil"
- "si ahorro 200 mil al mes en cuanto tiempo completo la meta del viaje"
- "puedo pagar una cuota de 300 mil"
- "si dejo de gastar en domicilios cuanto ahorro en 6 meses"

**Casos frontera**
- "cuanto gaste este mes" → `consultar_datos` (no hay hipótesis).
- "deberia tomar un credito de 5 millones" → pide **juicio** más que cálculo → `pedir_consejo`.
- "en cuanto tiempo ahorro un millon" → `simular_escenario` (proyección).

---

## 3. `aprender_concepto` — entender qué es o cómo funciona algo

Pregunta **general** sobre finanzas. **No** se refiere a la situación personal del usuario: pide
una explicación, una definición o una comparación conceptual.

**Señales típicas:** "qué es…", "cómo funciona…", "explícame…", "en qué consiste…",
"para qué sirve…", "diferencia entre…".

**Ejemplos**
- "que es el interes compuesto"
- "como funciona una cuenta de ahorros"
- "explicame que es la inflacion"
- "diferencia entre ahorro e inversion"

**Casos frontera**
- "que es un cdt y me conviene" → si el foco es entender → `aprender_concepto`; si el foco es
  decidir para él → `pedir_consejo`. La clave es "me conviene": gana `pedir_consejo`.
- "como funciona la app" → `ayuda_app` (es la app, no finanzas).
- "como calculo mi interes compuesto con mis datos" → lleva sus datos y cálculo → `simular_escenario`.

---

## 4. `pedir_consejo` — qué hacer: estrategia, juicio o recomendación

El usuario pide **opinión, estrategia o recomendación** sobre *su* situación. Puede mencionar
sus datos, pero **no pide un cálculo concreto**: pide qué hacer, si algo está bien o mal, o
elegir entre opciones ("me conviene A o B").

**Señales típicas:** "cómo puedo…", "qué me recomiendas…", "me conviene…", "estoy gastando
demasiado?", "qué hago para…", "vale la pena…".

**Ejemplos**
- "como puedo ahorrar mas"
- "me conviene ahorrar o invertir"
- "estoy gastando demasiado en salidas"
- "que estrategia me recomiendas para organizar mis gastos"

**Casos frontera**
- "como puedo ahorrar 300 mil este mes" → hay **cálculo con sus datos** → `simular_escenario`.
- "que es mejor entre cdt y cuenta de ahorros" → comparación conceptual pura → `aprender_concepto`;
  si añade "para mi" / "me conviene" → `pedir_consejo`.
- "como se hace un presupuesto" → explicación general → `aprender_concepto`.

---

## 5. `ayuda_app` — uso de la aplicación, cuenta y datos

Preguntas sobre **la app**: cómo hacer algo en ella, la cuenta, la privacidad/seguridad de los
datos, recordatorios, exportar, cambiar contraseña, crear o editar metas, qué puede hacer el
asistente, errores de funcionamiento.

**Señales típicas:** "cómo registro…", "dónde cambio…", "cómo exporto…", "es segura mi info?",
"qué puedes hacer", "por qué no me deja…".

**Ejemplos**
- "como registro un gasto"
- "donde cambio mi contraseña"
- "como exporto mis datos"
- "es segura mi informacion"
- "que puedes hacer"

**Casos frontera**
- "como creo una meta de ahorro" → `ayuda_app` (es una función).
- "como ahorro para una meta" → `pedir_consejo` (es estrategia, no una función de la app).
- "que es una meta de ahorro" → `aprender_concepto`.

---

## 6. `conversacion` — todo lo demás

Saludos, despedidas, agradecimientos, charla sobre el bot, seguimientos ("no entendí",
"explícamelo más fácil") y **cualquier** mensaje que no sea de finanzas ni de la app.

**Señales típicas:** "hola", "gracias", "chao", "quién eres", "no entendí", "y eso?",
"cuéntame un chiste", "qué hora es".

**Ejemplos**
- "hola parce"
- "gracias por la ayuda"
- "no entendi nada"
- "quien eres"
- "y entonces?"

**Casos frontera**
- "no entendi tu explicacion del interes compuesto" → seguiría siendo un seguimiento sobre
  finanzas; si el usuario sólo expresa que no entendió, sin pedir una explicación nueva →
  `conversacion` (seguimiento). Si pide "explícame otra vez qué es" → `aprender_concepto`.
- "gracias, cuanto gaste hoy" → mezcla; gana la petición de datos → `consultar_datos`.
- "ok" / "listo" / "de una" → `conversacion`.

---

## Regla de desempate (aplicarla en este orden)

1. **¿Pide un cálculo con sus datos?** (hipótesis, proyección, cuota, "me alcanza",
   "en cuánto tiempo", "si ahorro") → **`simular_escenario`**.
2. **¿Pide qué hacer / una opinión / elegir entre opciones para él?** → **`pedir_consejo`**.
3. **¿Sólo pide leer/sumar/mostrar datos ya registrados?** → **`consultar_datos`**.
4. **¿Es una explicación general de finanzas, sin su situación?** → **`aprender_concepto`**.
5. **¿Es sobre el funcionamiento de la app, la cuenta o la seguridad?** → **`ayuda_app`**.
6. **¿No es finanzas ni la app (saludo, gracias, seguimiento, charla)?** → **`conversacion`**.

### Errores frecuentes a evitar
- Etiquetar de `consultar_datos` algo que pide un número que aún no existe (eso es simular).
- Confundir `pedir_consejo` con `aprender_concepto`: el consejo es sobre *su* situación; el
  concepto es general y atemporal.
- Meter en `ayuda_app` preguntas de finanzas sólo porque nombran "la app" o "el asistente".
- Mandar a `conversacion` un mensaje que sí pide datos o consejo: la charla sólo gana cuando
  no hay ninguna intención de finanzas ni de la app.

### Cómo llenar los archivos
- `para_etiquetar_A.csv` y `para_etiquetar_B.csv`: columnas `id, texto, intencion`. Escribe en
  `intencion` **exactamente uno** de los 6 nombres (sin tildes, en minúsculas):
  `consultar_datos`, `simular_escenario`, `aprender_concepto`, `pedir_consejo`, `ayuda_app`,
  `conversacion`.
- Los dos etiquetadores trabajan por separado (órdenes distintos). Al terminar se comparan por
  `id`. Donde **no** coincidan, los ids van a `resolucion_desacuerdos.csv` (columnas `id,
  intencion`) y se llenan de común acuerdo.
