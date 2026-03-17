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
input bool   InpCheckEngulfing      = false;  // Require engulfing candle — KEEP FALSE untuk frekuensi entry normal [Engulf]
input bool   InpRequireFreshOB      = false;  // OB harus FRESH (belum disentuh) [OB]
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

input string sep_buy_trade          = "";     // ────── BUY Trade ──────
input bool   InpEnableBuyRR         = false;  // [BUY] Enable RR-based SL+TP (true=RR, false=Fixed)
input double InpBuyRR               = 2.0;    // [BUY] RR ratio (e.g. 2.0 = TP 2x SL)
input double InpBuySLMin            = 8.0;    // [BUY] Min SL distance (pts) — 0=off
input double InpBuySLMax            = 150.0;  // [BUY] Max SL distance (pts) — 0=off
input bool   InpBuyRiskPercent      = false;  // [BUY] Lot dari risk % balance (true) atau fixed (false)
input double InpBuyRiskPct          = 1.0;    // [BUY] Risk % per trade (hanya jika RiskPercent=true)

input string sep_sell_trade         = "";     // ────── SELL Trade ──────
input bool   InpEnableSellRR        = false;  // [SELL] Enable RR-based SL+TP (true=RR, false=Fixed)
input double InpSellRR              = 1.5;    // [SELL] RR ratio (e.g. 1.5 = TP 1.5x SL)
input double InpSellSLMin           = 8.0;    // [SELL] Min SL distance (pts) — 0=off
input double InpSellSLMax           = 150.0;  // [SELL] Max SL distance (pts) — 0=off
input bool   InpSellRiskPercent     = false;  // [SELL] Lot dari risk % balance (true) atau fixed (false)
input double InpSellRiskPct         = 1.0;    // [SELL] Risk % per trade (hanya jika RiskPercent=true)

input string sep_be_trade           = "";     // ────── Break Even ──────
input double BE_Trigger             = 3.0;    // [BE] Trigger profit ($)
input double BE_ProfitLock          = 2.0;    // [BE] Lock profit ($)

input group "═══ Features Config — Entry ═══"
input int    InpRSIPeriode              = 3;      // [RSI] Period
input bool   InpRequireBearishM1Sell    = false;  // [SELL] Require last M1 candle bearish
input bool   InpRequireBullishM1Buy     = false;  // [BUY]  Require last M1 candle bullish
input double InpBlockRangePercent       = 85.0;   // [PD] Block BUY di atas X% range
input int    InpRangeLookback           = 60;     // [PD] Lookback bars untuk range check

input group "═══ Features Config — Zone ═══"
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
input bool   InpEnableDraw           = false;  // Tampilkan drawing xxvw di chart (ON=slow saat backtest)
input bool   InpRequireFVGConfluence = false;  // Require FVG dekat OB untuk entry [FVG]
input bool   InpRequireOTE           = false;  // Require harga di OTE zone (61.8-78.6% fib) [OTE]
input bool   InpLiquidityFilter      = false;  // Block entry jika ada unswept liquidity di depan [LIQ]
input double InpLiquidityLookback    = 500.0;  // [LIQ] Max jarak liquidity yang diblok (pts)
input bool   InpDebugMode            = false;  // Enable Debug Prints

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
double g_BuyRR;
double g_BuySLMin;
double g_BuySLMax;
double g_BuyRiskPct;
double g_SellRiskPct;
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
bool   g_EnableBuyRR;
bool   g_BuyRiskPercent;
bool   g_SellRiskPercent;
bool   g_EnableBE_Buy;
bool   g_EnableBE_Sell;
bool   g_EnableReversalGuard;
bool   g_IgnoreManualTrades;
bool   g_DebugMode;
bool   g_ValidateEntry;
bool   g_BlockOverbought;
bool   g_BlockOversold;
bool   g_RequireFreshOB;
bool   g_RequireBearishM1Sell;
bool   g_RequireBullishM1Buy;
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

   // OB/FVG draw settings are hardcoded optimally in class constructors

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
   g_SellRiskPercent          = InpSellRiskPercent;
   g_SellRiskPct              = InpSellRiskPct;
   g_EnableBuyRR              = InpEnableBuyRR;
   g_BuyRR                    = InpBuyRR;
   g_BuySLMin                 = InpBuySLMin;
   g_BuySLMax                 = InpBuySLMax;
   g_BuyRiskPercent           = InpBuyRiskPercent;
   g_BuyRiskPct               = InpBuyRiskPct;
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
   g_RequireBearishM1Sell     = InpRequireBearishM1Sell;
   g_RequireBullishM1Buy      = InpRequireBullishM1Buy;
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
   InitRSI();
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
   CleanupRSI();
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

   // Rate-limited trace — print once per bar so journal doesn't flood
   static datetime s_lastTracedBar = 0;
   datetime curBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   bool doTrace = (curBar != s_lastTracedBar);
   if(doTrace) s_lastTracedBar = curBar;

   if(!tryBuy && !trySell)
   {
      if(doTrace) DebugPrint(StringFormat("⛔ Trend not aligned | Bias=%s Struct=%s Entry=%s",
         EnumToString(g_smcBias.GetTrend()),
         EnumToString(g_smcStruct.GetTrend()),
         EnumToString(g_smcEntry.GetTrend())));
      return;
   }

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

   if(!foundOB)
   {
      if(doTrace) DebugPrint(StringFormat("⛔ No OB found | tryBuy=%s trySell=%s BullOBs=%d BearOBs=%d",
         tryBuy?"Y":"N", trySell?"Y":"N",
         g_smcEntry.OB().GetBullishCount(), g_smcEntry.OB().GetBearishCount()));
      return;
   }

   if(ob.score < InpMinOBScore)
   {
      if(doTrace) DebugPrint(StringFormat("⛔ OB score %.2f < min %.2f", ob.score, InpMinOBScore));
      return;
   }

   if(IsOBUsed(ob.formationTime))
   {
      if(doTrace) DebugPrint("⛔ OB already used");
      return;
   }

   double entryPrice = 0;
   if(!IsInOBZone(ob, entryPrice))
   {
      if(doTrace) DebugPrint(StringFormat("⛔ Price %.2f not in OB zone [%.2f-%.2f] tol=%.1fpts",
         bid, ob.bottomPrice, ob.topPrice, InpRetestTolPoints));
      return;
   }

   // ── OTE Filter ────────────────────────────────────────────────────
   // Require price to be in the 61.8-78.6% fibonacci retracement zone
   // of the most recent swing. This ensures we only enter at optimal
   // price (not chasing, not too early in the retracement).
   if(InpRequireOTE)
   {
      if(!g_smcEntry.OTE().IsInOTEZone(bid))
      {
         DebugPrint(StringFormat("⛔ OTE: price %.2f not in OTE zone [%.2f-%.2f]",
                    bid, g_smcEntry.OTE().GetFib786(), g_smcEntry.OTE().GetFib618()));
         return;
      }
      DebugPrint("✅ OTE zone confirmed");
   }

   // ── Liquidity Filter ──────────────────────────────────────────────
   // Block entry if there is an unswept liquidity pool (equal highs/lows)
   // sitting between current price and trade direction within lookback distance.
   // ICT: price tends to sweep nearby liquidity before reversing.
   if(InpLiquidityFilter)
   {
      double liqRange = InpLiquidityLookback * _Point;
      SmcLiquidityLevel liq;

      if(orderType == ORDER_TYPE_BUY)
      {
         // Block BUY if there are unswept equal LOWS below (sell-side liquidity)
         // Price may sweep those lows first before reversing up
         if(g_smcEntry.Liquidity().GetNearestEqualLow(bid, liq))
         {
            if(liq.isValid && !liq.isSweep &&
               liq.price < bid && (bid - liq.price) < liqRange)
            {
               DebugPrint(StringFormat("⛔ LIQ: Unswept equal lows at %.2f below BUY entry", liq.price));
               return;
            }
         }
      }
      else // SELL
      {
         // Block SELL if there are unswept equal HIGHS above (buy-side liquidity)
         // Price may sweep those highs first before reversing down
         if(g_smcEntry.Liquidity().GetNearestEqualHigh(bid, liq))
         {
            if(liq.isValid && !liq.isSweep &&
               liq.price > bid && (liq.price - bid) < liqRange)
            {
               DebugPrint(StringFormat("⛔ LIQ: Unswept equal highs at %.2f above SELL entry", liq.price));
               return;
            }
         }
      }
   }

   // ── FVG Confluence Filter ─────────────────────────────────────────
   // If enabled: require a FRESH FVG overlapping or adjacent to the OB zone.
   // FVG acts as an imbalance magnet — price inside OB + FVG = high-confluence entry.
   if(InpRequireFVGConfluence)
   {
      SmcZone fvg;
      bool hasFVGConfluence = false;
      double fvgTol = InpRetestTolPoints * 3.0 * _Point; // slightly wider than OB tol

      if(orderType == ORDER_TYPE_BUY && g_smcEntry.FVG().GetNearestBullishFVG(bid, fvg))
      {
         // FVG must overlap or be adjacent to the OB zone
         if(fvg.IsFresh() && fvg.topPrice >= ob.bottomPrice - fvgTol
                          && fvg.bottomPrice <= ob.topPrice + fvgTol)
            hasFVGConfluence = true;
      }
      else if(orderType == ORDER_TYPE_SELL && g_smcEntry.FVG().GetNearestBearishFVG(bid, fvg))
      {
         if(fvg.IsFresh() && fvg.topPrice >= ob.bottomPrice - fvgTol
                          && fvg.bottomPrice <= ob.topPrice + fvgTol)
            hasFVGConfluence = true;
      }

      if(!hasFVGConfluence)
         { DebugPrint("⛔ No FVG confluence near OB — entry skipped"); return; }

      DebugPrint(StringFormat("✅ FVG confluence: FVG[%.2f-%.2f] overlaps OB[%.2f-%.2f]",
                 fvg.bottomPrice, fvg.topPrice, ob.bottomPrice, ob.topPrice));
   }

   if(InpBlockBuyAtATH  && orderType == ORDER_TYPE_BUY  && IsNearATH(InpATHATLThreshold, InpBiasTF))
      { DebugPrint("⛔ BUY blocked: near ATH"); return; }
   if(InpBlockSellAtATL && orderType == ORDER_TYPE_SELL && IsNearATL(InpATHATLThreshold, InpBiasTF))
      { DebugPrint("⛔ SELL blocked: near ATL"); return; }

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
      SmcZone fvgInfo;
      string fvgStr = "--";
      if(orderType == ORDER_TYPE_BUY  && g_smcEntry.FVG().GetNearestBullishFVG(bid, fvgInfo))
         fvgStr = StringFormat("%.2f-%.2f", fvgInfo.bottomPrice, fvgInfo.topPrice);
      if(orderType == ORDER_TYPE_SELL && g_smcEntry.FVG().GetNearestBearishFVG(bid, fvgInfo))
         fvgStr = StringFormat("%.2f-%.2f", fvgInfo.bottomPrice, fvgInfo.topPrice);

      SysPrint(StringFormat("✅ %s | OB[%.2f-%.2f] score=%.2f | FVG[%s]",
               (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"),
               ob.bottomPrice, ob.topPrice, ob.score, fvgStr));
      if(orderType == ORDER_TYPE_BUY)  g_lastBuyTime  = TimeCurrent();
      else                              g_lastSellTime = TimeCurrent();
      MarkOBUsed(ob.formationTime);
   }
}
