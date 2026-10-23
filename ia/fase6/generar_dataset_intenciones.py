"""
SmartMoney – Fase 6A
Genera el dataset de ENTRENAMIENTO del clasificador de INTENCIONES del asistente.

Fuente: vocabulario y plantillas escritos por el equipo a partir de la definición de las
6 intenciones (ver guia_etiquetado.md) y de cómo escribe la gente en Colombia.

REGLA ESTRICTA: este script NO lee ni copia NADA del formulario de la encuesta. El formulario
(ia/fase6/formulario_preguntas_respuestas.xlsx) queda reservado SOLO para la prueba final y se
procesa en otro script (preparar_formulario.py). Así el modelo nunca ve las frases reales antes
de evaluarse.

Salida: dataset_intenciones_entrenamiento.csv  (texto, intencion)
Uso:    python generar_dataset_intenciones.py [carpeta_salida]
"""
import csv
import os
import random
import re
import sys
import unicodedata

random.seed(7)

N_POR_INTENCION = 280

# ---------------------------------------------------------------------------
# Vocabulario variado (grupos de gasto, metas, productos financieros, periodos)
# ---------------------------------------------------------------------------
GRUPOS = [
    "comida", "mercado", "domicilios", "transporte", "arriendo", "servicios", "ropa",
    "salud", "entretenimiento", "salidas", "licor", "celular", "internet", "suscripciones",
    "educacion", "cafe", "restaurante", "gasolina", "mascota", "regalos", "viajes",
    "gimnasio", "uber", "taxi", "farmacia", "drogueria", "supermercado", "panaderia",
    "peluqueria", "tecnologia", "cine", "polas", "almuerzos", "rappi", "netflix",
]
PERIODOS = [
    "esta semana", "la semana pasada", "este mes", "el mes pasado", "hoy", "ayer",
    "este ano", "los ultimos 3 meses", "la quincena", "los ultimos 6 meses",
    "este trimestre", "el ano pasado", "en enero", "en febrero", "en marzo",
    "ultimamente", "los ultimos 7 dias", "el fin de semana",
]
METAS = [
    "meta de ahorro", "meta del viaje", "meta del celular", "meta de la moto",
    "meta del computador", "fondo de emergencia", "meta del arriendo", "meta de la casa",
    "meta de estudiar", "meta del carro", "meta de la bici", "meta del negocio",
    "meta del viaje a san andres", "meta del iphone",
]
PRODUCTOS = [
    "un cdt", "un celular nuevo", "un computador", "una moto", "un carro", "un viaje",
    "un apartamento", "un arriendo mas caro", "una bici", "un curso", "una casa",
    "un negocio", "un iphone", "una pantalla", "unos tenis", "unos audifonos",
]
MONTOS = [
    "50 mil", "100 mil", "150 mil", "200 mil", "250 mil", "300 mil", "400 mil",
    "500 mil", "600 mil", "700 mil", "800 mil", "un millon", "1.5 millones",
    "dos millones", "medio millon",
]
HORIZONTES = [
    "un ano", "6 meses", "3 meses", "un ano y medio", "dos anos", "12 meses",
    "5 anos", "un mes", "la quincena",
]
CONCEPTOS = [
    "interes compuesto", "interes simple", "inflacion", "tasa de interes", "presupuesto",
    "ahorro", "credito", "tarjeta de credito", "cdt", "cuenta de ahorros",
    "fondo de inversion", "acciones", "criptomonedas", "diversificacion", "deuda",
    "score", "historial crediticio", "ahorro programado", "gastos fijos",
    "gastos variables", "fondo de emergencia", "seguro", "pension", "cesantias",
    "prima", "rentabilidad", "riesgo", "liquidez", "plazo fijo", "regla 50/30/20",
    "metodo del sobre", "nomina", "prestamo", "hipoteca", "leasing", "bonos",
    "inversion", "capital", "patrimonio", "ingresos pasivos", "libertad financiera",
    "fondo indexado", "dolar", "peso colombiano", "trm", "iva", "retencion en la fuente",
    "declaracion de renta", "ahorro para el retiro", "fondo de cesantias", "alcancia",
]
SITUACIONES = [
    "gastar menos", "ahorrar mas", "salir de deudas", "organizar mis gastos",
    "controlar los domicilios", "no gastar en cosas innecesarias",
    "pagar la tarjeta de credito", "empezar a invertir", "hacer un presupuesto",
    "reducir el gasto en salidas", "ahorrar para una meta", "manejar mi plata",
    "no quedarme sin plata a fin de mes", "controlar mis impulsos", "invertir mis ahorros",
    "pagar mis deudas", "crear un fondo de emergencia", "vivir solo", "estudiar y trabajar",
]
FUNCIONES = [
    "registrar un gasto", "registrar un ingreso", "crear una meta", "editar una meta",
    "borrar una meta", "cambiar mi contrasena", "recuperar mi contrasena",
    "exportar mis datos", "descargar mis movimientos", "cambiar mi correo",
    "borrar mi cuenta", "eliminar un movimiento", "editar un gasto", "ver mis graficas",
    "cambiar de tema", "activar los recordatorios", "apagar las notificaciones",
    "configurar un presupuesto", "categorizar un gasto", "poner un limite de gasto",
    "ver mi historial", "sincronizar mis datos", "cambiar mi nombre", "cerrar sesion",
    "conectar mi cuenta", "marcar una meta como completada", "crear una categoria",
    "ver el resumen mensual",
]

# ---------------------------------------------------------------------------
# Plantillas por intención. Los marcadores {x} se reemplazan al azar.
# ---------------------------------------------------------------------------
PLANTILLAS = {
    "consultar_datos": [
        "cuanto gaste en {g} {per}", "cuanto he gastado en {g} {per}",
        "cuanto llevo gastado {per}", "cuanto he gastado {per}", "cuanto gaste {per}",
        "cuanto dinero he gastado en {g}", "cuanto he gastado en {g}",
        "dame el total de {g} {per}", "cual es el total de {g} {per}",
        "muestrame mis gastos de {g}", "muestrame los gastos {per}",
        "muestrame mis gastos {per}", "lista mis gastos de {g}",
        "dame el detalle de mis gastos {per}", "cuanto ingrese {per}",
        "cuales fueron mis ingresos {per}", "cuanto he ahorrado {per}",
        "cuanto llevo ahorrado", "como voy con la {meta}", "como va la {meta}",
        "cuanto llevo en la {meta}", "cuanto me falta para la {meta}",
        "cuanto he aportado a la {meta}", "en que he gastado mas {per}",
        "cual es mi gasto mas alto {per}", "que dia gaste mas {per}",
        "cual fue mi gasto mas grande {per}", "cuanto gaste en total {per}",
        "cuanto gaste en {g} vs {g2}", "compara mis gastos de {g} con {g2}",
        "en que se me va la plata {per}", "que categoria me gasto mas {per}",
        "cuantos movimientos tengo {per}", "dame un resumen de mis gastos {per}",
        "resumen de mis finanzas {per}", "cuanto tengo disponible", "cuanto me queda este mes",
        "cuantas veces gaste en {g} {per}", "muestrame mis {g} {per}",
        "cual es el promedio que gasto en {g}", "cuanto gaste en {g} y en {g2} {per}",
        "dime mis ultimos movimientos", "cuales son mis gastos fijos",
        "cuanto he gastado en total este mes", "mis ingresos y gastos {per}",
        "cual es mi balance {per}", "cuanto ahorre {per}",
        "como van mis metas de ahorro", "que metas tengo activas",
        "cuanto llevo de la {meta} y cuanto falta",
    ],
    "simular_escenario": [
        "me alcanza para {prod} si tengo {m}", "me alcanza para {prod} este mes",
        "me alcanza para comprar {prod}", "si ahorro {m} al mes cuanto junto en {hor}",
        "si ahorro {m} mensual cuanto tengo en {hor}",
        "si guardo {m} cada mes en cuanto llego a la {meta}",
        "en cuanto tiempo completo la {meta} si ahorro {m}",
        "cuanto tiempo necesito para la {meta}", "puedo pagar una cuota de {m}",
        "me alcanza para una cuota de {m}", "si dejo de gastar en {g} cuanto ahorro en {hor}",
        "si reduzco {g} a la mitad cuanto ahorro", "si bajo el gasto en {g} cuanto me sobra",
        "cuanto tendria que ahorrar al dia para la {meta}",
        "cuanto tengo que ahorrar al mes para la {meta}",
        "si gano {m} cuanto deberia ahorrar", "cuanto me sobra si gasto {m}",
        "me alcanza para {prod} y {prod2}", "cuanto puedo gastar sin pasarme de la meta",
        "si invierto {m} cuanto me da en {hor}", "cuanto necesito para {prod}",
        "calculame cuanto ahorro si dejo {g}",
        "cuanto me falta para llegar a {m} ahorrando",
        "si ahorro el 20 por ciento de {m} cuanto es",
        "me alcanza para pagar {prod} de {m} al mes",
        "cuanto tendria que dejar de gastar para ahorrar {m}",
        "si ahorro {m} por quincena cuanto junto en {hor}",
        "en cuanto tiempo puedo comprar {prod} ahorrando {m}",
        "si empiezo a ahorrar hoy cuando llego a {m}",
        "cuanto me rinde {m} si no lo gasto",
        "me alcanza el sueldo si pago una cuota de {m}",
        "cuanto necesito ahorrar por dia para {prod}",
        "si aporto {m} extra a la {meta} cuanto avanzo",
        "cuanto podria ahorrar si dejo las salidas",
        "calculame si me alcanza para {prod}",
        "si gasto {m} en {g} cuanto me queda",
        "cuanto tendria en {hor} si ahorro {m} cada semana",
        "me alcanza para {prod} sin tocar los ahorros",
        "cuanto debo ahorrar para tener {m} en {hor}",
        "si dejo de comprar {g} cuanto ahorro al mes",
        "puedo darme {prod} si ahorro {m}",
        "cuanto me falta para la {meta} si aporto {m}",
        "en cuanto tiempo pago {prod} con cuotas de {m}",
    ],
    "aprender_concepto": [
        "que es {c}", "que significa {c}", "como funciona {c}",
        "explicame {c}", "explicame que es {c}", "cuentame sobre {c}",
        "me explicas {c}", "quiero entender {c}", "no entiendo {c}",
        "no entiendo que es {c}", "que es eso de {c}", "en que consiste {c}",
        "para que sirve {c}", "diferencia entre {c} y {c2}", "que es mejor {c} o {c2}",
        "como se calcula {c}", "como empiezo en {c}", "que deberia saber de {c}",
        "que hay que saber de {c}", "me ensenas sobre {c}", "hablame de {c}",
        "que es {c} en palabras simples", "explicame {c} facil", "como se usa {c}",
        "de que depende {c}", "por que sube {c}", "que es lo que hace {c}",
        "quiero aprender de {c}", "ayudame a entender {c}", "que es {c} y para que sirve",
    ],
    "pedir_consejo": [
        "como puedo ahorrar mas", "que me recomiendas para {sit}",
        "me conviene {c} o {c2}", "me conviene ahorrar o invertir",
        "me conviene pagar la deuda o ahorrar", "estoy gastando mucho",
        "estoy gastando demasiado", "crees que gasto mucho", "como organizo mis gastos",
        "como hago para {sit}", "que hago para {sit}", "tienes algun consejo para {sit}",
        "que me aconsejas sobre {sit}", "dame un consejo para {sit}",
        "deberia ahorrar o gastar", "esta bien gastar tanto en {g}",
        "es malo gastar en {g}", "deberia comprar {prod}", "vale la pena {prod}",
        "que estrategia uso para {sit}", "como le hago para {sit}", "me ayudas a {sit}",
        "que puedo hacer con mi plata", "que hago si se me acaba la plata",
        "recomiendame como manejar mi plata", "esta bien que gaste en {g}",
        "como evito gastar en {g}", "que me recomiendas si gasto mucho en {g}",
        "deberia invertir una parte de mi plata", "es buena idea ahorrar en {c}",
        "como controlo el gasto en {g}", "que hago para no gastar en {g}",
        "me conviene {c} para mi situacion", "que me recomiendas para mi caso",
        "estoy haciendo bien mis finanzas", "como deberia repartir mi plata",
        "que hago primero, ahorrar o pagar deudas", "me conviene mas ahorrar o pagar {c}",
    ],
    "ayuda_app": [
        "como registro un gasto", "como registro un ingreso", "como creo una meta",
        "como edito una meta", "como borro una meta", "donde cambio mi contrasena",
        "como recupero mi contrasena", "olvide mi contrasena", "como cambio mi correo",
        "como exporto mis datos", "puedo descargar mis movimientos",
        "como elimino un gasto", "como edito un movimiento", "donde veo mis graficas",
        "como activo los recordatorios", "como apago las notificaciones",
        "como configuro un presupuesto", "como pongo un limite de gasto",
        "como veo mi historial", "la app es segura", "mis datos estan seguros",
        "quien puede ver mi informacion", "como cierro sesion", "como borro mi cuenta",
        "para que sirve esta app", "que puedes hacer", "que funciones tiene la app",
        "como cambio el tema", "como conecto mi cuenta", "por que no me deja registrar",
        "como uso la app", "donde registro mis ingresos",
        "como marco una meta como completada", "como funciona el asistente",
        "como exporto a excel", "como cambio mi nombre", "como sincronizo mis datos",
        "como creo una categoria", "como veo el resumen mensual",
        "como activo el modo oscuro", "puedo usar la app sin internet",
        "como elimino mi cuenta", "como actualizo mis ingresos",
        "como cambio mi foto de perfil", "como configuro mis metas",
        "donde estan mis datos guardados", "la app guarda mis datos en la nube",
        "como comparto mi progreso", "como reinicio mi contrasena",
        "como pongo recordatorio de pago",
    ],
    "conversacion": [
        "hola", "buenas", "buenos dias", "buenas tardes", "buenas noches", "que tal",
        "hey", "holi", "saludos", "buen dia", "como estas", "como va todo",
        "hola de nuevo", "buenas de nuevo", "epa", "que mas", "que hubo", "quiubo",
        "hola asistente", "hola amigo", "chao", "adios", "nos vemos", "hasta luego",
        "hasta pronto", "me voy", "bye", "chau", "me despido", "hablamos luego",
        "hasta manana", "gracias", "muchas gracias", "mil gracias", "gracias totales",
        "te agradezco", "gracias por la ayuda", "gracias por responder", "muy amable",
        "gracias crack", "se agradece", "gracias por todo", "de una gracias",
        "listo gracias", "ok gracias", "perfecto gracias", "gracias por explicar",
        "gracias por el dato", "agradecido", "gracias me sirvio", "chevere gracias",
        "quien eres", "eres un bot", "eres un robot", "eres humano", "como te llamas",
        "tienes nombre", "que eres", "eres una ia", "eres chatgpt", "que modelo eres",
        "quien te creo", "para que sirves", "que puedes hacer tu", "eres real",
        "eres inteligente", "sabes todo", "tienes sentimientos", "como funcionas",
        "de donde eres", "cuantos anos tienes", "eres de colombia", "hablas espanol",
        "no entendi", "no entendi nada", "no te entendi", "me perdi",
        "explicamelo mas facil", "explicamelo de otra forma", "puedes repetir",
        "no capte", "como asi", "no se que quisiste decir", "hablame mas simple",
        "mas despacio", "no entiendo esa parte", "y eso que significa",
        "puedes resumirlo", "dame un ejemplo", "no me quedo claro", "me lo repites",
        "sigues ahi", "estas ahi", "me escuchas", "no respondiste",
        "creo que no me entendiste", "ok", "listo", "de una", "vale", "dale",
        "perfecto", "bacano", "chevere", "bien", "genial", "super", "okey",
        "entendido", "aja", "claro", "obvio", "tal vez", "no se", "dejame pensar",
        "mmm", "hmm", "ah ok", "ah bueno", "ah ya", "enserio", "de verdad", "wow",
        "uff", "jaja", "que chistoso", "que gracioso", "que hora es",
        "como esta el clima", "que dia es hoy", "recomiendame una pelicula",
        "cuentame un chiste", "que hago hoy", "estoy aburrido", "juguemos algo",
        "cuentame algo", "como estas de animo", "que tal tu dia",
        "me ayudas con una tarea", "sabes programar", "cual es tu comida favorita",
        "te gusta el futbol", "quien gano el partido", "como va la seleccion",
        "estoy cansado", "tuve un dia largo", "estoy estresado", "ando aburrido",
        "que pereza todo", "la vida es dura", "no he dormido", "hoy fue un dia pesado",
        "me siento bien", "estoy feliz", "ando contento", "y tu", "y vos",
        "entonces que", "y ahora que", "algo mas", "cuentame mas",
    ],
}

# Combinaciones que multiplican las frases de conversación de forma natural.
SUFIJOS_CONV = ["", " parce", " mi llave", " mano", " bro", " amigo", " jefe", " crack", " ve"]
PREFIJOS_CONV = ["", "hola ", "buenas ", "hey "]

VOCAB = {
    "g": GRUPOS, "g2": GRUPOS, "per": PERIODOS, "meta": METAS, "prod": PRODUCTOS,
    "prod2": PRODUCTOS, "m": MONTOS, "hor": HORIZONTES, "c": CONCEPTOS, "c2": CONCEPTOS,
    "sit": SITUACIONES, "func": FUNCIONES,
}

# ---------------------------------------------------------------------------
# Estilo de escritura: minúsculas, sin tildes a veces, abreviaturas y typos
# ---------------------------------------------------------------------------
ABREV = {
    "que": "q", "porque": "pq", "para": "pa", "estoy": "stoy", "tambien": "tmb",
    "donde": "onde", "nada": "nda", "muchas": "muxas", "mucho": "muxo",
    "por favor": "porfa", "esta": "ta", "estan": "tan",
}


def quitar_tildes(s):
    return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")


def typo(s):
    """Error de digitación realista: borra, duplica o intercambia una letra."""
    if len(s) < 6:
        return s
    i = random.randrange(1, len(s) - 1)
    op = random.choice(["del", "dup", "swap"])
    if op == "del":
        return s[:i] + s[i + 1:]
    if op == "dup":
        return s[:i] + s[i] + s[i:]
    return s[:i - 1] + s[i] + s[i - 1] + s[i + 1:]


def abreviar(s):
    def rep(m):
        return ABREV[m.group(0).lower()]
    return re.sub(r"\b(" + "|".join(ABREV) + r")\b", rep, s)


def estilo(s):
    """Imita cómo se escribe en el celular. Mantiene la frase reconocible."""
    s = s.strip()
    if random.random() < 0.30:
        s = s.upper() if random.random() < 0.15 else s[:1].upper() + s[1:]
    if random.random() < 0.55:
        s = quitar_tildes(s)
    if random.random() < 0.35:
        s = abreviar(s)
    if random.random() < 0.14:
        s = typo(s)
    return " ".join(s.split())


def rellenar(plantilla):
    return re.sub(r"\{(\w+)\}", lambda m: random.choice(VOCAB[m.group(1)]), plantilla)


def candidatos(intencion):
    """Genera una lista (posiblemente larga) de frases candidatas para la intención."""
    vistas = set()
    salida = []

    def agrega(t):
        t = estilo(t)
        if len(t) < 2 or t.lower() in vistas:
            return
        vistas.add(t.lower())
        salida.append(t)

    # 1) plantillas con vocabulario (muchas combinaciones)
    plantillas = PLANTILLAS[intencion]
    for _ in range(N_POR_INTENCION * 25):
        agrega(rellenar(random.choice(plantillas)))

    # 2) combinaciones extra para conversación (prefijo + frase + sufijo)
    if intencion == "conversacion":
        base = PLANTILLAS["conversacion"]
        for _ in range(N_POR_INTENCION * 20):
            agrega(random.choice(PREFIJOS_CONV) + random.choice(base) + random.choice(SUFIJOS_CONV))

    return salida


def generar():
    filas = []
    usadas = set()
    for intencion in PLANTILLAS:
        cand = candidatos(intencion)
        random.shuffle(cand)
        n = 0
        for t in cand:
            if t.lower() in usadas:
                continue
            usadas.add(t.lower())
            filas.append((t, intencion))
            n += 1
            if n >= N_POR_INTENCION:
                break
        if n < N_POR_INTENCION:
            raise RuntimeError(f"{intencion}: solo se generaron {n} frases únicas (meta {N_POR_INTENCION})")
    random.shuffle(filas)
    return filas


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    filas = generar()
    ruta = os.path.join(out, "dataset_intenciones_entrenamiento.csv")
    with open(ruta, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(["texto", "intencion"])
        for t, i in filas:
            w.writerow([t, i])
    conteo = {}
    for _, i in filas:
        conteo[i] = conteo.get(i, 0) + 1
    print(f"{len(filas)} frases -> {ruta}")
    for i, c in conteo.items():
        print(f"  {i:18s} {c}")
