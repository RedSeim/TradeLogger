//+------------------------------------------------------------------+
//|                                                  TradeLogger.mq5 |
//|                         Trade Logger para Notion - Hub Central   |
//|                                                                  |
//|  Este EA detecta el cierre de operaciones y envía los datos      |
//|  a un servidor centralizado en la nube mediante HTTP POST.       |
//|                                                                  |
//|  CARACTERÍSTICAS:                                                |
//|  - Detección de cierre de trades en tiempo real                  |
//|  - Sincronización del historial completo al iniciar              |
//|  - Tracking de drawdown por estrategia (Magic Number)            |
//|  - Tracking de drawdown por cuenta                               |
//|                                                                  |
//|  VERSIÓN: MetaTrader 5                                           |
//+------------------------------------------------------------------+
#property copyright "Trade Logger System"
#property link      ""
#property version   "2.00"
#property strict


//+------------------------------------------------------------------+
//|                     CONFIGURACIÓN DEL USUARIO                    |
//+------------------------------------------------------------------+

//--- Identificador único para esta cuenta/terminal
input string   Identificador_Cuenta = "FTMO_01";

//--- URL base del servidor en la nube (sin endpoint)
input string   URL_Servidor_Base = "https://mi-app.onrender.com";

//--- Tiempo de espera para la petición HTTP (en milisegundos)
input int      Timeout_HTTP = 5000;

//--- Habilitar sincronización del historial al iniciar
input bool     Sincronizar_Historial = true;

//--- Días de historial a sincronizar (0 = todo el disponible)
input int      Dias_Historial = 30;

//--- Habilitar logs detallados en el diario
input bool     Modo_Debug = true;

//--- MODO TEST: Enviar trades de prueba al iniciar (para diagnóstico)
input bool     Enviar_Trades_Test = false;

//--- Número de trades de prueba a enviar (por estrategia)
input int      Num_Trades_Test = 10;


//+------------------------------------------------------------------+
//|                     VARIABLES GLOBALES                           |
//+------------------------------------------------------------------+

//--- Almacena los tickets de las posiciones abiertas actualmente
ulong    g_posicionesAbiertas[];

//--- Contador para verificar cambios en las posiciones
int      g_ultimoConteoPosiciones = 0;

//--- Bandera para la inicialización correcta
bool     g_inicializadoCorrectamente = false;

//--- URLs de los endpoints
string   g_urlTrade;
string   g_urlSync;
string   g_urlDrawdown;
string   g_urlTickets;

//--- Tracking de peak balance para drawdown
double   g_peakBalance = 0;

//--- Estructura para almacenar drawdown por estrategia
struct DrawdownPorEstrategia
{
    long     magicNumber;
    double   peakEquity;
    double   currentDrawdown;
    double   maxDrawdown;
};

//--- Array de drawdowns por estrategia
DrawdownPorEstrategia g_estrategias[];
int g_numEstrategias = 0;

//--- Último deal procesado (para detectar nuevos cierres)
ulong g_ultimoDealTicket = 0;


//+------------------------------------------------------------------+
//|                     FUNCIÓN DE INICIALIZACIÓN                    |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Construir URLs de endpoints
    g_urlTrade = URL_Servidor_Base + "/trade";
    g_urlSync = URL_Servidor_Base + "/sync";
    g_urlDrawdown = URL_Servidor_Base + "/drawdown";
    g_urlTickets = URL_Servidor_Base + "/tickets/" + Identificador_Cuenta;
    
    //--- Mostrar información de configuración
    Print("==============================================");
    Print("TradeLogger EA v2.0 (MT5) Iniciado");
    Print("Identificador de Cuenta: ", Identificador_Cuenta);
    Print("URL Base del Servidor: ", URL_Servidor_Base);
    Print("Sincronizar Historial: ", Sincronizar_Historial);
    Print("Días de Historial: ", Dias_Historial);
    Print("==============================================");
    
    //--- Verificar que la URL no esté vacía
    if (StringLen(URL_Servidor_Base) == 0)
    {
        Print("ERROR: La URL del servidor está vacía.");
        return INIT_FAILED;
    }
    
    //--- Verificar que el identificador no esté vacío
    if (StringLen(Identificador_Cuenta) == 0)
    {
        Print("ERROR: El identificador de cuenta está vacío.");
        return INIT_FAILED;
    }
    
    //--- Inicializar peak balance
    g_peakBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    //--- Inicializar array de estrategias
    ArrayResize(g_estrategias, 0);
    g_numEstrategias = 0;
    
    //--- Capturar el estado inicial de las posiciones abiertas
    CapturarPosicionesAbiertas();
    
    //--- Inicializar drawdown de estrategias activas
    InicializarDrawdownEstrategias();
    
    //--- Obtener el último deal del historial
    ObtenerUltimoDeal();
    
    g_inicializadoCorrectamente = true;
    
    //--- Sincronizar historial si está habilitado
    if (Sincronizar_Historial)
    {
        Print("Iniciando sincronización del historial...");
        SincronizarHistorial();
    }
    
    //--- MODO TEST: Enviar trades de prueba si está habilitado
    if (Enviar_Trades_Test)
    {
        Print("=== MODO TEST ACTIVADO ===");
        Print("Enviando ", Num_Trades_Test, " trades de prueba por estrategia...");
        EnviarTradesDePrueba();
    }
    
    return INIT_SUCCEEDED;
}


//+------------------------------------------------------------------+
//|                     FUNCIÓN DE DESINICIALIZACIÓN                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("TradeLogger EA detenido. Razón: ", reason);
}


//+------------------------------------------------------------------+
//|                     FUNCIÓN PRINCIPAL (TICK)                     |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Verificar inicialización
    if (!g_inicializadoCorrectamente)
    {
        return;
    }
    
    //--- Actualizar peak balance si es necesario
    double balanceActual = AccountInfoDouble(ACCOUNT_BALANCE);
    if (balanceActual > g_peakBalance)
    {
        g_peakBalance = balanceActual;
    }
    
    //--- Verificar si hay nuevos deals cerrados
    VerificarNuevosDeals();
}


//+------------------------------------------------------------------+
//|                     EVENTO DE TRADE                              |
//+------------------------------------------------------------------+
void OnTradeTransaction(
    const MqlTradeTransaction& trans,
    const MqlTradeRequest& request,
    const MqlTradeResult& result
)
{
    //--- Este evento se dispara cuando hay cambios en las transacciones
    
    if (!g_inicializadoCorrectamente)
    {
        return;
    }
    
    //--- Solo nos interesan los deals (transacciones completadas)
    if (trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
        //--- Un nuevo deal ha sido añadido
        if (Modo_Debug)
        {
            Print("OnTradeTransaction: Nuevo deal detectado. Ticket: ", trans.deal);
        }
        
        //--- Verificar si es un cierre de posición
        ProcessarDeal(trans.deal);
    }
}


//+------------------------------------------------------------------+
//|              OBTENER EL ÚLTIMO DEAL DEL HISTORIAL                |
//+------------------------------------------------------------------+
void ObtenerUltimoDeal()
{
    //--- Seleccionar todo el historial
    datetime desde = 0;
    datetime hasta = TimeCurrent();
    
    if (!HistorySelect(desde, hasta))
    {
        g_ultimoDealTicket = 0;
        return;
    }
    
    int totalDeals = HistoryDealsTotal();
    
    if (totalDeals > 0)
    {
        g_ultimoDealTicket = HistoryDealGetTicket(totalDeals - 1);
    }
    else
    {
        g_ultimoDealTicket = 0;
    }
    
    if (Modo_Debug)
    {
        Print("Último deal inicial: ", g_ultimoDealTicket);
    }
}


//+------------------------------------------------------------------+
//|              VERIFICAR SI HAY NUEVOS DEALS                       |
//+------------------------------------------------------------------+
void VerificarNuevosDeals()
{
    //--- Seleccionar el historial reciente
    datetime desde = TimeCurrent() - 86400;  // Últimas 24 horas
    datetime hasta = TimeCurrent();
    
    if (!HistorySelect(desde, hasta))
    {
        return;
    }
    
    int totalDeals = HistoryDealsTotal();
    
    //--- Recorrer desde el final buscando deals nuevos
    for (int i = totalDeals - 1; i >= 0; i--)
    {
        ulong dealTicket = HistoryDealGetTicket(i);
        
        //--- Si llegamos al último deal procesado, parar
        if (dealTicket <= g_ultimoDealTicket)
        {
            break;
        }
        
        //--- Procesar este deal
        ProcessarDeal(dealTicket);
    }
    
    //--- Actualizar el último deal
    if (totalDeals > 0)
    {
        ulong nuevoUltimo = HistoryDealGetTicket(totalDeals - 1);
        if (nuevoUltimo > g_ultimoDealTicket)
        {
            g_ultimoDealTicket = nuevoUltimo;
        }
    }
}


//+------------------------------------------------------------------+
//|              PROCESAR UN DEAL                                    |
//+------------------------------------------------------------------+
void ProcessarDeal(ulong dealTicket)
{
    //--- Obtener propiedades del deal
    ENUM_DEAL_ENTRY entrada = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
    
    //--- Solo procesar cierres de posición (DEAL_ENTRY_OUT)
    if (entrada != DEAL_ENTRY_OUT && entrada != DEAL_ENTRY_INOUT)
    {
        return;
    }
    
    //--- Obtener datos del deal
    long     magicNumber   = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
    string   simbolo       = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
    long     tipoDeal      = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
    double   volumen       = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
    double   profit        = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
    double   swap          = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
    double   comision      = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
    datetime tiempo        = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
    long     posicionId    = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
    string   comentario    = HistoryDealGetString(dealTicket, DEAL_COMMENT);
    
    //--- Calcular PnL total
    double pnlTotal = profit + swap + comision;
    
    //--- Balance actual
    double balanceActual = AccountInfoDouble(ACCOUNT_BALANCE);
    
    //--- Determinar dirección (la dirección del cierre es opuesta a la posición)
    string direccion = "";
    if (tipoDeal == DEAL_TYPE_BUY)
    {
        direccion = "BUY";  // Era una posición SELL que se cerró con BUY
    }
    else if (tipoDeal == DEAL_TYPE_SELL)
    {
        direccion = "SELL";  // Era una posición BUY que se cerró con SELL
    }
    else
    {
        return;  // Otro tipo de deal, ignorar
    }
    
    //--- Para el cierre, invertir la dirección (queremos la dirección original de la posición)
    if (direccion == "BUY")
    {
        direccion = "SELL";
    }
    else
    {
        direccion = "BUY";
    }
    
    //--- Determinar resultado
    string resultado = (pnlTotal >= 0) ? "WIN" : "LOSS";
    
    //--- Formatear fechas
    string fechaCierreStr = FormatearFechaISO(tiempo);
    
    //--- Obtener fecha de apertura de la posición
    datetime fechaApertura = ObtenerFechaAperturaposicion(posicionId);
    string fechaAperturaStr = FormatearFechaISO(fechaApertura);
    
    if (Modo_Debug)
    {
        Print("=== DEAL CERRADO DETECTADO ===");
        Print("Deal Ticket: ", dealTicket);
        Print("Position ID: ", posicionId);
        Print("Magic Number: ", magicNumber);
        Print("Símbolo: ", simbolo);
        Print("Dirección: ", direccion);
        Print("Volumen: ", volumen);
        Print("PnL: ", DoubleToString(pnlTotal, 2));
        Print("Resultado: ", resultado);
        Print("==============================");
    }
    
    //--- Construir JSON
    string jsonPayload = ConstruirJSON(
        (int)posicionId,  // Usar position ID como ticket
        (int)magicNumber,
        simbolo,
        direccion,
        volumen,
        pnlTotal,
        resultado,
        balanceActual,
        fechaAperturaStr,
        fechaCierreStr,
        comentario
    );
    
    //--- Enviar al servidor
    EnviarAlServidorURL(g_urlTrade, jsonPayload);
    
    //--- Actualizar y enviar drawdown
    ActualizarDrawdownEstrategia((int)magicNumber, pnlTotal);
    EnviarDrawdown((int)magicNumber);
}


//+------------------------------------------------------------------+
//|              OBTENER FECHA DE APERTURA DE POSICIÓN               |
//+------------------------------------------------------------------+
datetime ObtenerFechaAperturaposicion(long posicionId)
{
    //--- Buscar el deal de entrada de esta posición
    datetime desde = 0;
    datetime hasta = TimeCurrent();
    
    if (!HistorySelect(desde, hasta))
    {
        return TimeCurrent();
    }
    
    int totalDeals = HistoryDealsTotal();
    
    for (int i = 0; i < totalDeals; i++)
    {
        ulong dealTicket = HistoryDealGetTicket(i);
        
        if (HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) == posicionId)
        {
            ENUM_DEAL_ENTRY entrada = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
            
            if (entrada == DEAL_ENTRY_IN)
            {
                return (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
            }
        }
    }
    
    return TimeCurrent();
}


//+------------------------------------------------------------------+
//|              INICIALIZAR DRAWDOWN DE ESTRATEGIAS ACTIVAS         |
//+------------------------------------------------------------------+
void InicializarDrawdownEstrategias()
{
    //--- Obtener todas las estrategias únicas de posiciones abiertas
    int totalPosiciones = PositionsTotal();
    
    for (int i = 0; i < totalPosiciones; i++)
    {
        ulong ticket = PositionGetTicket(i);
        
        if (ticket > 0)
        {
            long magic = PositionGetInteger(POSITION_MAGIC);
            
            //--- Verificar si ya existe esta estrategia
            int idx = BuscarEstrategia((int)magic);
            
            if (idx == -1)
            {
                //--- Añadir nueva estrategia
                AgregarEstrategia((int)magic);
            }
        }
    }
    
    if (Modo_Debug)
    {
        Print("Estrategias inicializadas: ", g_numEstrategias);
    }
}


//+------------------------------------------------------------------+
//|              BUSCAR ÍNDICE DE UNA ESTRATEGIA                     |
//+------------------------------------------------------------------+
int BuscarEstrategia(int magicNumber)
{
    for (int i = 0; i < g_numEstrategias; i++)
    {
        if (g_estrategias[i].magicNumber == magicNumber)
        {
            return i;
        }
    }
    return -1;
}


//+------------------------------------------------------------------+
//|              AGREGAR UNA NUEVA ESTRATEGIA                        |
//+------------------------------------------------------------------+
void AgregarEstrategia(int magicNumber)
{
    g_numEstrategias++;
    ArrayResize(g_estrategias, g_numEstrategias);
    
    g_estrategias[g_numEstrategias - 1].magicNumber = magicNumber;
    g_estrategias[g_numEstrategias - 1].peakEquity = CalcularEquityEstrategia(magicNumber);
    g_estrategias[g_numEstrategias - 1].currentDrawdown = 0;
    g_estrategias[g_numEstrategias - 1].maxDrawdown = 0;
    
    if (Modo_Debug)
    {
        Print("Nueva estrategia registrada: Magic=", magicNumber, 
              " PeakEquity=", g_estrategias[g_numEstrategias - 1].peakEquity);
    }
}


//+------------------------------------------------------------------+
//|              CALCULAR EQUITY DE UNA ESTRATEGIA                   |
//+------------------------------------------------------------------+
double CalcularEquityEstrategia(int magicNumber)
{
    double equity = 0;
    
    //--- Seleccionar historial
    datetime desde = 0;
    datetime hasta = TimeCurrent();
    
    if (!HistorySelect(desde, hasta))
    {
        return 0;
    }
    
    int totalDeals = HistoryDealsTotal();
    
    //--- Sumar PnL de todos los deals cerrados de esta estrategia
    for (int i = 0; i < totalDeals; i++)
    {
        ulong dealTicket = HistoryDealGetTicket(i);
        
        if (HistoryDealGetInteger(dealTicket, DEAL_MAGIC) == magicNumber)
        {
            ENUM_DEAL_ENTRY entrada = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
            
            if (entrada == DEAL_ENTRY_OUT || entrada == DEAL_ENTRY_INOUT)
            {
                equity += HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                equity += HistoryDealGetDouble(dealTicket, DEAL_SWAP);
                equity += HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
            }
        }
    }
    
    return equity;
}


//+------------------------------------------------------------------+
//|              ACTUALIZAR DRAWDOWN DE UNA ESTRATEGIA               |
//+------------------------------------------------------------------+
void ActualizarDrawdownEstrategia(int magicNumber, double pnlTrade)
{
    int idx = BuscarEstrategia(magicNumber);
    
    if (idx == -1)
    {
        //--- Nueva estrategia, agregarla
        AgregarEstrategia(magicNumber);
        idx = g_numEstrategias - 1;
    }
    
    //--- Calcular nuevo equity de la estrategia
    double nuevoEquity = CalcularEquityEstrategia(magicNumber);
    
    //--- Actualizar peak si es mayor
    if (nuevoEquity > g_estrategias[idx].peakEquity)
    {
        g_estrategias[idx].peakEquity = nuevoEquity;
        g_estrategias[idx].currentDrawdown = 0;
    }
    else
    {
        //--- Calcular drawdown actual
        g_estrategias[idx].currentDrawdown = g_estrategias[idx].peakEquity - nuevoEquity;
        
        //--- Actualizar max drawdown si es mayor
        if (g_estrategias[idx].currentDrawdown > g_estrategias[idx].maxDrawdown)
        {
            g_estrategias[idx].maxDrawdown = g_estrategias[idx].currentDrawdown;
        }
    }
    
    if (Modo_Debug)
    {
        Print("Drawdown Estrategia ", magicNumber, 
              ": Actual=", DoubleToString(g_estrategias[idx].currentDrawdown, 2),
              " Max=", DoubleToString(g_estrategias[idx].maxDrawdown, 2),
              " Peak=", DoubleToString(g_estrategias[idx].peakEquity, 2));
    }
}


//+------------------------------------------------------------------+
//|              CALCULAR DRAWDOWN DE LA CUENTA                      |
//+------------------------------------------------------------------+
double CalcularDrawdownCuenta()
{
    double balanceActual = AccountInfoDouble(ACCOUNT_BALANCE);
    
    //--- Actualizar peak si es mayor
    if (balanceActual > g_peakBalance)
    {
        g_peakBalance = balanceActual;
    }
    
    //--- Calcular drawdown monetario
    double drawdown = g_peakBalance - balanceActual;
    
    return drawdown;
}


//+------------------------------------------------------------------+
//|              ENVIAR INFORMACIÓN DE DRAWDOWN                      |
//+------------------------------------------------------------------+
void EnviarDrawdown(int magicNumber)
{
    //--- Obtener drawdown de la cuenta
    double drawdownCuenta = CalcularDrawdownCuenta();
    
    //--- Obtener drawdown de la estrategia
    int idx = BuscarEstrategia(magicNumber);
    double drawdownEstrategia = 0;
    double maxDrawdownEstrategia = 0;
    double peakEstrategia = 0;
    
    if (idx != -1)
    {
        drawdownEstrategia = g_estrategias[idx].currentDrawdown;
        maxDrawdownEstrategia = g_estrategias[idx].maxDrawdown;
        peakEstrategia = g_estrategias[idx].peakEquity;
    }
    
    //--- Construir JSON
    string json = "{";
    json += "\"identificador_cuenta\":\"" + Identificador_Cuenta + "\",";
    json += "\"magic_number\":" + IntegerToString(magicNumber) + ",";
    json += "\"balance\":" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + ",";
    json += "\"equity\":" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + ",";
    json += "\"peak_balance\":" + DoubleToString(g_peakBalance, 2) + ",";
    json += "\"drawdown_cuenta\":" + DoubleToString(drawdownCuenta, 2) + ",";
    json += "\"drawdown_cuenta_pct\":" + DoubleToString((g_peakBalance > 0 ? (drawdownCuenta / g_peakBalance) * 100 : 0), 2) + ",";
    json += "\"drawdown_estrategia\":" + DoubleToString(drawdownEstrategia, 2) + ",";
    json += "\"max_drawdown_estrategia\":" + DoubleToString(maxDrawdownEstrategia, 2) + ",";
    json += "\"peak_estrategia\":" + DoubleToString(peakEstrategia, 2) + ",";
    json += "\"timestamp\":\"" + FormatearFechaISO(TimeCurrent()) + "\"";
    json += "}";
    
    //--- Enviar al servidor
    EnviarAlServidorURL(g_urlDrawdown, json);
}


//+------------------------------------------------------------------+
//|              CAPTURAR POSICIONES ACTUALMENTE ABIERTAS            |
//+------------------------------------------------------------------+
void CapturarPosicionesAbiertas()
{
    //--- Limpiar el array
    ArrayResize(g_posicionesAbiertas, 0);
    
    int totalPosiciones = PositionsTotal();
    
    for (int i = 0; i < totalPosiciones; i++)
    {
        ulong ticket = PositionGetTicket(i);
        
        if (ticket > 0)
        {
            int nuevoTamanio = ArraySize(g_posicionesAbiertas) + 1;
            ArrayResize(g_posicionesAbiertas, nuevoTamanio);
            g_posicionesAbiertas[nuevoTamanio - 1] = ticket;
        }
    }
    
    g_ultimoConteoPosiciones = ArraySize(g_posicionesAbiertas);
    
    if (Modo_Debug)
    {
        Print("Posiciones abiertas capturadas: ", g_ultimoConteoPosiciones);
    }
}


//+------------------------------------------------------------------+
//|              SINCRONIZAR HISTORIAL CON EL SERVIDOR               |
//+------------------------------------------------------------------+
void SincronizarHistorial()
{
    //--- Primero, obtener los tickets que ya existen en Notion
    int ticketsExistentes[];
    int numTicketsExistentes = ObtenerTicketsExistentes(ticketsExistentes);
    
    if (Modo_Debug)
    {
        Print("Tickets existentes en Notion: ", numTicketsExistentes);
    }
    
    //--- Calcular fecha límite
    datetime fechaLimite = 0;
    if (Dias_Historial > 0)
    {
        fechaLimite = TimeCurrent() - (Dias_Historial * 24 * 60 * 60);
    }
    
    //--- Seleccionar historial
    datetime desde = fechaLimite;
    datetime hasta = TimeCurrent();
    
    if (!HistorySelect(desde, hasta))
    {
        Print("ERROR: No se pudo seleccionar el historial.");
        return;
    }
    
    int totalDeals = HistoryDealsTotal();
    int tradesEnviados = 0;
    int tradesOmitidos = 0;
    
    Print("Analizando historial: ", totalDeals, " deals encontrados.");
    
    //--- Conjunto para evitar enviar el mismo position ID múltiples veces
    long posicionesEnviadas[];
    
    for (int i = 0; i < totalDeals; i++)
    {
        ulong dealTicket = HistoryDealGetTicket(i);
        
        //--- Solo procesar cierres
        ENUM_DEAL_ENTRY entrada = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
        
        if (entrada != DEAL_ENTRY_OUT && entrada != DEAL_ENTRY_INOUT)
        {
            continue;
        }
        
        //--- Obtener position ID
        long posicionId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
        
        //--- Verificar si ya enviamos esta posición
        bool yaEnviada = false;
        for (int j = 0; j < ArraySize(posicionesEnviadas); j++)
        {
            if (posicionesEnviadas[j] == posicionId)
            {
                yaEnviada = true;
                break;
            }
        }
        
        if (yaEnviada)
        {
            continue;
        }
        
        //--- Verificar si ya existe en Notion
        bool yaExiste = false;
        for (int k = 0; k < numTicketsExistentes; k++)
        {
            if (ticketsExistentes[k] == (int)posicionId)
            {
                yaExiste = true;
                break;
            }
        }
        
        if (yaExiste)
        {
            tradesOmitidos++;
            continue;
        }
        
        //--- Procesar y enviar este deal
        EnviarDealHistorico(dealTicket);
        tradesEnviados++;
        
        //--- Marcar como enviada
        int nuevoTamanio = ArraySize(posicionesEnviadas) + 1;
        ArrayResize(posicionesEnviadas, nuevoTamanio);
        posicionesEnviadas[nuevoTamanio - 1] = posicionId;
        
        //--- Pequeña pausa para no saturar el servidor
        Sleep(100);
    }
    
    Print("=== SINCRONIZACIÓN COMPLETADA ===");
    Print("Trades nuevos enviados: ", tradesEnviados);
    Print("Trades omitidos (ya existían): ", tradesOmitidos);
    Print("================================");
}


//+------------------------------------------------------------------+
//|              ENVIAR UN DEAL HISTÓRICO                            |
//+------------------------------------------------------------------+
void EnviarDealHistorico(ulong dealTicket)
{
    //--- Obtener datos del deal
    long     magicNumber   = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
    string   simbolo       = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
    long     tipoDeal      = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
    double   volumen       = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
    double   profit        = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
    double   swap          = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
    double   comision      = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
    datetime tiempo        = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
    long     posicionId    = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
    string   comentario    = HistoryDealGetString(dealTicket, DEAL_COMMENT);
    
    //--- Calcular PnL total
    double pnlTotal = profit + swap + comision;
    
    //--- Balance actual (aproximado para historial)
    double balanceActual = AccountInfoDouble(ACCOUNT_BALANCE);
    
    //--- Determinar dirección original de la posición
    string direccion = "";
    if (tipoDeal == DEAL_TYPE_BUY)
    {
        direccion = "SELL";  // Cierre con BUY = posición SELL
    }
    else if (tipoDeal == DEAL_TYPE_SELL)
    {
        direccion = "BUY";   // Cierre con SELL = posición BUY
    }
    else
    {
        return;
    }
    
    //--- Determinar resultado
    string resultado = (pnlTotal >= 0) ? "WIN" : "LOSS";
    
    //--- Formatear fechas
    string fechaCierreStr = FormatearFechaISO(tiempo);
    datetime fechaApertura = ObtenerFechaAperturaposicion(posicionId);
    string fechaAperturaStr = FormatearFechaISO(fechaApertura);
    
    //--- Construir JSON
    string jsonPayload = ConstruirJSON(
        (int)posicionId,
        (int)magicNumber,
        simbolo,
        direccion,
        volumen,
        pnlTotal,
        resultado,
        balanceActual,
        fechaAperturaStr,
        fechaCierreStr,
        comentario
    );
    
    //--- Enviar al servidor
    EnviarAlServidorURL(g_urlTrade, jsonPayload);
}


//+------------------------------------------------------------------+
//|              OBTENER TICKETS EXISTENTES DESDE EL SERVIDOR        |
//+------------------------------------------------------------------+
int ObtenerTicketsExistentes(int &tickets[])
{
    //--- Headers para la petición
    string headers = "Content-Type: application/json\r\n";
    
    char   postData[];
    char   resultado[];
    string resultadoHeaders;
    
    //--- Crear un array vacío para GET
    ArrayResize(postData, 0);
    
    if (Modo_Debug)
    {
        Print("Consultando tickets existentes: ", g_urlTickets);
    }
    
    //--- Realizar la petición HTTP GET
    int respuestaCode = WebRequest(
        "GET",
        g_urlTickets,
        headers,
        Timeout_HTTP,
        postData,
        resultado,
        resultadoHeaders
    );
    
    if (respuestaCode == -1)
    {
        int errorCode = GetLastError();
        Print("ERROR al obtener tickets existentes. Código: ", errorCode);
        ArrayResize(tickets, 0);
        return 0;
    }
    
    if (respuestaCode != 200)
    {
        Print("El servidor respondió con código ", respuestaCode);
        ArrayResize(tickets, 0);
        return 0;
    }
    
    //--- Parsear la respuesta JSON
    string respuestaTexto = CharArrayToString(resultado, 0, WHOLE_ARRAY, CP_UTF8);
    
    if (Modo_Debug)
    {
        Print("Respuesta de tickets: ", respuestaTexto);
    }
    
    //--- Parsear JSON simple
    int numTickets = ParsearArrayTickets(respuestaTexto, tickets);
    
    return numTickets;
}


//+------------------------------------------------------------------+
//|              PARSEAR ARRAY DE TICKETS DESDE JSON                 |
//+------------------------------------------------------------------+
int ParsearArrayTickets(string json, int &tickets[])
{
    //--- Buscar el array de tickets en el JSON
    int posInicio = StringFind(json, "[");
    int posFin = StringFind(json, "]");
    
    if (posInicio == -1 || posFin == -1 || posFin <= posInicio)
    {
        ArrayResize(tickets, 0);
        return 0;
    }
    
    //--- Extraer el contenido del array
    string contenido = StringSubstr(json, posInicio + 1, posFin - posInicio - 1);
    
    //--- Si está vacío, retornar 0
    contenido = StringTrimLeft(contenido);
    contenido = StringTrimRight(contenido);
    
    if (StringLen(contenido) == 0)
    {
        ArrayResize(tickets, 0);
        return 0;
    }
    
    //--- Contar comas para estimar tamaño
    int numComas = 0;
    for (int i = 0; i < StringLen(contenido); i++)
    {
        if (StringGetCharacter(contenido, i) == ',')
        {
            numComas++;
        }
    }
    
    //--- Reservar espacio
    int estimado = numComas + 1;
    ArrayResize(tickets, estimado);
    
    //--- Parsear cada número
    int numTickets = 0;
    string numero = "";
    
    for (int i = 0; i <= StringLen(contenido); i++)
    {
        ushort c = (i < StringLen(contenido)) ? StringGetCharacter(contenido, i) : ',';
        
        if (c == ',' || i == StringLen(contenido))
        {
            //--- Limpiar espacios
            numero = StringTrimLeft(numero);
            numero = StringTrimRight(numero);
            
            if (StringLen(numero) > 0)
            {
                tickets[numTickets] = (int)StringToInteger(numero);
                numTickets++;
            }
            numero = "";
        }
        else if (c >= '0' && c <= '9')
        {
            numero += CharToString((uchar)c);
        }
    }
    
    //--- Redimensionar al tamaño real
    ArrayResize(tickets, numTickets);
    
    return numTickets;
}


//+------------------------------------------------------------------+
//|              FORMATEAR FECHA EN FORMATO ISO 8601                 |
//+------------------------------------------------------------------+
string FormatearFechaISO(datetime fecha)
{
    return TimeToString(fecha, TIME_DATE) + "T" + TimeToString(fecha, TIME_SECONDS);
}


//+------------------------------------------------------------------+
//|              CONSTRUIR EL PAYLOAD JSON                           |
//+------------------------------------------------------------------+
string ConstruirJSON(
    int      ticket,
    int      magicNumber,
    string   simbolo,
    string   direccion,
    double   lotes,
    double   pnl,
    string   resultado,
    double   balance,
    string   fechaApertura,
    string   fechaCierre,
    string   comentario
)
{
    string json = "{";
    
    //--- Identificador de cuenta
    json += "\"identificador_cuenta\":\"" + Identificador_Cuenta + "\",";
    
    //--- Ticket
    json += "\"ticket\":" + IntegerToString(ticket) + ",";
    
    //--- Magic Number
    json += "\"magic_number\":" + IntegerToString(magicNumber) + ",";
    
    //--- Símbolo
    json += "\"simbolo\":\"" + simbolo + "\",";
    
    //--- Dirección
    json += "\"direccion\":\"" + direccion + "\",";
    
    //--- Lotes
    json += "\"lotes\":" + DoubleToString(lotes, 2) + ",";
    
    //--- PnL
    json += "\"pnl\":" + DoubleToString(pnl, 2) + ",";
    
    //--- Resultado
    json += "\"resultado\":\"" + resultado + "\",";
    
    //--- Balance
    json += "\"balance\":" + DoubleToString(balance, 2) + ",";
    
    //--- Fecha de apertura
    json += "\"fecha_apertura\":\"" + fechaApertura + "\",";
    
    //--- Fecha de cierre
    json += "\"fecha_cierre\":\"" + fechaCierre + "\",";
    
    //--- Comentario (escapar comillas)
    string comentarioEscapado = comentario;
    StringReplace(comentarioEscapado, "\"", "\\\"");
    json += "\"comentario\":\"" + comentarioEscapado + "\"";
    
    json += "}";
    
    return json;
}


//+------------------------------------------------------------------+
//|              ENVIAR DATOS AL SERVIDOR VÍA HTTP POST              |
//+------------------------------------------------------------------+
void EnviarAlServidorURL(string url, string jsonPayload)
{
    //--- Headers para la petición
    string headers = "Content-Type: application/json\r\n";
    
    //--- Convertir el JSON a array de bytes
    char   postData[];
    char   resultado[];
    string resultadoHeaders;
    
    StringToCharArray(jsonPayload, postData, 0, StringLen(jsonPayload), CP_UTF8);
    
    //--- Redimensionar para quitar el carácter nulo final
    ArrayResize(postData, StringLen(jsonPayload));
    
    if (Modo_Debug)
    {
        Print("Enviando JSON: ", jsonPayload);
        Print("URL: ", url);
    }
    
    //--- Realizar la petición HTTP POST
    int respuestaCode = WebRequest(
        "POST",
        url,
        headers,
        Timeout_HTTP,
        postData,
        resultado,
        resultadoHeaders
    );
    
    //--- Verificar el resultado
    if (respuestaCode == -1)
    {
        int errorCode = GetLastError();
        
        Print("ERROR en WebRequest. Código de error: ", errorCode);
        
        if (errorCode == 4014)
        {
            Print("SOLUCIÓN: Debes añadir la URL '", URL_Servidor_Base, 
                  "' a la lista de URLs permitidas en MT5.");
            Print("Ve a: Herramientas -> Opciones -> Expert Advisors -> ");
            Print("'Permitir WebRequest para las siguientes URLs' y añade tu URL.");
        }
        
        return;
    }
    
    //--- Procesar respuesta
    string respuestaTexto = CharArrayToString(resultado, 0, WHOLE_ARRAY, CP_UTF8);
    
    if (respuestaCode >= 200 && respuestaCode < 300)
    {
        Print("✓ Datos enviados correctamente. Código: ", respuestaCode);
        
        if (Modo_Debug)
        {
            Print("Respuesta del servidor: ", respuestaTexto);
        }
    }
    else
    {
        Print("ERROR: El servidor respondió con código ", respuestaCode);
        Print("Respuesta: ", respuestaTexto);
    }
}
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//|              ENVIAR TRADES DE PRUEBA (DIAGNÓSTICO)               |
//+------------------------------------------------------------------+
void EnviarTradesDePrueba()
{
    //--- Magic numbers de las 3 estrategias de prueba
    int magicNumbers[3] = {1111, 1112, 1113};
    
    //--- Símbolos de prueba
    string simbolos[5] = {"EURUSD", "GBPUSD", "USDJPY", "XAUUSD", "BTCUSD"};
    
    //--- Direcciones
    string direcciones[2] = {"BUY", "SELL"};
    
    //--- Balance simulado inicial
    double balanceSimulado = 100000.0;
    
    //--- Contador de ticket simulado
    int ticketBase = 90000000 + MathRand();
    
    Print("==============================================");
    Print("INICIANDO ENVÍO DE TRADES DE PRUEBA (MT5)");
    Print("Estrategias: 1111, 1112, 1113");
    Print("Trades por estrategia: ", Num_Trades_Test);
    Print("==============================================");
    
    int totalEnviados = 0;
    
    //--- Para cada estrategia
    for (int s = 0; s < 3; s++)
    {
        int magic = magicNumbers[s];
        
        Print("--- Enviando trades para estrategia Magic: ", magic, " ---");
        
        //--- Enviar N trades por estrategia
        for (int t = 0; t < Num_Trades_Test; t++)
        {
            //--- Generar datos aleatorios
            int ticketSimulado = ticketBase + (s * 100) + t;
            
            //--- Símbolo aleatorio
            int idxSimbolo = MathRand() % 5;
            string simbolo = simbolos[idxSimbolo];
            
            //--- Dirección aleatoria
            int idxDir = MathRand() % 2;
            string direccion = direcciones[idxDir];
            
            //--- Lotes aleatorios entre 0.01 y 2.0
            double lotes = NormalizeDouble(0.01 + (MathRand() % 200) * 0.01, 2);
            
            //--- PnL aleatorio entre -1000 y +1000
            double pnl = NormalizeDouble(-1000.0 + (MathRand() % 2001), 2);
            
            //--- Actualizar balance simulado
            balanceSimulado += pnl;
            
            //--- Resultado basado en PnL
            string resultado = (pnl >= 0) ? "WIN" : "LOSS";
            
            //--- Fechas simuladas (últimos 30 días)
            int diasAtras = MathRand() % 30;
            int horasAtras = MathRand() % 24;
            datetime fechaCierre = TimeCurrent() - (diasAtras * 86400) - (horasAtras * 3600);
            datetime fechaApertura = fechaCierre - (MathRand() % 86400);
            
            string fechaCierreStr = FormatearFechaISO(fechaCierre);
            string fechaAperturaStr = FormatearFechaISO(fechaApertura);
            
            //--- Comentario descriptivo
            string comentario = "TEST_TRADE_" + IntegerToString(s+1) + "_" + IntegerToString(t+1);
            
            //--- Construir JSON
            string jsonPayload = ConstruirJSON(
                ticketSimulado,
                magic,
                simbolo,
                direccion,
                lotes,
                pnl,
                resultado,
                balanceSimulado,
                fechaAperturaStr,
                fechaCierreStr,
                comentario
            );
            
            //--- Enviar al servidor
            if (Modo_Debug)
            {
                Print("Enviando trade de prueba #", (s * Num_Trades_Test + t + 1), 
                      ": Ticket=", ticketSimulado, 
                      " Magic=", magic, 
                      " ", simbolo, 
                      " ", direccion, 
                      " PnL=", DoubleToString(pnl, 2));
            }
            
            EnviarAlServidorURL(g_urlTrade, jsonPayload);
            totalEnviados++;
            
            //--- Pequeña pausa para no saturar el servidor
            Sleep(200);
        }
    }
    
    Print("==============================================");
    Print("ENVÍO DE TRADES DE PRUEBA COMPLETADO");
    Print("Total enviados: ", totalEnviados);
    Print("Balance simulado final: ", DoubleToString(balanceSimulado, 2));
    Print("==============================================");
    
    //--- Enviar drawdown de prueba para cada estrategia
    Print("Enviando datos de drawdown de prueba...");
    
    for (int d = 0; d < 3; d++)
    {
        EnviarDrawdownDePrueba(magicNumbers[d], balanceSimulado);
        Sleep(200);
    }
    
    Print("=== MODO TEST FINALIZADO ===");
}


//+------------------------------------------------------------------+
//|              ENVIAR DRAWDOWN DE PRUEBA                           |
//+------------------------------------------------------------------+
void EnviarDrawdownDePrueba(int magicNumber, double balance)
{
    //--- Simular valores de drawdown
    double peakBalance = balance * 1.1;
    double drawdownCuenta = peakBalance - balance;
    double drawdownPct = (drawdownCuenta / peakBalance) * 100;
    
    double peakEstrategia = 5000 + (MathRand() % 5000);
    double ddEstrategia = MathRand() % 2000;
    double maxDdEstrategia = ddEstrategia * 1.5;
    
    //--- Construir JSON
    string json = "{";
    json += "\"identificador_cuenta\":\"" + Identificador_Cuenta + "\",";
    json += "\"magic_number\":" + IntegerToString(magicNumber) + ",";
    json += "\"balance\":" + DoubleToString(balance, 2) + ",";
    json += "\"equity\":" + DoubleToString(balance * 0.99, 2) + ",";
    json += "\"peak_balance\":" + DoubleToString(peakBalance, 2) + ",";
    json += "\"drawdown_cuenta\":" + DoubleToString(drawdownCuenta, 2) + ",";
    json += "\"drawdown_cuenta_pct\":" + DoubleToString(drawdownPct, 2) + ",";
    json += "\"drawdown_estrategia\":" + DoubleToString(ddEstrategia, 2) + ",";
    json += "\"max_drawdown_estrategia\":" + DoubleToString(maxDdEstrategia, 2) + ",";
    json += "\"peak_estrategia\":" + DoubleToString(peakEstrategia, 2) + ",";
    json += "\"timestamp\":\"" + FormatearFechaISO(TimeCurrent()) + "\"";
    json += "}";
    
    //--- Enviar al servidor
    Print("Enviando drawdown de prueba para Magic: ", magicNumber);
    EnviarAlServidorURL(g_urlDrawdown, json);
}
//+------------------------------------------------------------------+
