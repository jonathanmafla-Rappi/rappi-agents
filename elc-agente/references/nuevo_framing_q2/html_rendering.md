# Render HTML ejecutivo - Nuevo Framing Q2

## Objetivo
Convertir el JSON consolidado del reporte `nuevo_framing_q2` en un dashboard HTML ejecutivo, legible y visualmente limpio, sin alterar la lógica del reporte.

## Fuente obligatoria
- La única fuente para el render es el JSON consolidado del reporte ya generado.
- El HTML no recalcula métricas.
- El HTML no consulta Snowflake.
- El HTML no modifica QTD, GAP ni valores semanales.
- Si falta una métrica en el JSON, se muestra tal como venga:
  - `N/A`
  - `Pending definition`
  - `null`

## Principio central
Esta capa es solo de presentación.

Toda la lógica de negocio ya debe venir resuelta desde el JSON consolidado, incluyendo:
- HC real como `COUNT(DISTINCT ...)`
- `% target HC old`
- target macro de stores recalculado
- target macro de productividad recalculado
- corte temporal correcto para `QTD` y `GAP`

## Componentes obligatorios del dashboard
1. Hero header
   - título del reporte
   - quarter
   - fecha de cobertura real (`actuals_loaded_through`)

2. Summary cards superiores
   - Available QTD
   - Active QTD
   - Activation Rate QTD
   - principales gaps negativos por canal

3. Resumen ejecutivo por canal
   - Hunting
   - Inside Sales Outbound
   - Inside Sales Inbound
   - Self-Onboarding
   - Brand Expansion

4. Tablas por sección
   - Main Metrics
   - Hunting
   - Inside Sales Outbound
   - Inside Sales Inbound
   - Self-Onboarding
   - Brand Expansion

5. Footer corto
   - aclarar que `N/A` = sin fuente validada
   - aclarar que `Pending definition` = definición de negocio pendiente

## Reglas del hero
El hero debe mostrar solo:
- título del reporte
- quarter
- fecha de cobertura real (`actuals_loaded_through`)

No debe mostrar:
- explicaciones metodológicas
- mensajes de corrección
- textos operativos internos

## Reglas visuales
- Fondo general claro
- Tarjetas KPI con jerarquía visual fuerte
- Bordes suaves y sombras ligeras
- Tablas con header sticky si es posible
- Primera columna fija o visualmente destacada

### GAP
- GAP negativo:
  - texto rojo
  - fondo rojo suave
- GAP positivo:
  - texto verde
  - fondo verde suave

### Placeholders
- `N/A`:
  - gris
  - itálica
- `Pending definition`:
  - visible como texto
  - estilo muted
- `null`:
  - renderizar como `—`
  - estilo tenue

## Reglas de clasificación visual de filas

### 1) Filas target
Una fila debe marcarse como target si:
- `label` empieza por `Target`
- o `label` contiene `% Target`

Ejemplos:
- `Target Hunting Store_Created`
- `Target Hunting Productivity`
- `Target Hunting Headcount`
- `% Target Hunters Old`
- `% Target Agents Old`
- `Target Total New Available Stores Self Onboarding`
- `Target Brand Expansion Store_Created`

Render esperado:
- clase de fila: `row-target`
- badge visual opcional: `Target`

### 2) Filas recalculadas
Una fila debe marcarse como recalculada si representa un target macro derivado desde granularidad baja y no una lectura directa/promediada.

Ejemplos típicos:
- `Target Hunting Store_Created`
- `Target Hunting Productivity`
- `Target Inside Sales Outbound Store_Created`
- `Target Inside Sales Outbound Productivity`
- `Target Inside Sales Inbound Store_Created`
- `Target Inside Sales Inbound Productivity`

Render esperado:
- clase de fila: `row-calculated`
- badge visual opcional: `Recalculado`

### 3) Filas target + recalculadas
Algunas filas pueden cumplir ambas condiciones.

Ejemplo:
- `Target Hunting Productivity`

Render esperado:
- clase de fila: `row-target row-calculated`
- badges opcionales:
  - `Target`
  - `Recalculado`

## Reglas de datos
- Mantener el eje semanal completo del quarter.
- No ocultar semanas futuras.
- No convertir `null` en `0`.
- No eliminar filas solo porque no tengan datos.
- Si una fila tiene `values_by_week` como texto (`N/A`, `Pending definition`, etc.), renderizarlo como una celda expandida a todo el bloque semanal.
- Si una fila tiene valores por semana, renderizar una celda por semana.
- `QTD` se muestra exactamente como venga en el JSON.
- `GAP` se muestra exactamente como venga en el JSON.

## Formatos
- `integer`: miles con separador, sin decimales
- `number`: 2 decimales
- `percent`: multiplicar por 100 y mostrar `%` con 2 decimales
- `null`: mostrar `—`

## Reglas específicas del reporte corregido
El dashboard debe respetar que:
- `HC real` ya viene calculado como `COUNT(DISTINCT ...)`
- `% target HC old` ya viene calculado
- `target stores` y `target productividad` ya vienen recalculados a nivel macro
- el HTML no debe volver a promediar productividades target
- el HTML no debe volver a recalcular headcount
- el HTML no debe reinterpretar GAP ni QTD

## Reglas específicas para Self-Onboarding y Brand Expansion
- En Self-Onboarding y Brand Expansion:
  - `Target Total New Available Stores` sí debe renderizarse cuando exista en el JSON.
  - `Target Store_Created` debe seguir visible como fila aunque no exista fuente todavía.
  - Si aún no existe target de `Store_Created`, mostrar `N/A`.
- No usar `ACTIVE` como sustituto de `Store_Created` target.

## Render recomendado de celdas

### Celdas numéricas
- usar el formato definido en `format`

### Celdas nulas
Render recomendado:
    <td class="null">—</td>

### Celdas textuales globales
Cuando `values_by_week` sea texto, renderizar una sola celda expandida sobre todas las semanas:
    <td class="muted" colspan="13">N/A</td>

o
    <td class="muted" colspan="13">Pending definition</td>

## Render recomendado de filas

### Fila target
    <tr class="row-target">
      <td class="kpi">
        Target Hunting Headcount
        <span class="target-badge">Target</span>
      </td>
      ...
    </tr>

### Fila recalculada
    <tr class="row-calculated">
      <td class="kpi">
        Target Hunting Store_Created
        <span class="calc-badge">Recalculado</span>
      </td>
      ...
    </tr>

### Fila target + recalculada
    <tr class="row-target row-calculated">
      <td class="kpi">
        Target Hunting Productivity
        <span class="target-badge">Target</span>
        <span class="calc-badge">Recalculado</span>
      </td>
      ...
    </tr>

## Componentes derivados sugeridos
Si el JSON ya trae suficiente info, se puede derivar visualmente:
- top summary cards
- overview por canal
- highlights de gaps
- badges de target y recalculado

Pero nunca recalcular ni reinterpretar reglas de negocio.

## Orden recomendado de render
1. leer metadata del reporte
2. renderizar hero
3. renderizar summary cards
4. renderizar resumen por canal
5. renderizar tablas por sección
6. renderizar footer

## Regla crítica final
Esta capa es solo de presentación.

Toda la lógica de negocio, QTD, GAP, headcount distinto, target HC old, target stores recalculado, target productividad recalculado y cobertura semanal ya debe venir resuelta desde el JSON consolidado.