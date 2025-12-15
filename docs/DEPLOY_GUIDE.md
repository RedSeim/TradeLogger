# 🚀 Guía de Despliegue en la Nube

Esta guía cubre el despliegue del servidor Python en servicios gratuitos de hosting, para obtener una URL pública que usarás en tus MetaTraders.

---

## Opción 1: Render (RECOMENDADO)

Render es la opción más sencilla y tiene un tier gratuito generoso.

### Paso 1: Crear Cuenta

1. Ve a [https://render.com](https://render.com)
2. Regístrate con GitHub, GitLab o email
3. Verifica tu email

### Paso 2: Subir el Código a GitHub

1. Crea un repositorio en GitHub
2. Sube la carpeta `server/` con estos archivos:
   ```
   server/
   ├── main.py
   └── requirements.txt
   ```

### Paso 3: Crear el Servicio Web

1. En el dashboard de Render, haz clic en **"New +"** → **"Web Service"**
2. Conecta tu repositorio de GitHub
3. Configura:
   - **Name**: `mt4-trade-logger`
   - **Region**: Elige la más cercana a tus VPS
   - **Branch**: `main`
   - **Root Directory**: `server` (si subiste toda la estructura)
   - **Runtime**: Python 3
   - **Build Command**: `pip install -r requirements.txt`
   - **Start Command**: `uvicorn main:app --host 0.0.0.0 --port $PORT`

### Paso 4: Configurar Variables de Entorno

En la sección **"Environment"**, añade:

| Key                      | Value                        | Requerida |
|--------------------------|------------------------------|-----------|
| `NOTION_API_KEY`         | `secret_tu_token_aqui`       | ✅ Sí     |
| `NOTION_DATABASE_ID`     | ID de Trading Journal        | ✅ Sí     |
| `NOTION_CUENTAS_DB_ID`   | ID de Cuentas                | ✅ Sí     |
| `NOTION_ESTRATEGIAS_DB_ID`| ID de Estrategias           | ✅ Sí     |
| `NOTION_DRAWDOWN_DB_ID`  | ID de Drawdown (si lo usas)  | ❌ Opcional |

> ⚠️ **IMPORTANTE**: Nunca compartas estas claves públicamente.

### Paso 5: Desplegar

1. Haz clic en **"Create Web Service"**
2. Espera a que termine el build (2-5 minutos)
3. Tu URL será algo como: `https://mt4-trade-logger.onrender.com`

### Paso 6: Verificar

Visita `https://tu-app.onrender.com/` en el navegador. Deberías ver:
```json
{
  "status": "online",
  "service": "MT4 Trade Logger",
  "version": "2.0.0",
  "notion_configured": true,
  "drawdown_db_configured": false
}
```

> 💡 **Nota**: El tier gratuito de Render "duerme" después de 15 minutos de inactividad. La primera petición después de dormir tarda ~30 segundos. Para trading activo, considera el tier de pago ($7/mes).

---

## Opción 2: Railway

Railway es otra excelente opción con un proceso simple.

### Paso 1: Crear Cuenta

1. Ve a [https://railway.app](https://railway.app)
2. Inicia sesión con GitHub

### Paso 2: Crear Nuevo Proyecto

1. Haz clic en **"New Project"**
2. Selecciona **"Deploy from GitHub repo"**
3. Autoriza Railway a acceder a tus repositorios
4. Selecciona el repositorio con el código del servidor

### Paso 3: Configurar Variables

1. Ve a la pestaña **"Variables"**
2. Añade:
   - `NOTION_API_KEY` = tu token
   - `NOTION_DATABASE_ID` = tu database id
   - `NOTION_DRAWDOWN_DB_ID` = (opcional) tu drawdown db id

### Paso 4: Configurar Build

Railway detecta automáticamente que es Python. Verifica:
- **Start Command**: `uvicorn main:app --host 0.0.0.0 --port $PORT`

### Paso 5: Generar Dominio

1. Ve a **"Settings"**
2. En **"Domains"**, haz clic en **"Generate Domain"**
3. Tu URL será algo como: `https://mt4-trade-logger-production.up.railway.app`

### Paso 6: Verificar

Visita la URL para confirmar que funciona.

> 💡 **Nota**: Railway ofrece $5 de crédito gratuito mensual, suficiente para uso ligero.

---

## Opción 3: PythonAnywhere

PythonAnywhere es ideal si prefieres una interfaz más tradicional.

### Paso 1: Crear Cuenta

1. Ve a [https://www.pythonanywhere.com](https://www.pythonanywhere.com)
2. Crea una cuenta gratuita (Beginner)

### Paso 2: Subir Archivos

1. Ve a la pestaña **"Files"**
2. Crea la carpeta `/home/tu_usuario/mt4_logger/`
3. Sube `main.py` y `requirements.txt`

### Paso 3: Crear Entorno Virtual

1. Abre una consola Bash
2. Ejecuta:
   ```bash
   cd mt4_logger
   python3.10 -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   ```

### Paso 4: Crear Web App

1. Ve a la pestaña **"Web"**
2. Haz clic en **"Add a new web app"**
3. Selecciona **"Manual configuration"**
4. Elige **Python 3.10**

### Paso 5: Configurar WSGI

1. Edita el archivo WSGI (link en la página de la web app)
2. Reemplaza todo el contenido con:

```python
import sys
import os

# Añadir el directorio del proyecto
project_home = '/home/TU_USUARIO/mt4_logger'
if project_home not in sys.path:
    sys.path.insert(0, project_home)

# Configurar variables de entorno
os.environ['NOTION_API_KEY'] = 'secret_tu_token_aqui'
os.environ['NOTION_DATABASE_ID'] = 'tu_database_id_aqui'
os.environ['NOTION_DRAWDOWN_DB_ID'] = ''  # Opcional

# Importar la aplicación FastAPI
from main import app

# PythonAnywhere usa WSGI, necesitamos un adaptador
from async_asgi_shim import create_wsgi_application
application = create_wsgi_application(app)
```

> ⚠️ **Nota**: PythonAnywhere tiene limitaciones con FastAPI/ASGI en el tier gratuito. Render o Railway son mejores opciones para FastAPI.

### Paso 6: Recargar

1. Haz clic en **"Reload"** en la página de la web app
2. Tu URL será: `https://tu_usuario.pythonanywhere.com`

---

## 🔧 Configuración Final en MetaTrader

Una vez tengas tu URL, configura cada instancia de MT4:

### 1. Permitir WebRequest

1. En MT4, ve a: **Herramientas** → **Opciones** → **Expert Advisors**
2. Marca: **"Permitir WebRequest para las siguientes URLs"**
3. Añade tu URL BASE (ej: `https://mt4-trade-logger.onrender.com`)

> ⚠️ En v2.0, solo necesitas la URL base, el EA añade automáticamente los endpoints.

### 2. Configurar el EA

1. Copia `TradeLogger.mq4` a `MQL4/Experts/`
2. Compila el EA (F7 en MetaEditor)
3. Añádelo a un gráfico
4. Configura los inputs:

| Input | Descripción | Ejemplo |
|-------|-------------|---------|
| `Identificador_Cuenta` | Nombre único de la cuenta | `FTMO_01` |
| `URL_Servidor_Base` | URL base (sin /trade) | `https://mi-app.onrender.com` |
| `Sincronizar_Historial` | Enviar historial al iniciar | `true` |
| `Dias_Historial` | Límite de días (0=todo) | `30` |
| `Modo_Debug` | Ver logs detallados | `true` |

### 3. Verificar Conexión

1. En el diario de MT4, deberías ver:
   ```
   ==============================================
   TradeLogger EA v2.0 Iniciado
   Identificador de Cuenta: FTMO_01
   URL Base del Servidor: https://...
   Sincronizar Historial: true
   Días de Historial: 30
   ==============================================
   ```

2. Si `Sincronizar_Historial` está activo, verás:
   ```
   Iniciando sincronización del historial...
   Analizando historial: X órdenes encontradas.
   === SINCRONIZACIÓN COMPLETADA ===
   Trades nuevos enviados: Y
   Trades omitidos (ya existían): Z
   ================================
   ```

3. Cierra una operación de prueba y verifica que aparezca en Notion

---

## 🔄 Actualización del Servidor

### En Render:
Cada push a GitHub despliega automáticamente.

### En Railway:
Igual, despliegue automático con cada push.

### En PythonAnywhere:
1. Sube los archivos actualizados
2. Haz clic en **"Reload"**

---

## 🛡️ Seguridad

- **Variables de entorno**: Nunca hardcodees las API keys en el código
- **HTTPS**: Todas las URLs de estos servicios usan HTTPS por defecto
- **Rate limiting**: Considera añadir rate limiting si tienes muchas cuentas

---

## ❓ Troubleshooting

### "Error 4060" en MT4
- La URL no está en la lista de permitidas
- Añádela en Opciones → Expert Advisors

### "Error 5203" en MT4
- URL inválida o servidor no accesible
- Verifica que el servidor esté corriendo

### El servidor duerme (Render gratuito)
- Es normal, la primera petición tarda más
- Considera upgrade a tier de pago para trading activo

### "property is not a property" en logs del servidor
- Los nombres de columnas en Notion no coinciden
- Revisa `NOTION_SETUP.md` para los nombres exactos

### Sincronización lenta
- Normal con muchos trades históricos
- El EA hace pausas de 100ms entre envíos para no saturar

### Trades duplicados
- El sistema detecta y omite duplicados automáticamente
- Si ves duplicados, verifica que el `Identificador_Cuenta` sea consistente
