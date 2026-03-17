//+------------------------------------------------------------------+
//| SMC_EA_TradeManagement.mqh                                       |
//| Updated with Grid Recovery Integration                           |
//+------------------------------------------------------------------+
#ifndef __SMC_EA_TRADEMANAGEMENT_V2_MQH__
#define __SMC_EA_TRADEMANAGEMENT_V2_MQH__

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include "SMC_EA_TradeExecution_v2.mqh"
#include "SMC_EA_GridRecovery.mqh"

extern CTrade g_trade;
extern CPositionInfo m_position;
extern datetime g_lastBuyTime;
extern datetime g_lastSellTime;

extern int g_maxBuy;
extern int g_maxSell;
extern int g_minSecondBetweenSameSide;
extern int g_magicNumber;
extern int g_minDistancePoints;

extern double g_ProfitTarget;
extern double g_FixedTP;
extern double g_lot;
extern double g_RGSensitivity;
extern double g_MaxDDEquityHigh;
extern double g_MaxDDPercent;

// Floating Loss (NEW)
extern bool g_EnableFloatingLimit;
extern bool g_FloatingStopTrading;
extern double g_FloatingLimitValue;
extern bool g_FloatingLossTriggered;

// Daily Loss (OLD - for RM)
extern bool g_EnableDailyLossLimit;
extern bool g_UseDailyLossAsPercent;
extern double g_DailyLossLimitValue;
extern bool g_AutoStopTradingToday;

extern bool g_EnableReversalGuard;
extern bool g_EnableMaxDD;
extern bool g_MaxDDStopTrading;
extern bool g_MaxDDTriggered;
extern bool g_EnableBE_Buy;
extern bool g_EnableBE_Sell;
extern bool g_IgnoreManualTrades;

// Entry Validation
extern bool   g_ValidateEntry;
extern bool   g_BlockOverbought;
extern bool   g_BlockOversold;
extern double g_BlockRangePercent;
extern int    g_RangeLookback;
extern int    g_RSIPeriode;
extern bool   g_RequireBearishM1Sell;
extern bool   g_RequireBullishM1Buy;

// Persistent RSI handle — created once in InitRSI(), reused every tick
static int g_rsiHandle = INVALID_HANDLE;

void InitRSI()
{
   if(g_rsiHandle != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
   g_rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, g_RSIPeriode, PRICE_CLOSE);
}
void CleanupRSI()
{
   if(g_rsiHandle != INVALID_HANDLE) { IndicatorRelease(g_rsiHandle); g_rsiHandle = INVALID_HANDLE; }
}

//+------------------------------------------------------------------+
//| Helper Set BreakEven (lock profit in $) untuk semua posisi       |
//+------------------------------------------------------------------+
void LockProfitAll(double triggerProfitUsd, double lockProfitUsd)
{
    int total = PositionsTotal();
    for(int i = total - 1; i >= 0; i--)
    {
        if(!m_position.SelectByIndex(i)) continue;
        if(m_position.Symbol() != _Symbol) continue;
        
        long posMagic = (long)PositionGetInteger(POSITION_MAGIC);
        if(g_IgnoreManualTrades && posMagic != g_magicNumber)
          continue;
    
        long posType   = PositionGetInteger(POSITION_TYPE);
        double entry   = PositionGetDouble(POSITION_PRICE_OPEN);
        double sl      = PositionGetDouble(POSITION_SL);
        double volume  = PositionGetDouble(POSITION_VOLUME);
        ulong ticket   = PositionGetInteger(POSITION_TICKET);
        double profit  = PositionGetDouble(POSITION_PROFIT);

        // ════════════════════════════════════════════════════════════════
        // CHECK: Skip based on direction enable setting
        // ════════════════════════════════════════════════════════════════
        if(posType == POSITION_TYPE_BUY && !g_EnableBE_Buy)
           continue;
        if(posType == POSITION_TYPE_SELL && !g_EnableBE_Sell)
           continue;

        double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
        double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

        if(tickSize == 0.0 || tickValue == 0.0) continue;
        double pointValue = tickValue / tickSize;
        if(pointValue <= 0.0) continue;

        double priceOffset = MathAbs(lockProfitUsd) / (pointValue * volume);

        double lockPrice = 0.0;
        if(posType == POSITION_TYPE_BUY)
            lockPrice = entry + priceOffset;
        else if(posType == POSITION_TYPE_SELL)
            lockPrice = entry - priceOffset;
        else
            continue;

        if(profit < triggerProfitUsd) continue;

        // Skip if SL already better than lockPrice
        if(posType == POSITION_TYPE_BUY && sl >= lockPrice) continue;
        if(posType == POSITION_TYPE_SELL && sl != 0 && sl <= lockPrice) continue;

        ResetLastError();
        bool ok = g_trade.PositionModify(ticket, lockPrice, PositionGetDouble(POSITION_TP));
        if(ok)
            SysPrint(StringFormat("✅ LockProfit: %s BE applied ticket=%I64u newSL=%.5f profit=%.2f",
                        posType == POSITION_TYPE_BUY ? "BUY" : "SELL",
                        ticket, lockPrice, profit));
        else
            ErrorPrint(StringFormat("❌ LockProfit: BE failed ticket=%I64u _LastError=%d",
                        ticket, GetLastError()));
    }
}

//+------------------------------------------------------------------+
//| Helper Check order before open position                          |
//+------------------------------------------------------------------+
bool CanOpenNewOrder(ENUM_ORDER_TYPE type)
{
   const bool wantBuy  = (type == ORDER_TYPE_BUY);
   const double curPrice = wantBuy
      ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
      : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double lastPrice = 0.0;
   datetime latestOpenTime = 0;

   const int total = PositionsTotal();
   for(int i=0; i<total; ++i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != g_magicNumber) continue;

      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(wantBuy && pt != POSITION_TYPE_BUY)  continue;
      if(!wantBuy && pt != POSITION_TYPE_SELL) continue;

      datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
      if(ot > latestOpenTime)
      {
         latestOpenTime = ot;
         lastPrice      = PositionGetDouble(POSITION_PRICE_OPEN);
      }
   }

   if(lastPrice == 0.0)
   {
      DebugPrint(StringFormat("DBG %s OK: no same-side open positions",
                  wantBuy ? "BUY" : "SELL"));
      return true;
   }

   double distancePoints = MathAbs(curPrice - lastPrice) / _Point;
   if(distancePoints < g_minDistancePoints)
   {
      DebugPrint(StringFormat("Skip %s: distance %.1f < MinDistance %.1f (cur=%.2f last=%.2f)",
                  wantBuy ? "BUY" : "SELL",
                  distancePoints, (double)g_minDistancePoints, curPrice, lastPrice));
      return false;
   }

   if(wantBuy && curPrice > lastPrice)
   {
      DebugPrint(StringFormat("Skip BUY: current %.2f > last BUY %.2f", curPrice, lastPrice));
      return false;
   }
   if(!wantBuy && curPrice < lastPrice)
   {
      DebugPrint(StringFormat("Skip SELL: current %.2f < last SELL %.2f", curPrice, lastPrice));
      return false;
   }

   if(wantBuy)
   {
      if(CountOpenPositionsBySide(_Symbol, g_magicNumber, true) >= g_maxBuy) return false;
      if(g_minSecondBetweenSameSide > 0 && (TimeCurrent() - g_lastBuyTime) < g_minSecondBetweenSameSide) return false;
   }
   else
   {
      if(CountOpenPositionsBySide(_Symbol, g_magicNumber, false) >= g_maxSell) return false;
      if(g_minSecondBetweenSameSide > 0 && (TimeCurrent() - g_lastSellTime) < g_minSecondBetweenSameSide) return false;
   }

   DebugPrint(StringFormat("DBG %s OK: cur=%.2f last=%.2f dist=%.1f pts",
               wantBuy ? "BUY" : "SELL", curPrice, lastPrice, distancePoints));
   return true;
}

//+------------------------------------------------------------------+
//| Manage Position - Updated with Grid Recovery Check               |
//+------------------------------------------------------------------+
void Manage_Position()
{
   // ==== 1. Gather data first (don't modify while iterating) ====
   int totalOrders = PositionsTotal();
   double totalProfit = 0.0;      // NET floating (includes profit & loss)
   
   // Store tickets to close separately
   ulong ticketsToClose[];
   ArrayResize(ticketsToClose, 0);

   // First pass: calculate totals and identify positions to close
   for(int i = 0; i < totalOrders; i++)
   {
      if(!m_position.SelectByIndex(i)) continue;
      if(m_position.Symbol() != _Symbol) continue;
      
      // ════════════════════════════════════════════════════════════════
      // BUG FIX: Simpan semua data DI AWAL sebelum panggil function lain!
      // IsGridActive() -> CountGridPositions() -> PositionSelectByTicket()
      // akan MENGUBAH selected position, bikin m_position.Ticket() SALAH!
      // ════════════════════════════════════════════════════════════════
      ulong currentTicket = m_position.Ticket();
      double posProfit = m_position.Profit();
      ENUM_POSITION_TYPE posType = m_position.PositionType();
      long posMagic = m_position.Magic();
      
      if(g_IgnoreManualTrades && posMagic != g_magicNumber)
         continue;
      
      totalProfit += posProfit;  // Sum ALL (positive and negative)
      
      int direction = (posType == POSITION_TYPE_BUY) ? 1 : -1;
      
      // ╔════════════════════════════════════════════════════════════╗
      // ║ GRID CHECK: Skip individual FixedTP if Grid is handling   ║
      // ╚════════════════════════════════════════════════════════════╝
      if(IsGridActive(direction))
      {
         // Grid Recovery handles TP for this direction
         // Skip individual FixedTP close
         continue;
      }
      
      // Mark for FixedTP close (only if NOT in grid mode)
      if(posProfit >= g_FixedTP)
      {
         // Skip FixedTP close untuk SELL yang sudah punya RR TP
         // Biarkan broker yang close di TP price yang sudah di-set
         if(posType == POSITION_TYPE_SELL)
         {
            double posTP = PositionGetDouble(POSITION_TP);
            if(posTP > 0.0)
            {
               DebugPrint(StringFormat("[TradeManagement] Skip FixedTP SELL #%I64u: RR TP=%.2f set",
                           currentTicket, posTP));
               continue;
            }
         }

         if(posType == POSITION_TYPE_BUY)
         {
            double posTP = PositionGetDouble(POSITION_TP);
            if(posTP > 0.0)
            {
               DebugPrint(StringFormat("[TradeManagement] Skip FixedTP BUY #%I64u: RR TP=%.2f set",
                           currentTicket, posTP));
               continue;
            }
         }
         
         int size = ArraySize(ticketsToClose);
         ArrayResize(ticketsToClose, size + 1);
         ticketsToClose[size] = currentTicket;
         
         DebugPrint(StringFormat("[TradeManagement] Mark close: %s #%I64u | Profit=$%.2f >= FixedTP=$%.2f",
                     posType == POSITION_TYPE_BUY ? "BUY" : "SELL",
                     currentTicket, posProfit, g_FixedTP));
      }
   }
   
   // ==== 2. Close positions marked for FixedTP (backward loop) ====
   for(int i = ArraySize(ticketsToClose) - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(ticketsToClose[i]))
      {
         double posProfit = PositionGetDouble(POSITION_PROFIT);
         SysPrint(StringFormat("Close single position profit %.2f >= FixedTP %.2f", posProfit, g_FixedTP));
         ClosePosition(ticketsToClose[i]);
      }
   }

   // ==== 3. Global TP Check ====
   // Re-count after individual closes
   int remainingPositions = 0;
   double remainingProfit = 0.0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(!m_position.SelectByIndex(i)) continue;
      if(m_position.Symbol() != _Symbol) continue;
      
      long posMagic = (long)PositionGetInteger(POSITION_MAGIC);
      if(g_IgnoreManualTrades && posMagic != g_magicNumber)
         continue;
      
      remainingPositions++;
      remainingProfit += m_position.Profit();
   }
   
   if(remainingProfit >= g_ProfitTarget && remainingPositions > 0)
   {
      SysPrint(StringFormat("Global TP: %.2f >= %.2f -> close all positions", remainingProfit, g_ProfitTarget));
      CloseAllPositions();
      return;
   }

   // ==== 4. FLOATING LOSS CHECK (NEW - SEPARATE!) ====
   if(g_EnableFloatingLimit && remainingProfit < 0 && remainingPositions > 0)
   {
      if(MathAbs(remainingProfit) >= g_FloatingLimitValue)
      {
         SysPrint("🚨 FLOATING LOSS TRIGGERED!");
         SysPrint(StringFormat("   Floating: -$%.2f >= Limit: $%.2f", MathAbs(remainingProfit), g_FloatingLimitValue));
         CloseAllPositions();
         
         // Stop trading until new day
         if(g_FloatingStopTrading)
         {
            g_FloatingLossTriggered = true;
            SysPrint("🛑 Trading STOPPED until new day!");
         }
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Detect Fast Reversal                                             |
//+------------------------------------------------------------------+
bool DetectFastReversal(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return false;
   
   double profit = PositionGetDouble(POSITION_PROFIT);
   double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   
   // === MINIMUM HOLDING TIME: 10 bars ===
   int barsSinceOpen = iBarShift(_Symbol, PERIOD_CURRENT, openTime);
   if(barsSinceOpen < 10)
      return false;
   
   // === MINIMUM LOSS: $3.00 sebelum RG aktif ===
   if(profit > -3.00)
      return false;
   
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentPrice = (type == POSITION_TYPE_BUY) ? bid : ask;
   
   // === Get ATR value from unified ATR engine ===
   double atrPrice = GetATR(0);
   if(atrPrice <= 0)
      return false;
   
   // === Get last 7 bars ===
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, 8, rates) < 8) return false;
   
   // === Count consecutive bars against ===
   int consecutiveAgainst = 0;
   double totalMoveAgainst = 0;
   
   for(int i = 1; i <= 6; i++)
   {
      bool barAgainst = false;
      double barMove = 0;
      
      if(type == POSITION_TYPE_BUY)
      {
         barAgainst = (rates[i].close < rates[i].open);
         barMove = rates[i].open - rates[i].close;
      }
      else
      {
         barAgainst = (rates[i].close > rates[i].open);
         barMove = rates[i].close - rates[i].open;
      }
      
      if(barAgainst)
      {
         consecutiveAgainst++;
         totalMoveAgainst += barMove;
      }
      else
      {
         break;
      }
   }
   
   // === Price distance from entry ===
   double moveFromEntry = 0;
   if(type == POSITION_TYPE_BUY)
      moveFromEntry = entryPrice - currentPrice;
   else
      moveFromEntry = currentPrice - entryPrice;
   
   // Skip if not losing
   if(moveFromEntry <= 0) return false;
   
   // === Thresholds ===
   double baseMultiplier = g_RGSensitivity + 0.5;
   
   double t1_threshold = atrPrice * 0.5;
   double t2_threshold = atrPrice * baseMultiplier;
   double t3_threshold = atrPrice * (baseMultiplier + 0.3);
   double t4_threshold = atrPrice * (baseMultiplier + 0.5);
   
   // === TRIGGER 1: 5+ consecutive bars + significant move ===
   if(consecutiveAgainst >= 5 && totalMoveAgainst > t1_threshold)
   {
      SysPrint(StringFormat("🛡️ RG-T1: %d bars, move=%.2f, loss=$%.2f", 
                  consecutiveAgainst, totalMoveAgainst, MathAbs(profit)));
      return true;
   }
   
   // === TRIGGER 2: 4 bars + move > 1.0 ATR ===
   if(consecutiveAgainst >= 4 && totalMoveAgainst > t2_threshold)
   {
      SysPrint(StringFormat("🛡️ RG-T2: 4 bars, move=%.2f > %.2f, loss=$%.2f", 
                  totalMoveAgainst, t2_threshold, MathAbs(profit)));
      return true;
   }
   
   // === TRIGGER 3: Big move (1.3 ATR) + strong acceleration ===
   if(moveFromEntry > t3_threshold)
   {
      double bar1Size = MathAbs(rates[1].close - rates[1].open);
      double bar2Size = MathAbs(rates[2].close - rates[2].open);
      
      if(bar1Size > bar2Size * 2.0 && consecutiveAgainst >= 3)
      {
         SysPrint(StringFormat("🛡️ RG-T3: Accelerating! move=%.2f, loss=$%.2f", 
                     moveFromEntry, MathAbs(profit)));
         return true;
      }
   }
   
   // === TRIGGER 4: Massive spike (1.5 ATR single bar) ===
   double lastBarMove = MathAbs(rates[1].close - rates[1].open);
   bool lastBarAgainst = (type == POSITION_TYPE_BUY) 
                         ? (rates[1].close < rates[1].open)
                         : (rates[1].close > rates[1].open);
   
   if(lastBarAgainst && lastBarMove > t4_threshold && consecutiveAgainst >= 2)
   {
      SysPrint(StringFormat("🛡️ RG-T4: Massive spike=%.2f, loss=$%.2f", 
                  lastBarMove, MathAbs(profit)));
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check and Close on Reversal                                      |
//+------------------------------------------------------------------+
void CheckAndCloseOnReversal()
{
   if(!g_EnableReversalGuard) return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != g_magicNumber) continue;
      
      if(DetectFastReversal(ticket))
      {
         SysPrint(StringFormat("🛡️ Reversal Guard: Closing position #%I64u", ticket));
         ClosePosition(ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| Max Drawdown Guard - Equity Based Protection                     |
//+------------------------------------------------------------------+
bool CheckMaxDrawdown()
{
   if(!g_EnableMaxDD) return true;
   
   // If already triggered and stop trading enabled, block
   if(g_MaxDDTriggered && g_MaxDDStopTrading)
   {
      return false;
   }
   
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Update equity high watermark
   if(equity > g_MaxDDEquityHigh)
      g_MaxDDEquityHigh = equity;
   
   // Calculate current drawdown from high
   double drawdown = g_MaxDDEquityHigh - equity;
   double ddPercent = (g_MaxDDEquityHigh > 0) ? (drawdown / g_MaxDDEquityHigh) * 100.0 : 0.0;
   
   // Check if drawdown exceeds threshold
   if(ddPercent >= g_MaxDDPercent)
   {
      SysPrint("🚨 MAX DRAWDOWN TRIGGERED!");
      SysPrint(StringFormat("   Equity High: %.2f", g_MaxDDEquityHigh));
      SysPrint(StringFormat("   Current Equity: %.2f", equity));
      SysPrint(StringFormat("   Drawdown: %.2f (%.2f%%)", drawdown, ddPercent));
      SysPrint(StringFormat("   Threshold: %.2f%%", g_MaxDDPercent));
      
      // Close all positions immediately
      CloseAllPositions();
      
      // Mark as triggered
      if(g_MaxDDStopTrading)
      {
         g_MaxDDTriggered = true;
         SysPrint("🛑 Trading STOPPED until new day!");
      }
      
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Reset All Daily Protection Flags (call on new day)               |
//+------------------------------------------------------------------+
void ResetAllDailyProtection()
{
   bool wasReset = false;
   
   // Reset Max DD
   if(g_MaxDDTriggered)
   {
      g_MaxDDTriggered = false;
      SysPrint("✅ Max DD flag reset");
      wasReset = true;
   }
   
   // Reset Floating Loss
   if(g_FloatingLossTriggered)
   {
      g_FloatingLossTriggered = false;
      SysPrint("✅ Floating Loss flag reset");
      wasReset = true;
   }
   
   // Reset Grid Tracking on new day
   ResetGridTracking();
   
   // Always update equity high on new day
   g_MaxDDEquityHigh = AccountInfoDouble(ACCOUNT_EQUITY);
   
   if(wasReset)
      SysPrint("✅ All protection flags reset for new day");
}

//+------------------------------------------------------------------+
//| Get Max DD Status for Dashboard                                  |
//+------------------------------------------------------------------+
string GetMaxDDStatus()
{
   if(!g_EnableMaxDD)
      return "📉 DD Guard: OFF";
   
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdown = g_MaxDDEquityHigh - equity;
   double ddPercent = (g_MaxDDEquityHigh > 0) ? (drawdown / g_MaxDDEquityHigh) * 100.0 : 0.0;
   
   if(g_MaxDDTriggered)
      return StringFormat("🚨 DD TRIGGERED! (%.1f%%)", ddPercent);
   
   string status = "";
   if(ddPercent >= g_MaxDDPercent * 0.8)
      status = StringFormat("⚠️ DD: %.1f%% / %.1f%% [WARNING]", ddPercent, g_MaxDDPercent);
   else if(ddPercent >= g_MaxDDPercent * 0.5)
      status = StringFormat("🟡 DD: %.1f%% / %.1f%%", ddPercent, g_MaxDDPercent);
   else
      status = StringFormat("🟢 DD: %.1f%% / %.1f%%", ddPercent, g_MaxDDPercent);
   
   return status;
}

//+------------------------------------------------------------------+
//| Get Floating Loss Status for Dashboard                           |
//+------------------------------------------------------------------+
string GetFloatingLossStatus()
{
   if(!g_EnableFloatingLimit)
      return "💰 Floating Limit: OFF";
   
   // Calculate current floating
   double floatingPL = 0;
   int posCount = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(!m_position.SelectByIndex(i)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != g_magicNumber) continue;
      floatingPL += PositionGetDouble(POSITION_PROFIT);
      posCount++;
   }
   
   if(g_FloatingLossTriggered)
      return StringFormat("🚨 FL TRIGGERED! ($%.2f)", floatingPL);
   
   if(posCount == 0)
      return StringFormat("🟢 Floating: $0 / $%.0f", g_FloatingLimitValue);
   
   if(floatingPL < 0)
   {
      double pct = (MathAbs(floatingPL) / g_FloatingLimitValue) * 100.0;
      if(pct >= 80)
         return StringFormat("⚠️ Floating: -$%.2f / $%.0f [WARNING]", MathAbs(floatingPL), g_FloatingLimitValue);
      else if(pct >= 50)
         return StringFormat("🟡 Floating: -$%.2f / $%.0f", MathAbs(floatingPL), g_FloatingLimitValue);
   }
   
   return StringFormat("🟢 Floating: $%.2f / $%.0f", floatingPL, g_FloatingLimitValue);
}

//+------------------------------------------------------------------+
//| Validate Entry - Check if entry position is ideal                |
//+------------------------------------------------------------------+
bool IsEntryValid(ENUM_ORDER_TYPE orderType)
{
   // ── Sell: M1 bearish confirmation ──
   if(orderType == ORDER_TYPE_SELL && g_RequireBearishM1Sell)
   {
      MqlRates m1[];
      ArraySetAsSeries(m1, true);
      if(CopyRates(_Symbol, PERIOD_CURRENT, 1, 1, m1) >= 1)
      {
         if(m1[0].close >= m1[0].open)
            { DebugPrint(StringFormat("⛔ M1 bearish wait (o=%.2f c=%.2f)", m1[0].open, m1[0].close)); return false; }
      }
   }

   // ── BUY: M1 bullish confirmation ──
   if(orderType == ORDER_TYPE_BUY && g_RequireBullishM1Buy)
   {
      MqlRates m1[];
      ArraySetAsSeries(m1, true);
      if(CopyRates(_Symbol, PERIOD_CURRENT, 1, 1, m1) >= 1)
      {
         if(m1[0].close <= m1[0].open)
            { DebugPrint(StringFormat("⛔ M1 bullish wait (o=%.2f c=%.2f)", m1[0].open, m1[0].close)); return false; }
      }
   }

   // ── RSI Check ──
   if(g_BlockOverbought || g_BlockOversold)
   {
      if(g_rsiHandle == INVALID_HANDLE) InitRSI();
      double rsiBuffer[];
      ArraySetAsSeries(rsiBuffer, true);
      if(CopyBuffer(g_rsiHandle, 0, 0, 1, rsiBuffer) >= 1)
      {
         double rsi = rsiBuffer[0];
         if(orderType == ORDER_TYPE_BUY  && g_BlockOverbought && rsi > 70)
            { DebugPrint(StringFormat("⛔ RSI BUY block: %.1f > 70", rsi)); return false; }
         if(orderType == ORDER_TYPE_BUY  && g_BlockOversold  && rsi < 30)
            { DebugPrint(StringFormat("⛔ RSI BUY block: %.1f < 30", rsi)); return false; }
         if(orderType == ORDER_TYPE_SELL && g_BlockOverbought && rsi > 70)
            { DebugPrint(StringFormat("⛔ RSI SELL block: %.1f > 70", rsi)); return false; }
      }
   }

   // ── Range Position Check (only if ValidateEntry = true) ──
   if(!g_ValidateEntry) return true;

   double highestHigh = 0, lowestLow = 999999;
   for(int i = 1; i <= g_RangeLookback; i++)
   {
      double h = iHigh(_Symbol, Period(), i);
      double l = iLow(_Symbol, Period(), i);
      if(h > highestHigh) highestHigh = h;
      if(l < lowestLow)   lowestLow   = l;
   }

   double range = highestHigh - lowestLow;
   if(range <= 0) return true;

   double currentPrice  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double pricePosition = (currentPrice - lowestLow) / range * 100;

   if(orderType == ORDER_TYPE_BUY && pricePosition >= g_BlockRangePercent)
      { DebugPrint(StringFormat("⛔ Range BUY block: price at %.0f%% > %.0f%%", pricePosition, g_BlockRangePercent)); return false; }
   if(orderType == ORDER_TYPE_SELL && pricePosition <= (100 - g_BlockRangePercent))
      { DebugPrint(StringFormat("⛔ Range SELL block: price at %.0f%%", pricePosition)); return false; }

   return true;
}

#endif
