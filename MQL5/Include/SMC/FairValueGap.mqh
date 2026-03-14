//+------------------------------------------------------------------+
//|                                                 FairValueGap.mqh |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict

#ifndef __SMC_FAIR_VALUE_GAP_MQH__
#define __SMC_FAIR_VALUE_GAP_MQH__

#include "Core/SmcDrawing.mqh"

//+------------------------------------------------------------------+
//| CSmcFairValueGap - Fair Value Gap (FVG) 検出・管理                |
//|                                                                    |
//| 3本ローソク足パターンでギャップ(インバランス)を検出。              |
//| Bullish FVG: 3本目の安値 > 1本目の高値                             |
//| Bearish FVG: 3本目の高値 < 1本目の安値                             |
//+------------------------------------------------------------------+
class CSmcFairValueGap : public CSmcBase
  {
private:
   //--- 設定
   int               m_lookbackBars;
   int               m_maxFVGs;
   int               m_maxDrawFVGs;   // max FVGs drawn (history)
   datetime          m_lastBarTime;   // last bar time for detect-once-per-bar
   int               m_maxAge;
   double            m_minSizePips;

   //--- データ
   SmcZone           m_bullishFVGs[];
   SmcZone           m_bearishFVGs[];
   int               m_bullishCount;
   int               m_bearishCount;
   bool              m_needsFullRedraw;   // true on new bar → full delete+redraw once

   //--- 描画色
   color             m_colorBullish;
   color             m_colorBearish;

public:
                     CSmcFairValueGap();
                    ~CSmcFairValueGap();

   bool              Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                          const bool enableDraw = false,
                          const double minSizePips = 2.0,
                          const int maxAge = 200);
   virtual bool      Update();
   virtual void      Clean();

   //--- 設定
   void              SetMinSizePips(const double pips) { m_minSizePips = pips; }
   void              SetMaxAge(const int age) { m_maxAge = age; }

   //--- Bullish FVG
   int               GetBullishCount() const { return m_bullishCount; }
   bool              GetBullishFVG(const int index, SmcZone &fvg) const;
   bool              GetNearestBullishFVG(const double price, SmcZone &fvg) const;

   //--- Bearish FVG
   int               GetBearishCount() const { return m_bearishCount; }
   bool              GetBearishFVG(const int index, SmcZone &fvg) const;
   bool              GetNearestBearishFVG(const double price, SmcZone &fvg) const;

   //--- ユーティリティ
   int               GetFreshBullishCount() const;
   int               GetFreshBearishCount() const;
   bool              IsPriceInBullishFVG(const double price) const;
   bool              IsPriceInBearishFVG(const double price) const;

public:
   void              SetMaxDrawFVGs(const int n) { m_maxDrawFVGs = n; }
private:
   void              DetectFVGs();
   void              PurgeInactiveFVGs();
   bool              IsAlreadyTracked(const datetime formTime, const bool isBull) const;
   void              UpdateStates();
   ENUM_FVG_PROBABILITY DetermineProbability(const int barIndex, const bool isBullish);
   void              DrawFVGs();
  };

//+------------------------------------------------------------------+
CSmcFairValueGap::CSmcFairValueGap()
   : m_lookbackBars(300)
   , m_maxFVGs(10)        // hardcoded optimal: track up to 10 FVGs per side
   , m_maxAge(100)        // hardcoded optimal: expire after 100 bars
   , m_maxDrawFVGs(5)     // hardcoded optimal: show 5 per side on chart
   , m_lastBarTime(0)
   , m_minSizePips(2.0)
   , m_bullishCount(0)
   , m_bearishCount(0)
   , m_needsFullRedraw(true)
   , m_colorBullish(C'0,180,80')
   , m_colorBearish(C'180,50,50')
  {
  }

CSmcFairValueGap::~CSmcFairValueGap()
  {
   ArrayFree(m_bullishFVGs);
   ArrayFree(m_bearishFVGs);
  }

//+------------------------------------------------------------------+
bool CSmcFairValueGap::Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                            const bool enableDraw, const double minSizePips,
                            const int maxAge)
  {
   if(!CSmcBase::Init(symbol, timeframe, enableDraw))
      return false;

   m_prefix = "SMC_FVG_" + IntegerToString((int)timeframe) + "_";
   m_minSizePips = minSizePips;
   m_maxAge      = maxAge;

   ArrayResize(m_bullishFVGs, m_maxFVGs);
   ArrayResize(m_bearishFVGs, m_maxFVGs);

   return true;
  }

//+------------------------------------------------------------------+
bool CSmcFairValueGap::Update()
  {
   if(!m_initialized)
      return false;

   // Re-detect only on new bar to preserve mitigationTime / state history
   datetime currentBar = iTime(m_symbol, m_timeframe, 0);
   if(currentBar != m_lastBarTime)
     {
      m_lastBarTime = currentBar;
      m_needsFullRedraw = true;   // trigger full redraw once on new bar

      // KEY FIX: Do NOT reset counts — preserve TESTED/BROKEN state.
      // Compact arrays first (remove broken/expired), then detect new FVGs.
      PurgeInactiveFVGs();
      DetectFVGs();
     }

   UpdateStates();  // runs every tick to track touches in real-time

   if(m_enableDraw)
      DrawFVGs();

   return true;
  }

void CSmcFairValueGap::Clean()
  {
   CSmcDrawing::DeleteObjectsByPrefix(m_prefix);
   CSmcDrawing::Redraw();
  }

//+------------------------------------------------------------------+
bool CSmcFairValueGap::GetBullishFVG(const int index, SmcZone &fvg) const
  {
   if(index < 0 || index >= m_bullishCount)
      return false;
   fvg = m_bullishFVGs[index];
   return true;
  }

bool CSmcFairValueGap::GetBearishFVG(const int index, SmcZone &fvg) const
  {
   if(index < 0 || index >= m_bearishCount)
      return false;
   fvg = m_bearishFVGs[index];
   return true;
  }

//+------------------------------------------------------------------+
bool CSmcFairValueGap::GetNearestBullishFVG(const double price, SmcZone &fvg) const
  {
   double minDist = DBL_MAX;
   bool found     = false;

   for(int i = 0; i < m_bullishCount; i++)
     {
      if(!m_bullishFVGs[i].IsActive())
         continue;
      double dist = MathAbs(price - m_bullishFVGs[i].GetCenter());
      if(dist < minDist)
        {
         minDist = dist;
         fvg     = m_bullishFVGs[i];
         found   = true;
        }
     }
   return found;
  }

bool CSmcFairValueGap::GetNearestBearishFVG(const double price, SmcZone &fvg) const
  {
   double minDist = DBL_MAX;
   bool found     = false;

   for(int i = 0; i < m_bearishCount; i++)
     {
      if(!m_bearishFVGs[i].IsActive())
         continue;
      double dist = MathAbs(price - m_bearishFVGs[i].GetCenter());
      if(dist < minDist)
        {
         minDist = dist;
         fvg     = m_bearishFVGs[i];
         found   = true;
        }
     }
   return found;
  }

//+------------------------------------------------------------------+
int CSmcFairValueGap::GetFreshBullishCount() const
  {
   int c = 0;
   for(int i = 0; i < m_bullishCount; i++)
      if(m_bullishFVGs[i].IsFresh())
         c++;
   return c;
  }

int CSmcFairValueGap::GetFreshBearishCount() const
  {
   int c = 0;
   for(int i = 0; i < m_bearishCount; i++)
      if(m_bearishFVGs[i].IsFresh())
         c++;
   return c;
  }

bool CSmcFairValueGap::IsPriceInBullishFVG(const double price) const
  {
   for(int i = 0; i < m_bullishCount; i++)
      if(m_bullishFVGs[i].IsActive() &&
         price >= m_bullishFVGs[i].bottomPrice &&
         price <= m_bullishFVGs[i].topPrice)
         return true;
   return false;
  }

bool CSmcFairValueGap::IsPriceInBearishFVG(const double price) const
  {
   for(int i = 0; i < m_bearishCount; i++)
      if(m_bearishFVGs[i].IsActive() &&
         price >= m_bearishFVGs[i].bottomPrice &&
         price <= m_bearishFVGs[i].topPrice)
         return true;
   return false;
  }

//+------------------------------------------------------------------+
//| FVG検出: 3本ローソク足パターン                                    |
//|                                                                    |
//| Bullish FVG: candle[i-2].Low > candle[i].High (ギャップ上)         |
//| Bearish FVG: candle[i-2].High < candle[i].Low (ギャップ下)         |
//+------------------------------------------------------------------+
void CSmcFairValueGap::DetectFVGs()
  {
   double minSize = PipsToPrice(m_minSizePips);
   int limit = MathMin(m_lookbackBars, iBars(m_symbol, m_timeframe) - 3);

   for(int i = 2; i < limit; i++)
     {
      double high0 = High(i - 2);  // 最新側 (3本目)
      double low0  = Low(i - 2);
      double high2 = High(i);      // 最古側 (1本目)
      double low2  = Low(i);
      datetime midTime = Time(i - 1); // 中央のバー

      //--- Bullish FVG: 3本目の安値 > 1本目の高値
      if(low0 > high2)
        {
         double gapSize = low0 - high2;
         // KEY FIX: dedup check — skip if this FVG is already tracked
         if(gapSize >= minSize && !IsAlreadyTracked(midTime, true) && m_bullishCount < m_maxFVGs)
           {
            m_bullishFVGs[m_bullishCount].Init();
            m_bullishFVGs[m_bullishCount].topPrice      = low0;    // FVG上端
            m_bullishFVGs[m_bullishCount].bottomPrice    = high2;   // FVG下端
            m_bullishFVGs[m_bullishCount].formationTime    = midTime;
            m_bullishFVGs[m_bullishCount].formationEndTime = Time(i - 2);
            m_bullishFVGs[m_bullishCount].formationBar     = i - 1;
            m_bullishFVGs[m_bullishCount].isBullish      = true;
            m_bullishFVGs[m_bullishCount].state           = ZONE_FRESH;
            m_bullishFVGs[m_bullishCount].age             = i - 1;
            m_bullishFVGs[m_bullishCount].isValid         = true;
            m_bullishFVGs[m_bullishCount].probability     =
               (ENUM_ZONE_PROBABILITY)DetermineProbability(i - 1, true);
            m_bullishFVGs[m_bullishCount].score =
               (m_bullishFVGs[m_bullishCount].probability == PROB_HIGH) ? 0.8 : 0.5;
            m_bullishCount++;
           }
        }

      //--- Bearish FVG: 3本目の高値 < 1本目の安値
      if(high0 < low2)
        {
         double gapSize = low2 - high0;
         if(gapSize >= minSize && !IsAlreadyTracked(midTime, false) && m_bearishCount < m_maxFVGs)
           {
            m_bearishFVGs[m_bearishCount].Init();
            m_bearishFVGs[m_bearishCount].topPrice      = low2;    // FVG上端
            m_bearishFVGs[m_bearishCount].bottomPrice    = high0;   // FVG下端
            m_bearishFVGs[m_bearishCount].formationTime    = midTime;
            m_bearishFVGs[m_bearishCount].formationEndTime = Time(i - 2);
            m_bearishFVGs[m_bearishCount].formationBar     = i - 1;
            m_bearishFVGs[m_bearishCount].isBullish      = false;
            m_bearishFVGs[m_bearishCount].state           = ZONE_FRESH;
            m_bearishFVGs[m_bearishCount].age             = i - 1;
            m_bearishFVGs[m_bearishCount].isValid         = true;
            m_bearishFVGs[m_bearishCount].probability     =
               (ENUM_ZONE_PROBABILITY)DetermineProbability(i - 1, false);
            m_bearishFVGs[m_bearishCount].score =
               (m_bearishFVGs[m_bearishCount].probability == PROB_HIGH) ? 0.8 : 0.5;
            m_bearishCount++;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| 重複チェック: formationTime が既にトラック済みかどうか確認          |
//+------------------------------------------------------------------+
bool CSmcFairValueGap::IsAlreadyTracked(const datetime formTime, const bool isBull) const
  {
   if(isBull)
     {
      for(int j = 0; j < m_bullishCount; j++)
         if(m_bullishFVGs[j].formationTime == formTime)
            return true;
     }
   else
     {
      for(int j = 0; j < m_bearishCount; j++)
         if(m_bearishFVGs[j].formationTime == formTime)
            return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| 無効FVGを配列から除去してスロットを解放                             |
//+------------------------------------------------------------------+
void CSmcFairValueGap::PurgeInactiveFVGs()
  {
   int newCount = 0;
   for(int i = 0; i < m_bullishCount; i++)
     {
      if(m_bullishFVGs[i].isValid)
         m_bullishFVGs[newCount++] = m_bullishFVGs[i];
     }
   m_bullishCount = newCount;

   newCount = 0;
   for(int i = 0; i < m_bearishCount; i++)
     {
      if(m_bearishFVGs[i].isValid)
         m_bearishFVGs[newCount++] = m_bearishFVGs[i];
     }
   m_bearishCount = newCount;
  }

//+------------------------------------------------------------------+
//| FVG確率分類                                                        |
//+------------------------------------------------------------------+
ENUM_FVG_PROBABILITY CSmcFairValueGap::DetermineProbability(const int barIndex,
      const bool isBullish)
  {
//--- 3本すべて同方向の場合は高確率
   bool allSame = true;
   for(int i = barIndex - 1; i <= barIndex + 1; i++)
     {
      if(isBullish && !IsBullishCandle(i))
         allSame = false;
      if(!isBullish && !IsBearishCandle(i))
         allSame = false;
     }

   if(allSame)
      return FVG_HIGH_PROB;

//--- ブレイクアウェイ判定 (大きなギャップ)
   double avgRange = GetAverageRange(20);
   double gapSize  = isBullish ?
                     (Low(barIndex - 1) - High(barIndex + 1)) :
                     (Low(barIndex + 1) - High(barIndex - 1));

   if(MathAbs(gapSize) > avgRange * 2.0)
      return FVG_BREAKAWAY;

   return FVG_LOW_PROB;
  }

//+------------------------------------------------------------------+
void CSmcFairValueGap::UpdateStates()
  {
   double currentBid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

   for(int i = 0; i < m_bullishCount; i++)
     {
      if(!m_bullishFVGs[i].isValid)
         continue;

      // KEY: update age for scoring only — FVGs only die when price fills them
      m_bullishFVGs[i].age = iBarShift(m_symbol, m_timeframe, m_bullishFVGs[i].formationTime);

      //--- 価格がFVGゾーン内に入った
      if(currentBid <= m_bullishFVGs[i].topPrice &&
         currentBid >= m_bullishFVGs[i].bottomPrice)
        {
         if(m_bullishFVGs[i].state == ZONE_FRESH)
           { m_bullishFVGs[i].state = ZONE_TESTED; m_bullishFVGs[i].mitigationTime = TimeCurrent(); }
        }

      //--- FVGが完全に埋まった (TESTED → BROKEN)
      if(currentBid < m_bullishFVGs[i].bottomPrice &&
         m_bullishFVGs[i].state == ZONE_TESTED)
        {
         m_bullishFVGs[i].state          = ZONE_BROKEN;
         m_bullishFVGs[i].mitigationTime = TimeCurrent();
         m_bullishFVGs[i].isValid        = false;
        }
      //--- 直接貫通: FRESH でも下抜けなら即 BROKEN
      else if(currentBid < m_bullishFVGs[i].bottomPrice &&
              m_bullishFVGs[i].state == ZONE_FRESH)
        {
         m_bullishFVGs[i].mitigationTime = TimeCurrent();
         m_bullishFVGs[i].state          = ZONE_BROKEN;
         m_bullishFVGs[i].isValid        = false;
        }
     }

   for(int i = 0; i < m_bearishCount; i++)
     {
      if(!m_bearishFVGs[i].isValid)
         continue;

      // KEY: update age for scoring only — FVGs only die when price fills them
      m_bearishFVGs[i].age = iBarShift(m_symbol, m_timeframe, m_bearishFVGs[i].formationTime);

      if(currentBid >= m_bearishFVGs[i].bottomPrice &&
         currentBid <= m_bearishFVGs[i].topPrice)
        {
         if(m_bearishFVGs[i].state == ZONE_FRESH)
           { m_bearishFVGs[i].state = ZONE_TESTED; m_bearishFVGs[i].mitigationTime = TimeCurrent(); }
        }

      if(currentBid > m_bearishFVGs[i].topPrice &&
         m_bearishFVGs[i].state == ZONE_TESTED)
        {
         m_bearishFVGs[i].state          = ZONE_BROKEN;
         m_bearishFVGs[i].mitigationTime = TimeCurrent();
         m_bearishFVGs[i].isValid        = false;
        }
      //--- 直接貫通: FRESH でも上抜けなら即 BROKEN
      else if(currentBid > m_bearishFVGs[i].topPrice &&
              m_bearishFVGs[i].state == ZONE_FRESH)
        {
         m_bearishFVGs[i].mitigationTime = TimeCurrent();
         m_bearishFVGs[i].state          = ZONE_BROKEN;
         m_bearishFVGs[i].isValid        = false;
        }
     }
  }

//+------------------------------------------------------------------+
void CSmcFairValueGap::DrawFVGs()
  {
   //--------------------------------------------------------------------
   // Anti-flicker strategy:
   //   - New bar  → full delete+redraw (m_needsFullRedraw == true)
   //   - Every tick → FVG boxes are fixed (no extend needed — right edge
   //                  is capped at formationEndTime for FRESH FVGs)
   //                  Only call Redraw if a state change happened.
   //--------------------------------------------------------------------

   if(!m_needsFullRedraw)
      return;  // FVG right edge is static (formationEndTime) — no tick update needed

   CSmcDrawing::DeleteObjectsByPrefix(m_prefix);

   // Draw all valid bullish FVGs — index 0 = newest
   for(int i = 0; i < m_bullishCount; i++)
     {
      if(!m_bullishFVGs[i].isValid) continue;
      if(m_bullishFVGs[i].state == ZONE_BROKEN) continue;

      bool     isFresh   = m_bullishFVGs[i].IsFresh();
      datetime rightEdge = isFresh
         ? ((m_bullishFVGs[i].formationEndTime > 0) ? m_bullishFVGs[i].formationEndTime : m_bullishFVGs[i].formationTime)
         : m_bullishFVGs[i].mitigationTime;
      color    clr       = m_colorBullish;
      string   name      = m_prefix + "BULL_" + IntegerToString(i);
      string   label     = m_prefix + "BULL_L_" + IntegerToString(i);
      string   tag       = isFresh ? "FVG+" : "FVG+(t)";

      CSmcDrawing::DrawZone(name, m_bullishFVGs[i].formationTime, m_bullishFVGs[i].topPrice,
                            rightEdge, m_bullishFVGs[i].bottomPrice, clr, 20, isFresh,
                            isFresh ? STYLE_SOLID : STYLE_DOT);
      CSmcDrawing::DrawText(label, m_bullishFVGs[i].formationTime,
                            m_bullishFVGs[i].topPrice, tag, clr, 7);
     }

   // Draw all valid bearish FVGs
   for(int i = 0; i < m_bearishCount; i++)
     {
      if(!m_bearishFVGs[i].isValid) continue;
      if(m_bearishFVGs[i].state == ZONE_BROKEN) continue;

      bool     isFresh   = m_bearishFVGs[i].IsFresh();
      datetime rightEdge = isFresh
         ? ((m_bearishFVGs[i].formationEndTime > 0) ? m_bearishFVGs[i].formationEndTime : m_bearishFVGs[i].formationTime)
         : m_bearishFVGs[i].mitigationTime;
      color    clr       = m_colorBearish;
      string   name      = m_prefix + "BEAR_" + IntegerToString(i);
      string   label     = m_prefix + "BEAR_L_" + IntegerToString(i);
      string   tag       = isFresh ? "FVG-" : "FVG-(t)";

      CSmcDrawing::DrawZone(name, m_bearishFVGs[i].formationTime, m_bearishFVGs[i].topPrice,
                            rightEdge, m_bearishFVGs[i].bottomPrice, clr, 20, isFresh,
                            isFresh ? STYLE_SOLID : STYLE_DOT);
      CSmcDrawing::DrawText(label, m_bearishFVGs[i].formationTime,
                            m_bearishFVGs[i].topPrice, tag, clr, 7);
     }

   m_needsFullRedraw = false;
   CSmcDrawing::Redraw();
  }

#endif // __SMC_FAIR_VALUE_GAP_MQH__
//+------------------------------------------------------------------+
