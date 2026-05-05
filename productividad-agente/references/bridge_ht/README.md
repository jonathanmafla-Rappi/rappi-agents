# Bridge HT — Stores vs Target

## Objetivo
Este paquete implementa el reporte estándar de **bridge de stores vs target para Hunting (HT)**,
descomponiendo el gap en 4 efectos: Productividad, Madurez, Headcount, Ausencias.

El reporte tiene dos modalidades:
- **QTD**: todas las semanas del quarter con real disponible.
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
- Tablas: `HT_FUNNEL_GOLD`, `TG_HT_2026_GOLD`

## Flujo de ejecución

1. **Detectar corte temporal**
   - Consultar `DISTINCT WEEK_DATE` del funnel HT para Q activo
   - QTD: todas las semanas disponibles
   - LW: solo MAX(WEEK_DATE)

2. **Ejecutar query principal** (`queries.sql → bridge_main`)
   - LEFT JOIN universo target ← real por AGING + COUNTRY + WEEK
   - Calcular prod_real, prod_tg, dias_pp_tg, dias_pp_real por combinación

3. **Calcular los 4 efectos** con descomposición secuencial que cierra exacto:
   - S0 → S1: Productividad
   - S1 → S2m: Madurez
   - S2m → S2: Headcount
   - S2 → S3: Ausencias

4. **Verificar cierre** — suma de efectos debe igualar stores_real − stores_tg

5. **Renderizar HTML** — usando plantilla en assets/ y reglas de html_rendering.md

## Lógica del actual (stores real)
El real INCLUYE stores de hunters con HC=0 (salidos del equipo).
Esto es consistente con el total operativo bruto del período.

## Diferencias vs Bridge IS
- HT no tiene canales OB/IB — solo 1 bloque de 4 efectos
- El efecto Ausencias captura los días trabajados reales vs los implícitos en el target
- El universo base es la tabla de targets (no FULL OUTER JOIN) para controlar
  correctamente filas con target pero sin real (capturadas en Headcount)

## Reglas críticas de negocio

### dias_pp_tg (días implícitos por agente en el target)
- `dias_pp_tg = stores_tg / (hc_tg × prod_tg)` cuando el denominador > 0
- Refleja cuántos días/semana asume el target por cada hunter

### Descomposición secuencial (4 mundos)
- **S0**: tg_hc × dias_pp_tg × tg_prod  → target reconstruido
- **S1**: tg_hc × dias_pp_tg × prod_real → sustituye prod real
- **S2m**: tg_hc_total × (hc_real/hc_real_total) × dias_pp_tg × prod_real → sustituye mix aging
- **S2**: hc_real × dias_pp_tg × prod_real → sustituye volumen HC
- **S3**: stores_real (total bruto incluyendo HC=0) → sustituye días reales

### Target alineado temporalmente
- Filtrar TG_HT_2026_GOLD con WEEK IN semanas_validas (nunca full quarter vs parcial)
- Join: COUNTRY + AGING + WEEK

### Aging mapping
- 'New Entry' → '01 - new entry'
- 'Junior'    → '02 - junior'
- 'Senior'    → '03 - senior'
