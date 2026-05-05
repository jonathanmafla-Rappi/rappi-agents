# Render HTML ejecutivo — Bridge IS

## Objetivo
Convertir los datos del bridge IS (stores vs target) en un HTML ejecutivo
con gráfica de cascada (waterfall) interactiva y tabla de resumen.

## Fuente obligatoria
Los datos provienen exclusivamente del resultado de las queries en Snowflake.
El HTML no recalcula métricas ni consulta Snowflake.

## Componentes obligatorios

### 1. Header
- Título: "Bridge IS — Stores vs Target"
- Modalidad: "QTD" o "LW"
- Semanas incluidas: lista de fechas cubiertas
- Generado en: fecha actual

### 2. KPI cards (fila superior)
| Card | Valor |
|---|---|
| Target total | SUM(stores_tg) |
| Real total | SUM(stores_real) |
| Desvío | stores_real − stores_tg (con signo) |
| Desvío % | desvio / target (con signo y 1 decimal) |

Colores:
- Desvío positivo: verde
- Desvío negativo: rojo

### 3. Gráfica waterfall (obligatoria — usar D3.js)

#### Estructura de barras (orden fijo):
1. Target total → barra base, arranca desde 0
2. OB – Productividad → efecto, puede ser negativo o positivo
3. OB – Headcount → efecto
4. OB – Maturity → efecto
5. IB – Productividad → efecto
6. IB – Headcount → efecto
7. IB – Maturity → efecto
8. Real total → barra total, arranca desde 0

#### Reglas de implementación D3.js:
- Calcular `start` y `end` explícitamente para cada barra ANTES de dibujar:
  - Barra base: start=0, end=target_total, cursor=target_total
  - Barra efecto: start=cursor, end=cursor+delta, cursor+=delta
  - Barra total: start=0, end=real_total
- Altura de barra = Math.abs(y(start) - y(end))
- Conectores horizontales punteados entre barras
- Verificar antes de dibujar: target_total + SUM(deltas) == real_total
- NUNCA usar Chart.js ni barras apiladas con barra transparente

#### Colores:
- Barra base y total: #185FA5
- Efecto positivo: #1D9E75
- Efecto negativo: #A32D2D
- Efecto cero: gris

#### Labels sobre cada barra:
- Barras base/total: valor absoluto formateado
- Efectos: valor con signo (ej: −276) + % sobre target (ej: −10.4%)

#### Separadores visuales:
- Línea vertical punteada entre bloque OB (barras 2–4) y bloque IB (barras 5–7)
- Labels de grupo "OUTBOUND" e "INBOUND" encima del separador

#### Tooltip al hover:
- Nombre del efecto
- Valor absoluto con signo
- % sobre target con signo
- Nivel acumulado

### 4. Tabla de resumen

| Efecto | Stores | % TG |
|---|---|---|
| OB – Productividad | −276 | −10.4% |
| OB – Headcount | −264 | −10.0% |
| OB – Maturity | +321 | +12.1% |
| IB – Productividad | +35 | +1.3% |
| IB – Headcount | +286 | +10.8% |
| IB – Maturity | 0 | — |
| **Desvío total** | **+102** | **+3.8%** |

Colores en columna Stores:
- Positivo: verde
- Negativo: rojo
- Cero: gris muted

### 5. Footer
- "Fuente: Snowflake · IS_FUNNEL_GOLD · TG_IS_2026_GOLD"
- "Semanas incluidas: [lista]"
- "Modalidad: QTD | LW"

## Reglas visuales generales
- Fondo general: variable CSS `--color-background-primary` o blanco #FAFAFA
- Tarjetas con fondo `--color-background-secondary` o #F5F5F3
- Bordes suaves, sombras ligeras
- Fuente: system-ui, sans-serif
- Responsive: canvas se adapta al ancho del contenedor

## Inyección de datos
Los datos se inyectan como constantes JS en el `<script>` del HTML:

```javascript
const BRIDGE_DATA = {
  modalidad: "QTD",               // "QTD" | "LW"
  semanas: ["2026-03-30", "2026-04-06", "2026-04-20"],
  target_total: 4868,
  real_total: 4567,
  desvio: -301,
  desvio_pct: -6.2,
  efectos: [
    { label: "OB – Productividad", delta: -634 },
    { label: "OB – Headcount",     delta: -512 },
    { label: "OB – Maturity",      delta:  602 },
    { label: "IB – Productividad", delta: -397 },
    { label: "IB – Headcount",     delta:  643 },
    { label: "IB – Maturity",      delta:   -3 }
  ]
};
```

## Verificación obligatoria antes de generar
- `target_total + SUM(efectos.delta) === real_total` → si no, corregir datos
- `SUM(efectos.delta) === desvio` → verificar consistencia
