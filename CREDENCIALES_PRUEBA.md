# 🔐 Credenciales de Prueba - TrazaBox

## 📱 Para probar la app

**Importante:** En la app solo se ingresa el **RUT sin puntos ni guión**

---

## 👨‍💼 ADMINISTRADOR

```
RUT para login: 111111111
Nombre: Admin TRAZA
Rol: Administrador
```

---

## 👔 SUPERVISORES

### Supervisor 1 (supervisa FTTH)
```
RUT para login: 123456789
Nombre: Supervisor 1 TRAZA
Rol: Supervisor
Tecnología: Supervisa FTTH
```

### Supervisor 2 (supervisa NTT)
```
RUT para login: 987654321
Nombre: Supervisor 2 TRAZA
Rol: Supervisor
Tecnología: Supervisa NTT
```

---

## 👷 TÉCNICOS FTTH

### Técnico 1
```
RUT para login: 150000001
Nombre: Juan Pérez (FTTH)
Rol: Técnico
Tecnología: FTTH
Supervisor: Supervisor 1 TRAZA
```

### Técnico 2
```
RUT para login: 150000002
Nombre: María González (FTTH)
Rol: Técnico
Tecnología: FTTH
Supervisor: Supervisor 1 TRAZA
```

### Técnico 3
```
RUT para login: 150000003
Nombre: Pedro Rojas (FTTH)
Rol: Técnico
Tecnología: FTTH
Supervisor: Supervisor 1 TRAZA
```

### Técnico 4
```
RUT para login: 150000004
Nombre: Ana Silva (FTTH)
Rol: Técnico
Tecnología: FTTH
Supervisor: Supervisor 1 TRAZA
```

### Técnico 5
```
RUT para login: 150000005
Nombre: Carlos Muñoz (FTTH)
Rol: Técnico
Tecnología: FTTH
Supervisor: Supervisor 1 TRAZA
```

---

## 👷 TÉCNICOS NTT (Neutra)

### Técnico 1
```
RUT para login: 160000001
Nombre: Luis Torres (NTT)
Rol: Técnico
Tecnología: NTT
Supervisor: Supervisor 2 TRAZA
```

### Técnico 2
```
RUT para login: 160000002
Nombre: Sandra Díaz (NTT)
Rol: Técnico
Tecnología: NTT
Supervisor: Supervisor 2 TRAZA
```

### Técnico 3
```
RUT para login: 160000003
Nombre: Jorge Vega (NTT)
Rol: Técnico
Tecnología: NTT
Supervisor: Supervisor 2 TRAZA
```

### Técnico 4
```
RUT para login: 160000004
Nombre: Patricia Morales (NTT)
Rol: Técnico
Tecnología: NTT
Supervisor: Supervisor 2 TRAZA
```

### Técnico 5
```
RUT para login: 160000005
Nombre: Roberto Castro (NTT)
Rol: Técnico
Tecnología: NTT
Supervisor: Supervisor 2 TRAZA
```

---

## 🎯 Recomendación para Primera Prueba

Usa este técnico FTTH:
```
RUT: 150000001
Nombre: Juan Pérez (FTTH)
```

Es el más fácil de recordar para pruebas rápidas.

---

## ➕ Agregar Más Usuarios

Para agregar usuarios adicionales, ejecutar en Supabase:

```sql
INSERT INTO usuarios (rut, nombre, telefono, rol_id, tecnologia, supervisor_id, activo) 
VALUES (
    '17000000-1',  -- RUT con guión
    'Nuevo Técnico',
    '+56900000010',
    (SELECT id FROM roles WHERE nombre = 'tecnico'),
    'FTTH',  -- o 'NTT' o 'HFC'
    2,  -- ID del supervisor (2 = Supervisor 1, 3 = Supervisor 2)
    TRUE
);
```

---

## 🔒 Seguridad

⚠️ **Importante:** Estos son usuarios de **PRUEBA**. 

En producción:
- Usa RUTs reales de tu equipo
- Implementa contraseñas si es necesario
- Habilita RLS (Row Level Security) en Supabase
- Agrega validación adicional

---

**Total de usuarios creados:** 13
- 1 Admin
- 2 Supervisores  
- 5 Técnicos FTTH
- 5 Técnicos NTT

