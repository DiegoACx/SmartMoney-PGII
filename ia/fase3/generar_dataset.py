"""
SmartMoney – Fase 3 (Idea 1)
Genera el dataset de ENTRENAMIENTO del clasificador de movimientos.

Fuente: vocabulario escrito por el equipo a partir de la definición de los 13 grupos
(DANE + grupo 13) y de marcas/lugares comunes en Colombia. NO usa frases de la encuesta:
la encuesta queda reservada solo para la prueba.

Salida: dataset_entrenamiento.csv  (texto, grupo_id, grupo_nombre, origen)
Uso:    python generar_dataset.py [carpeta_salida]
"""
import random, sys, unicodedata, csv, os

random.seed(42)

GRUPOS = {
    1: "Mercado", 2: "Licor y cigarrillos", 3: "Ropa y calzado", 4: "Vivienda y servicios",
    5: "Hogar", 6: "Salud", 7: "Transporte", 8: "Celular, internet y suscripciones",
    9: "Entretenimiento", 10: "Educación", 11: "Comidas fuera y domicilios",
    12: "Otros gastos personales", 13: "Obligaciones y transferencias",
}

# ---------------------------------------------------------------------------
# Vocabulario base por grupo: lo que la gente escribe (1–3 palabras)
# ---------------------------------------------------------------------------
BASE = {
1: """mercado, mercado del mes, mercado quincenal, mercadito, compras del mes, víveres, remesa,
arroz, huevos, cubeta de huevos, leche, pan, panadería pan, queso, mantequilla, arepas, harina pan,
frijoles, lentejas, garbanzos, pasta, espaguetis, aceite, azúcar, sal, panela, café molido, chocolate,
carne, carne molida, pollo, pechuga, cerdo, chuleta, pescado, atún, salchichas, jamón, mortadela,
frutas, verduras, plátanos, papa, yuca, tomate, cebolla, aguacate, banano, manzanas, naranjas, limones,
fruver, plaza de mercado, galería, surtifruver, legumbres, granos, cereal, avena, yogur, kumis,
gaseosa para la casa, agua en bolsa, jugos hit, galletas, mecato para la casa, enlatados, salsa de tomate,
mayonesa, condimentos, revuelto, mazorca, tienda de la esquina, tienda, la tienda, compras tienda,
leche y pan, huevos y arepas, frutas y verduras, carnes, carnicería, pollo asadero crudo, pollo crudo,
alimentos, comida para la casa, despensa, abarrotes, minimercado, supermercado, súper, salsamentaria""",
2: """cerveza, cervezas, polas, pola, aguardiente, guaro, ron, ron medellín, whisky, vino, tequila,
vodka, cigarrillos, cigarros, cajetilla, cajetilla de cigarrillos, marlboro, lucky strike, vape,
vapeador, líquido vape, pod, tabaco, encendedor, six pack, canasta de cerveza, media de aguardiente,
botella de ron, licor, licores, trago, tragos, guaro antioqueño, club colombia, poker, águila, costeñita,
aguila light, corona, licorera, estanco, chorro, chicha, refajo, cerveza artesanal, shots, cocteles para la casa,
cigarrillo suelto, cerveza tienda, polas con amigos, botella de vino""",
3: """ropa, camisa, camiseta, pantalón, jean, jeans, sudadera, chaqueta, buzo, hoodie, vestido, falda,
blusa, ropa interior, medias, calzoncillos, brasier, pijama, zapatos, tenis, zapatillas, sandalias, chanclas,
botas, uniforme, ropa del trabajo, ropa de bebé, ropa niños, cinturón, gorra, bolso, cartera de cuero, maleta,
morral de ropa, vestido de baño, licra, ropa deportiva, tenis nike, tenis adidas, zapatos de cuero, arreglo de ropa,
modista, remendar pantalón, lavandería de ropa, zapatería, arreglo de zapatos, embolada, koaj, arturo calle,
studio f, tennis, falabella ropa, ropa americana, pacas, camisa polo, chaqueta de jean, abrigo""",
4: """arriendo, pago arriendo, arriendo apartamento, arriendo habitación, arriendo cuarto, pieza,
renta, administración, cuota de administración, luz, recibo de la luz, energía, factura de energía, agua,
recibo del agua, acueducto, gas, gas natural, recibo del gas, cilindro de gas, pipeta de gas, servicios,
servicios públicos, recibos, aseo recibo, alcantarillado, essa, epm, acueducto de bucaramanga, amb,
vanti, gasoriente, codensa, enel, air-e, emcali, cuota del apartamento, hipoteca,
reparación casa, plomero, electricista, arreglo de la casa, pintura de la casa, cerrajero, mantenimiento apartamento,
depósito arriendo, servicios de la casa, pago servicios""",
5: """aseo, productos de aseo, detergente, jabón en polvo, fab, ariel, suavizante, cloro, límpido, varsol,
jabón rey, lavaloza, axion, esponjas, escoba, trapero, recogedor, bolsas de basura, papel higiénico, servilletas,
toallas de cocina, ambientador, insecticida, raid, ollas, sartén, platos, vasos, cubiertos, tupperware, licuadora,
olla arrocera, nevera, lavadora, estufa, microondas, ventilador, colchón, cama, sábanas, cobija, almohada, toallas,
cortinas, muebles, sofá, mesa, sillas, escritorio, closet, bombillos, pilas, extensión eléctrica, herramientas para la casa,
homecenter, easy, ferretería, tornillos, home center, adornos, decoración, empleada doméstica, señora del aseo,
lavado de muebles, cosas para la casa, artículos del hogar, menaje""",
6: """droguería, drogas, medicamentos, medicinas, pastillas, acetaminofén, ibuprofeno, dolex, advil,
antibiótico, jarabe, vitaminas, suero, curitas, alcohol antiséptico, cita médica, consulta médica, médico,
médico general, especialista, odontólogo, dentista, ortodoncia, limpieza dental, exámenes, exámenes de laboratorio,
laboratorio, ecografía, radiografía, terapia, fisioterapia, psicólogo, optómetra, gafas, lentes, lentes de contacto,
copago, cuota moderadora, eps, medicina prepagada, sura, sanitas, urgencias, clínica, hospital, vacuna, farmacia,
farmatodo, cruz verde, la rebaja, cafam droguería, colsubsidio droguería, inyección, tapabocas, pruebas de embarazo,
anticonceptivos, preservativos, insulina, nutricionista, dermatólogo""",
7: """transporte, pasaje, pasajes, bus, buseta, metrolínea, transmilenio, metro, sitp, mio, colectivo,
taxi, uber, didi, indriver, cabify, picap, mototaxi, gasolina, tanqueada, tanquear, acpm, parqueadero,
parqueo, peaje, peajes, lavada del carro, lavada de la moto, taller, mecánico, cambio de aceite, llantas,
repuestos moto, repuestos carro, soat, revisión técnico mecánica, tecnomecánica, cuota de la moto, multa de tránsito,
pasaje intermunicipal, tiquete de bus, terminal, bus a bogotá, tiquete avión, vuelo, avianca, latam, wingo,
bicicleta, arreglo bicicleta, patineta, recarga tarjeta tullave, recarga metrolínea, recarga cívica,
transporte al trabajo, transporte universidad, pasaje a la u, carrera de taxi, moto, mantenimiento moto""",
8: """recarga, recarga celular, recarga claro, recarga tigo, recarga movistar, recarga wom, plan celular,
plan de datos, plan claro, plan tigo, plan movistar, paquete de datos, minutos, internet, internet hogar,
wifi, factura internet, claro hogar, tigo une, etb, movistar fibra, telefonía, celular, cuota del celular,
celular nuevo, cargador celular, audífonos, forro celular, protector de pantalla, netflix, spotify, disney plus,
hbo max, max, prime video, amazon prime, youtube premium, apple music, icloud, google one, google drive,
chatgpt plus, crunchyroll, paramount, star plus, deezer, suscripción, suscripciones, streaming, televisión por cable,
directv, plan pospago, prepago, datos móviles, arreglo celular, reparación celular, pantalla celular""",
9: """entretenimiento, cine, boletas de cine, cine colombia, procinal, cinemark, crispetas cine, salidas,
salida con amigos, rumba, discoteca, fiesta, concierto, boletas concierto, teatro, partido de fútbol,
boleta estadio, bolos, billar, tejo, karaoke, parque de diversiones, piscina, paseo, viaje, vacaciones,
hotel, airbnb, finca, juegos, videojuegos, play, playstation, xbox, nintendo, steam, juego de celular,
free fire, skins, robux, apuestas, lotería, chance, baloto, casino, gimnasio, mensualidad gimnasio, smart fit,
bodytech, fútbol, cancha sintética, alquiler cancha, mascota, comida perro, comida gato, concentrado perro,
veterinario, peluquería canina, arena gato, juguete mascota, libro de lectura, revista, hobbies, manualidades,
instrumento musical, salida a comer helado, parque, museo, ciclopaseo, ecoparque""",
10: """educación, matrícula, matrícula universidad, semestre, pago semestre, pensión colegio, colegio,
mensualidad colegio, universidad, unab, uis, uts, sena, curso, curso inglés, inglés, curso online, udemy,
platzi, coursera, diplomado, posgrado, especialización, maestría, fotocopias, copias, impresiones, impresión,
libros, libro universidad, cuadernos, útiles, útiles escolares, lápices, esferos, calculadora, cartulina,
materiales universidad, trabajos de la u, carnet estudiantil, derechos de grado, inscripción, examen icfes,
saber pro, tutorías, clases particulares, refuerzo, lista escolar, uniforme colegio, transporte escolar,
ruta del colegio, guardería, jardín infantil, papelería, panamericana""",
11: """almuerzo, almuerzos, corrientazo, menú del día, desayuno, desayuno afuera, comida afuera, cena,
cena afuera, restaurante, rappi, domicilio, domicilios, didi food, ifood, pedido rappi, pizza, hamburguesa,
perro caliente, salchipapa, empanadas, arepa de huevo, pollo asado, asadero, frisby, kfc, mcdonalds, el corral,
crepes, sushi, comida china, comida rápida, onces, algo, mecato, snack, café, tinto, juan valdez, tostao,
oma, starbucks, pastel, buñuelo, pandebono, avena y pan, jugo natural, granizado, helado, cono, postre,
almuerzo trabajo, almuerzo universidad, cafetería, cafetería u, panadería tinto,
chorizo, picada, parrilla, almuerzo ejecutivo, comida callejera, fritanga, chuzo, tamal, lechona, bandeja paisa,
gaseosa, botella de agua, jugo, papas, paquete de papas, dulces, chicles""",
12: """peluquería, corte de pelo, motilada, barbería, barbero, uñas, manicure, pedicure, cejas, depilación,
cera, tinte, maquillaje, cremas, crema corporal, bloqueador, desodorante, shampoo, champú, acondicionador,
jabón de baño, cepillo de dientes, crema dental, enjuague bucal, toallas higiénicas, tampones, perfume,
loción, rasuradora, cuchillas de afeitar, cuidado personal, spa, masaje, regalo, regalos,
regalo cumpleaños, regalo mamá, detalle, flores, tarjeta de regalo, donación, limosna, diezmo, ofrenda iglesia,
propina, tatuaje, piercing, accesorios, reloj, aretes, joyería, gafas de sol, sombrilla,
cosméticos, belleza, salón de belleza, gastos personales, varios, otros, gastos varios, imprevistos""",
13: """icetex, cuota icetex, crédito icetex, tarjeta de crédito, pago tarjeta, pago tarjeta de crédito,
cuota tarjeta, préstamo, pago préstamo, cuota del préstamo, crédito, cuota crédito, crédito de libre inversión,
crédito bancolombia, cuota banco, deuda, deudas, pago deuda, abono deuda, gota a gota, prestamista, fiado,
pagar fiado, cuota, cuotas, pila, planilla pila, seguridad social, salud y pensión, pensión voluntaria, aportes pila,
impuestos, impuesto, dian, declaración de renta, retención, predial, impuesto vehicular, 4x1000, cuota de manejo,
envío a mi mamá, plata a mi mamá, nequi a mamá, transferencia, transferencia nequi, daviplata, envío daviplata,
giro, giro a mi familia, efecty, envío efecty, plata para la casa, aporte a la casa, ayuda a mis papás, mesada hijo,
cuota alimentaria, pensión alimentaria, préstamo a un amigo, devolver plata, pago a amigo, seguro de vida, póliza,
cuota addi, sistecrédito, cuota sistecrédito, brilla, crédito brilla, codeudor, embargo""",
}

# Marcas / lugares que se combinan con verbos o grupos para dar variedad
COMBINA = {
1: (["compra", "mercado", "compras", ""], ["d1", "ara", "éxito", "olímpica", "jumbo", "carulla", "isimo", "justo y bueno", "makro", "la tienda", "la plaza", "surtifruver", "merkepaís", "mercacentro", "colsubsidio"]),
2: (["", "compra"], ["cerveza", "polas", "guaro", "cigarrillos", "ron"]),
3: (["compra", ""], ["zara", "koaj", "arturo calle", "studio f", "h&m", "bershka", "nike", "adidas", "falabella", "tennis", "americanino", "gef", "punto blanco", "spring step", "bata", "vélez", "pat primo"]),
4: (["pago", "recibo", "factura", ""], ["luz", "agua", "gas", "arriendo", "administración", "essa", "epm", "vanti", "acueducto", "enel"]),
5: (["compra", ""], ["homecenter", "easy", "ferretería", "alkosto", "ktronix", "falabella hogar", "tugó", "jamar", "dollarcity", "miniso"]),
6: (["", "pago", "compra"], ["droguería", "cruz verde", "la rebaja", "farmatodo", "copago eps", "cita odontólogo", "examen de sangre", "pastillas", "medicamentos"]),
7: (["", "pago"], ["uber", "didi", "taxi", "metrolínea", "transmilenio", "gasolina", "parqueadero", "peaje", "soat", "indriver", "pasaje bus", "tanqueada moto"]),
8: (["pago", "recarga", ""], ["claro", "tigo", "movistar", "wom", "etb", "netflix", "spotify", "disney", "youtube premium", "amazon prime", "hbo", "internet", "plan celular"]),
9: (["", "salida", "boletas"], ["cine", "concierto", "rumba", "discoteca", "partido", "bolos", "tejo", "piscina", "parque", "finca"]),
10: (["pago", "", "compra"], ["matrícula", "semestre", "curso", "fotocopias", "libros", "cuadernos", "inglés", "diplomado", "pensión colegio", "útiles"]),
11: (["", "pedido", "domicilio"], ["rappi", "didi food", "frisby", "kfc", "mcdonalds", "el corral", "crepes", "juan valdez", "tostao", "presto", "dominos", "papa johns", "subway", "kokoriko", "jeno's pizza"]),
12: (["", "pago", "compra"], ["peluquería", "barbería", "uñas", "manicure", "perfume", "cremas", "regalo", "maquillaje", "depilación", "spa"]),
13: (["pago", "cuota", "abono", ""], ["icetex", "tarjeta", "préstamo", "crédito", "nequi", "daviplata", "pila", "dian", "addi", "sistecrédito", "banco", "bancolombia", "davivienda", "deuda"]),
}

PREFIJOS = ["", "", "", "", "pago ", "compra ", "pagué ", "gasto ", "compré "]
SUFIJOS = ["", "", "", "", "", " del mes", " de la semana", " hoy", " quincena"]


def quitar_tildes(s):
    return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")


def typo(s):
    """Error de digitación realista: borrar, duplicar o intercambiar una letra."""
    if len(s) < 5:
        return s
    i = random.randrange(1, len(s) - 1)
    op = random.choice(["del", "dup", "swap"])
    if op == "del":
        return s[:i] + s[i + 1:]
    if op == "dup":
        return s[:i] + s[i] + s[i:]
    return s[:i - 1] + s[i] + s[i - 1] + s[i + 1:]


def estilo(s):
    """Imita cómo se escribe en el celular: mayúscula inicial, sin tildes, errores."""
    r = random.random()
    if r < 0.55:
        s = s[:1].upper() + s[1:]
    elif r < 0.62:
        s = s.upper()
    if random.random() < 0.35:
        s = quitar_tildes(s)
    if random.random() < 0.12:
        s = typo(s)
    return s.strip()


def limpia(lista):
    return [x.strip() for x in lista.replace("\n", " ").split(",") if x.strip()]


def generar(n_por_grupo=260):
    filas = []
    for g, texto in BASE.items():
        base = limpia(texto)
        verbos, marcas = COMBINA[g]
        vistos = set()
        # 1) todas las frases base tal cual (origen=equipo)
        for b in base:
            filas.append((b, g, "base"))
            vistos.add(b.lower())
        # 2) variaciones hasta completar n_por_grupo
        intentos = 0
        while len(vistos) < n_por_grupo and intentos < n_por_grupo * 40:
            intentos += 1
            r = random.random()
            if r < 0.35:
                s = (random.choice(verbos) + " " + random.choice(marcas)).strip()
            elif r < 0.70:
                b = random.choice(base)
                pre = "" if b.split()[0] in ("pago", "compra", "compras", "recarga", "cuota") else random.choice(PREFIJOS)
                suf = "" if len(b.split()) > 2 else random.choice(SUFIJOS)
                s = pre + b + suf
            else:
                s = random.choice(base)
            s = estilo(s.strip())
            if s.lower() in vistos or len(s) < 2:
                continue
            vistos.add(s.lower())
            filas.append((s, g, "variacion"))
    random.shuffle(filas)
    return filas


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    filas = generar()
    ruta = os.path.join(out, "dataset_entrenamiento.csv")
    with open(ruta, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(["texto", "grupo_id", "grupo_nombre", "origen"])
        for t, g, o in filas:
            w.writerow([t, g, GRUPOS[g], o])
    print(f"{len(filas)} frases -> {ruta}")
