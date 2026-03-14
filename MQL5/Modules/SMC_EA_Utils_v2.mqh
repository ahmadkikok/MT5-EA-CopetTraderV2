//+------------------------------------------------------------------+
//| SMC_EA_Utils_v2.mqh                                              |
//| Helper functions: logging, OB tracker, ATH/ATL, trend align,    |
//| entry checks, performance display.                               |
//+------------------------------------------------------------------+
#ifndef __SMC_EA_UTILS_V2_MQH__
#define __SMC_EA_UTILS_V2_MQH__

#include <SMC/SmcManager.mqh>
#include <Trade/PositionInfo.mqh>
#include "SMC_EA_TradeExecution_v2.mqh"

extern CSmcManager g_smcEntry;
extern CSmcManager g_smcStruct;
extern CSmcManager g_smcBias;
extern CPositionInfo m_position;

extern int    g_magicNumber;
extern int    g_maxBuy;
extern int    g_maxSell;
extern int    g_minSecondBetweenSameSide;
extern int    g_minDistancePoints;
extern int    g_usedOBTimes_limit;
extern bool   g_DebugMode;
extern bool   g_IgnoreManualTrades;
extern double g_FloatingLimitValue;
extern bool   g_FloatingStopTrading;
extern bool   g_FloatingLossTriggered;
extern bool   g_MaxDDTriggered;
extern bool   g_MaxDDStopTrading;
extern bool   g_EnableBE_Buy;
extern bool   g_EnableBE_Sell;
extern bool   g_EnableReversalGuard;
extern bool   g_EnablePDFilter;
extern bool   g_BlockBadPDEntry;
extern double g_PDMaxRangePercent;
extern bool   g_ValidateEntry;
extern ENUM_TIMEFRAMES BiasTF;
extern ENUM_TIMEFRAMES StructTF;

extern datetime g_lastBuyTime;
extern datetime g_lastSellTime;
extern datetime g_usedOBTimes[];

//+------------------------------------------------------------------+
//| Logging                                                          |
//+------------------------------------------------------------------+
void DebugPrint(string msg) { if(!g_DebugMode) return; Print("[DEBUG] ", msg); }
void SysPrint(string msg)   { Print("[SYS] ",   msg); }
void ErrorPrint(string msg) { Print("[ERROR] ", msg); }

//+------------------------------------------------------------------+
//| OB Used tracking (same as v1.08)                                 |
//+------------------------------------------------------------------+
bool IsOBUsed(datetime t)
{
   for(int i = 0; i < ArraySize(g_usedOBTimes); i++)
      if(g_usedOBTimes[i] == t) return true;
   return false;
}
void MarkOBUsed(datetime t)
{
   int n = ArraySize(g_usedOBTimes);
   if(n >= g_usedOBTimes_limit) { ArrayRemove(g_usedOBTimes, 0, 1); n--; }
   ArrayResize(g_usedOBTimes, n + 1);
   g_usedOBTimes[n] = t;
}

//+------------------------------------------------------------------+
//| ATH/ATL helpers (no HTFFilter dependency)                        |
//+------------------------------------------------------------------+
bool IsNearATH(double threshPts, ENUM_TIMEFRAMES tf)
{
   int bars = iBars(_Symbol, tf);
   if(bars < 2) return false;
   double highest = 0;
   for(int i = 1; i < MathMin(bars, 500); i++)
      if(iHigh(_Symbol, tf, i) > highest) highest = iHigh(_Symbol, tf, i);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return (highest - bid) < threshPts * _Point;
}
bool IsNearATL(double threshPts, ENUM_TIMEFRAMES tf)
{
   int bars = iBars(_Symbol, tf);
   if(bars < 2) return false;
   double lowest = DBL_MAX;
   for(int i = 1; i < MathMin(bars, 500); i++)
      if(iLow(_Symbol, tf, i) < lowest) lowest = iLow(_Symbol, tf, i);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return (bid - lowest) < threshPts * _Point;
}

//+------------------------------------------------------------------+
//| CanOpenNewOrder — distance + max positions + timing              |
//+------------------------------------------------------------------+
/*bool CanOpenNewOrder(ENUM_ORDER_TYPE type)
{
   bool isBuy = (type == ORDER_TYPE_BUY);
   if(isBuy && CountOpenPositionsBySide(_Symbol, g_magicNumber, true)  >= g_maxBuy)  return false;
   if(!isBuy && CountOpenPositionsBySide(_Symbol, g_magicNumber, false) >= g_maxSell) return false;

   datetime &lastT = isBuy ? g_lastBuyTime : g_lastSellTime;
   if(TimeCurrent() - lastT < g_minSecondBetweenSameSide) return false;

   // Min distance from existing positions
   double entryPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                              : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!m_position.SelectByIndex(i)) continue;
      if(m_position.Symbol() != _Symbol) continue;
      if((long)m_position.Magic() != g_magicNumber) continue;
      if((m_position.PositionType() == POSITION_TYPE_BUY)  != isBuy) continue;
      if(MathAbs(entryPrice - m_position.PriceOpen()) / _Point < g_minDistancePoints) return false;
   }
   return true;
}*/

//+------------------------------------------------------------------+
//| MTF Trend check using xxvw                                       |
//+------------------------------------------------------------------+
bool IsTrendAligned(ENUM_ORDER_TYPE type)
{
   ENUM_SMC_TREND bias   = g_smcBias.GetTrend();
   ENUM_SMC_TREND strct  = g_smcStruct.GetTrend();
   ENUM_SMC_TREND entry  = g_smcEntry.GetTrend();

   // Bias MUST have direction
   if(bias == SMC_TREND_RANGING) return false;

   bool wantBull = (type == ORDER_TYPE_BUY);

   // Bias must agree
   if(wantBull  && bias != SMC_TREND_BULLISH) return false;
   if(!wantBull && bias != SMC_TREND_BEARISH) return false;

   // At least 1 other TF must agree
   int agree = 0;
   if(wantBull  && strct == SMC_TREND_BULLISH) agree++;
   if(!wantBull && strct == SMC_TREND_BEARISH) agree++;
   if(wantBull  && entry == SMC_TREND_BULLISH) agree++;
   if(!wantBull && entry == SMC_TREND_BEARISH) agree++;

   // Don't allow opposite direction on any TF
   if(wantBull  && entry == SMC_TREND_BEARISH) return false;
   if(!wantBull && entry == SMC_TREND_BULLISH) return false;

   return (agree >= 1);
}

//+------------------------------------------------------------------+
//| OB Retest check                                                  |
//+------------------------------------------------------------------+
bool IsInOBZone(const SmcZone &ob, double &entryPrice)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double tol = InpRetestTolPoints * _Point;

   if(ob.isBullish)
   {
      if(bid <= ob.topPrice + tol && bid >= ob.bottomPrice - tol)
         { entryPrice = ask; return true; }
   }
   else
   {
      if(ask >= ob.bottomPrice - tol && ask <= ob.topPrice + tol)
         { entryPrice = bid; return true; }
   }
   return false;
}

//+------------------------------------------------------------------+
//| UpdateComment                                                    |
//+------------------------------------------------------------------+
struct PerformanceData { int totalWin; int totalLoss; double totalProfit;
                         double winRateDaily; double winRateWeekly; double winRateMonthly; };
PerformanceData CachedPerf;
datetime LastPerfUpdate = 0;

PerformanceData CalculatePerformance()
{
   PerformanceData d; ZeroMemory(d);
   datetime now = TimeCurrent();
   datetime dayStart  = iTime(_Symbol, PERIOD_D1, 0);
   MqlDateTime tm; TimeToStruct(now, tm);
   datetime weekStart  = now - (tm.day_of_week * 86400);
   tm.day = 1; tm.hour = 0; tm.min = 0; tm.sec = 0;
   datetime monthStart = StructToTime(tm);
   int dT=0,dW=0,wT=0,wW=0,mT=0,mW=0;
   if(!HistorySelect(0, now)) return d;
   int deals = HistoryDealsTotal();
   for(int i=0;i<deals;i++)
   {
      ulong tk = HistoryDealGetTicket(i);
      if((int)HistoryDealGetInteger(tk,DEAL_ENTRY)==DEAL_ENTRY_IN) continue;
      double p = HistoryDealGetDouble(tk,DEAL_PROFIT)+HistoryDealGetDouble(tk,DEAL_SWAP)+HistoryDealGetDouble(tk,DEAL_COMMISSION);
      datetime dt = (datetime)HistoryDealGetInteger(tk,DEAL_TIME);
      d.totalProfit += p;
      if(p>0.00001) d.totalWin++; else if(p<-0.00001) d.totalLoss++;
      if(dt>=dayStart)  { dT++; if(p>0.00001) dW++; }
      if(dt>=weekStart) { wT++; if(p>0.00001) wW++; }
      if(dt>=monthStart){ mT++; if(p>0.00001) mW++; }
   }
   if(dT>0) d.winRateDaily   = (double)dW/dT*100;
   if(wT>0) d.winRateWeekly  = (double)wW/wT*100;
   if(mT>0) d.winRateMonthly = (double)mW/mT*100;
   return d;
}

void UpdateComment(string extra)
{
   ENUM_SMC_TREND biasTrend  = g_smcBias.GetTrend();
   ENUM_SMC_TREND structTrend = g_smcStruct.GetTrend();
   ENUM_SMC_TREND entryTrend  = g_smcEntry.GetTrend();

   string biasStr  = (biasTrend  == SMC_TREND_BULLISH) ? "🟢 BULL" :
                     (biasTrend  == SMC_TREND_BEARISH) ? "🔴 BEAR" : "⬜ RANGE";
   string structStr= (structTrend == SMC_TREND_BULLISH) ? "🟢 BULL" :
                     (structTrend == SMC_TREND_BEARISH) ? "🔴 BEAR" : "⬜ RANGE";
   string entryStr = (entryTrend  == SMC_TREND_BULLISH) ? "🟢 BULL" :
                     (entryTrend  == SMC_TREND_BEARISH) ? "🔴 BEAR" : "⬜ RANGE";

   // OB info
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   SmcZone nearBull, nearBear;
   string obBullStr = "--", obBearStr = "--";
   if(g_smcEntry.OB().GetNearestBullishOB(bid, nearBull))
      obBullStr = StringFormat("%.2f-%.2f [%s]", nearBull.bottomPrice, nearBull.topPrice,
                               nearBull.IsFresh() ? "F" : "T");
   if(g_smcEntry.OB().GetNearestBearishOB(bid, nearBear))
      obBearStr = StringFormat("%.2f-%.2f [%s]", nearBear.bottomPrice, nearBear.topPrice,
                               nearBear.IsFresh() ? "F" : "T");

   // PD Zone
   double pdPct = g_smcEntry.PD().GetZonePercent(bid);
   string pdStr  = StringFormat("%.0f%% (%s)", pdPct,
                   g_smcEntry.PD().IsPremium() ? "PREMIUM" :
                   g_smcEntry.PD().IsDiscount() ? "DISCOUNT" : "EQ");

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   string ddStatus      = GetMaxDDStatus();
   string floatStatus   = GetFloatingLossStatus();
   string dailyStatus   = RM_GetDailyLossStatus();
   string gridStatus    = GetGridRecoveryStatus();
   string pdLvlStatus   = GetPDStatus();
   string newsStatus    = GetNewsStatus();

   if(TimeCurrent() - LastPerfUpdate > 10)
      { CachedPerf = CalculatePerformance(); LastPerfUpdate = TimeCurrent(); }

   Comment(StringFormat(
      "═══ Market Structure (xxvw) ═══\n"
      "Bias   (%s): %s\n"
      "Struct (%s): %s\n"
      "Entry  (%s): %s\n"
      "\n"
      "═══ Order Blocks ═══\n"
      "Bull OB: %s\n"
      "Bear OB: %s\n"
      "PD Zone: %s\n"
      "\n"
      "═══ Protection Status ═══\n"
      "%s\n%s\n%s\n%s\n"
      "\n"
      "═══ Filters ═══\n"
      "Spread: %d | %s\n"
      "\n"
      "═══ Performance ═══\n"
      "Win: %d | Loss: %d | P/L: $%.2f\n"
      "Daily: %.1f%% | Week: %.1f%% | Month: %.1f%%\n"
      "\n%s\n%s",
      EnumToString(InpBiasTF),   biasStr,
      EnumToString(InpStructTF), structStr,
      EnumToString(Period()),    entryStr,
      obBullStr, obBearStr, pdStr,
      ddStatus, floatStatus, dailyStatus, gridStatus,
      spread, newsStatus,
      CachedPerf.totalWin, CachedPerf.totalLoss, CachedPerf.totalProfit,
      CachedPerf.winRateDaily, CachedPerf.winRateWeekly, CachedPerf.winRateMonthly,
      pdLvlStatus, extra
   ));
}


#endif // __SMC_EA_UTILS_V2_MQH__
