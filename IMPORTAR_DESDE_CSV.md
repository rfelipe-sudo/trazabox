# 📥 IMPORTAR DATOS DESDE CSV A SUPABASE TRAZA

## 📋 Formato esperado del CSV

Tu archivo CSV debe tener estas columnas (mínimo):

```csv
rut_tecnico,tecnico,fecha_trabajo,orden_trabajo,tipo_orden,tecnologia,estado
12345678-9,Juan Pérez,04/02/2026,OT-123456,3_PLAY,FTTH,Completado
11111111-1,María López,04/02/2026,OT-123457,1_PLAY,NTT,Completado
```

### Columnas obligatorias:
- `rut_tecnico`: RUT del técnico (ej: 12345678-9)
- `tecnico`: Nombre completo
- `fecha_trabajo`: Formato DD/MM/YYYY
- `orden_trabajo`: Número de OT
- `tipo_orden`: Uno de: `1_PLAY`, `2_PLAY`, `3_PLAY`, `MODIFICACION`, `EXTENSOR`, `DECODIFICADOR`
- `tecnologia`: `FTTH`, `NTT` o `HFC`
- `estado`: `Completado`, `Cancelado`, `No Realizada`, etc.

### Columnas opcionales:
- `cliente`: Nombre del cliente
- `direccion`: Dirección de instalación
- `comuna`: Comuna
- `region`: Región

---

## 🔧 Paso 1: Preparar el CSV

1. Abre tu archivo en Excel
2. Asegúrate de que las fechas estén en formato `DD/MM/YYYY`
3. Verifica que los RUTs tengan guión: `12345678-9`
4. Guarda como CSV (UTF-8)

---

## 📤 Paso 2: Importar a Supabase

### Método A: Desde la interfaz de Supabase

1. Ve a tu proyecto TRAZA en Supabase
2. Click en **Table Editor** → `produccion_traza`
3. Click en **Insert** → **Import data from CSV**
4. Selecciona tu archivo
5. Mapea las columnas
6. Click en **Import**

### Método B: Usando SQL (para archivos grandes)

1. Convierte tu CSV a SQL usando este script de Python:

```python
import csv
import sys

def csv_to_sql(csv_file):
    with open(csv_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        
        print("-- Importar producción desde CSV")
        print("INSERT INTO produccion_traza (rut_tecnico, tecnico, fecha_trabajo, orden_trabajo, tipo_orden, tecnologia, estado, cliente, comuna, region)")
        print("VALUES")
        
        rows = []
        for row in reader:
            # Calcular puntos RGU según tipo
            tipo = row['tipo_orden']
            if tipo == '3_PLAY':
                puntos = 3.0
            elif tipo == '2_PLAY':
                puntos = 2.0
            elif tipo == '1_PLAY':
                puntos = 1.0
            elif tipo in ['MODIFICACION', 'EXTENSOR']:
                puntos = 0.75
            elif tipo == 'DECODIFICADOR':
                puntos = 0.5
            else:
                puntos = 0.0
            
            values = f"('{row['rut_tecnico']}', '{row['tecnico']}', '{row['fecha_trabajo']}', '{row['orden_trabajo']}', '{row['tipo_orden']}', '{row['tecnologia']}', {puntos}, '{row['estado']}')"
            rows.append(values)
        
        print(',\n'.join(rows))
        print("ON CONFLICT (orden_trabajo) DO NOTHING;")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        csv_to_sql(sys.argv[1])
    else:
        print("Uso: python csv_to_sql.py tu_archivo.csv")
```

2. Ejecuta: `python csv_to_sql.py datos_traza.csv > importar.sql`
3. Copia el contenido de `importar.sql` y ejecútalo en Supabase

---

## ✅ Paso 3: Verificar

```sql
-- Ver total de órdenes importadas
SELECT COUNT(*) FROM produccion_traza;

-- Ver técnicos únicos
SELECT rut_tecnico, tecnico, COUNT(*) as ordenes
FROM produccion_traza
GROUP BY rut_tecnico, tecnico
ORDER BY ordenes DESC;

-- Ver producción por tecnología
SELECT tecnologia, COUNT(*) as ordenes, SUM(puntos_rgu) as total_rgu
FROM produccion_traza
WHERE estado = 'Completado'
GROUP BY tecnologia;
```

---

## 🔄 Paso 4: Actualizar diariamente

Una vez cargada la data inicial, puedes:

1. **Manualmente**: Importar CSV diario
2. **AppScript**: Crear script que cargue desde Google Sheets
3. **API**: Conectar con sistema fuente directamente

¿Necesitas ayuda con alguna de estas opciones?

