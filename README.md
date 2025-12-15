# MT4/MT5 Trade Logger → Notion v2.0

Sistema centralizado para registrar operaciones de trading desde múltiples instancias de MetaTrader 4 o MetaTrader 5 hacia una base de datos de Notion.

## ✨ Características

- **Compatible con MT4 y MT5** - EAs nativos para ambas plataformas
- **Registro en tiempo real** de trades cerrados
- **Sincronización de historial** - Detecta y envía trades pasados que falten en Notion
- **Tracking de drawdown** por cuenta y por estrategia (Magic Number)
- **Detección de duplicados** automática
- **Multi-cuenta** - Soporta múltiples VPS/terminales

## 📐 Arquitectura

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   MT4 VPS #1    │     │   MT4 VPS #2    │     │   MT4 VPS #N    │
│  (FTMO_01 EA)   │     │  (FTMO_02 EA)   │     │  (PROP_XYZ EA)  │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         │ POST JSON             │ POST JSON             │ POST JSON
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │   Servidor Python      │
                    │   (FastAPI en Render)  │
                    │   https://xxx.onrender │
                    └────────────┬───────────┘
                                 │
                                 │ API Request
                                 ▼
                    ┌────────────────────────┐
                    │      Notion API        │
                    │   (Base de Datos)      │
                    └────────────────────────┘
```

## 📁 Estructura del Proyecto

```
mt4_notion_logger/
├── client/
│   ├── TradeLogger.mq4      # Expert Advisor para MT4 (v2.0)
│   └── TradeLogger.mq5      # Expert Advisor para MT5 (v2.0)
├── server/
│   ├── main.py              # Servidor FastAPI (v2.0.0)
│   └── requirements.txt     # Dependencias Python
├── docs/
│   ├── NOTION_SETUP.md      # Instrucciones para Notion
│   └── DEPLOY_GUIDE.md      # Guía de despliegue en la nube
└── README.md
```

## 🚀 Inicio Rápido

1. **Configurar Notion** → Ver `docs/NOTION_SETUP.md`
2. **Desplegar Servidor** → Ver `docs/DEPLOY_GUIDE.md`  
3. **Instalar EA en MT4** → Copiar `client/TradeLogger.mq4` a `MQL4/Experts`
4. **Compilar y configurar** → Añadir el EA a un gráfico

## ⚙️ Configuración del EA

| Input | Descripción | Ejemplo |
|-------|-------------|---------|
| `Identificador_Cuenta` | Nombre único de la cuenta | `FTMO_01` |
| `URL_Servidor_Base` | URL del servidor (sin endpoint) | `https://mi-app.onrender.com` |
| `Sincronizar_Historial` | Enviar historial faltante al iniciar | `true` |
| `Dias_Historial` | Límite de días a sincronizar (0=todo) | `30` |

## 📊 Endpoints del Servidor

| Endpoint | Método | Descripción |
|----------|--------|-------------|
| `/` | GET | Estado del servidor |
| `/trade` | POST | Registrar un trade |
| `/tickets/{cuenta}` | GET | Obtener tickets existentes |
| `/drawdown` | POST | Registrar métricas de drawdown |

## 📝 Licencia

Uso libre para trading personal.
