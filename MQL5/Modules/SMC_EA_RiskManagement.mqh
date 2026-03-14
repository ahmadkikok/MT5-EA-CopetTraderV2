//+------------------------------------------------------------------+
//| SMC_EA_RiskManagement.mqh                                        |
//+------------------------------------------------------------------+
#ifndef __SMC_EA_RISKMANAGEMENT_MQH__
#define __SMC_EA_RISKMANAGEMENT_MQH__

#include <Trade/PositionInfo.mqh>
static CPositionInfo RM_pos;

//--- diambil dari main
extern int    g_magicNumber;
extern bool   g_EnableDailyLossLimit;
extern bool   g_UseDailyLossAsPercent;
extern bool   g_AutoStopTradingToday;
extern double g_DailyLossLimitValue;

//--- state internal modul
static bool     g_rm_blockedToday = false;
static datetime g_rm_lastReset    = 0;

//void ErrorPrint(string msg);
//void SysPrint(string msg);
//void DebugPrint(string msg);

//+------------------------------------------------------------------+
//| Helper: awal hari (server time)                                  |
//+------------------------------------------------------------------+
inline datetime RM_TodayStart()
{
   datetime now = TimeCurrent();
   MqlDateTime t; TimeToStruct(now, t);
   t.hour = 0; t.min = 0; t.sec = 0;
   return StructToTime(t);
}

//+------------------------------------------------------------------+
//| Hitung P/L net hari ini (closed deals only!)                     |
//+------------------------------------------------------------------+
inline double RM_GetTodayNetProfit(const string symbol, const long magic)
{
   datetime from = RM_TodayStart();
   datetime to   = TimeCurrent();

   if(!HistorySelect(from, to)) return 0.0;

   double pnl = 0.0;
   int deals = HistoryDealsTotal();
   for(int i=0; i<deals; i++)
   {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(deal_ticket == 0) continue;

      string sym   = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
      long   mg    = (long)HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
      int    entry = (int)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);

      if(sym != symbol || mg != magic) continue;

      if(entry == DEAL_ENTRY_OUT)
      {
         double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT)
                       + HistoryDealGetDouble(deal_ticket, DEAL_SWAP)
                       + HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
         pnl += profit;
      }
   }
   return pnl;
}

//+------------------------------------------------------------------+
//| Reset status daily loss saat hari berganti                       |
//+------------------------------------------------------------------+
inline void RM_ResetIfNewDay()
{
   datetime today0 = RM_TodayStart();
   if(g_rm_lastReset == 0 || g_rm_lastReset < today0)
   {
      g_rm_lastReset  = today0;
      g_rm_blockedToday = false;
      SysPrint("✅ RM: New day detected, daily closed loss block reset");
   }
}

//+------------------------------------------------------------------+
//| Check apakah daily CLOSED loss limit breach                      |
//+------------------------------------------------------------------+
inline bool RM_CheckDailyLossLimit()
{
   if(!g_EnableDailyLossLimit) return true;
   if(g_rm_blockedToday)       return false;

   double todayPnl = RM_GetTodayNetProfit(_Symbol, g_magicNumber);
   if(todayPnl >= 0.0) return true;

   bool breach = false;
   double limit = 0.0;
   
   if(g_UseDailyLossAsPercent)
   {
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      limit = -MathAbs(g_DailyLossLimitValue) / 100.0 * bal;
      if(todayPnl <= limit) breach = true;
   }
   else
   {
      limit = -MathAbs(g_DailyLossLimitValue);
      if(todayPnl <= limit) breach = true;
   }

   if(breach)
   {
      SysPrint("🛑 RM: Daily CLOSED loss limit breached!");
      SysPrint(StringFormat("   Today Closed P/L: $%.2f", todayPnl));
      SysPrint(StringFormat("   Limit: $%.2f", limit));
      SysPrint("🛑 Trading blocked until tomorrow.");
      if(g_AutoStopTradingToday) g_rm_blockedToday = true;
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Get Daily CLOSED Loss Status for Dashboard                       |
//+------------------------------------------------------------------+
string RM_GetDailyLossStatus()
{
   if(!g_EnableDailyLossLimit)
      return "📊 Daily Loss: OFF";
   
   double todayPnl = RM_GetTodayNetProfit(_Symbol, g_magicNumber);
   double limit = g_DailyLossLimitValue;
   
   if(g_UseDailyLossAsPercent)
      limit = AccountInfoDouble(ACCOUNT_BALANCE) * g_DailyLossLimitValue / 100.0;
   
   if(g_rm_blockedToday)
      return StringFormat("🚨 DAILY BLOCKED! ($%.2f)", todayPnl);
   
   if(todayPnl < 0)
   {
      double pct = (MathAbs(todayPnl) / limit) * 100.0;
      if(pct >= 80)
         return StringFormat("⚠️ Daily: $%.2f / -$%.0f [WARNING]", todayPnl, limit);
      else if(pct >= 50)
         return StringFormat("🟡 Daily: $%.2f / -$%.0f", todayPnl, limit);
   }
   
   return StringFormat("🟢 Daily: $%.2f / -$%.0f", todayPnl, limit);
}

//+------------------------------------------------------------------+
//| Get Today's Statistics (legacy function)                         |
//+------------------------------------------------------------------+
string RM_GetTodayStats()
{
   double todayPnl = RM_GetTodayNetProfit(_Symbol, g_magicNumber);
   double limit = g_DailyLossLimitValue;
   
   if(g_UseDailyLossAsPercent)
      limit = AccountInfoDouble(ACCOUNT_BALANCE) * g_DailyLossLimitValue / 100.0;
   
   string stats = StringFormat(
      "📊 Today's Closed Stats:\n"
      "   P/L: $%.2f\n"
      "   Loss Limit: $%.2f\n"
      "   Status: %s",
      todayPnl,
      limit,
      g_rm_blockedToday ? "🔴 BLOCKED" : "🟢 ACTIVE"
   );
   
   return stats;
}

#endif
