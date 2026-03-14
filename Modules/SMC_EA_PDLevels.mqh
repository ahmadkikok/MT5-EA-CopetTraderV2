//+------------------------------------------------------------------+
//| SMC_EA_PDLevels.mqh                                              |
//| Previous Day High/Low - Key Liquidity Levels                     |
//+------------------------------------------------------------------+
#ifndef __SMC_EA_PDLEVELS_MQH__
#define __SMC_EA_PDLEVELS_MQH__

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
double g_PDH = 0.0;                    // Previous Day High
double g_PDL = 0.0;                    // Previous Day Low
double g_PWH = 0.0;                    // Previous Week High
double g_PWL = 0.0;                    // Previous Week Low
datetime g_lastPDUpdate = 0;           // Last update time
// ─── Margin-Safety externs (set from main EA) ───
extern bool   g_EnablePDMarginCheck;
extern double g_PDMarginBuffer;
extern double g_PDMaxRangePercent;
extern double g_lot;

//void ErrorPrint(string msg);
//void SysPrint(string msg);
//void DebugPrint(string msg);

//+------------------------------------------------------------------+
//| Update PDL/PDH Levels (Daily)                                    |
//+------------------------------------------------------------------+
void UpdatePDLevels()
{
   MqlRates daily[];
   ArraySetAsSeries(daily, true);
   
   // Get yesterday's candle (index 1 = yesterday, 0 = today)
   if(CopyRates(_Symbol, PERIOD_D1, 1, 1, daily) == 1)
   {
      g_PDH = daily[0].high;
      g_PDL = daily[0].low;
      
      SysPrint(StringFormat("📊 PDL/PDH Updated: PDH=%.5f | PDL=%.5f", g_PDH, g_PDL));
   }
   else
   {
      DebugPrint("⚠️ Failed to get PDL/PDH data");
   }
}

//+------------------------------------------------------------------+
//| Update PWL/PWH Levels (Weekly)                                   |
//+------------------------------------------------------------------+
void UpdatePWLevels()
{
   MqlRates weekly[];
   ArraySetAsSeries(weekly, true);
   
   // Get last week's candle
   if(CopyRates(_Symbol, PERIOD_W1, 1, 1, weekly) == 1)
   {
      g_PWH = weekly[0].high;
      g_PWL = weekly[0].low;
      
      SysPrint(StringFormat("📊 PWL/PWH Updated: PWH=%.5f | PWL=%.5f", g_PWH, g_PWL));
   }
}

//+------------------------------------------------------------------+
//| Check if needs update (call this in OnTick)                      |
//+------------------------------------------------------------------+
void CheckAndUpdatePDLevels()
{
   datetime now = TimeCurrent();
   
   // Update once per day (check if new day started)
   datetime todayStart = now - (now % 86400); // Start of today 00:00
   
   if(g_lastPDUpdate == 0 || g_lastPDUpdate < todayStart)
   {
      UpdatePDLevels();
      UpdatePWLevels();
      g_lastPDUpdate = now;
      
      // Draw levels on chart
      DrawPDLevels();
   }
}

//+------------------------------------------------------------------+
//| Check if price is near PDH                                       |
//+------------------------------------------------------------------+
bool IsNearPDH(double price, double tolerancePoints = 50.0)
{
   if(g_PDH == 0.0) return false;
   
   double distance = MathAbs(price - g_PDH);
   double tolerance = tolerancePoints * _Point;
   
   return (distance <= tolerance);
}

//+------------------------------------------------------------------+
//| Check if price is near PDL                                       |
//+------------------------------------------------------------------+
bool IsNearPDL(double price, double tolerancePoints = 50.0)
{
   if(g_PDL == 0.0) return false;
   
   double distance = MathAbs(price - g_PDL);
   double tolerance = tolerancePoints * _Point;
   
   return (distance <= tolerance);
}

//+------------------------------------------------------------------+
//| Check if price is near PWH                                       |
//+------------------------------------------------------------------+
bool IsNearPWH(double price, double tolerancePoints = 100.0)
{
   if(g_PWH == 0.0) return false;
   
   double distance = MathAbs(price - g_PWH);
   double tolerance = tolerancePoints * _Point;
   
   return (distance <= tolerance);
}

//+------------------------------------------------------------------+
//| Check if price is near PWL                                       |
//+------------------------------------------------------------------+
bool IsNearPWL(double price, double tolerancePoints = 100.0)
{
   if(g_PWL == 0.0) return false;
   
   double distance = MathAbs(price - g_PWL);
   double tolerance = tolerancePoints * _Point;
   
   return (distance <= tolerance);
}

//+------------------------------------------------------------------+
//| Get PD Zone State (-1=below PDL, 0=between, 1=above PDH)         |
//+------------------------------------------------------------------+
int GetPDZoneState(double price)
{
   if(g_PDH == 0.0 || g_PDL == 0.0) return 0;
   
   if(price > g_PDH) return 1;       // Above PDH (premium)
   if(price < g_PDL) return -1;      // Below PDL (discount)
   return 0;                          // Between PDL-PDH
}

//+------------------------------------------------------------------+
//| Check PDL/PDH Confluence with Order Block                        |
//+------------------------------------------------------------------+
bool HasPDConfluence(bool isBuySetup, double price, double maxRangePercent = 30.0)
{
   // Convert % to points tolerance
   // Use same % logic: if price within X% of PDL/PDH edge
   if(g_PDH == 0.0 || g_PDL == 0.0) return false;
   
   double range = g_PDH - g_PDL;
   double tolerancePoints = range * maxRangePercent / 100.0 / _Point;
   
   if(isBuySetup)
   {
      // BUY Setup: Look for confluence with PDL (support)
      if(IsNearPDL(price, tolerancePoints))
      {
         SysPrint(StringFormat("✅ BUY Confluence: Price %.5f near PDL %.5f (tolerance=%.0f pts)", price, g_PDL, tolerancePoints));
         return true;
      }
      
      // Also check PWL for stronger support
      if(IsNearPWL(price, tolerancePoints * 2))
      {
         SysPrint(StringFormat("✅ BUY Confluence: Price %.5f near PWL %.5f (STRONG)", price, g_PWL));
         return true;
      }
   }
   else
   {
      // SELL Setup: Look for confluence with PDH (resistance)
      if(IsNearPDH(price, tolerancePoints))
      {
         SysPrint(StringFormat("✅ SELL Confluence: Price %.5f near PDH %.5f (tolerance=%.0f pts)", price, g_PDH, tolerancePoints));
         return true;
      }
      
      // Also check PWH for stronger resistance
      if(IsNearPWH(price, tolerancePoints * 2))
      {
         SysPrint(StringFormat("✅ SELL Confluence: Price %.5f near PWH %.5f (STRONG)", price, g_PWH));
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Block Bad Entries (BUY near PDH, SELL near PDL)                  |
//+------------------------------------------------------------------+
bool IsPDLevelBlocking(ENUM_ORDER_TYPE orderType, double price, double maxRangePercent = 30.0)
{
   if(g_PDH == 0.0 || g_PDL == 0.0) return false;

   // ── Calculate PD range ──
   double range = g_PDH - g_PDL;
   if(range <= 0.0) return false;

   // ── Calculate allowed zones (% from edges) ──
   double buyZoneTop  = g_PDL + (range * maxRangePercent / 100.0);   // Lower X% = BUY zone
   double sellZoneBot = g_PDH - (range * maxRangePercent / 100.0);   // Upper X% = SELL zone

   // ══════════════════════════════════════════════════════════════
   // LOGIC:
   // BUY allowed  → price in LOWER zone (≤ buyZoneTop)
   // SELL allowed → price in UPPER zone (≥ sellZoneBot)
   // Middle zone  → BLOCKED for both
   // ══════════════════════════════════════════════════════════════

   if(orderType == ORDER_TYPE_BUY)
   {
      if(price > buyZoneTop)
      {
         DebugPrint(StringFormat("⛔ BUY BLOCKED (PD Zone) | Entry=%.2f > BuyZone=%.2f | PDL=%.2f | PDH=%.2f | Range=%.0f pts | MaxPercent=%.0f%%",
                     price, buyZoneTop, g_PDL, g_PDH, range / _Point, maxRangePercent));
         return true;  // BLOCK
      }

      DebugPrint(StringFormat("✅ BUY Allowed (PD Zone) | Entry=%.2f ≤ BuyZone=%.2f | PDL=%.2f | Range=%.0f pts",
                  price, buyZoneTop, g_PDL, range / _Point));
   }
   else if(orderType == ORDER_TYPE_SELL)
   {
      if(price < sellZoneBot)
      {
         DebugPrint(StringFormat("⛔ SELL BLOCKED (PD Zone) | Entry=%.2f < SellZone=%.2f | PDH=%.2f | PDL=%.2f | Range=%.0f pts | MaxPercent=%.0f%%",
                     price, sellZoneBot, g_PDH, g_PDL, range / _Point, maxRangePercent));
         return true;  // BLOCK
      }

      DebugPrint(StringFormat("✅ SELL Allowed (PD Zone) | Entry=%.2f ≥ SellZone=%.2f | PDH=%.2f | Range=%.0f pts",
                  price, sellZoneBot, g_PDH, range / _Point));
   }

   return false;  // ALLOWED
}

//+------------------------------------------------------------------+
//| Draw PDL/PDH Levels on Chart                                     |
//+------------------------------------------------------------------+
void DrawPDLevels()
{
   // Delete old lines
   ObjectDelete(0, "PDH_LINE");
   ObjectDelete(0, "PDL_LINE");
   ObjectDelete(0, "PWH_LINE");
   ObjectDelete(0, "PWL_LINE");
   ObjectDelete(0, "PDH_LABEL");
   ObjectDelete(0, "PDL_LABEL");
   ObjectDelete(0, "PWH_LABEL");
   ObjectDelete(0, "PWL_LABEL");
   
   if(g_PDH == 0.0 || g_PDL == 0.0) return;
   
   // PDH Line (Red - Resistance)
   ObjectCreate(0, "PDH_LINE", OBJ_HLINE, 0, 0, g_PDH);
   ObjectSetInteger(0, "PDH_LINE", OBJPROP_COLOR, clrCrimson);
   ObjectSetInteger(0, "PDH_LINE", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, "PDH_LINE", OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, "PDH_LINE", OBJPROP_BACK, false);
   
   // PDH Label
   ObjectCreate(0, "PDH_LABEL", OBJ_TEXT, 0, TimeCurrent(), g_PDH);
   ObjectSetString(0, "PDH_LABEL", OBJPROP_TEXT, StringFormat("  PDH: %.5f", g_PDH));
   ObjectSetInteger(0, "PDH_LABEL", OBJPROP_COLOR, clrCrimson);
   ObjectSetInteger(0, "PDH_LABEL", OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, "PDH_LABEL", OBJPROP_ANCHOR, ANCHOR_LEFT);
   
   // PDL Line (Green - Support)
   ObjectCreate(0, "PDL_LINE", OBJ_HLINE, 0, 0, g_PDL);
   ObjectSetInteger(0, "PDL_LINE", OBJPROP_COLOR, clrLimeGreen);
   ObjectSetInteger(0, "PDL_LINE", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, "PDL_LINE", OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, "PDL_LINE", OBJPROP_BACK, false);
   
   // PDL Label
   ObjectCreate(0, "PDL_LABEL", OBJ_TEXT, 0, TimeCurrent(), g_PDL);
   ObjectSetString(0, "PDL_LABEL", OBJPROP_TEXT, StringFormat("  PDL: %.5f", g_PDL));
   ObjectSetInteger(0, "PDL_LABEL", OBJPROP_COLOR, clrLimeGreen);
   ObjectSetInteger(0, "PDL_LABEL", OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, "PDL_LABEL", OBJPROP_ANCHOR, ANCHOR_LEFT);
   
   // PWH Line (Dark Red - Weekly Resistance)
   if(g_PWH > 0)
   {
      ObjectCreate(0, "PWH_LINE", OBJ_HLINE, 0, 0, g_PWH);
      ObjectSetInteger(0, "PWH_LINE", OBJPROP_COLOR, clrDarkRed);
      ObjectSetInteger(0, "PWH_LINE", OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, "PWH_LINE", OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, "PWH_LINE", OBJPROP_BACK, true);
      
      ObjectCreate(0, "PWH_LABEL", OBJ_TEXT, 0, TimeCurrent(), g_PWH);
      ObjectSetString(0, "PWH_LABEL", OBJPROP_TEXT, StringFormat("  PWH: %.5f", g_PWH));
      ObjectSetInteger(0, "PWH_LABEL", OBJPROP_COLOR, clrDarkRed);
      ObjectSetInteger(0, "PWH_LABEL", OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, "PWH_LABEL", OBJPROP_ANCHOR, ANCHOR_LEFT);
   }
   
   // PWL Line (Dark Green - Weekly Support)
   if(g_PWL > 0)
   {
      ObjectCreate(0, "PWL_LINE", OBJ_HLINE, 0, 0, g_PWL);
      ObjectSetInteger(0, "PWL_LINE", OBJPROP_COLOR, clrDarkGreen);
      ObjectSetInteger(0, "PWL_LINE", OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, "PWL_LINE", OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, "PWL_LINE", OBJPROP_BACK, true);
      
      ObjectCreate(0, "PWL_LABEL", OBJ_TEXT, 0, TimeCurrent(), g_PWL);
      ObjectSetString(0, "PWL_LABEL", OBJPROP_TEXT, StringFormat("  PWL: %.5f", g_PWL));
      ObjectSetInteger(0, "PWL_LABEL", OBJPROP_COLOR, clrDarkGreen);
      ObjectSetInteger(0, "PWL_LABEL", OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, "PWL_LABEL", OBJPROP_ANCHOR, ANCHOR_LEFT);
   }
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Cleanup PD Objects                                               |
//+------------------------------------------------------------------+
void CleanupPDLevels()
{
   ObjectDelete(0, "PDH_LINE");
   ObjectDelete(0, "PDL_LINE");
   ObjectDelete(0, "PWH_LINE");
   ObjectDelete(0, "PWL_LINE");
   ObjectDelete(0, "PDH_LABEL");
   ObjectDelete(0, "PDL_LABEL");
   ObjectDelete(0, "PWH_LABEL");
   ObjectDelete(0, "PWL_LABEL");
}

//+------------------------------------------------------------------+
//| Get PD Status for Dashboard                                      |
//+------------------------------------------------------------------+
string GetPDStatus()
{
   if(g_PDH == 0.0 || g_PDL == 0.0)
      return "📊 PD Levels: Loading...";
   
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int zone = GetPDZoneState(bid);
   
   string zoneStr = "";
   if(zone == 1) zoneStr = "🔴 Above PDH";
   else if(zone == -1) zoneStr = "🟢 Below PDL";
   else zoneStr = "🟡 Between";
   
   return StringFormat("📊 PDH:%.5f | PDL:%.5f | %s", g_PDH, g_PDL, zoneStr);
}

//+------------------------------------------------------------------+
//| PD Entry Position Safety Check (Dynamic Margin-Based)            |
//| Returns TRUE when entry price has enough "breathing room" to PDL |
//| (for BUY) or PDH (for SELL) relative to margin call distance.    |
//+------------------------------------------------------------------+
bool IsPDSpreadSafeForMargin(double lotSize, ENUM_ORDER_TYPE orderType, double entryPrice)
{
   // Skip if disabled or PD levels not loaded
   if(!g_EnablePDMarginCheck) return true;
   if(g_PDH == 0.0 || g_PDL == 0.0) return true;

   // ── Calculate point value ($/point/lot) ──
   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize == 0.0 || tickValue == 0.0) return true;   // can't calc → allow

   double pointValuePerLot = tickValue / tickSize * _Point;

   // ── Margin call distance (how many points price can move before MC) ──
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(freeMargin <= 0.0) return false;   // no margin → block

   double marginCallDistance = freeMargin / (pointValuePerLot * lotSize);

   // ── Required safe distance (margin call distance × safety ratio) ──
   double requiredDistance = marginCallDistance * g_PDMarginBuffer;

   // ── Check entry position safety ──
   if(orderType == ORDER_TYPE_BUY)
   {
      // BUY: check distance to PDL (downside risk)
      // Positive = entry above PDL (need safety check)
      // Negative = entry below PDL (SAFE - buying at discount)
      double distanceToPDL = (entryPrice - g_PDL) / _Point;
      
      // Entry BELOW PDL → Always safe for BUY (buying cheaper than previous day low)
      if(distanceToPDL < 0.0)
      {
         DebugPrint(StringFormat("✅ BUY Safe (Below PDL) | Entry=%.5f < PDL=%.5f | Distance=%.0f pts | Free=$%.2f",
                     entryPrice, g_PDL, distanceToPDL, freeMargin));
         return true;
      }
      
      // Entry ABOVE PDL → Check if too close to margin call
      if(distanceToPDL < requiredDistance)
      {
         double potentialLoss = distanceToPDL * pointValuePerLot * lotSize;
         SysPrint(StringFormat("⛔ BUY BLOCKED (PD Margin Safety) | Entry=%.5f | PDL=%.5f | Distance=%.0f pts | PotentialLoss=$%.2f | Required=%.0f pts (MC dist=%.0f × %.1fx) | Free=$%.2f",
                     entryPrice, g_PDL, distanceToPDL, potentialLoss, requiredDistance, marginCallDistance, g_PDMarginBuffer, freeMargin));
         return false;
      }
      
      double potentialLoss = distanceToPDL * pointValuePerLot * lotSize;
      DebugPrint(StringFormat("✅ BUY Safe (Above PDL) | Entry=%.5f | PDL=%.5f | Distance=%.0f pts | PotentialLoss=$%.2f | Required=%.0f pts | Free=$%.2f",
                  entryPrice, g_PDL, distanceToPDL, potentialLoss, requiredDistance, freeMargin));
   }
   else if(orderType == ORDER_TYPE_SELL)
   {
      // SELL: check distance to PDH (upside risk)
      // Positive = entry below PDH (need safety check)
      // Negative = entry above PDH (SAFE - selling at premium)
      double distanceToPDH = (g_PDH - entryPrice) / _Point;
      
      // Entry ABOVE PDH → Always safe for SELL (selling higher than previous day high)
      if(distanceToPDH < 0.0)
      {
         DebugPrint(StringFormat("✅ SELL Safe (Above PDH) | Entry=%.5f > PDH=%.5f | Distance=%.0f pts | Free=$%.2f",
                     entryPrice, g_PDH, distanceToPDH, freeMargin));
         return true;
      }
      
      // Entry BELOW PDH → Check if too close to margin call
      if(distanceToPDH < requiredDistance)
      {
         double potentialLoss = distanceToPDH * pointValuePerLot * lotSize;
         SysPrint(StringFormat("⛔ SELL BLOCKED (PD Margin Safety) | Entry=%.5f | PDH=%.5f | Distance=%.0f pts | PotentialLoss=$%.2f | Required=%.0f pts (MC dist=%.0f × %.1fx) | Free=$%.2f",
                     entryPrice, g_PDH, distanceToPDH, potentialLoss, requiredDistance, marginCallDistance, g_PDMarginBuffer, freeMargin));
         return false;
      }
      
      double potentialLoss = distanceToPDH * pointValuePerLot * lotSize;
      DebugPrint(StringFormat("✅ SELL Safe (Below PDH) | Entry=%.5f | PDH=%.5f | Distance=%.0f pts | PotentialLoss=$%.2f | Required=%.0f pts | Free=$%.2f",
                  entryPrice, g_PDH, distanceToPDH, potentialLoss, requiredDistance, freeMargin));
   }

   return true;
}

#endif