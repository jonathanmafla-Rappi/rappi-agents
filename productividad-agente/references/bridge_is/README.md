# Bridge IS — Stores vs Target

## Objetivo
Este paquete implementa el reporte estándar de **bridge de stores vs target para Inside Sales (IS)**,
descomponiendo el gap en 6 efectos: OB-Productividad, OB-Headcount, OB-Maturity,
IB-Productividad, IB-Headcount, IB-Maturity.

El reporte tiene dos modalidades:
- **QTD**: todas las semanas del quarter con real disponible (semana vencida).
- **LW** (Last Week): solo la última semana con real disponible.

## Archivos incluidos
- `README.md` — este archivo
- `report_spec.yaml` — definición del reporte: modalidades, efectos, reglas de cierre
- `queries.sql` — queries canónicas para obtener los datos del bridge
- `html_rendering.md` — reglas para renderizar el bridge como HTML ejecutivo
- `bridge_template.html` (en assets/) — plantilla base del HTML

## Fuente de datos
Única fuente: Snowflake vía MCP.

- Base: `RP_GOLD_DB_PROD`
- Esquema: `RESTAURANTS_HUNTING`
- Tablas: `IS_FUNNEL_GOLD`, `TG_IS_2026_GOLD`

## Flujo de ejecución

1. **Detectar corte temporal** (ver `report_spec.yaml → temporal_detection`)
   - Consultar `DISTINCT WEEK_DATE` del funnel real para Q2
   - QTD: todas las semanas disponibles
   - LW: solo la semana máxima disponible

2. **Ejecutar query principal** (`queries.sql → bridge_main`)
   - FULL OUTER JOIN real ↔ target por PROYECTO + AGING + COUNTRY + WEEK
   - Calcular prod_real, prod_tg, prod_tg_mix_real, asist_real, asist_tg por proyecto

3. **Calcular los 6 efectos** (ver `report_spec.yaml → effects`)
   - Usando descomposición secuencial que cierra exacto
   - Residuo de cierre absorbido en ef_hc

4. **Verificar cierre** — suma de efectos debe igualar stores_real − stores_tg

5. **Renderizar HTML** — usando plantilla en assets/ y reglas de html_rendering.md

## Lógica de corte temporal (semana vencida)

El agente opera en modalidad **semana vencida**: el bridge siempre incluye
semanas cuyo real ya esté cargado en el funnel.

Ejemplo:
- Si hoy es **4 de mayo** y el funnel tiene hasta la semana del 27-abr:
  - QTD = 30-mar + 06-abr + 13-abr + 20-abr + 27-abr
  - LW  = solo 27-abr
- Si hoy es **28 de abril** y el funnel solo tiene hasta 20-abr:
  - QTD = 30-mar + 06-abr + 13-abr + 20-abr
  - LW  = solo 20-abr

**Nunca** comparar target full-quarter contra actual parcial.

## Reglas críticas de negocio

### Target de STORES
- Usar `SUM(TARGET)` donde `TIPO_TARGET = 'STORES'`
- FULL OUTER JOIN con el real para no perder semanas con target pero sin real (y viceversa)

### Target de HC
- Usar `AVG(TARGET)` donde `TIPO_TARGET = 'HC'`
- Es stock semanal, no flujo — no sumar semanas

### Target de PRODUCTIVIDAD
- Usar `AVG(TARGET)` donde `TIPO_TARGET = 'PRODUCTIVIDAD'`
- Ponderar por `hc_tg × dias_tg_por_agente` para obtener prod_tg global

### dias_tg_por_agente
- `dias_tg_por_agente = stores_tg / (hc_tg × prod_tg)` cuando el denominador > 0, else 0

### prod_tg_mix_real
- Productividad target ponderada con el MIX REAL de aging (para aislar efecto maturity)
- `prod_tg_mix_real = SUM(prod_tg × hc_real × dias_tg_por_agente) / SUM(hc_real × dias_tg_por_agente)`

### Descomposición secuencial (cierre exacto)
Ver `report_spec.yaml → effects` para la fórmula completa.
El residuo de cierre siempre se absorbe en `ef_hc`.
