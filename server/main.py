"""
=============================================================================
                    MT4 TRADE LOGGER - SERVIDOR CENTRAL
=============================================================================

Servidor FastAPI que recibe operaciones de trading desde múltiples
instancias de MetaTrader 4 y las guarda en una base de datos de Notion.

CARACTERÍSTICAS:
- Registro de trades en tiempo real
- Sincronización de historial (detecta duplicados)
- Tracking de drawdown por estrategia y cuenta
- Almacenamiento de métricas de drawdown en Notion

Diseñado para ser desplegado en servicios como:
- Render (render.com)
- Railway (railway.app)
- PythonAnywhere (pythonanywhere.com)

Autor: Trade Logger System
Versión: 2.0.0
=============================================================================
"""

import os
import logging
from datetime import datetime
from typing import Optional

import httpx
from fastapi import FastAPI
from fastapi import HTTPException
from fastapi import Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from pydantic import Field


# =============================================================================
#                           CONFIGURACIÓN DE LOGGING
# =============================================================================

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)

logger = logging.getLogger(__name__)


# =============================================================================
#                           VARIABLES DE ENTORNO
# =============================================================================

NOTION_API_KEY = os.environ.get("NOTION_API_KEY", "")
NOTION_DATABASE_ID = os.environ.get("NOTION_DATABASE_ID", "")

# Base de datos para relaciones bidireccionales
NOTION_CUENTAS_DB_ID = os.environ.get("NOTION_CUENTAS_DB_ID", "")
NOTION_ESTRATEGIAS_DB_ID = os.environ.get("NOTION_ESTRATEGIAS_DB_ID", "")

# Base de datos opcional para drawdown
NOTION_DRAWDOWN_DB_ID = os.environ.get("NOTION_DRAWDOWN_DB_ID", "")

# Validar configuración al inicio
if not NOTION_API_KEY:
    logger.warning("⚠️  NOTION_API_KEY no está configurada.")

if not NOTION_DATABASE_ID:
    logger.warning("⚠️  NOTION_DATABASE_ID no está configurada.")

# Cache para IDs de páginas de relaciones (evita búsquedas repetidas)
_cache_cuentas: dict[str, str] = {}
_cache_estrategias: dict[int, str] = {}


# =============================================================================
#                           CONFIGURACIÓN DE NOTION
# =============================================================================

NOTION_API_URL = "https://api.notion.com/v1/pages"
NOTION_QUERY_URL = "https://api.notion.com/v1/databases"
NOTION_VERSION = "2022-06-28"


# =============================================================================
#                           MODELOS DE DATOS
# =============================================================================

class TradeData(BaseModel):
    """
    Modelo para los datos de una operación de trading recibida desde MT4.
    """
    
    identificador_cuenta: str = Field(
        ...,
        description="Identificador único de la cuenta/terminal (ej: FTMO_01)"
    )
    
    ticket: int = Field(
        ...,
        description="Número de ticket de la orden"
    )
    
    magic_number: int = Field(
        default=0,
        description="Magic Number del EA que abrió la orden"
    )
    
    simbolo: str = Field(
        ...,
        description="Par de divisas o instrumento (ej: EURUSD)"
    )
    
    direccion: str = Field(
        ...,
        description="Dirección de la operación (BUY o SELL)"
    )
    
    lotes: float = Field(
        ...,
        description="Tamaño del lote operado"
    )
    
    pnl: float = Field(
        ...,
        description="Profit/Loss total de la operación"
    )
    
    resultado: str = Field(
        ...,
        description="Resultado de la operación (WIN o LOSS)"
    )
    
    balance: float = Field(
        ...,
        description="Balance de la cuenta después del cierre"
    )
    
    fecha_apertura: Optional[str] = Field(
        default=None,
        description="Fecha y hora de apertura (ISO 8601)"
    )
    
    fecha_cierre: str = Field(
        ...,
        description="Fecha y hora de cierre (ISO 8601)"
    )
    
    comentario: Optional[str] = Field(
        default="",
        description="Comentario de la orden"
    )


class DrawdownData(BaseModel):
    """
    Modelo para los datos de drawdown recibidos desde MT4.
    """
    
    identificador_cuenta: str = Field(
        ...,
        description="Identificador único de la cuenta/terminal"
    )
    
    magic_number: int = Field(
        default=0,
        description="Magic Number de la estrategia"
    )
    
    balance: float = Field(
        ...,
        description="Balance actual de la cuenta"
    )
    
    equity: float = Field(
        ...,
        description="Equity actual de la cuenta"
    )
    
    peak_balance: float = Field(
        ...,
        description="Balance máximo histórico de la cuenta"
    )
    
    drawdown_cuenta: float = Field(
        ...,
        description="Drawdown monetario actual de la cuenta"
    )
    
    drawdown_cuenta_pct: float = Field(
        ...,
        description="Drawdown porcentual de la cuenta"
    )
    
    drawdown_estrategia: float = Field(
        ...,
        description="Drawdown monetario actual de la estrategia"
    )
    
    max_drawdown_estrategia: float = Field(
        ...,
        description="Máximo drawdown histórico de la estrategia"
    )
    
    peak_estrategia: float = Field(
        ...,
        description="Peak equity de la estrategia"
    )
    
    timestamp: str = Field(
        ...,
        description="Fecha y hora de la medición"
    )


# =============================================================================
#                           APLICACIÓN FASTAPI
# =============================================================================

app = FastAPI(
    title="MT4 Trade Logger",
    description="Servidor central para registrar operaciones de trading en Notion",
    version="2.0.0"
)

# Configurar CORS para permitir peticiones desde cualquier origen
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# =============================================================================
#                           FUNCIONES AUXILIARES
# =============================================================================

def formatear_fecha_notion(fecha_str: str) -> str:
    """
    Convierte una fecha de MT4 al formato esperado por Notion.
    
    Args:
        fecha_str: Fecha en formato "YYYY.MM.DDTHH:MM:SS" o similar
        
    Returns:
        Fecha en formato ISO 8601 para Notion
    """
    
    if not fecha_str:
        return datetime.now().isoformat()
    
    # Intentar parsear diferentes formatos
    formatos_posibles = [
        "%Y.%m.%dT%H:%M:%S",    # Formato MT4
        "%Y-%m-%dT%H:%M:%S",    # ISO estándar
        "%Y.%m.%d %H:%M:%S",    # Alternativo
        "%Y-%m-%d %H:%M:%S",    # Alternativo
    ]
    
    for formato in formatos_posibles:
        try:
            fecha_parseada = datetime.strptime(fecha_str, formato)
            return fecha_parseada.isoformat()
        except ValueError:
            continue
    
    # Si no se pudo parsear, devolver la fecha actual
    logger.warning(f"No se pudo parsear la fecha: {fecha_str}")
    return datetime.now().isoformat()


def get_notion_headers() -> dict:
    """
    Retorna los headers necesarios para las peticiones a Notion.
    """
    return {
        "Authorization": f"Bearer {NOTION_API_KEY}",
        "Content-Type": "application/json",
        "Notion-Version": NOTION_VERSION
    }


async def verificar_ticket_existe(ticket: int, identificador_cuenta: str) -> bool:
    """
    Verifica si un ticket ya existe en la base de datos de Notion.
    
    Args:
        ticket: Número de ticket a verificar
        identificador_cuenta: Identificador de la cuenta
        
    Returns:
        True si el ticket ya existe, False en caso contrario
    """
    
    if not NOTION_API_KEY or not NOTION_DATABASE_ID:
        return False
    
    query_url = f"{NOTION_QUERY_URL}/{NOTION_DATABASE_ID}/query"
    
    # Filtrar por ticket (ahora usamos rich_text ya que Title es Símbolo)
    payload = {
        "filter": {
            "property": "Ticket",
            "number": {
                "equals": ticket
            }
        },
        "page_size": 1
    }
    
    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(
                query_url,
                headers=get_notion_headers(),
                json=payload,
                timeout=30.0
            )
            
            if response.status_code == 200:
                data = response.json()
                return len(data.get("results", [])) > 0
            else:
                logger.warning(f"Error verificando ticket: {response.status_code}")
                return False
                
        except httpx.RequestError as e:
            logger.error(f"Error de conexión verificando ticket: {str(e)}")
            return False


async def buscar_o_crear_cuenta(nombre_cuenta: str) -> str:
    """
    Busca una cuenta en la base de datos de Cuentas y devuelve su page_id.
    Si no existe, la crea automáticamente.
    """
    
    # Verificar cache primero
    if nombre_cuenta in _cache_cuentas:
        return _cache_cuentas[nombre_cuenta]
    
    if not NOTION_CUENTAS_DB_ID:
        logger.warning("NOTION_CUENTAS_DB_ID no configurado, no se puede crear relación.")
        return ""
    
    query_url = f"{NOTION_QUERY_URL}/{NOTION_CUENTAS_DB_ID}/query"
    
    payload = {
        "filter": {
            "property": "Nombre",
            "title": {
                "equals": nombre_cuenta
            }
        },
        "page_size": 1
    }
    
    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(
                query_url,
                headers=get_notion_headers(),
                json=payload,
                timeout=30.0
            )
            
            if response.status_code == 200:
                data = response.json()
                results = data.get("results", [])
                
                if results:
                    page_id = results[0]["id"]
                    _cache_cuentas[nombre_cuenta] = page_id
                    return page_id
                else:
                    # No existe, crear nueva
                    return await crear_cuenta(nombre_cuenta)
            else:
                logger.error(f"Error buscando cuenta: {response.status_code}")
                return ""
                
        except httpx.RequestError as e:
            logger.error(f"Error de conexión buscando cuenta: {str(e)}")
            return ""


async def crear_cuenta(nombre_cuenta: str) -> str:
    """Crea una nueva cuenta en la base de datos de Cuentas."""
    
    payload = {
        "parent": {
            "database_id": NOTION_CUENTAS_DB_ID
        },
        "properties": {
            "Nombre": {
                "title": [
                    {
                        "text": {
                            "content": nombre_cuenta
                        }
                    }
                ]
            }
        }
    }
    
    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(
                NOTION_API_URL,
                headers=get_notion_headers(),
                json=payload,
                timeout=30.0
            )
            
            if response.status_code == 200:
                page_id = response.json().get("id", "")
                _cache_cuentas[nombre_cuenta] = page_id
                logger.info(f"✓ Cuenta '{nombre_cuenta}' creada en Notion")
                return page_id
            else:
                logger.error(f"Error creando cuenta: {response.status_code}")
                return ""
                
        except httpx.RequestError as e:
            logger.error(f"Error de conexión creando cuenta: {str(e)}")
            return ""


async def buscar_o_crear_estrategia(magic_number: int) -> str:
    """
    Busca una estrategia en la base de datos de Estrategias y devuelve su page_id.
    Si no existe, la crea automáticamente.
    """
    
    if magic_number in _cache_estrategias:
        return _cache_estrategias[magic_number]
    
    if not NOTION_ESTRATEGIAS_DB_ID:
        logger.warning("NOTION_ESTRATEGIAS_DB_ID no configurado, no se puede crear relación.")
        return ""
    
    query_url = f"{NOTION_QUERY_URL}/{NOTION_ESTRATEGIAS_DB_ID}/query"
    
    payload = {
        "filter": {
            "property": "Magic Number",
            "number": {
                "equals": magic_number
            }
        },
        "page_size": 1
    }
    
    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(
                query_url,
                headers=get_notion_headers(),
                json=payload,
                timeout=30.0
            )
            
            if response.status_code == 200:
                data = response.json()
                results = data.get("results", [])
                
                if results:
                    page_id = results[0]["id"]
                    _cache_estrategias[magic_number] = page_id
                    return page_id
                else:
                    return await crear_estrategia(magic_number)
            else:
                logger.error(f"Error buscando estrategia: {response.status_code}")
                return ""
                
        except httpx.RequestError as e:
            logger.error(f"Error de conexión buscando estrategia: {str(e)}")
            return ""


async def crear_estrategia(magic_number: int) -> str:
    """Crea una nueva estrategia en la base de datos de Estrategias."""
    
    nombre = f"Estrategia {magic_number}" if magic_number != 0 else "Manual (0)"
    
    payload = {
        "parent": {
            "database_id": NOTION_ESTRATEGIAS_DB_ID
        },
        "properties": {
            "Nombre": {
                "title": [
                    {
                        "text": {
                            "content": nombre
                        }
                    }
                ]
            },
            "Magic Number": {
                "number": magic_number
            }
        }
    }
    
    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(
                NOTION_API_URL,
                headers=get_notion_headers(),
                json=payload,
                timeout=30.0
            )
            
            if response.status_code == 200:
                page_id = response.json().get("id", "")
                _cache_estrategias[magic_number] = page_id
                logger.info(f"✓ Estrategia '{nombre}' (Magic: {magic_number}) creada en Notion")
                return page_id
            else:
                logger.error(f"Error creando estrategia: {response.status_code}")
                return ""
                
        except httpx.RequestError as e:
            logger.error(f"Error de conexión creando estrategia: {str(e)}")
            return ""


async def obtener_tickets_cuenta(identificador_cuenta: str) -> list[int]:
    """
    Obtiene todos los tickets existentes para una cuenta específica.
    
    Args:
        identificador_cuenta: Identificador de la cuenta
        
    Returns:
        Lista de tickets existentes
    """
    
    if not NOTION_API_KEY or not NOTION_DATABASE_ID:
        return []
    
    query_url = f"{NOTION_QUERY_URL}/{NOTION_DATABASE_ID}/query"
    
    tickets = []
    has_more = True
    start_cursor = None
    
    while has_more:
        payload = {
            "filter": {
                "property": "Cuenta",
                "select": {
                    "equals": identificador_cuenta
                }
            },
            "page_size": 100
        }
        
        if start_cursor:
            payload["start_cursor"] = start_cursor
        
        async with httpx.AsyncClient() as client:
            try:
                response = await client.post(
                    query_url,
                    headers=get_notion_headers(),
                    json=payload,
                    timeout=60.0
                )
                
                if response.status_code == 200:
                    data = response.json()
                    
                    # Extraer tickets de los resultados
                    for page in data.get("results", []):
                        props = page.get("properties", {})
                        ticket_prop = props.get("Ticket", {})
                        title_list = ticket_prop.get("title", [])
                        
                        if title_list:
                            ticket_str = title_list[0].get("text", {}).get("content", "")
                            if ticket_str.isdigit():
                                tickets.append(int(ticket_str))
                    
                    has_more = data.get("has_more", False)
                    start_cursor = data.get("next_cursor")
                else:
                    logger.error(f"Error obteniendo tickets: {response.status_code}")
                    has_more = False
                    
            except httpx.RequestError as e:
                logger.error(f"Error de conexión obteniendo tickets: {str(e)}")
                has_more = False
    
    return tickets


async def enviar_a_notion(trade: TradeData, verificar_duplicado: bool = True) -> dict:
    """
    Envía los datos de una operación a la API de Notion.
    
    Args:
        trade: Datos de la operación de trading
        verificar_duplicado: Si True, verifica que el ticket no exista antes de crear
        
    Returns:
        Respuesta de la API de Notion
        
    Raises:
        HTTPException: Si hay error en la comunicación con Notion
    """
    
    # Verificar configuración
    if not NOTION_API_KEY or not NOTION_DATABASE_ID:
        raise HTTPException(
            status_code=500,
            detail="Notion API Key o Database ID no configurados en el servidor."
        )
    
    # Verificar si ya existe (para evitar duplicados en sincronización)
    if verificar_duplicado:
        existe = await verificar_ticket_existe(trade.ticket, trade.identificador_cuenta)
        if existe:
            logger.info(f"Trade {trade.ticket} ya existe en Notion, omitiendo.")
            return {
                "id": "duplicate",
                "status": "skipped",
                "message": "El ticket ya existe en la base de datos"
            }
    
    # Formatear fechas
    fecha_cierre_iso = formatear_fecha_notion(trade.fecha_cierre)
    fecha_apertura_iso = formatear_fecha_notion(trade.fecha_apertura) if trade.fecha_apertura else None
    
    # Buscar o crear las páginas de relación
    cuenta_page_id = await buscar_o_crear_cuenta(trade.identificador_cuenta)
    estrategia_page_id = await buscar_o_crear_estrategia(trade.magic_number)
    
    # Construir el payload para Notion
    payload = {
        "parent": {
            "database_id": NOTION_DATABASE_ID
        },
        "properties": {
            # Título de la página: Símbolo (par de divisas)
            "Símbolo": {
                "title": [
                    {
                        "text": {
                            "content": trade.simbolo
                        }
                    }
                ]
            },
            
            # Ticket como número (para búsquedas)
            "Ticket": {
                "number": trade.ticket
            },
            
            # Dirección (BUY/SELL)
            "Dirección": {
                "select": {
                    "name": trade.direccion
                }
            },
            
            # Lotes
            "Lotes": {
                "number": trade.lotes
            },
            
            # PnL
            "PnL": {
                "number": trade.pnl
            },
            
            # Resultado (WIN/LOSS)
            "Resultado": {
                "select": {
                    "name": trade.resultado
                }
            },
            
            # Balance
            "Balance": {
                "number": trade.balance
            },
            
            # Fecha de cierre
            "Fecha Cierre": {
                "date": {
                    "start": fecha_cierre_iso
                }
            },
            
            # Comentario
            "Comentario": {
                "rich_text": [
                    {
                        "text": {
                            "content": trade.comentario or ""
                        }
                    }
                ]
            }
        }
    }
    
    # Añadir relación bidireccional con Cuenta (si está configurada)
    if cuenta_page_id:
        payload["properties"]["Cuenta"] = {
            "relation": [
                {
                    "id": cuenta_page_id
                }
            ]
        }
    
    # Añadir relación bidireccional con Estrategia (si está configurada)
    if estrategia_page_id:
        payload["properties"]["Estrategia"] = {
            "relation": [
                {
                    "id": estrategia_page_id
                }
            ]
        }
    
    # Añadir fecha de apertura si existe
    if fecha_apertura_iso:
        payload["properties"]["Fecha Apertura"] = {
            "date": {
                "start": fecha_apertura_iso
            }
        }
    
    logger.info(f"Enviando trade a Notion: Ticket={trade.ticket}, Cuenta={trade.identificador_cuenta}")
    
    # Realizar la petición a Notion
    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(
                NOTION_API_URL,
                headers=get_notion_headers(),
                json=payload,
                timeout=30.0
            )
            
            # Verificar respuesta
            if response.status_code == 200:
                logger.info(f"✓ Trade {trade.ticket} registrado correctamente en Notion")
                return response.json()
            else:
                error_detail = response.json()
                logger.error(f"Error de Notion: {response.status_code} - {error_detail}")
                raise HTTPException(
                    status_code=response.status_code,
                    detail=f"Error de Notion: {error_detail.get('message', 'Error desconocido')}"
                )
                
        except httpx.RequestError as e:
            logger.error(f"Error de conexión con Notion: {str(e)}")
            raise HTTPException(
                status_code=503,
                detail=f"Error de conexión con Notion: {str(e)}"
            )


async def guardar_drawdown_notion(drawdown: DrawdownData) -> dict:
    """
    Guarda los datos de drawdown en Notion.
    
    Si NOTION_DRAWDOWN_DB_ID está configurado, usa esa base de datos.
    De lo contrario, no guarda (solo loguea).
    
    Args:
        drawdown: Datos de drawdown
        
    Returns:
        Respuesta de la API de Notion
    """
    
    db_id = NOTION_DRAWDOWN_DB_ID or NOTION_DATABASE_ID
    
    if not NOTION_API_KEY or not db_id:
        logger.info(f"Drawdown recibido pero no hay DB configurada para guardarlo: "
                   f"Cuenta={drawdown.identificador_cuenta}, DD Cuenta={drawdown.drawdown_cuenta}")
        return {"status": "logged_only", "message": "No hay base de datos de drawdown configurada"}
    
    # Si no hay base de datos de drawdown específica, solo logueamos
    if not NOTION_DRAWDOWN_DB_ID:
        logger.info(f"📊 Drawdown - Cuenta: {drawdown.identificador_cuenta}, "
                   f"Magic: {drawdown.magic_number}, "
                   f"DD Cuenta: ${drawdown.drawdown_cuenta:.2f} ({drawdown.drawdown_cuenta_pct:.2f}%), "
                   f"DD Estrategia: ${drawdown.drawdown_estrategia:.2f}")
        return {"status": "logged", "message": "Drawdown registrado en logs"}
    
    # Si hay base de datos de drawdown, guardar
    fecha_iso = formatear_fecha_notion(drawdown.timestamp)
    
    payload = {
        "parent": {
            "database_id": NOTION_DRAWDOWN_DB_ID
        },
        "properties": {
            "Timestamp": {
                "title": [
                    {
                        "text": {
                            "content": fecha_iso
                        }
                    }
                ]
            },
            "Cuenta": {
                "select": {
                    "name": drawdown.identificador_cuenta
                }
            },
            "Magic Number": {
                "number": drawdown.magic_number
            },
            "Balance": {
                "number": drawdown.balance
            },
            "Equity": {
                "number": drawdown.equity
            },
            "Peak Balance": {
                "number": drawdown.peak_balance
            },
            "DD Cuenta ($)": {
                "number": drawdown.drawdown_cuenta
            },
            "DD Cuenta (%)": {
                "number": drawdown.drawdown_cuenta_pct
            },
            "DD Estrategia ($)": {
                "number": drawdown.drawdown_estrategia
            },
            "Max DD Estrategia ($)": {
                "number": drawdown.max_drawdown_estrategia
            },
            "Peak Estrategia": {
                "number": drawdown.peak_estrategia
            }
        }
    }
    
    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(
                NOTION_API_URL,
                headers=get_notion_headers(),
                json=payload,
                timeout=30.0
            )
            
            if response.status_code == 200:
                logger.info(f"✓ Drawdown guardado: Cuenta={drawdown.identificador_cuenta}")
                return response.json()
            else:
                error_detail = response.json()
                logger.error(f"Error guardando drawdown: {response.status_code}")
                return {"status": "error", "detail": str(error_detail)}
                
        except httpx.RequestError as e:
            logger.error(f"Error de conexión guardando drawdown: {str(e)}")
            return {"status": "error", "detail": str(e)}


# =============================================================================
#                           ENDPOINTS
# =============================================================================

@app.get("/")
async def root():
    """
    Endpoint raíz para verificar que el servidor está activo.
    """
    
    return {
        "status": "online",
        "service": "MT4 Trade Logger",
        "version": "2.0.0",
        "notion_configured": bool(NOTION_API_KEY and NOTION_DATABASE_ID),
        "drawdown_db_configured": bool(NOTION_DRAWDOWN_DB_ID)
    }


@app.get("/health")
async def health_check():
    """
    Endpoint de health check para monitoreo.
    """
    
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat()
    }


@app.get("/tickets/{identificador_cuenta}")
async def obtener_tickets(identificador_cuenta: str):
    """
    Endpoint para obtener todos los tickets existentes de una cuenta.
    
    Usado por el EA para sincronización de historial.
    
    Args:
        identificador_cuenta: Identificador de la cuenta
        
    Returns:
        Lista de tickets existentes
    """
    
    logger.info(f"Solicitando tickets para cuenta: {identificador_cuenta}")
    
    tickets = await obtener_tickets_cuenta(identificador_cuenta)
    
    logger.info(f"Retornando {len(tickets)} tickets para {identificador_cuenta}")
    
    return {
        "cuenta": identificador_cuenta,
        "total": len(tickets),
        "tickets": tickets
    }


@app.post("/trade")
async def registrar_trade(trade: TradeData):
    """
    Endpoint principal para recibir y registrar operaciones de trading.
    
    Verifica automáticamente si el trade ya existe para evitar duplicados.
    
    Args:
        trade: Datos de la operación (ver modelo TradeData)
        
    Returns:
        Confirmación del registro
    """
    
    logger.info(f"Recibida operación: Cuenta={trade.identificador_cuenta}, "
                f"Ticket={trade.ticket}, Símbolo={trade.simbolo}, "
                f"PnL={trade.pnl}, Resultado={trade.resultado}")
    
    # Enviar a Notion (con verificación de duplicados)
    resultado_notion = await enviar_a_notion(trade, verificar_duplicado=True)
    
    # Verificar si fue omitido por duplicado
    if resultado_notion.get("status") == "skipped":
        return {
            "success": True,
            "message": f"Trade {trade.ticket} ya existe, omitido",
            "status": "skipped",
            "cuenta": trade.identificador_cuenta
        }
    
    return {
        "success": True,
        "message": f"Trade {trade.ticket} registrado correctamente",
        "notion_page_id": resultado_notion.get("id", ""),
        "cuenta": trade.identificador_cuenta
    }


@app.post("/trade/batch")
async def registrar_trades_batch(trades: list[TradeData]):
    """
    Endpoint para registrar múltiples operaciones a la vez.
    
    Útil para sincronización inicial o recuperación de histórico.
    Verifica duplicados automáticamente.
    
    Args:
        trades: Lista de operaciones a registrar
        
    Returns:
        Resumen del registro
    """
    
    resultados = []
    errores = []
    omitidos = []
    
    for trade in trades:
        try:
            resultado = await enviar_a_notion(trade, verificar_duplicado=True)
            
            if resultado.get("status") == "skipped":
                omitidos.append({
                    "ticket": trade.ticket,
                    "status": "skipped",
                    "message": "Ya existe"
                })
            else:
                resultados.append({
                    "ticket": trade.ticket,
                    "status": "success",
                    "page_id": resultado.get("id", "")
                })
                
        except HTTPException as e:
            errores.append({
                "ticket": trade.ticket,
                "status": "error",
                "detail": str(e.detail)
            })
    
    return {
        "total_recibidos": len(trades),
        "exitosos": len(resultados),
        "omitidos": len(omitidos),
        "fallidos": len(errores),
        "resultados": resultados,
        "omitidos_detalle": omitidos,
        "errores": errores
    }


@app.post("/drawdown")
async def registrar_drawdown(drawdown: DrawdownData):
    """
    Endpoint para recibir y registrar datos de drawdown.
    
    Recibe información de drawdown por cuenta y por estrategia.
    
    Args:
        drawdown: Datos de drawdown (ver modelo DrawdownData)
        
    Returns:
        Confirmación del registro
    """
    
    logger.info(f"📊 Drawdown recibido: Cuenta={drawdown.identificador_cuenta}, "
                f"Magic={drawdown.magic_number}, "
                f"DD Cuenta=${drawdown.drawdown_cuenta:.2f} ({drawdown.drawdown_cuenta_pct:.2f}%), "
                f"DD Estrategia=${drawdown.drawdown_estrategia:.2f}")
    
    # Guardar en Notion (si está configurado)
    resultado = await guardar_drawdown_notion(drawdown)
    
    return {
        "success": True,
        "message": "Drawdown registrado",
        "cuenta": drawdown.identificador_cuenta,
        "magic_number": drawdown.magic_number,
        "drawdown_cuenta": drawdown.drawdown_cuenta,
        "drawdown_estrategia": drawdown.drawdown_estrategia,
        "storage_status": resultado.get("status", "unknown")
    }


@app.post("/sync")
async def sincronizar_historial(trades: list[TradeData]):
    """
    Endpoint específico para sincronización de historial.
    
    Similar a /trade/batch pero optimizado para sincronización masiva.
    
    Args:
        trades: Lista de trades históricos
        
    Returns:
        Resumen de la sincronización
    """
    
    logger.info(f"Iniciando sincronización de {len(trades)} trades")
    
    # Usar el endpoint batch
    return await registrar_trades_batch(trades)


# =============================================================================
#                           MANEJO DE ERRORES
# =============================================================================

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """
    Manejador global de excepciones para logging.
    """
    
    logger.error(f"Error no manejado: {str(exc)}")
    
    return {
        "success": False,
        "error": str(exc),
        "path": request.url.path
    }


# =============================================================================
#                           PUNTO DE ENTRADA
# =============================================================================

if __name__ == "__main__":
    import uvicorn
    
    # Obtener puerto de la variable de entorno (para Render, Railway, etc.)
    port = int(os.environ.get("PORT", 8000))
    
    logger.info(f"Iniciando servidor en puerto {port}")
    
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=port,
        reload=False
    )
