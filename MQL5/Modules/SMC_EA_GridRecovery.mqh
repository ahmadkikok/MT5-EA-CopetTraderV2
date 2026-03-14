//+------------------------------------------------------------------+
//| SMC_EA_GridRecovery.mqh                                          |
//| Grid Recovery + Trailing BE System                               |
//| Version: 1.4 - FIXED (MinLock as BUMP, not trigger threshold)    |
//+------------------------------------------------------------------+
#ifndef __SMC_EA_GRIDRECOVERY_MQH__
#define __SMC_EA_GRIDRECOVERY_MQH__

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

// === EXTERN from Main EA ===
extern CTrade g_trade;
extern CPositionInfo m_position;
extern int    g_magicNumber;
extern double g_FixedTP;
extern bool   g_IgnoreManualTrades;

// === GRID SETTINGS ===
bool   g_EnableGridRecovery      = true;
double g_GridLockProfitTrigger   = 0.0;
bool   g_GridTrailFloatingOnly   = true;
double g_GridTrailStep           = 2.0;
bool   g_GridPerPosition         = true;
double g_GridMinLockPercent      = 0.0;

// === GRID TRACKING ===
double g_gridFirstEntryPrice = 0;
double g_gridHighestPrice    = 0;
double g_gridLowestPrice     = 999999;
double g_gridCommonTP        = 0;
bool   g_gridTrailingActive  = false;
int    g_gridDirection       = 0;
double g_gridLastBESetPrice  = 0;

//void ErrorPrint(string msg);
//void SysPrint(string msg);
//void DebugPrint(string msg);

//+------------------------------------------------------------------+
//| Initialize Grid Settings                                         |
//+------------------------------------------------------------------+
void InitGridRecovery(bool enable, double trailStep,
                      double lockTrigger, bool trailFloatingOnly, bool perPosition,
                      double minLockPercent)
{
   g_EnableGridRecovery = enable;
   g_GridTrailStep = trailStep;
   g_GridLockProfitTrigger = lockTrigger;
   g_GridTrailFloatingOnly = trailFloatingOnly;
   g_GridPerPosition = perPosition;
   g_GridMinLockPercent = minLockPercent;
   
   ResetGridTracking();
   
   if(g_EnableGridRecovery)
   {
      SysPrint(StringFormat("✅ Grid Recovery ON | Step=$%.2f | Lock=$%.2f | Float+=%s | Mode=%s | MinLock=%.0f%%", 
                  g_GridTrailStep, g_GridLockProfitTrigger,
                  g_GridTrailFloatingOnly ? "YES" : "NO",
                  g_GridPerPosition ? "PerPosition" : "GridHigh",
                  g_GridMinLockPercent));
   }
}

//+------------------------------------------------------------------+
//| Reset Grid Tracking                                              |
//+------------------------------------------------------------------+
void ResetGridTracking()
{
   g_gridFirstEntryPrice = 0;
   g_gridHighestPrice = 0;
   g_gridLowestPrice = 999999;
   g_gridCommonTP = 0;
   g_gridTrailingActive = false;
   g_gridDirection = 0;
   g_gridLastBESetPrice = 0;
}

//+------------------------------------------------------------------+
//| Convert Dollar to Price                                          |
//+------------------------------------------------------------------+
double GridConvertDollarToPrice(double dollarAmount, double volume)
{
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tickValue <= 0 || volume <= 0) return 0;
   
   return dollarAmount * tickSize / (tickValue * volume);
}

//+------------------------------------------------------------------+
//| Count Grid Positions                                             |
//+------------------------------------------------------------------+
int CountGridPositions(int direction)
{
   int count = 0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      
      long posMagic = (long)PositionGetInteger(POSITION_MAGIC);
      if(g_IgnoreManualTrades && posMagic != g_magicNumber) continue;
      
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      if(direction == 1 && posType != POSITION_TYPE_BUY) continue;
      if(direction == -1 && posType != POSITION_TYPE_SELL) continue;
      
      count++;
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| Get First Position Entry                                         |
//+------------------------------------------------------------------+
double GetFirstPositionEntry(int direction)
{
   double firstEntry = 0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      
      long posMagic = (long)PositionGetInteger(POSITION_MAGIC);
      if(g_IgnoreManualTrades && posMagic != g_magicNumber) continue;
      
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      if(direction == 1 && posType != POSITION_TYPE_BUY) continue;
      if(direction == -1 && posType != POSITION_TYPE_SELL) continue;
      
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      
      if(direction == 1)
      {
         if(entry > firstEntry || firstEntry == 0)
            firstEntry = entry;
      }
      else
      {
         if(entry < firstEntry || firstEntry == 0)
            firstEntry = entry;
      }
   }
   
   return firstEntry;
}

//+------------------------------------------------------------------+
//| Get Grid Total Volume                                            |
//+------------------------------------------------------------------+
double GetGridTotalVolume(int direction)
{
   double totalVolume = 0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      
      long posMagic = (long)PositionGetInteger(POSITION_MAGIC);
      if(g_IgnoreManualTrades && posMagic != g_magicNumber) continue;
      
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      if(direction == 1 && posType != POSITION_TYPE_BUY) continue;
      if(direction == -1 && posType != POSITION_TYPE_SELL) continue;
      
      totalVolume += PositionGetDouble(POSITION_VOLUME);
   }
   
   return totalVolume;
}

//+------------------------------------------------------------------+
//| Get Average Entry Price                                          |
//+------------------------------------------------------------------+
double GetGridAverageEntry(int direction)
{
   double totalValue = 0;
   double totalVolume = 0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      
      long posMagic = (long)PositionGetInteger(POSITION_MAGIC);
      if(g_IgnoreManualTrades && posMagic != g_magicNumber) continue;
      
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      if(direction == 1 && posType != POSITION_TYPE_BUY) continue;
      if(direction == -1 && posType != POSITION_TYPE_SELL) continue;
      
      double volume = PositionGetDouble(POSITION_VOLUME);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      
      totalValue += entry * volume;
      totalVolume += volume;
   }
   
   if(totalVolume <= 0) return 0;
   return totalValue / totalVolume;
}

//+------------------------------------------------------------------+
//| Get Grid Floating Profit                                         |
//+------------------------------------------------------------------+
double GetGridFloatingProfit(int direction)
{
   double totalProfit = 0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      
      long posMagic = (long)PositionGetInteger(POSITION_MAGIC);
      if(g_IgnoreManualTrades && posMagic != g_magicNumber) continue;
      
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      if(direction == 1 && posType != POSITION_TYPE_BUY) continue;
      if(direction == -1 && posType != POSITION_TYPE_SELL) continue;
      
      totalProfit += PositionGetDouble(POSITION_PROFIT);
   }
   
   return totalProfit;
}

//+------------------------------------------------------------------+
//| Modify Grid Positions SL - FIXED with MinLock                    |
//+------------------------------------------------------------------+
void ModifyGridPositionsSL(int direction, double newSL, double stepPrice = 0)
{
   int modified = 0;
   int skipped = 0;
   
   // Calculate minimum lock price based on percentage
   double minLockPrice = 0;
   if(stepPrice > 0 && g_GridMinLockPercent > 0)
      minLockPrice = stepPrice * (g_GridMinLockPercent / 100.0);
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      
      long posMagic = (long)PositionGetInteger(POSITION_MAGIC);
      if(g_IgnoreManualTrades && posMagic != g_magicNumber) continue;
      
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      if(direction == 1 && posType != POSITION_TYPE_BUY) continue;
      if(direction == -1 && posType != POSITION_TYPE_SELL) continue;
      
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      double posProfit = PositionGetDouble(POSITION_PROFIT);
      double posEntry  = PositionGetDouble(POSITION_PRICE_OPEN);
      
      // FLOATING+ ONLY CHECK
      if(g_GridTrailFloatingOnly && posProfit <= 0)
      {
         skipped++;
         continue;
      }
      
      // SAFETY CHECK: Skip if newSL worse than entry
      if(direction == 1 && newSL < posEntry)
      {
         skipped++;
         continue;
      }
      if(direction == -1 && newSL > posEntry)
      {
         skipped++;
         continue;
      }
      
      // MIN LOCK: Bump BE if too close to entry
      double finalBE = newSL;
      
      if(minLockPrice > 0)
      {
         double minBE = 0;
         if(direction == 1)
            minBE = posEntry + minLockPrice;
         else
            minBE = posEntry - minLockPrice;
         
         if(direction == 1 && newSL < minBE)
            finalBE = minBE;
         if(direction == -1 && newSL > minBE)
            finalBE = minBE;
      }
      
      bool shouldModify = false;
      
      if(direction == 1)
         shouldModify = (finalBE > currentSL || currentSL == 0);
      else
         shouldModify = (finalBE < currentSL || currentSL == 0);
      
      if(shouldModify)
      {
         finalBE = NormalizeDouble(finalBE, _Digits);
         if(g_trade.PositionModify(ticket, finalBE, currentTP))
         {
            modified++;
            DebugPrint(StringFormat("🔒 Grid BE: #%I64u | Entry=%.3f | BE=%.3f | Profit=$%.2f", 
                           ticket, posEntry, finalBE, posProfit));
         }
      }
   }
   
   if(modified > 0)
      SysPrint(StringFormat("🔒 Grid BE Update: Modified=%d | Skipped=%d | MinLock=%.0f%%", 
                  modified, skipped, g_GridMinLockPercent));
}

//+------------------------------------------------------------------+
//| Close Grid Positions                                             |
//+------------------------------------------------------------------+
void CloseGridPositions(int direction)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      
      long posMagic = (long)PositionGetInteger(POSITION_MAGIC);
      if(g_IgnoreManualTrades && posMagic != g_magicNumber) continue;
      
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      if(direction == 1 && posType != POSITION_TYPE_BUY) continue;
      if(direction == -1 && posType != POSITION_TYPE_SELL) continue;
      
      g_trade.PositionClose(ticket);
   }
}

//+------------------------------------------------------------------+
//| Check if Grid Active                                             |
//+------------------------------------------------------------------+
bool IsGridActive(int direction)
{
   if(!g_EnableGridRecovery) return false;
   return (CountGridPositions(direction) >= 2);
}

//+------------------------------------------------------------------+
//| Trail Per-Position Mode - FIXED (MinLock as BUMP not threshold)  |
//+------------------------------------------------------------------+
void TrailPerPosition(int direction)
{
   string dirStr = (direction == 1) ? "BUY" : "SELL";
   int modified = 0;
   int skipped = 0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      
      long posMagic = (long)PositionGetInteger(POSITION_MAGIC);
      if(g_IgnoreManualTrades && posMagic != g_magicNumber) continue;
      
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      if(direction == 1 && posType != POSITION_TYPE_BUY) continue;
      if(direction == -1 && posType != POSITION_TYPE_SELL) continue;
      
      double posEntry  = PositionGetDouble(POSITION_PRICE_OPEN);
      double posProfit = PositionGetDouble(POSITION_PROFIT);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      double posVolume = PositionGetDouble(POSITION_VOLUME);
      
      // FloatOnly logic
      if(g_GridTrailFloatingOnly && posProfit <= 0)
      {
         skipped++;
         continue;
      }
      
      // Convert step to price
      double stepPrice = GridConvertDollarToPrice(g_GridTrailStep, posVolume);
      
      // ✅ FIXED: Use FULL step, not 75% (must reach TrailStep to set BE)
      int stepsReached = (int)MathFloor(posProfit / g_GridTrailStep);
      
      // ✅ FIXED: SKIP if no full step reached (original behavior)
      if(stepsReached < 1)
      {
         skipped++;
         continue;  // Must reach $4 before setting BE
      }
      
      // Calculate BE: entry + (steps - 1) * stepPrice
      // Step 1 → BE at entry
      // Step 2 → BE at entry + 1 step
      double newBE = 0;
      
      if(direction == 1)
         newBE = posEntry + ((stepsReached - 1) * stepPrice);
      else
         newBE = posEntry - ((stepsReached - 1) * stepPrice);
      
      // ✅ NOW Apply MinLock as BUMP (not threshold!)
      // MinLock = minimum distance from entry
      if(g_GridMinLockPercent > 0)
      {
         double minLockPrice = stepPrice * (g_GridMinLockPercent / 100.0);
         double minBE = 0;
         
         if(direction == 1)
            minBE = posEntry + minLockPrice;
         else
            minBE = posEntry - minLockPrice;
         
         // Bump BE if below minimum
         if(direction == 1 && newBE < minBE)
         {
            DebugPrint(StringFormat("⬆️ PerPos MinLock: Bump %.5f → %.5f (%.0f%%)", 
                           newBE, minBE, g_GridMinLockPercent));
            newBE = minBE;
         }
         if(direction == -1 && newBE > minBE)
         {
            DebugPrint(StringFormat("⬇️ PerPos MinLock: Bump %.5f → %.5f (%.0f%%)", 
                           newBE, minBE, g_GridMinLockPercent));
            newBE = minBE;
         }
      }
      
      newBE = NormalizeDouble(newBE, _Digits);
      
      // Safety: Don't set BE worse than entry
      if(direction == 1 && newBE < posEntry)
         newBE = posEntry;
      if(direction == -1 && newBE > posEntry)
         newBE = posEntry;
      
      // Check if should modify
      bool shouldModify = false;
      
      if(currentSL == 0.0)
      {
         shouldModify = true;
      }
      else
      {
         if(direction == 1)
            shouldModify = (newBE > currentSL);
         else
            shouldModify = (newBE < currentSL);
      }
      
      if(shouldModify)
      {
         if(g_trade.PositionModify(ticket, newBE, currentTP))
         {
            modified++;
            SysPrint(StringFormat("📍 PerPos BE: %s #%I64u | Entry=%.5f | Profit=$%.2f | Steps=%d | BE=%.5f", 
                        dirStr, ticket, posEntry, posProfit, stepsReached, newBE));
         }
      }
      else
      {
         skipped++;
      }
   }
   
   if(modified > 0 || skipped > 0)
      SysPrint(StringFormat("🔄 PerPos %s: Modified=%d | Skipped=%d", dirStr, modified, skipped));
}

//+------------------------------------------------------------------+
//| Manage Grid Direction - FIXED VERSION                            |
//+------------------------------------------------------------------+
void ManageGridDirection(int direction, int posCount)
{
   string dirStr = (direction == 1) ? "BUY" : "SELL";
   
   double totalVolume = GetGridTotalVolume(direction);
   double avgEntry = GetGridAverageEntry(direction);
   double floatingProfit = GetGridFloatingProfit(direction);
   double singleLot = (posCount > 0) ? totalVolume / posCount : 0.01;
   
   // Initialize Grid
   if(g_gridDirection != direction || g_gridFirstEntryPrice == 0)
   {
      g_gridDirection = direction;
      g_gridFirstEntryPrice = GetFirstPositionEntry(direction);
      g_gridTrailingActive = (g_GridLockProfitTrigger <= 0);
      g_gridLastBESetPrice = 0;
      
      double tpDistance = GridConvertDollarToPrice(g_FixedTP, singleLot);
      
      if(direction == 1)
         g_gridCommonTP = g_gridFirstEntryPrice + tpDistance;
      else
         g_gridCommonTP = g_gridFirstEntryPrice - tpDistance;
      
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      g_gridHighestPrice = bid;
      g_gridLowestPrice = ask;
      
      SysPrint(StringFormat("📊 Grid %s: Pos=%d | First=%.5f | Avg=%.5f | TP=%.5f | Step=$%.2f",  
                  dirStr, posCount, g_gridFirstEntryPrice, avgEntry, g_gridCommonTP, g_GridTrailStep));
   }
   
   // Get Current Price
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentPrice = (direction == 1) ? bid : ask;
   
   // Check TP Reached
   bool tpReached = (direction == 1) ? (bid >= g_gridCommonTP) : (ask <= g_gridCommonTP);
   
   if(tpReached)
   {
      SysPrint(StringFormat("🎯 Grid %s TP REACHED! Price=%.5f | TP=%.5f | Profit=$%.2f", 
                  dirStr, currentPrice, g_gridCommonTP, floatingProfit));
      CloseGridPositions(direction);
      ResetGridTracking();
      return;
   }
   
   // Activate Trailing
   if(!g_gridTrailingActive && g_GridLockProfitTrigger > 0)
   {
      if(floatingProfit >= g_GridLockProfitTrigger)
      {
         g_gridTrailingActive = true;
         SysPrint(StringFormat("🔓 Grid %s Trail ON! Total=$%.2f >= $%.2f",  
                     dirStr, floatingProfit, g_GridLockProfitTrigger));
      }
   }
   
   // Trail BE - FIXED VERSION
   if(g_gridTrailingActive)
   {
      double stepPrice = GridConvertDollarToPrice(g_GridTrailStep, singleLot);
      
      // FIX: Grid-High triggers setiap price bergerak 1 FULL step dari last BE
      // (bukan 25% — itu sama aja kayak PerPosition, terlalu sering)
      double minStepTrigger = stepPrice;
      
      if(direction == 1)  // BUY
      {
         if(bid > g_gridHighestPrice)
         {
            g_gridHighestPrice = bid;
            
            bool shouldUpdateBE = false;
            
            // FIX: First time ALWAYS set BE
            if(g_gridLastBESetPrice == 0)
            {
               shouldUpdateBE = true;
               SysPrint(StringFormat("🔓 Grid BUY: First BE set | High=%.5f", g_gridHighestPrice));
            }
            else
            {
               double priceMovement = g_gridHighestPrice - g_gridLastBESetPrice;
               if(priceMovement >= minStepTrigger)
               {
                  shouldUpdateBE = true;
                  DebugPrint(StringFormat("📈 Grid BUY: Movement %.5f >= 1 Step %.5f", 
                                 priceMovement, minStepTrigger));
               }
            }
            
            if(shouldUpdateBE)
            {
               double newBE = g_gridHighestPrice - stepPrice;
               
               // Safety: Ensure BE not below lowest entry
               double lowestEntry = 999999;
               for(int i = 0; i < PositionsTotal(); i++)
               {
                  ulong ticket = PositionGetTicket(i);
                  if(!PositionSelectByTicket(ticket)) continue;
                  if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
                  
                  long posMagic = (long)PositionGetInteger(POSITION_MAGIC);
                  if(g_IgnoreManualTrades && posMagic != g_magicNumber) continue;
                  
                  ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                  if(posType != POSITION_TYPE_BUY) continue;
                  
                  double entry = PositionGetDouble(POSITION_PRICE_OPEN);
                  if(entry < lowestEntry)
                     lowestEntry = entry;
               }
               
               if(newBE < lowestEntry)
                  newBE = lowestEntry;
               
               SysPrint(StringFormat("📈 Grid BUY Step: High=%.5f | LastBE=%.5f | NewBE=%.5f", 
                           g_gridHighestPrice, g_gridLastBESetPrice, newBE));
               
               ModifyGridPositionsSL(direction, newBE, stepPrice);
               g_gridLastBESetPrice = g_gridHighestPrice;
            }
         }
      }
      else  // SELL
      {
         if(ask < g_gridLowestPrice)
         {
            g_gridLowestPrice = ask;
            
            bool shouldUpdateBE = false;
            
            // FIX: First time ALWAYS set BE
            if(g_gridLastBESetPrice == 0)
            {
               shouldUpdateBE = true;
               SysPrint(StringFormat("🔓 Grid SELL: First BE set | Low=%.5f", g_gridLowestPrice));
            }
            else
            {
               double priceMovement = g_gridLastBESetPrice - g_gridLowestPrice;
               if(priceMovement >= minStepTrigger)
               {
                  shouldUpdateBE = true;
                  DebugPrint(StringFormat("📉 Grid SELL: Movement %.5f >= 1 Step %.5f", 
                                 priceMovement, minStepTrigger));
               }
            }
            
            if(shouldUpdateBE)
            {
               double newBE = g_gridLowestPrice + stepPrice;
               
               // Safety: Ensure BE not above highest entry
               double highestEntry = 0;
               for(int i = 0; i < PositionsTotal(); i++)
               {
                  ulong ticket = PositionGetTicket(i);
                  if(!PositionSelectByTicket(ticket)) continue;
                  if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
                  
                  long posMagic = (long)PositionGetInteger(POSITION_MAGIC);
                  if(g_IgnoreManualTrades && posMagic != g_magicNumber) continue;
                  
                  ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                  if(posType != POSITION_TYPE_SELL) continue;
                  
                  double entry = PositionGetDouble(POSITION_PRICE_OPEN);
                  if(entry > highestEntry)
                     highestEntry = entry;
               }
               
               if(newBE > highestEntry)
                  newBE = highestEntry;
               
               SysPrint(StringFormat("📉 Grid SELL Step: Low=%.5f | LastBE=%.5f | NewBE=%.5f", 
                           g_gridLowestPrice, g_gridLastBESetPrice, newBE));
               
               ModifyGridPositionsSL(direction, newBE, stepPrice);
               g_gridLastBESetPrice = g_gridLowestPrice;
            }
         }
      }
      
      // Force BE check for stagnant grids
      if(g_gridLastBESetPrice == 0 && floatingProfit > g_GridTrailStep)
      {
         double avgEntry = GetGridAverageEntry(direction);
         
         SysPrint(StringFormat("⚡ Grid %s: Force BE at entry | Profit=$%.2f", 
                     dirStr, floatingProfit));
         
         ModifyGridPositionsSL(direction, avgEntry, stepPrice);
         g_gridLastBESetPrice = (direction == 1) ? g_gridHighestPrice : g_gridLowestPrice;
      }
   }
}

//+------------------------------------------------------------------+
//| MAIN: Manage Grid Recovery                                       |
//+------------------------------------------------------------------+
void ManageGridRecovery()
{
   if(!g_EnableGridRecovery) return;
   
   int buyCount = CountGridPositions(1);
   int sellCount = CountGridPositions(-1);
   
   // Minimal 2 posisi untuk grid mode aktif
   if(buyCount >= 2)
   {
      if(g_GridPerPosition)
         TrailPerPosition(1);
      else
         ManageGridDirection(1, buyCount);
   }
   
   if(sellCount >= 2)
   {
      if(g_GridPerPosition)
         TrailPerPosition(-1);
      else
         ManageGridDirection(-1, sellCount);
   }
   
   // Reset tracking untuk GridHigh mode
   if(!g_GridPerPosition && buyCount < 2 && sellCount < 2 && g_gridDirection != 0)
   {
      DebugPrint("🔄 Grid Reset");
      ResetGridTracking();
   }
}

//+------------------------------------------------------------------+
//| Get Grid Status for Dashboard                                    |
//+------------------------------------------------------------------+
string GetGridRecoveryStatus()
{
   if(!g_EnableGridRecovery) return "Grid: OFF";
   
   int buyCount = CountGridPositions(1);
   int sellCount = CountGridPositions(-1);
   
   if(buyCount < 2 && sellCount < 2)
      return "Grid: Standby";
   
   string status = "Grid: ";
   
   if(buyCount >= 2)
   {
      double profit = GetGridFloatingProfit(1);
      string trail = (g_gridTrailingActive && g_gridDirection == 1) ? "🔓" : "";
      status += StringFormat("BUY[%d]:$%.1f%s", buyCount, profit, trail);
   }
   
   if(sellCount >= 2)
   {
      if(buyCount >= 2) status += " | ";
      double profit = GetGridFloatingProfit(-1);
      string trail = (g_gridTrailingActive && g_gridDirection == -1) ? "🔓" : "";
      status += StringFormat("SELL[%d]:$%.1f%s", sellCount, profit, trail);
   }
   
   return status;
}

#endif