# 📊 Configuración de la Base de Datos en Notion

Esta guía te ayudará a configurar correctamente tus bases de datos de Notion para recibir las operaciones de trading.

> **Nota**: El sistema usa **relaciones bidireccionales** para Cuenta y Estrategia, lo que permite filtrar y agrupar trades fácilmente.

---

## Paso 1: Crear una Integración de Notion

1. Ve a [https://www.notion.so/my-integrations](https://www.notion.so/my-integrations)
2. Haz clic en **"+ New integration"**
3. Configura:
   - **Name**: `MT4 Trade Logger`
   - **Associated workspace**: Selecciona tu workspace
4. Haz clic en **"Submit"**
5. **IMPORTANTE**: Copia el **"Internal Integration Secret"** (empieza con `secret_...`)
   - Este será tu `NOTION_API_KEY`

---

## Paso 2: Crear las Bases de Datos

Necesitas crear **3 bases de datos** (mínimo 2 para relaciones):

### 2.1 Base de Datos: Cuentas

| Propiedad | Tipo     | Descripción              |
|-----------|----------|--------------------------|
| `Nombre`  | **Title** | Nombre de la cuenta (ej: FTMO_01) |

### 2.2 Base de Datos: Estrategias

| Propiedad      | Tipo      | Descripción                    |
|----------------|-----------|--------------------------------|
| `Nombre`       | **Title** | Nombre descriptivo             |
| `Magic Number` | **Number**| Magic Number del EA            |

### 2.3 Base de Datos: Trading Journal (Principal)

| Propiedad       | Tipo         | Descripción                          |
|-----------------|--------------|--------------------------------------|
| `Símbolo`       | **Title**    | Par/instrumento (columna principal)  |
| `Ticket`        | **Number**   | Número de ticket de la orden         |
| `Cuenta`        | **Relation** | → Relación bidireccional a Cuentas   |
| `Estrategia`    | **Relation** | → Relación bidireccional a Estrategias |
| `Dirección`     | **Select**   | BUY o SELL                           |
| `Lotes`         | **Number**   | Tamaño del lote                      |
| `PnL`           | **Number**   | Profit/Loss en USD                   |
| `Resultado`     | **Select**   | WIN o LOSS                           |
| `Balance`       | **Number**   | Balance después del cierre           |
| `Fecha Apertura`| **Date**     | Fecha/hora de apertura               |
| `Fecha Cierre`  | **Date**     | Fecha/hora de cierre                 |
| `Comentario`    | **Text**     | Comentario de la orden               |

---

## Paso 3: Crear las Relaciones Bidireccionales

### Relación: Cuenta

1. En **Trading Journal**, añade una propiedad
2. Selecciona tipo: **Relation**
3. Selecciona la base de datos: **Cuentas**
4. Activa: **"Show on Cuentas"** (esto la hace bidireccional)
5. Nombre de la propiedad inversa: `Trades`

### Relación: Estrategia

1. Repite el proceso para **Estrategia** → **Estrategias**
2. Activa: **"Show on Estrategias"**
3. Nombre de la propiedad inversa: `Trades`

---

## Paso 4: Configurar Propiedades Select

**Dirección:**
- `BUY` (color verde)
- `SELL` (color rojo)

**Resultado:**
- `WIN` (color verde)
- `LOSS` (color rojo)

---

## Paso 5: Conectar la Integración

Para **CADA** base de datos (Cuentas, Estrategias, Trading Journal):

1. Abre la base de datos
2. Haz clic en **"..."** → **"Connections"** → **"Connect to"**
3. Selecciona **MT4 Trade Logger**

---

## Paso 6: Obtener los Database IDs

Abre cada base de datos en el navegador y extrae el ID de la URL:

```
https://www.notion.so/workspace/Nombre-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX?v=...
                                      ↑ Este es el Database ID (32 chars)
```

### Variables de Entorno Requeridas

| Variable                  | Base de Datos    | Requerida |
|---------------------------|------------------|-----------|
| `NOTION_API_KEY`          | -                | ✅ Sí     |
| `NOTION_DATABASE_ID`      | Trading Journal  | ✅ Sí     |
| `NOTION_CUENTAS_DB_ID`    | Cuentas          | ✅ Sí     |
| `NOTION_ESTRATEGIAS_DB_ID`| Estrategias      | ✅ Sí     |
| `NOTION_DRAWDOWN_DB_ID`   | Drawdown Tracker | ❌ Opcional |

---

## Paso 7: (OPCIONAL) Base de Datos de Drawdown

Si quieres guardar el historial de drawdown:

| Propiedad             | Tipo       | Descripción                      |
|-----------------------|------------|----------------------------------|
| `Timestamp`           | **Title**  | Fecha/hora (columna principal)   |
| `Cuenta`              | **Relation**| → Relación a Cuentas            |
| `Estrategia`          | **Relation**| → Relación a Estrategias        |
| `Balance`             | **Number** | Balance actual                   |
| `Equity`              | **Number** | Equity actual                    |
| `Peak Balance`        | **Number** | Balance máximo alcanzado         |
| `DD Cuenta ($)`       | **Number** | Drawdown monetario de la cuenta  |
| `DD Cuenta (%)`       | **Number** | Drawdown % de la cuenta          |
| `DD Estrategia ($)`   | **Number** | Drawdown monetario de la estrategia |

---

## 🎨 Vistas Recomendadas

Con relaciones bidireccionales, puedes crear vistas potentes:

### En Trading Journal:
- **Por Símbolo**: Agrupa por Símbolo (columna principal)
- **Por Cuenta**: Filtra por la relación Cuenta
- **Por Estrategia**: Filtra por la relación Estrategia

### En Cuentas:
- Verás automáticamente todos los trades vinculados en la columna **Trades**
- Puedes calcular totales con rollups

### En Estrategias:
- Igual que Cuentas, verás los trades por estrategia

---

## ❓ Solución de Problemas

### "property is not a property..."
- Verifica los nombres exactos de las propiedades (mayúsculas, tildes)

### "Could not find database..."
- Conecta la integración a TODAS las bases de datos

### Cuentas/Estrategias no se crean automáticamente
- Verifica que `NOTION_CUENTAS_DB_ID` y `NOTION_ESTRATEGIAS_DB_ID` estén configurados
- El sistema crea automáticamente las páginas de relación si no existen

### Trades duplicados
- El sistema usa el campo `Ticket` (Number) para detectar duplicados
