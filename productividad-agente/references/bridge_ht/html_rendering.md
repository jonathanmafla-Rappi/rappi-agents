# Render HTML ejecutivo — Bridge HT

## Objetivo
Convertir los datos del bridge HT (stores vs target) en un HTML ejecutivo
con gráfica de cascada (waterfall) D3.js interactiva y tabla de resumen.

## Fuente obligatoria
Los datos provienen exclusivamente del resultado de las queries en Snowflake.
El HTML no recalcula métricas ni consulta Snowflake.

## Componentes obligatorios

### 1. Header
- Título: "Bridge HT — Stores vs Target"
- Modalidad: "QTD" o "LW"
- Semanas incluidas: lista de fechas cubiertas
- Nota: "Actual incluye tiendas de hunters salidos (HC=0)"
- Generado en: fecha actual

### 2. KPI cards (fila superior)
| Card | Valor |
|---|---|
| Target total | target_oficial |
| Real total | stores_real |
| Desvío | stores_real − target_oficial (con signo) |
| Desvío % | desvio / target_oficial (con signo, 1 decimal) |

Colores:
- Desvío positivo: verde (#1D9E75)
- Desvío negativo: rojo (#A32D2D)

### 3. Gráfica waterfall (obligatoria — D3.js)

#### Estructura de barras (orden fijo):
1. Target → barra base, arranca desde 0, valor = target_oficial
2. Productividad → efecto (puede ser + o -)
3. Madurez → efecto (puede ser + o -)
4. Headcount → efecto (puede ser + o -)
5. Ausencias → efecto (puede ser + o -)
6. Actual → barra total, arranca desde 0, valor = stores_real

#### Subtítulos bajo cada efecto:
- Productividad: "Stores/día bajo target"
- Madurez: positivo → "Mix más senior de lo esperado" | negativo → "Mix más junior de lo esperado"
- Headcount: positivo → "Más personas de lo planificado" | negativo → "Menos personas de lo planificado"
- Ausencias: "Días no trabajados vs target"
- Actual: "Incluye hunters salidos (HC=0)"

#### Reglas de implementación D3.js (OBLIGATORIO):
- Calcular `start` y `end` explícitamente para cada barra ANTES de dibujar:
  - Barra base (Target): start=0, end=target_oficial, cursor=target_oficial
  - Barra efecto: start=cursor, end=cursor+delta, cursor+=delta
  - Barra total (Actual): start=0, end=stores_real
- Altura de barra = Math.abs(y(start) - y(end))
- Conectores horizontales punteados entre barras de efecto
- Verificar antes de dibujar: target_reconstruido + SUM(deltas) == stores_real
- NUNCA usar Chart.js ni barras apiladas con barra transparente

#### Colores:
- Barra base y total: #185FA5
- Efecto positivo: #3B6D11
- Efecto negativo: #A32D2D

#### Labels sobre cada barra:
- Barras base/total: valor absoluto formateado con separador de miles
- Efectos: valor con signo (ej: −105) + % sobre target_oficial (ej: −6.9%)

#### Flecha de gap total:
- A la derecha del chart: flecha roja de target a actual con el valor del gap

#### Tooltip al hover:
- Nombre del efecto
- Valor absoluto con signo
- % sobre target con signo
- Nivel acumulado (solo efectos)

### 4. Tabla de resumen

| Efecto | Stores | % TG |
|---|---|---|
| Productividad | −518 | −12.8% |
| Madurez | −7 | −0.2% |
| Headcount | +135 | +3.3% |
| Ausencias | −86 | −2.1% |
| **Desvío total** | **−475** | **−11.8%** |

Colores en columna Stores:
- Positivo: verde con pill verde claro
- Negativo: rojo con pill rojo claro
- Cero: gris

### 5. Footer
- "Fuente: Snowflake · HT_FUNNEL_GOLD · TG_HT_2026_GOLD"
- "Actual incluye hunters con HC=0 (salidos del equipo)"
- "Semanas incluidas: [lista]"
- "Modalidad: QTD | LW"

## Reglas visuales generales
- Mismo sistema de diseño que bridge_is (mismas variables CSS, mismos colores)
- Fondo: #F7F6F3, tarjetas blancas, bordes #E2E0D8
- Fuente: system-ui, sans-serif, 13px base
- Responsive: SVG con viewBox se adapta al ancho del contenedor
- Usar SVG (D3.js) en lugar de Canvas para el waterfall HT

## Inyección de datos
Los datos se inyectan como constantes JS en el `<script>` del HTML:

```javascript
const BRIDGE_DATA = {
  modalidad:             "QTD",
  semanas:               ["2026-03-30", "2026-04-06", "2026-04-13", "2026-04-20"],
  target_oficial:        4036,
  target_reconstruido:   3930,   // S0 — base del bridge
  real_total:            3561,
  desvio:                -475,
  desvio_pct:            -11.8,
  efectos: [
    { label: "Productividad", delta: -518, sub_pos: "Prod/día sobre target",    sub_neg: "Stores/día bajo target" },
    { label: "Madurez",       delta:   -7, sub_pos: "Mix más senior esperado",  sub_neg: "Mix más junior esperado" },
    { label: "Headcount",     delta:  135, sub_pos: "Más personas planificadas",sub_neg: "Menos personas planificadas" },
    { label: "Ausencias",     delta:  -86, sub_pos: "Más días trabajados",      sub_neg: "Días no trabajados" }
  ]
};
```

## Verificación obligatoria antes de generar
- `target_reconstruido + SUM(efectos.delta) === real_total` → si no, revisar datos
- `SUM(efectos.delta) === real_total - target_reconstruido` → consistencia interna
- El desvio en KPIs usa `real_total - target_oficial` (no target_reconstruido)
