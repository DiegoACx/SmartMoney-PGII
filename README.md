# SmartMoney-PGII

Plataforma móvil inteligente de educación y gestión financiera personal 
para trabajadores independientes y jóvenes adultos en Colombia.

Proyecto de Grado I — Ingeniería de Sistemas, UNAB.

## Stack tecnológico
- Frontend: Flutter (Dart)
- Backend / Base de datos: Supabase

## Cómo levantar el entorno
1. Instalar Flutter SDK
2. Clonar este repositorio
3. Ejecutar `flutter pub get`
4. Configurar las variables de entorno de Supabase (ver `.env.example`)
5. Ejecutar `flutter run`

## Autores
- Diego Armando Castro Duarte
- Juan José García Almeida

## Director
- Feisar Enrique Moreno Corzo

## Arquitectura del proyecto

El código en `lib/` está organizado en 3 capas con responsabilidades separadas:

### `data/`
Única capa que se comunica con Supabase. Contiene los repositorios
(`transacciones_repository.dart`, `metas_repository.dart`, `usuario_repository.dart`)
que hacen consultas puras (traer, insertar, actualizar, eliminar). No contiene
ningún cálculo ni lógica de negocio.

### `logic/`
Contiene los cálculos financieros puros (utilidad, flujo de caja, regla del
umbral del 40%, proyecciones). Esta capa **nunca importa Supabase** ni conoce
de dónde vienen los datos — solo recibe información y devuelve resultados
calculados. Al no depender de una fuente externa, se puede probar de forma
aislada.

### `presentation/`
Contiene las pantallas y widgets de la app. Regla clave: **la UI solo llama a
`logic/`, nunca a `data/` directamente.**

### Regla general (caja negra)

La UI no sabe cómo se calculan los datos ni de dónde vienen — solo consume
funciones que expone la capa `logic/`. Si en el futuro se cambia la fuente de
datos (ej. otro proveedor en vez de Supabase), solo se modifica `data/` y el
resto del proyecto no se ve afectado.

**Flujo de datos:** `data/` → `logic/` → `presentation/`
