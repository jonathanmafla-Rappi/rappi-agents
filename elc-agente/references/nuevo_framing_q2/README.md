# Nuevo Framing Q2

## Objetivo
Este paquete implementa el reporte `Nuevo Framing Q2` usando Snowflake como única fuente de verdad, conservando la estructura del sheet original pero calculando las métricas desde tablas `_GOLD`.

El reporte puede entregarse en:
- JSON
- tabla markdown
- dashboard HTML ejecutivo

## Archivos incluidos
- `report_spec.yaml`
  - estructura del reporte
  - secciones
  - filas KPI
  - reglas de QTD y GAP

- `queries.sql`
  - queries oficiales por sección

- `sample_output.json`
  - contrato esperado de salida

- `html_rendering.md`
  - reglas para convertir el JSON en dashboard HTML ejecutivo

- `dashboard_template.html`
  - plantilla base del dashboard HTML ejecutivo

## Fuente de datos
Única fuente: Snowflake vía MCP.

Base:
- `RP_GOLD_DB_PROD`

Esquema:
- `RESTAURANTS_HUNTING`

Tablas usadas:
- `ELC_FUNNEL_GOLD`
- `TG_ELC_2026_GOLD`
- `HT_FUNNEL_GOLD`
- `TG_HT_2026_GOLD`
- `IS_FUNNEL_GOLD`
- `TG_IS_2026_GOLD`

## Flujo de ejecución
1. Ejecutar `week_axis`
2. Construir el eje completo del quarter desde `TG_ELC_2026_GOLD`
3. Ejecutar las queries por sección definidas en `queries.sql`
4. Expandir cada sección a todas las semanas del quarter
5. Calcular `QTD`
6. Calcular `GAP`
7. Renderizar JSON final
8. Opcional: transformar a markdown o HTML ejecutivo

## Reglas críticas de negocio

### 1) Filtro temporal
- Filtrar siempre por `Q` usando el campo explícito `Q`
- No derivar quarter desde fechas

### 2) Eje semanal
- El eje semanal sale siempre de `TG_ELC_2026_GOLD`
- No usar actuals para construir el eje
- No ocultar semanas futuras
- Semanas futuras sin actual deben quedar en `null`

### 3) Targets ELC
- `AVAILABLE` y `ACTIVE` en `TG_ELC_2026_GOLD` son targets de flujo semanal
- Antes de cualquier join con actuals, agregar targets con `SUM(TARGET)`
- Mantener granularidad completa del target
- Incluir `COUNTRY` y `CHANNEL_GROUP` cuando aplique
- No duplicar targets por cruzarlos contra varias filas de `TYPE`

### 4) HC real
- `HC real = COUNT(DISTINCT HUNTER_EMAIL) WHERE HC = 1`
- Nunca sumar la columna `HC`

### 5) HC target
- `HC` target es stock semanal
- Para QTD, usar promedio semanal del target
- No sumar semanas de HC target

### 6) HC old
- `% HC old real = HC senior distinto / HC total distinto`
- `% target HC old = HC target senior / HC target total`

Mapeo de aging:
- `New Entry -> 01 - new entry`
- `Junior -> 02 - junior`
- `Senior -> 03 - senior`

### 7) Productividad real
- `PRODUCTIVIDAD real agregada = SUM(STORES_TOTALES) / SUM(DIAS_TRABAJADOS)`
- Nunca promediar productividades ya calculadas

### 8) Target macro de stores y productividad
No promediar productividades target a nivel macro.

La regla correcta es recalcular desde granularidad baja:

```text
target_stores_hunter =
PRODUCTIVIDAD_TARGET(semana, país, aging, proyecto si aplica) * DIAS_TRABAJADOS_REALES(hunter, semana)
target_stores_macro = SUM(target_stores_hunter)
target_productividad_macro = SUM(target_stores_hunter) / SUM(DIAS_TRABAJADOS_REALES)