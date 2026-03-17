# 📊 **TABLA COMPARACIÓN DE TURNOS - TRAZA**

## 🕐 **HORARIOS POR TURNO:**

| Concepto | Turno 5x2 | Turno 6x1 |
|----------|-----------|-----------|
| **Nombre** | 5 días trabajo, 2 descanso | 6 días trabajo, 1 descanso |
| **L-V Inicio** | 09:15 | 09:45 |
| **L-V Fin** | 19:00 | 18:30 |
| **Sáb Inicio** | 10:00 | 10:00 |
| **Sáb Fin** | 14:00 | 14:00 |
| **Dom/Festivos** | Día libre (todo = hora extra) | Día libre (todo = hora extra) |

---

## 📐 **CÁLCULO DE INICIO TARDÍO:**

### **Turno 5x2:**

| Día | Hora Esperada | Hora Real | Inicio Tardío |
|-----|---------------|-----------|---------------|
| Lunes | 09:15 | 09:30 | ✅ 15 min |
| Lunes | 09:15 | 10:00 | ⚠️ 45 min |
| Sábado | 10:00 | 10:30 | ⚠️ 30 min |
| Domingo | - | 10:00 | ❌ 0 min (día libre) |

### **Turno 6x1:**

| Día | Hora Esperada | Hora Real | Inicio Tardío |
|-----|---------------|-----------|---------------|
| Lunes | 09:45 | 10:00 | ✅ 15 min |
| Lunes | 09:45 | 10:30 | ⚠️ 45 min |
| Sábado | 10:00 | 10:30 | ⚠️ 30 min |
| Domingo | - | 10:00 | ❌ 0 min (día libre) |

---

## ⏰ **CÁLCULO DE HORAS EXTRAS:**

### **Turno 5x2:**

| Día | Hora Límite | Hora Real | Hora Extra |
|-----|-------------|-----------|------------|
| Lunes | 19:00 | 18:30 | ❌ 0 min |
| Lunes | 19:00 | 19:30 | ✅ 30 min |
| Lunes | 19:00 | 20:00 | ✅ 60 min |
| Sábado | 14:00 | 14:30 | ✅ 30 min |
| Domingo | - | Cualquiera | ✅ TODO (100%) |

### **Turno 6x1:**

| Día | Hora Límite | Hora Real | Hora Extra |
|-----|-------------|-----------|------------|
| Lunes | 18:30 | 18:00 | ❌ 0 min |
| Lunes | 18:30 | 19:00 | ✅ 30 min |
| Lunes | 18:30 | 20:00 | ✅ 90 min |
| Sábado | 14:00 | 14:30 | ✅ 30 min |
| Domingo | - | Cualquiera | ✅ TODO (100%) |

---

## 🔍 **EJEMPLO COMPARATIVO:**

### **Escenario:** Técnico trabaja Lunes 05/01/26

**Órdenes del día:**
- Orden 1: 09:30 - 10:00 (30 min)
- Orden 2: 14:00 - 15:00 (60 min)
- Orden 3: 18:00 - 19:15 (75 min)

### **Si el técnico es Turno 5x2:**

| Concepto | Cálculo | Resultado |
|----------|---------|-----------|
| **Inicio Tardío** | 09:30 - 09:15 = 15 min | ⚠️ 15 min |
| **Hora Extra** | 19:15 - 19:00 = 15 min | ✅ 15 min |
| **Total trabajo** | 30 + 60 + 75 = 165 min | 2h 45min |

### **Si el técnico es Turno 6x1:**

| Concepto | Cálculo | Resultado |
|----------|---------|-----------|
| **Inicio Tardío** | 09:30 - 09:45 = 0 min (inició antes) | ✅ 0 min |
| **Hora Extra** | 19:15 - 18:30 = 45 min | ⚠️ 45 min |
| **Total trabajo** | 30 + 60 + 75 = 165 min | 2h 45min |

---

## 📊 **DIFERENCIAS CLAVE:**

| Aspecto | Turno 5x2 | Turno 6x1 |
|---------|-----------|-----------|
| **Flexibilidad matinal** | Más flexible (inicia 09:15) | Menos flexible (inicia 09:45) |
| **Flexibilidad vespertina** | Menos flexible (termina 19:00) | Más flexible (termina 18:30) |
| **Días de trabajo/semana** | 5 días | 6 días |
| **Horas extra comienzan** | Después de 19:00 | Después de 18:30 |
| **Inicio tardío comienza** | Después de 09:15 | Después de 09:45 |

---

## 🎯 **RECOMENDACIONES:**

### **Para supervisores:**

1. **Turno 5x2:**
   - ✅ Mejor para técnicos que necesitan flexibilidad matinal
   - ✅ Pueden trabajar hasta las 19:00 sin hora extra
   - ⚠️ Menos días de descanso (2 por semana)

2. **Turno 6x1:**
   - ✅ Más días de trabajo (mejor para producción)
   - ✅ Terminan antes (18:30)
   - ⚠️ Deben ser más puntuales en la mañana (09:45)

### **Para técnicos:**

- Verifica tu turno en la app (se muestra en "Tu Mes")
- Si llegas tarde frecuentemente:
  - **Turno 5x2**: Llegar antes de 09:15
  - **Turno 6x1**: Llegar antes de 09:45
- Si haces horas extras:
  - **Turno 5x2**: Se cuentan después de 19:00
  - **Turno 6x1**: Se cuentan después de 18:30

---

## 🔧 **CÓMO SE ASIGNA EL TURNO:**

El turno de cada técnico se almacena en la tabla `tecnicos_traza_zc`:

```sql
SELECT rut, nombre_completo, tipo_turno
FROM tecnicos_traza_zc
WHERE activo = true;
```

**Valores válidos:**
- `'5x2'` - Turno 5 días trabajo, 2 descanso
- `'6x1'` - Turno 6 días trabajo, 1 descanso

**Por defecto:** Si un técnico no tiene `tipo_turno` asignado, se asume `'6x1'`.

---

## 📝 **QUERIES ÚTILES:**

### **Ver técnicos por turno:**

```sql
SELECT 
    tipo_turno,
    COUNT(*) AS cantidad_tecnicos
FROM tecnicos_traza_zc
WHERE activo = true
GROUP BY tipo_turno;
```

### **Cambiar turno de un técnico:**

```sql
UPDATE tecnicos_traza_zc
SET tipo_turno = '5x2'
WHERE rut = '12345678-9';
```

### **Ver inicio tardío por turno (Enero 2026):**

```sql
SELECT 
    tipo_turno,
    COUNT(*) AS dias_con_tardanza,
    ROUND(AVG(minutos_inicio_tardio), 2) AS promedio_minutos,
    ROUND(SUM(minutos_inicio_tardio) / 60.0, 2) AS total_horas
FROM v_tiempos_diarios
WHERE EXTRACT(MONTH FROM fecha_completa) = 1
  AND EXTRACT(YEAR FROM fecha_completa) = 2026
  AND minutos_inicio_tardio > 0
GROUP BY tipo_turno;
```

### **Ver horas extras por turno (Enero 2026):**

```sql
SELECT 
    tipo_turno,
    COUNT(*) AS dias_con_hora_extra,
    ROUND(AVG(minutos_hora_extra), 2) AS promedio_minutos,
    ROUND(SUM(minutos_hora_extra) / 60.0, 2) AS total_horas
FROM v_tiempos_diarios
WHERE EXTRACT(MONTH FROM fecha_completa) = 1
  AND EXTRACT(YEAR FROM fecha_completa) = 2026
  AND minutos_hora_extra > 0
GROUP BY tipo_turno;
```

---

**🎉 Sistema actualizado con soporte completo para múltiples turnos!**

