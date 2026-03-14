//+------------------------------------------------------------------+
//|              SMC_CopetTrader v2.0                                |
//| Core SMC via xxvw SMC_ICT_Library (github.com/xxvw)             |
//| Protection: Grid, RiskManagement, NewsFilter, PDLevels (legacy) |
//+------------------------------------------------------------------+
#property copyright "CopetTrader v2.0"
#property version   "2.00"
#property strict

#include <SMC/SmcManager.mqh>
#include "Modules/SMC_EA_RiskManagement.mqh"
#include "Modules/SMC_EA_TradeManagement_v2.mqh"
#include "Modules/SMC_EA_GridRecovery.mqh"
#include "Modules/SMC_EA_NewsFilter.mqh"
#include "Modules/SMC_EA_PDLevels.mqh"
#include "Modules/SMC_EA_Utils_v2.mqh"

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
input group "═══ Main Control ═══"
input int             InpMinATRPoints        = 30;         // ATR Points minimum (pts)
input double          InpRetestTolPoints     = 10.0;       // OB retest tolerance (pts)
input int             InpSlippage            = 10;         // Slippage
input ENUM_TIMEFRAMES InpStructTF            = PERIOD_M5;  // Timeframe Struktur
input ENUM_TIMEFRAMES InpBiasTF              = PERIOD_M15; // Timeframe Bias

input group "═══ Trading Controls ═══"
input int    InpMagic               = 12345;  // Magic Number
input double InpLot                 = 0.01;   // Fixed Lot
input double ProfitTarget           = 10;     // Target profit total (USD)
input double FixedTP                = 4;      // TP per position (USD)
input int    InpMaxBuyPositions     = 3;      // Max Buy Position
input int    InpMaxSellPositions    = 3;      // Max Sell Position
input int    InpMinSecondsBetween   = 30;     // Delay antar entry (sec)
input int    InpMinDistancePoints   = 5000;   // Min jarak antar entry (pts)

input group "═══ Main Features ═══"
input string sep_prot               = "";     // ────── Protection ──────
input bool   InpEnableGridRecovery  = true;   // Enable Grid Recovery TP [Grid]
input bool   InpEnableFloatingLimit = true;   // Enable Floating Loss Limit [FLProt]
input bool   InpEnableDailyLimit    = true;   // Enable Daily Closed Loss Limit [DLProt]
input bool   InpEnableMaxDD         = true;   // Enable Max Drawdown Guard [DDProt]
input bool   InpReversalGuard       = true;   // Enable Reversal Guard [RG]
input string sep_trade              = "";     // ────── Trade ──────
input bool   InpUseOBBasedSL        = false;  // Enable OB-based StopLoss [OBSL]
input bool   InpApplyOBSL_Buy       = false;  // [OBSL] Apply for Buy
input bool   InpApplyOBSL_Sell      = false;  // [OBSL] Apply for Sell
input bool   InpEnableBE_Buy        = false;  // Enable BE for BUY [BE]
input bool   InpEnableBE_Sell       = true;   // Enable BE for SELL [BE]
input bool   InpCheckEngulfing      = false;  // Require confirmation candle [Engulf]
input bool   InpRequireFreshOB      = true;   // OB harus FRESH (belum disentuh) [OB]
input double InpMinOBScore          = 0.5;    // Min OB score 0.0-1.0 (0.5=medium) [OB]
input string sep_entry              = "";     // ────── Entry ──────
input bool   InpBlockOverbought     = true;   // Block BUY if RSI > 70 [RSI]
input bool   InpBlockOversold       = true;   // Block SELL if RSI < 30 [RSI]
input bool   InpValidateEntry       = false;  // Block BUY di Premium / SELL di Discount [PD]
input string sep_zone               = "";     // ────── Zone ──────
input bool   InpBlockBuyAtATH       = true;   // Block BUY near ATH [ATH]
input bool   InpBlockSellAtATL      = true;   // Block SELL near ATL [ATL]
input bool   InpEnablePDFilter      = true;   // Enable PDL/PDH Filter [PDFilter]
input bool   InpBlockBadPDEntry     = true;   // Block BUY@PDH / SELL@PDL [PDFilter]
input string sep_filters            = "";     // ────── Filters ──────
input bool   InpEnableKillZone      = false;  // Hanya entry saat London/NY session [KZ]
input bool   InpEnableNews          = false;  // Enable News Filter [News]
input bool   InpIgnoreManualTrades  = false;  // Abaikan posisi manual (magic != EA) [Manual]

input group "═══ Features Config — Protection ═══"
input double InpGridTrailStep       = 2.0;    // [Grid] Trail Step ($)
input double InpGridLockTrigger     = 0.0;    // [Grid] Lock Trigger ($) — 0=trail immediately
input bool   InpGridTrailFloatOnly  = true;   // [Grid] Trail Floating+ Only
input bool   InpGridPerPosition     = false;  // [Grid] Trail Mode: Per-Position / Grid-High
input double InpGridMinLockPercent  = 0.0;    // [Grid] Min Lock (% of Step)
input double InpFloatingLimitValue  = 30.0;   // [FLProt] Max Floating Loss ($)
input bool   InpFloatingStopTrading = true;   // [FLProt] Stop Trading setelah hit
input bool   InpDailyLimitPercent   = false;  // [DLProt] Hitung sebagai % Balance
input double InpDailyLimitValue     = 50.0;   // [DLProt] Max Daily Loss ($ atau %)
input bool   InpAutoStopTrading     = true;   // [DLProt] Stop Trading sampai hari berikutnya
input double InpMaxDDPercent        = 5.0;    // [DDProt] Max Drawdown (% of Equity)
input bool   InpMaxDDStopTrading    = true;   // [DDProt] Stop Trading setelah hit
input double InpRGSensitivity       = 0.5;    // [RG] 0.3=Agresif, 0.5=Normal, 0.8=Konservatif

input group "═══ Features Config — Trade ═══"
input double InpSLFixedTP           = 1.0;    // [OBSL] SL buffer multiplier (x ATR)
input bool   InpEnableSellRR        = false;  // [SELL] Enable RR-based TP for Sell
input double InpSellRR              = 1.5;    // [SELL] RR ratio (1.5 = TP 1.5x SL)
input double InpSellSLMin           = 8.0;    // [SELL] Min SL distance (pts) — 0=off
input double InpSellSLMax           = 150.0;  // [SELL] Max SL distance (pts) — 0=off
input double BE_Trigger             = 3.0;    // [BE] Trigger profit ($)
input double BE_ProfitLock          = 2.0;    // [BE] Lock profit ($)

input group "═══ Features Config — Entry ═══"
input int    InpRSIPeriode          = 3;      // [RSI] Period
input double InpBlockRangePercent   = 85.0;   // [PD] Block BUY di atas X% range
input int    InpRangeLookback       = 60;     // [PD] Lookback bars untuk range check

input group "═══ Features Config — Zone ═══"
input int    InpMaxOBHistory         = 3;      // [OB] Jumlah OB history yang ditampilkan (per side)
input int    InpMaxFVGHistory        = 5;      // [FVG] Jumlah FVG history yang ditampilkan (per side)
input double InpATHATLThreshold     = 3000;   // [ATH/ATL] Jarak threshold ke ATH/ATL (pts)
input double InpPDMaxRangePercent   = 30.0;   // [PDFilter] Max Entry Zone (% dari PD Range)
input bool   InpShowPDLevels        = true;   // [PDFilter] Tampilkan PDL/PDH di chart
input bool   InpEnablePDMarginCheck = false;  // [PDMargin] Enable PD margin safety check
input double InpPDMarginBuffer      = 1.2;    // [PDMargin] Safety buffer (1.2=20% extra)

input group "═══ Features Config — Filters ═══"
input string InpNewsAPIKey          = "zJ08WeTxPBXcJtHywB3Y4Ai"; // [News] FCS API Key
input int    InpNewsBufferBefore    = 30;     // [News] Buffer sebelum news (min)
input int    InpNewsBufferAfter     = 30;     // [News] Buffer setelah news (min)

input group "═══ Misc ═══"
input bool   InpEnableDraw          = false;  // Tampilkan drawing xxvw di chart (ON=slow saat backtest)
input int    InpOBMaxAge            = 30;     // Max umur OB dalam bars (kurangi = lebih sedikit kotak)
input bool   InpDebugMode           = false;  // Enable Debug Prints

//+------------------------------------------------------------------+
//| xxvw SMC Managers                                                |
//+------------------------------------------------------------------+
CSmcManager g_smcEntry;
CSmcManager g_smcStruct;
CSmcManager g_smcBias;

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CTrade        g_trade;
CPositionInfo m_position;

int    g_magicNumber;
int    g_slippage;
int    g_maxBuy;
int    g_maxSell;
int    g_minSecondBetweenSameSide;
int    g_minDistancePoints;
int    g_usedOBTimes_limit  = 200;
int    MinATRPoints;
int    g_RangeLookback;
int    g_RSIPeriode;
double g_ProfitTarget;
double g_FixedTP;
double g_lot;
double g_SLFixedTP;
double g_SellRR;
double g_SellSLMin;
double g_SellSLMax;
double g_RGSensitivity;
double g_MaxDDEquityHigh    = 0;
double g_MaxDDPercent;
double g_FloatingLimitValue;
double g_DailyLossLimitValue;
double g_BlockRangePercent;
double g_MinOBStrength;
double g_PDMaxRangePercent;
double g_PDMarginBuffer;
bool   g_stopLossOB;
bool   g_ApplyOBSL_Buy;
bool   g_ApplyOBSL_Sell;
bool   g_EnableSellRR;
bool   g_EnableBE_Buy;
bool   g_EnableBE_Sell;
bool   g_EnableReversalGuard;
bool   g_IgnoreManualTrades;
bool   g_DebugMode;
bool   g_ValidateEntry;
bool   g_BlockOverbought;
bool   g_BlockOversold;
bool   g_RequireFreshOB;
bool   g_EnableOBStrengthFilter;
bool   g_FloatingLossTriggered  = false;
bool   g_MaxDDTriggered         = false;
bool   g_EnableMaxDD;
bool   g_MaxDDStopTrading;
bool   g_EnableFloatingLimit;
bool   g_FloatingStopTrading;
bool   g_EnableDailyLossLimit;
bool   g_UseDailyLossAsPercent;
bool   g_AutoStopTradingToday;
bool   g_RGSensitivity_dummy;
bool   g_EnablePDFilter;
bool   g_RequirePDConfluence    = false;
bool   g_BlockBadPDEntry;
bool   g_ShowPDLevels;
bool   g_EnablePDMarginCheck;
datetime g_usedOBTimes[];
datetime g_lastBuyTime  = 0;
datetime g_lastSellTime = 0;
ENUM_TIMEFRAMES BiasTF;
ENUM_TIMEFRAMES StructTF;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!g_smcEntry.Init(_Symbol,  PERIOD_CURRENT, InpEnableDraw, false, false)) return INIT_FAILED;
   if(!g_smcStruct.Init(_Symbol, InpStructTF,    false,         false, false)) return INIT_FAILED;
   if(!g_smcBias.Init(_Symbol,   InpBiasTF,      false,         false, false)) return INIT_FAILED;

   // Limit OB count to prevent chart clutter + improve performance
   g_smcEntry.OB().SetMaxAge(InpOBMaxAge);
   g_smcStruct.OB().SetMaxAge(InpOBMaxAge);
   g_smcBias.OB().SetMaxAge(InpOBMaxAge);
   g_smcEntry.OB().SetMaxDrawOBs(InpMaxOBHistory);
   g_smcEntry.FVG().SetMaxDrawFVGs(InpMaxFVGHistory);

   BiasTF   = InpBiasTF;
   StructTF = InpStructTF;

   g_magicNumber              = InpMagic;
   g_slippage                 = InpSlippage;
   g_maxBuy                   = InpMaxBuyPositions;
   g_maxSell                  = InpMaxSellPositions;
   g_minSecondBetweenSameSide = InpMinSecondsBetween;
   g_minDistancePoints        = InpMinDistancePoints;
   g_ProfitTarget             = ProfitTarget;
   g_FixedTP                  = FixedTP;
   g_lot                      = InpLot;
   MinATRPoints               = InpMinATRPoints;
   g_stopLossOB               = InpUseOBBasedSL;
   g_SLFixedTP                = InpSLFixedTP;
   g_ApplyOBSL_Buy            = InpApplyOBSL_Buy;
   g_ApplyOBSL_Sell           = InpApplyOBSL_Sell;
   g_EnableSellRR             = InpEnableSellRR;
   g_SellRR                   = InpSellRR;
   g_SellSLMin                = InpSellSLMin;
   g_SellSLMax                = InpSellSLMax;
   g_EnableBE_Buy             = InpEnableBE_Buy;
   g_EnableBE_Sell            = InpEnableBE_Sell;
   g_EnableReversalGuard      = InpReversalGuard;
   g_RGSensitivity            = InpRGSensitivity;
   g_IgnoreManualTrades       = InpIgnoreManualTrades;
   g_DebugMode                = InpDebugMode;
   g_ValidateEntry            = InpValidateEntry;
   g_BlockOverbought          = InpBlockOverbought;
   g_BlockOversold            = InpBlockOversold;
   g_BlockRangePercent        = InpBlockRangePercent;
   g_RangeLookback            = InpRangeLookback;
   g_RSIPeriode               = InpRSIPeriode;
   g_RequireFreshOB           = InpRequireFreshOB;
   g_MinOBStrength            = InpMinOBScore * 10.0;
   g_EnableOBStrengthFilter   = true;
   g_EnableFloatingLimit      = InpEnableFloatingLimit;
   g_FloatingLimitValue       = InpFloatingLimitValue;
   g_FloatingStopTrading      = InpFloatingStopTrading;
   g_FloatingLossTriggered    = false;
   g_EnableDailyLossLimit     = InpEnableDailyLimit;
   g_UseDailyLossAsPercent    = InpDailyLimitPercent;
   g_DailyLossLimitValue      = InpDailyLimitValue;
   g_AutoStopTradingToday     = InpAutoStopTrading;
   g_EnableMaxDD              = InpEnableMaxDD;
   g_MaxDDPercent             = InpMaxDDPercent;
   g_MaxDDStopTrading         = InpMaxDDStopTrading;
   g_MaxDDTriggered           = false;
   g_MaxDDEquityHigh          = AccountInfoDouble(ACCOUNT_EQUITY);
   g_EnablePDFilter           = InpEnablePDFilter;
   g_BlockBadPDEntry          = InpBlockBadPDEntry;
   g_PDMaxRangePercent        = InpPDMaxRangePercent;
   g_ShowPDLevels             = InpShowPDLevels;
   g_EnablePDMarginCheck      = InpEnablePDMarginCheck;
   g_PDMarginBuffer           = InpPDMarginBuffer;
   g_RequirePDConfluence      = false;

   CheckAndUpdatePDLevels();
   InitGridRecovery(InpEnableGridRecovery, InpGridTrailStep, InpGridLockTrigger,
                    InpGridTrailFloatOnly, InpGridPerPosition, InpGridMinLockPercent);
   InitATR(14);
   InitNewsFilter(InpEnableNews, InpNewsAPIKey, InpNewsBufferBefore, InpNewsBufferAfter);
   ArrayResize(g_usedOBTimes, 0);

   SysPrint("═══════════════════════════════════════════");
   SysPrint("✅ SMC_CopetTrader v2.0 initialized");
   SysPrint("   Library  : xxvw SMC_ICT_Library");
   SysPrint(StringFormat("   Bias=%s | Struct=%s | Entry=%s",
            EnumToString(InpBiasTF), EnumToString(InpStructTF), EnumToString((ENUM_TIMEFRAMES)Period())));
   SysPrint(StringFormat("   Magic=%d | Lot=%.2f | ATR min=%d pts",
            g_magicNumber, g_lot, MinATRPoints));
   SysPrint(StringFormat("   KillZone=%s | IgnoreManual=%s | Debug=%s",
            InpEnableKillZone?"ON":"OFF", InpIgnoreManualTrades?"ON":"OFF",
            InpDebugMode?"ON":"OFF"));
   SysPrint("═══════════════════════════════════════════");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   g_smcEntry.Clean();
   g_smcStruct.Clean();
   g_smcBias.Clean();
   CleanupATRHandle();
   CleanupPDLevels();
   Comment("");
   SysPrint(StringFormat("SMC_CopetTrader v2.0 deinit. Reason: %d", reason));
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   ForceATRWarmup();
   double atrPrice  = GetATR(0);
   double atrPoints = atrPrice / _Point;
   if(atrPrice <= 0 || atrPoints < MinATRPoints) return;

   g_smcEntry.Update();
   g_smcStruct.Update();
   g_smcBias.Update();

   if(g_EnablePDFilter) CheckAndUpdatePDLevels();

   static datetime lastResetDay = 0;
   datetime todayStart = TimeCurrent() - (TimeCurrent() % 86400);
   if(todayStart > lastResetDay)
      { lastResetDay = todayStart; ResetAllDailyProtection(); }

   if(g_FloatingLossTriggered && g_FloatingStopTrading)
      { UpdateComment("🛑 FLOATING LOSS - STOPPED"); return; }
   if(g_MaxDDTriggered && g_MaxDDStopTrading)
      { UpdateComment("🚨 MAX DD - STOPPED"); return; }

   ManageGridRecovery();
   if(g_EnableBE_Buy || g_EnableBE_Sell) LockProfitAll(BE_Trigger, BE_ProfitLock);
   Manage_Position();
   if(g_EnableReversalGuard) CheckAndCloseOnReversal();
   if(!CheckMaxDrawdown()) { UpdateComment("🚨 MAX DRAWDOWN"); return; }

   UpdateNewsFilter();
   RM_ResetIfNewDay();
   if(!RM_CheckDailyLossLimit()) { UpdateComment("🛑 DAILY LIMIT"); return; }
   if(InpEnableNews && IsInNewsBlackout()) { UpdateComment("🚫 NEWS BLACKOUT"); return; }

   UpdateComment("");

   if(InpEnableKillZone)
   {
      if(!g_smcEntry.KZ().IsInSession(SESSION_LONDON) &&
         !g_smcEntry.KZ().IsInSession(SESSION_NEWYORK)) return;
   }

   bool tryBuy  = IsTrendAligned(ORDER_TYPE_BUY);
   bool trySell = IsTrendAligned(ORDER_TYPE_SELL);
   if(!tryBuy && !trySell) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   SmcZone ob;
   ENUM_ORDER_TYPE orderType = ORDER_TYPE_BUY;
   bool foundOB = false;

   if(tryBuy && g_smcEntry.OB().GetNearestBullishOB(bid, ob))
      if(!g_RequireFreshOB || ob.IsFresh())
         { foundOB = true; orderType = ORDER_TYPE_BUY; }

   if(!foundOB && trySell && g_smcEntry.OB().GetNearestBearishOB(bid, ob))
      if(!g_RequireFreshOB || ob.IsFresh())
         { foundOB = true; orderType = ORDER_TYPE_SELL; }

   if(!foundOB) return;

   if(ob.score < InpMinOBScore)
      { DebugPrint(StringFormat("⛔ OB score %.2f < min %.2f", ob.score, InpMinOBScore)); return; }
   if(IsOBUsed(ob.formationTime)) return;

   double entryPrice = 0;
   if(!IsInOBZone(ob, entryPrice)) return;

   if(InpBlockBuyAtATH  && orderType == ORDER_TYPE_BUY  && IsNearATH(InpATHATLThreshold, InpBiasTF)) return;
   if(InpBlockSellAtATL && orderType == ORDER_TYPE_SELL && IsNearATL(InpATHATLThreshold, InpBiasTF)) return;

   if(g_EnablePDFilter && g_BlockBadPDEntry)
   {
      double ep = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                 : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(IsPDLevelBlocking(orderType, ep, g_PDMaxRangePercent))
         { SysPrint("⛔ Blocked by PDL/PDH filter"); return; }
   }

   if(g_ValidateEntry)
   {
      if(orderType == ORDER_TYPE_BUY  && g_smcEntry.PD().IsPremium())
         { DebugPrint("⛔ BUY blocked: price in Premium zone"); return; }
      if(orderType == ORDER_TYPE_SELL && g_smcEntry.PD().IsDiscount())
         { DebugPrint("⛔ SELL blocked: price in Discount zone"); return; }
   }

   if(!CanOpenNewOrder(orderType)) return;

   if(InpCheckEngulfing)
   {
      bool conf = (orderType == ORDER_TYPE_BUY) ? IsBullishEngulfing(1) : IsBearishEngulfing(1);
      if(!conf) return;
   }

   if(!IsEntryValid(orderType)) return;

   bool ok = OpenPosition(orderType, g_lot, ob);
   if(ok)
   {
      SysPrint(StringFormat("✅ %s | OB[%.2f-%.2f] score=%.2f",
               (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"),
               ob.bottomPrice, ob.topPrice, ob.score));
      if(orderType == ORDER_TYPE_BUY)  g_lastBuyTime  = TimeCurrent();
      else                              g_lastSellTime = TimeCurrent();
      MarkOBUsed(ob.formationTime);
   }
}
