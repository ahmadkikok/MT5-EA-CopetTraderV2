//+------------------------------------------------------------------+
//| SMC_EA_TradeExecution_v2.mqh                                     |
//| No dependency on old SMC_EA_OrderBlocks / MarketStructure.       |
//| Uses SmcZone from xxvw SMC_ICT_Library.                          |
//+------------------------------------------------------------------+
#ifndef __SMC_EA_TRADEEXECUTION_V2_MQH__
#define __SMC_EA_TRADEEXECUTION_V2_MQH__

#include <SMC/SmcManager.mqh>
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

extern CTrade g_trade;
extern int    g_magicNumber;
extern int    g_slippage;
extern int    g_maxSell;
extern int    g_maxBuy;
extern double g_FixedTP;
extern double g_SLFixedTP;

extern bool g_IgnoreManualTrades;
extern bool g_stopLossOB;
extern bool   g_ApplyOBSL_Buy;
extern bool   g_ApplyOBSL_Sell;
extern bool   g_EnableSellRR;
extern double g_SellRR;
extern double g_SellSLMin;
extern double g_SellSLMax;

//void ErrorPrint(string msg);
//void SysPrint(string msg);
//void DebugPrint(string msg);

extern ENUM_TIMEFRAMES BiasTF;
extern ENUM_TIMEFRAMES StructTF;

static int             g_atrHandle   = INVALID_HANDLE;
static string          g_atrSymbol   = "";
static ENUM_TIMEFRAMES g_atrTF       = PERIOD_CURRENT;
static int             g_atrPeriod   = 14;

//+------------------------------------------------------------------+
//| Helper Count position                                            |
//+------------------------------------------------------------------+
int CountOpenPositionsBySide(const string symbol, const long magic, const bool isBuy)
{
   int count = 0;
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
      long mg = (long)PositionGetInteger(POSITION_MAGIC);
      if(mg != magic) continue;

      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(isBuy && pt == POSITION_TYPE_BUY)   count++;
      if(!isBuy && pt == POSITION_TYPE_SELL) count++;
   }
   return count;
}

ENUM_ORDER_TYPE OrderTypeFromOB(const SmcZone &ob)
{
   return ob.isBullish ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
}

//+------------------------------------------------------------------+
//| Auto filling mode                                                |
//+------------------------------------------------------------------+
bool SendOrderWithFallback(MqlTradeRequest &request, MqlTradeResult &result)
{
   ENUM_ORDER_TYPE_FILLING modes[3] =
   {
      ORDER_FILLING_IOC,
      ORDER_FILLING_FOK,
      ORDER_FILLING_RETURN
   };

   for(int i = 0; i < 3; i++)
   {
      request.type_filling = modes[i];

      if(OrderSend(request, result))
      {
         DebugPrint(StringFormat("✅ Order success with filling: %s",
                     EnumToString(request.type_filling)));
         return true;
      }

      if(result.retcode != 10030) // INVALID_FILL
      {
         // error lain → jangan retry
         break;
      }

      DebugPrint(StringFormat("⚠️ Filling %s rejected, retrying...",
                  EnumToString(request.type_filling)));
   }

   return false;
}

//+------------------------------------------------------------------+
//| OpenPosition with OB-based SL                                    |
//+------------------------------------------------------------------+
// FIX: OpenPosition sekarang menerima OB aktif sebagai parameter
// Sebelumnya SL pakai g_usedOBTimes (OB trade lalu / kosong saat pertama kali)
// Sekarang SL langsung pakai ob.bottomPrice (BUY) atau ob.topPrice (SELL) = proper ICT placement
bool OpenPosition(ENUM_ORDER_TYPE type, double lot, const SmcZone &ob)
{
   if(type == ORDER_TYPE_BUY)
   {
      if(CountOpenPositionsBySide(_Symbol,g_magicNumber,true) >= g_maxBuy)
      {
         DebugPrint("⏸️ Max BUY positions reached, skip open");
         return false;
      }
   }
   else if(type == ORDER_TYPE_SELL)
   {
      if(CountOpenPositionsBySide(_Symbol,g_magicNumber,false) >= g_maxSell)
      {
         DebugPrint("⏸️ Max SELL positions reached, skip open");
         return false;
      }
   }

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = _Symbol;
   request.volume    = lot;
   request.type      = type;
   request.price     = (type==ORDER_TYPE_BUY ? SymbolInfoDouble(_Symbol,SYMBOL_ASK)
                                             : SymbolInfoDouble(_Symbol,SYMBOL_BID));
   request.deviation = g_slippage;
   request.magic     = g_magicNumber;
   request.type_filling = ORDER_FILLING_RETURN;

   // === OB-based SL Calculation (FIXED) ===
   // FIX: SL ditempatkan di luar OB zone:
   //   BUY  → SL = ob.bottomPrice  - buffer  (di bawah demand zone)
   //   SELL → SL = ob.topPrice + buffer  (di atas supply zone)
   // Buffer = g_SLFixedTP * ATR untuk menghindari fake-out
   bool applySL = false;
   if(g_stopLossOB)
   {
      if((type == ORDER_TYPE_BUY  && g_ApplyOBSL_Buy) ||
         (type == ORDER_TYPE_SELL && g_ApplyOBSL_Sell))
         applySL = true;
   }

   if(applySL)
   {
      // Validasi OB: ob.formationTime harus valid
      if(ob.formationTime == 0)
      {
         SysPrint("⚠️ OB-SL: ob.formationTime invalid, SL = 0 (no SL set)");
         request.sl = 0.0;
      }
      else
      {
         // Buffer = SLFixedTP * ATR (pakai ATR entry timeframe)
         double atr    = GetATR(1);  // last closed bar ATR
         double buffer = atr * g_SLFixedTP;
         if(buffer <= 0) buffer = ob.topPrice - ob.bottomPrice;  // fallback = OB range

         double slPrice = 0.0;
         if(type == ORDER_TYPE_BUY)
         {
            // SL di bawah OB low
            slPrice = ob.bottomPrice - buffer;
            
            // Safety: SL harus di bawah entry price
            if(slPrice >= request.price)
            {
               SysPrint(StringFormat("⚠️ OB-SL BUY: sl=%.2f >= entry=%.2f, set sl=entry-buffer", slPrice, request.price));
               slPrice = request.price - buffer;
            }
         }
         else
         {
            // SL di atas OB high
            slPrice = ob.topPrice + buffer;
            
            // Safety: SL harus di atas entry price
            if(slPrice <= request.price)
            {
               SysPrint(StringFormat("⚠️ OB-SL SELL: sl=%.2f <= entry=%.2f, set sl=entry+buffer", slPrice, request.price));
               slPrice = request.price + buffer;
            }
         }

         request.sl = NormalizeDouble(slPrice, _Digits);

         double slPips = MathAbs(request.price - request.sl) / _Point;
         SysPrint(StringFormat("📍 OB-SL %s: entry=%.2f | OB[%.2f-%.2f] | buffer=%.2f | SL=%.2f (%.0f pts)",
                     (type==ORDER_TYPE_BUY?"BUY":"SELL"),
                     request.price, ob.bottomPrice, ob.topPrice, buffer,
                     request.sl, slPips));
      }
   }
   else
   {
      request.sl = 0.0;
   }

   // === SELL SL Guard: min/max distance check ===
   // Skip trade kalau SL terlalu dekat (noise) atau terlalu jauh (news spike)
   if(type == ORDER_TYPE_SELL && request.sl > 0.0)
   {
      double slDist = MathAbs(request.sl - request.price) / _Point;
      if(slDist < g_SellSLMin)
      {
         SysPrint(StringFormat("[SLGuard] ⛔ SELL SKIP: SL too close (%.1f pts < min %.1f pts)", slDist, g_SellSLMin));
         return false;
      }
      if(g_SellSLMax > 0 && slDist > g_SellSLMax)
      {
         SysPrint(StringFormat("[SLGuard] ⛔ SELL SKIP: SL too far (%.1f pts > max %.1f pts)", slDist, g_SellSLMax));
         return false;
      }
   }

   request.tp = 0.0;

   // === RR-based TP untuk SELL ===
   if(type == ORDER_TYPE_SELL && g_EnableSellRR && request.sl > 0.0)
   {
      double slDist = request.sl - request.price;
      double tpPrice = request.price - (slDist * g_SellRR);
      if(tpPrice < request.price)
      {
         request.tp = NormalizeDouble(tpPrice, _Digits);
         SysPrint(StringFormat("🎯 SELL RR TP: entry=%.2f SL=%.2f RR=%.1f TP=%.2f",
                  request.price, request.sl, g_SellRR, request.tp));
      }
   }

   // ╔══════════════════════════════════════════════════════════════╗
   // ║                    DEBUG BLOCK START                         ║
   // ╚══════════════════════════════════════════════════════════════╝
   DebugPrint("═══════════════════════════════════════════════════════");
   DebugPrint("📤 OpenPosition Request");
   DebugPrint("═══════════════════════════════════════════════════════");
   DebugPrint(StringFormat("   Action      : %s", EnumToString(request.action)));
   DebugPrint(StringFormat("   Symbol      : %s", request.symbol));
   DebugPrint(StringFormat("   Type        : %s", EnumToString(request.type)));
   DebugPrint(StringFormat("   Volume      : %.2f", request.volume));
   DebugPrint(StringFormat("   Price       : %.5f", request.price));
   DebugPrint(StringFormat("   SL          : %.5f", request.sl));
   DebugPrint(StringFormat("   TP          : %.5f", request.tp));
   DebugPrint(StringFormat("   Deviation   : %d", request.deviation));
   DebugPrint(StringFormat("   Magic       : %d", request.magic));
   DebugPrint(StringFormat("   Type Filling: %s", EnumToString(request.type_filling)));
   DebugPrint(StringFormat("   Comment     : %s", request.comment));
   DebugPrint("───────────────────────────────────────────────────────");
   
   // === Symbol Info Debug ===
   DebugPrint("📊 Symbol Info");
   DebugPrint("───────────────────────────────────────────────────────");
   DebugPrint(StringFormat("   Bid            : %.5f", SymbolInfoDouble(_Symbol, SYMBOL_BID)));
   DebugPrint(StringFormat("   Ask            : %.5f", SymbolInfoDouble(_Symbol, SYMBOL_ASK)));
   DebugPrint(StringFormat("   Spread         : %d pts", (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)));
   DebugPrint(StringFormat("   Volume Min     : %.2f", SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)));
   DebugPrint(StringFormat("   Volume Max     : %.2f", SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)));
   DebugPrint(StringFormat("   Volume Step    : %.2f", SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP)));
   DebugPrint(StringFormat("   Filling Mode   : %d", (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE)));
   DebugPrint(StringFormat("   Stops Level    : %d pts", (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)));
   DebugPrint(StringFormat("   Freeze Level   : %d pts", (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL)));
   DebugPrint(StringFormat("   Trade Allowed  : %s", SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_FULL ? "YES" : "NO"));
   DebugPrint("───────────────────────────────────────────────────────");
   
   // === Account Info Debug ===
   DebugPrint("💰 Account Info");
   DebugPrint("───────────────────────────────────────────────────────");
   DebugPrint(StringFormat("   Balance        : %.2f", AccountInfoDouble(ACCOUNT_BALANCE)));
   DebugPrint(StringFormat("   Equity         : %.2f", AccountInfoDouble(ACCOUNT_EQUITY)));
   DebugPrint(StringFormat("   Free Margin    : %.2f", AccountInfoDouble(ACCOUNT_MARGIN_FREE)));
   DebugPrint(StringFormat("   Trade Allowed  : %s", AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) ? "YES" : "NO"));
   DebugPrint(StringFormat("   EA Allowed     : %s", AccountInfoInteger(ACCOUNT_TRADE_EXPERT) ? "YES" : "NO"));
   DebugPrint("═══════════════════════════════════════════════════════");
   // ╔══════════════════════════════════════════════════════════════╗
   // ║                    DEBUG BLOCK END                           ║
   // ╚══════════════════════════════════════════════════════════════╝

   if(!SendOrderWithFallback(request, result))
   {
      ErrorPrint("═══════════════════════════════════════════════════════");
      ErrorPrint("❌ OrderSend FAILED!");
      ErrorPrint("═══════════════════════════════════════════════════════");
      ErrorPrint(StringFormat("   LastError      : %d", GetLastError()));
      ErrorPrint(StringFormat("   Retcode        : %d", result.retcode));
      ErrorPrint(StringFormat("   Retcode Desc   : %s", GetRetcodeDescription(result.retcode)));
      ErrorPrint(StringFormat("   Deal           : %I64d", result.deal));
      ErrorPrint(StringFormat("   Order          : %I64d", result.order));
      ErrorPrint(StringFormat("   Volume         : %.2f", result.volume));
      ErrorPrint(StringFormat("   Price          : %.5f", result.price));
      ErrorPrint(StringFormat("   Comment        : %s", result.comment));
      ErrorPrint("═══════════════════════════════════════════════════════");
      ResetLastError();
      return false;
   }
   
   SysPrint("═══════════════════════════════════════════════════════");
   SysPrint("✅ OrderSend SUCCESS!");
   SysPrint("═══════════════════════════════════════════════════════");
   SysPrint(StringFormat("   Retcode        : %d", result.retcode));
   SysPrint(StringFormat("   Deal           : %I64d", result.deal));
   SysPrint(StringFormat("   Order          : %I64d", result.order));
   SysPrint(StringFormat("   Volume         : %.2f", result.volume));
   SysPrint(StringFormat("   Price          : %.5f", result.price));
   SysPrint("═══════════════════════════════════════════════════════");
            
   return true;
}

//+------------------------------------------------------------------+
//| Helper: Get Retcode Description                                  |
//+------------------------------------------------------------------+
string GetRetcodeDescription(uint retcode)
{
   switch(retcode)
   {
      case 10004: return "REQUOTE";
      case 10006: return "REJECT";
      case 10007: return "CANCEL";
      case 10008: return "PLACED";
      case 10009: return "DONE";
      case 10010: return "DONE_PARTIAL";
      case 10011: return "ERROR";
      case 10012: return "TIMEOUT";
      case 10013: return "INVALID";
      case 10014: return "INVALID_VOLUME";
      case 10015: return "INVALID_PRICE";
      case 10016: return "INVALID_STOPS";
      case 10017: return "TRADE_DISABLED";
      case 10018: return "MARKET_CLOSED";
      case 10019: return "NO_MONEY";
      case 10020: return "PRICE_CHANGED";
      case 10021: return "PRICE_OFF";
      case 10022: return "INVALID_EXPIRATION";
      case 10023: return "ORDER_CHANGED";
      case 10024: return "TOO_MANY_REQUESTS";
      case 10025: return "NO_CHANGES";
      case 10026: return "SERVER_DISABLES_AT";
      case 10027: return "CLIENT_DISABLES_AT";
      case 10028: return "LOCKED";
      case 10029: return "FROZEN";
      case 10030: return "INVALID_FILL";
      case 10031: return "CONNECTION";
      case 10032: return "ONLY_REAL";
      case 10033: return "LIMIT_ORDERS";
      case 10034: return "LIMIT_VOLUME";
      case 10035: return "INVALID_ORDER";
      case 10036: return "POSITION_CLOSED";
      default:    return StringFormat("UNKNOWN (%d)", retcode);
   }
}

//+------------------------------------------------------------------+
//| Helper close position                                            |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;
   
   long posMagic = (long)PositionGetInteger(POSITION_MAGIC);
   if(g_IgnoreManualTrades && posMagic != g_magicNumber)
      return;
   
   bool ok = g_trade.PositionClose(ticket);
   if(ok)
      SysPrint(StringFormat("✅ Position closed: ticket=%I64u", ticket));
   else
      ErrorPrint(StringFormat("❌ Close failed: ticket=%I64u | _LastError=%d", ticket, GetLastError()));
}

//+------------------------------------------------------------------+
//| Close semua posisi                                               |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   int total = PositionsTotal();
   for(int i = total-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(PositionSelectByTicket(ticket))
      {
         string sym = PositionGetString(POSITION_SYMBOL);
         if(sym != _Symbol) continue;
         
         long posMagic = (long)PositionGetInteger(POSITION_MAGIC);
         if(g_IgnoreManualTrades && posMagic != g_magicNumber)
            continue;
                     
         ClosePosition(ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| IsDirectionAllowed - Integrated MTF Check                        |
// IsDirectionAllowed removed - handled by main EA via xxvw SmcManager
//+------------------------------------------------------------------+
void InitATR(const int period)
{
   g_atrPeriod = period;

   // Release old handle if exists
   if(g_atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_atrHandle);
      g_atrHandle = INVALID_HANDLE;
   }

   g_atrHandle = iATR(_Symbol, Period(), g_atrPeriod);
   g_atrSymbol = _Symbol;
   g_atrTF     = Period();

   if(g_atrHandle == INVALID_HANDLE)
   {
      ErrorPrint(StringFormat("❌ ATR init failed. Error=%d", GetLastError()));
      return;
   }

   int waitCount = 0;
   const int maxWait = 100; // ~2s if 20ms
   while(BarsCalculated(g_atrHandle) <= 0 && waitCount < maxWait)
   {
      Sleep(20);
      waitCount++;
   }

   int calc = BarsCalculated(g_atrHandle);
   DebugPrint(StringFormat("✅ ATR initialized: period=%d, BarsCalculated=%d", g_atrPeriod, calc));
}

// Cache ATR terakhir
static double g_atrLastValue = 0.0;

//+------------------------------------------------------------------+
//| HYBRID ATR (Live-Stable + Debug + Fallback)                      |
//+------------------------------------------------------------------+
double GetATR(const int shift = 0)
{
    // Re-init kalau symbol/TF berubah atau handle invalid
    if(g_atrHandle == INVALID_HANDLE ||
       g_atrSymbol != _Symbol ||
       g_atrTF     != Period())
    {
        InitATR(g_atrPeriod);
    }

    // Jika tetap invalid → fallback total
    if(g_atrHandle == INVALID_HANDLE)
    {
        //DebugPrint(StringFormat("ATR FALLBACK: Handle invalid, using lastATR=%.6f", g_atrLastValue));
        return g_atrLastValue;
    }

    int calc = BarsCalculated(g_atrHandle);

    // Jika BarsCalculated tidak valid → fallback
    if(calc <= shift)
    {
        //DebugPrint(StringFormat("ATR FALLBACK: BarsCalc=%d → using lastATR=%.6f", calc, g_atrLastValue));

        return g_atrLastValue;
    }

    // Normal read
    double buf[];
    ArraySetAsSeries(buf, true);

    int copied = CopyBuffer(g_atrHandle, 0, shift, 1, buf);
    if(copied != 1)
    {
        //DebugPrint(StringFormat("ATR FALLBACK: CopyBuffer failed (%d) → using lastATR=%.6f", copied, g_atrLastValue));
        return g_atrLastValue;
    }

    // Value valid?
    if(buf[0] <= 0.0)
    {
        //DebugPrint(StringFormat("ATR FALLBACK: buf invalid (%.6f) → using lastATR=%.6f", buf[0], g_atrLastValue));

        return g_atrLastValue;
    }

    // Update cache
    g_atrLastValue = buf[0];

    // Debug normal
    //DebugPrint(StringFormat("ATR Debug: ATR=%.6f | lastATR=%.6f | BarsCalc=%d | Handle=%d | TF=%s",
    //                buf[0], g_atrLastValue, calc, g_atrHandle, EnumToString(Period())));

    return buf[0];
}

//+------------------------------------------------------------------+
//| Cleanup ATR Handle                                               |
//+------------------------------------------------------------------+
void CleanupATRHandle()
{
   if(g_atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_atrHandle);
      g_atrHandle = INVALID_HANDLE;
      DebugPrint("✅ ATR Handle released");
   }
}

//+------------------------------------------------------------------+
//| Helpers for Check Engulfing Pattern                              |
//+------------------------------------------------------------------+
bool IsBullishEngulfing(int shift = 1)
{
    MqlRates c[];
    ArraySetAsSeries(c, true);
    if(CopyRates(_Symbol, Period(), shift, 2, c) < 2) return false;

    if(c[0].close > c[0].open && c[1].close < c[1].open)
    {
        if(c[0].close > c[1].open && c[0].open < c[1].close)
        {
            DebugPrint(StringFormat("✅ Bullish Engulfing detected @ shift %d", shift));
            return true;
        }
    }
    return false;
}

bool IsBearishEngulfing(int shift = 1)
{
    MqlRates c[];
    ArraySetAsSeries(c, true);
    if(CopyRates(_Symbol, Period(), shift, 2, c) < 2) return false;

    if(c[0].close < c[0].open && c[1].close > c[1].open)
    {
        if(c[0].close < c[1].open && c[0].open > c[1].close)
        {
            DebugPrint(StringFormat("✅ Bearish Engulfing detected @ shift %d", shift));
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Force ATR Warmup (LIVE FIX)                                     |
//| Karena di LIVE, BarsCalculated sering 0 (history belum ready)   |
//| Fungsi ini memaksa re-init ATR setiap 5 detik sampai READY.     |
//+------------------------------------------------------------------+
void ForceATRWarmup()
{
    static datetime last = 0;
    if(TimeCurrent() - last < 5)   // jalan 1x tiap 5 detik
        return;

    last = TimeCurrent();

    // Kalau ATR belum siap, re-init
    if(g_atrHandle == INVALID_HANDLE ||
       g_atrSymbol != _Symbol ||
       g_atrTF     != Period() ||
       BarsCalculated(g_atrHandle) <= 0)
    {
        DebugPrint("⚠️ ATR not ready → forcing re-init");

        InitATR(g_atrPeriod);
    }
}

#endif // __SMC_EA_TRADEEXECUTION_V2_MQH__
