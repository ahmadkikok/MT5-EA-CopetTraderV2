//+------------------------------------------------------------------+
//|                                                   OrderBlock.mqh |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict

#ifndef __SMC_ORDER_BLOCK_MQH__
#define __SMC_ORDER_BLOCK_MQH__

#include "MarketStructure.mqh"

//+------------------------------------------------------------------+
//| CSmcOrderBlock - オーダーブロック検出・管理                         |
//|                                                                    |
//| BOS/CHoCH前の最後の逆方向キャンドルをOBとして検出。               |
//| 状態管理: FRESH -> TESTED -> MITIGATED -> BROKEN                   |
//+------------------------------------------------------------------+
class CSmcOrderBlock : public CSmcBase
  {
private:
   //--- モジュール参照
   CSmcMarketStructure *m_structure;
   bool              m_ownStructure;

   //--- 設定
   int               m_lookbackBars;
   int               m_maxOBs;
   int               m_maxDrawOBs;  // max OBs drawn per side (history)
   datetime          m_lastBarTime;  // last bar time for detect-once-per-bar
   int               m_maxAge;
   double            m_minStrength;     // 最小インパルス強度倍率

   //--- データ
   SmcZone           m_bullishOBs[];
   SmcZone           m_bearishOBs[];
   int               m_bullishCount;
   int               m_bearishCount;
   bool              m_initialScanDone;
   bool              m_needsFullRedraw;   // true on new bar → full delete+redraw once
   // Blacklist: formationTimes of LRU-evicted OBs — never re-detect these
   datetime          m_evictedBull[];
   datetime          m_evictedBear[];
   int               m_evictedBullCount;
   int               m_evictedBearCount;

   //--- 描画色
   color             m_colorBullish;
   color             m_colorBearish;

public:
                     CSmcOrderBlock();
                    ~CSmcOrderBlock();

   bool              Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                          const bool enableDraw = false,
                          CSmcMarketStructure *structure = NULL);
   virtual bool      Update();
   virtual void      Clean();

   //--- 設定
   void              SetMaxAge(const int age)     { m_maxAge = age; }
   void              SetMaxDrawOBs(const int n) { m_maxDrawOBs = n; }
   void              SetMinStrength(const double str) { m_minStrength = str; }

   //--- Bullish OB
   int               GetBullishCount() const { return m_bullishCount; }
   bool              GetBullishOB(const int index, SmcZone &ob) const;
   bool              GetNearestBullishOB(const double price, SmcZone &ob) const;

   //--- Bearish OB
   int               GetBearishCount() const { return m_bearishCount; }
   bool              GetBearishOB(const int index, SmcZone &ob) const;
   bool              GetNearestBearishOB(const double price, SmcZone &ob) const;

   //--- ユーティリティ
   int               GetFreshBullishCount() const;
   int               GetFreshBearishCount() const;
   double            GetStopLossForBuy(const SmcZone &ob) const;
   double            GetStopLossForSell(const SmcZone &ob) const;

   //--- 構造参照
   CSmcMarketStructure *Structure() { return m_structure; }

private:
   void              DetectOrderBlocks();
   void              PurgeInactiveOBs();
   void              UpdateStates();
   bool              IsImpulsiveMove(const int startBar, const int direction);
   bool              IsAlreadyTracked(const datetime formTime, const bool isBull) const;
   double            CalcOBScore(const SmcZone &ob) const;
   void              DrawOrderBlocks();
  };

//+------------------------------------------------------------------+
CSmcOrderBlock::CSmcOrderBlock()
   : m_structure(NULL)
   , m_ownStructure(false)
   , m_lookbackBars(100)
   , m_maxOBs(20)
   , m_maxAge(150)
   , m_maxDrawOBs(5)
   , m_minStrength(1.5)
   , m_bullishCount(0)
   , m_bearishCount(0)
   , m_initialScanDone(false)
   , m_needsFullRedraw(true)
   , m_evictedBullCount(0)
   , m_evictedBearCount(0)
   , m_colorBullish(C'0,150,200')
   , m_colorBearish(C'200,100,50')
  {
  }

CSmcOrderBlock::~CSmcOrderBlock()
  {
   if(m_ownStructure && m_structure != NULL)
     {
      delete m_structure;
      m_structure = NULL;
     }
   ArrayFree(m_bullishOBs);
   ArrayFree(m_bearishOBs);
  }

//+------------------------------------------------------------------+
bool CSmcOrderBlock::Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                          const bool enableDraw, CSmcMarketStructure *structure)
  {
   if(!CSmcBase::Init(symbol, timeframe, enableDraw))
      return false;

   m_prefix = "SMC_OB_" + IntegerToString((int)timeframe) + "_";

   if(structure != NULL)
     {
      m_structure    = structure;
      m_ownStructure = false;
     }
   else
     {
      m_structure = new CSmcMarketStructure();
      if(!m_structure.Init(symbol, timeframe, enableDraw))
        {
         delete m_structure;
         m_structure = NULL;
         return false;
        }
      m_ownStructure = true;
     }

   ArrayResize(m_bullishOBs, m_maxOBs);
   ArrayResize(m_bearishOBs, m_maxOBs);
   // Blacklist can hold up to 200 evicted times
   ArrayResize(m_evictedBull, 200);
   ArrayResize(m_evictedBear, 200);

   return true;
  }

//+------------------------------------------------------------------+
bool CSmcOrderBlock::Update()
  {
   if(!m_initialized || m_structure == NULL)
      return false;

   if(m_ownStructure)
      m_structure.Update();

   datetime currentBar = iTime(m_symbol, m_timeframe, 0);
   if(currentBar != m_lastBarTime)
     {
      m_lastBarTime = currentBar;
      m_needsFullRedraw = true;   // trigger full redraw once on new bar

      // KEY FIX: Do NOT reset counts here — preserve TESTED/BROKEN state history.
      // Instead: first compact the arrays (remove broken/expired), then detect new OBs.
      PurgeInactiveOBs();
      DetectOrderBlocks();
     }

   UpdateStates();  // runs every tick

   if(m_enableDraw)
      DrawOrderBlocks();

   return true;
  }

void CSmcOrderBlock::Clean()
  {
   CSmcDrawing::DeleteObjectsByPrefix(m_prefix);
   if(m_ownStructure && m_structure != NULL)
      m_structure.Clean();
   CSmcDrawing::Redraw();
  }

//+------------------------------------------------------------------+
bool CSmcOrderBlock::GetBullishOB(const int index, SmcZone &ob) const
  {
   if(index < 0 || index >= m_bullishCount)
      return false;
   ob = m_bullishOBs[index];
   return true;
  }

bool CSmcOrderBlock::GetBearishOB(const int index, SmcZone &ob) const
  {
   if(index < 0 || index >= m_bearishCount)
      return false;
   ob = m_bearishOBs[index];
   return true;
  }

//+------------------------------------------------------------------+
bool CSmcOrderBlock::GetNearestBullishOB(const double price, SmcZone &ob) const
  {
   double minDist = DBL_MAX;
   bool found     = false;

   for(int i = 0; i < m_bullishCount; i++)
     {
      if(!m_bullishOBs[i].IsActive())
         continue;
      double dist = MathAbs(price - m_bullishOBs[i].GetCenter());
      if(dist < minDist)
        {
         minDist = dist;
         ob      = m_bullishOBs[i];
         found   = true;
        }
     }
   return found;
  }

bool CSmcOrderBlock::GetNearestBearishOB(const double price, SmcZone &ob) const
  {
   double minDist = DBL_MAX;
   bool found     = false;

   for(int i = 0; i < m_bearishCount; i++)
     {
      if(!m_bearishOBs[i].IsActive())
         continue;
      double dist = MathAbs(price - m_bearishOBs[i].GetCenter());
      if(dist < minDist)
        {
         minDist = dist;
         ob      = m_bearishOBs[i];
         found   = true;
        }
     }
   return found;
  }

//+------------------------------------------------------------------+
int CSmcOrderBlock::GetFreshBullishCount() const
  {
   int count = 0;
   for(int i = 0; i < m_bullishCount; i++)
      if(m_bullishOBs[i].IsFresh())
         count++;
   return count;
  }

int CSmcOrderBlock::GetFreshBearishCount() const
  {
   int count = 0;
   for(int i = 0; i < m_bearishCount; i++)
      if(m_bearishOBs[i].IsFresh())
         count++;
   return count;
  }

double CSmcOrderBlock::GetStopLossForBuy(const SmcZone &ob) const
  {
   return ob.bottomPrice - PipsToPrice(2);
  }

double CSmcOrderBlock::GetStopLossForSell(const SmcZone &ob) const
  {
   return ob.topPrice + PipsToPrice(2);
  }

//+------------------------------------------------------------------+
//| OB検出: BOS/CHoCH前の最後の逆方向ローソク足                       |
//| KEY FIX: デュープ防止 — formationTime でチェック済みエントリをスキップ |
//+------------------------------------------------------------------+
void CSmcOrderBlock::DetectOrderBlocks()
  {
   double avgRange = GetAverageRange(20);
   if(avgRange == 0)
      return;

   int limit = MathMin(m_lookbackBars, iBars(m_symbol, m_timeframe) - 5);

   for(int i = 2; i < limit; i++)
     {
      bool isBull = IsBullishCandle(i);
      bool isBear = IsBearishCandle(i);

      //--- Bullish OB: 陰線の後に強い上昇インパルス
      if(isBear && IsImpulsiveMove(i - 1, 1))
        {
         if(!IsAlreadyTracked(Time(i), true) && m_bullishCount < m_maxOBs)
           {
            m_bullishOBs[m_bullishCount].Init();
            m_bullishOBs[m_bullishCount].topPrice      = High(i);
            m_bullishOBs[m_bullishCount].bottomPrice    = Low(i);
            m_bullishOBs[m_bullishCount].formationTime  = Time(i);
            m_bullishOBs[m_bullishCount].formationBar   = i;
            m_bullishOBs[m_bullishCount].isBullish      = true;
            m_bullishOBs[m_bullishCount].state           = ZONE_FRESH;
            m_bullishOBs[m_bullishCount].candleCount     = 1;
            m_bullishOBs[m_bullishCount].age             = i;
            m_bullishOBs[m_bullishCount].isValid         = true;
            m_bullishOBs[m_bullishCount].probability =
               (m_bullishOBs[m_bullishCount].candleCount == 1) ? PROB_HIGH : PROB_LOW;
            m_bullishOBs[m_bullishCount].score = CalcOBScore(m_bullishOBs[m_bullishCount]);
            m_bullishCount++;
           }
        }

      //--- Bearish OB: 陽線の後に強い下降インパルス
      if(isBull && IsImpulsiveMove(i - 1, -1))
        {
         if(!IsAlreadyTracked(Time(i), false) && m_bearishCount < m_maxOBs)
           {
            m_bearishOBs[m_bearishCount].Init();
            m_bearishOBs[m_bearishCount].topPrice      = High(i);
            m_bearishOBs[m_bearishCount].bottomPrice    = Low(i);
            m_bearishOBs[m_bearishCount].formationTime  = Time(i);
            m_bearishOBs[m_bearishCount].formationBar   = i;
            m_bearishOBs[m_bearishCount].isBullish      = false;
            m_bearishOBs[m_bearishCount].state           = ZONE_FRESH;
            m_bearishOBs[m_bearishCount].candleCount     = 1;
            m_bearishOBs[m_bearishCount].age             = i;
            m_bearishOBs[m_bearishCount].isValid         = true;
            m_bearishOBs[m_bearishCount].probability =
               (m_bearishOBs[m_bearishCount].candleCount == 1) ? PROB_HIGH : PROB_LOW;
            m_bearishOBs[m_bearishCount].score = CalcOBScore(m_bearishOBs[m_bearishCount]);
            m_bearishCount++;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| 重複チェック: formationTime が既にトラック済みまたはブラックリスト   |
//+------------------------------------------------------------------+
bool CSmcOrderBlock::IsAlreadyTracked(const datetime formTime, const bool isBull) const
  {
   if(isBull)
     {
      for(int j = 0; j < m_bullishCount; j++)
         if(m_bullishOBs[j].formationTime == formTime)
            return true;
      // Also check eviction blacklist — never re-detect evicted OBs
      for(int j = 0; j < m_evictedBullCount; j++)
         if(m_evictedBull[j] == formTime)
            return true;
     }
   else
     {
      for(int j = 0; j < m_bearishCount; j++)
         if(m_bearishOBs[j].formationTime == formTime)
            return true;
      for(int j = 0; j < m_evictedBearCount; j++)
         if(m_evictedBear[j] == formTime)
            return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| 無効OBを配列から除去してスロットを解放 — 除去したものはブラックリストへ |
//+------------------------------------------------------------------+
void CSmcOrderBlock::PurgeInactiveOBs()
  {
   //--- Compact bullish array, blacklist everything removed
   int newCount = 0;
   for(int i = 0; i < m_bullishCount; i++)
     {
      if(m_bullishOBs[i].isValid)
         m_bullishOBs[newCount++] = m_bullishOBs[i];
      else
        {
         // Blacklist so DetectOrderBlocks never re-adds this OB
         if(m_evictedBullCount < 200)
            m_evictedBull[m_evictedBullCount++] = m_bullishOBs[i].formationTime;
        }
     }
   m_bullishCount = newCount;

   //--- Compact bearish array
   newCount = 0;
   for(int i = 0; i < m_bearishCount; i++)
     {
      if(m_bearishOBs[i].isValid)
         m_bearishOBs[newCount++] = m_bearishOBs[i];
      else
        {
         if(m_evictedBearCount < 200)
            m_evictedBear[m_evictedBearCount++] = m_bearishOBs[i].formationTime;
        }
     }
   m_bearishCount = newCount;
  }

//+------------------------------------------------------------------+
//| インパルシブムーブ判定                                             |
//+------------------------------------------------------------------+
bool CSmcOrderBlock::IsImpulsiveMove(const int startBar, const int direction)
  {
   double avgBody = GetAverageCandleBody(20);
   if(avgBody == 0)
      return false;

   int consecutive = 0;
   double totalMove = 0;

   for(int i = startBar; i >= MathMax(0, startBar - 3); i--)
     {
      double body = CandleBody(i);
      if(direction > 0 && IsBullishCandle(i) && body > avgBody * m_minStrength)
        {
         totalMove += body;
         consecutive++;
        }
      else if(direction < 0 && IsBearishCandle(i) && body > avgBody * m_minStrength)
        {
         totalMove += body;
         consecutive++;
        }
     }

   return (consecutive >= 1 && totalMove > avgBody * 2.0);
  }

//+------------------------------------------------------------------+
//| OB状態更新                                                         |
//+------------------------------------------------------------------+
void CSmcOrderBlock::UpdateStates()
  {
   double currentBid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

   //--- Bullish OB状態更新
   for(int i = 0; i < m_bullishCount; i++)
     {
      if(!m_bullishOBs[i].isValid)
         continue;

      // KEY: update age for scoring only — do NOT expire by age alone
      // OBs only become invalid when price actually breaks through them
      m_bullishOBs[i].age = iBarShift(m_symbol, m_timeframe, m_bullishOBs[i].formationTime);

      //--- 価格がOBゾーン内に入った場合
      if(currentBid <= m_bullishOBs[i].topPrice && currentBid >= m_bullishOBs[i].bottomPrice)
        {
         if(m_bullishOBs[i].state == ZONE_FRESH)
           { m_bullishOBs[i].state = ZONE_TESTED; m_bullishOBs[i].mitigationTime = TimeCurrent(); }
        }

      //--- 下抜けでブレイク (FRESH or TESTED —直接貫通も検出)
      if(currentBid < m_bullishOBs[i].bottomPrice &&
         (m_bullishOBs[i].state == ZONE_TESTED || m_bullishOBs[i].state == ZONE_FRESH))
        {
         if(m_bullishOBs[i].mitigationTime == 0)
            m_bullishOBs[i].mitigationTime = TimeCurrent();
         m_bullishOBs[i].state   = ZONE_BROKEN;
         m_bullishOBs[i].isValid = false;
        }
     }

   //--- Bearish OB状態更新
   for(int i = 0; i < m_bearishCount; i++)
     {
      if(!m_bearishOBs[i].isValid)
         continue;

      // KEY: update age for scoring only — do NOT expire by age alone
      m_bearishOBs[i].age = iBarShift(m_symbol, m_timeframe, m_bearishOBs[i].formationTime);

      if(currentBid >= m_bearishOBs[i].bottomPrice && currentBid <= m_bearishOBs[i].topPrice)
        {
         if(m_bearishOBs[i].state == ZONE_FRESH)
           { m_bearishOBs[i].state = ZONE_TESTED; m_bearishOBs[i].mitigationTime = TimeCurrent(); }
        }

      //--- 上抜けでブレイク (FRESH or TESTED)
      if(currentBid > m_bearishOBs[i].topPrice &&
         (m_bearishOBs[i].state == ZONE_TESTED || m_bearishOBs[i].state == ZONE_FRESH))
        {
         if(m_bearishOBs[i].mitigationTime == 0)
            m_bearishOBs[i].mitigationTime = TimeCurrent();
         m_bearishOBs[i].state   = ZONE_BROKEN;
         m_bearishOBs[i].isValid = false;
        }
     }
  }

//+------------------------------------------------------------------+
double CSmcOrderBlock::CalcOBScore(const SmcZone &ob) const
  {
   double score = 0.5;

   if(ob.probability == PROB_HIGH)
      score += 0.2;
   if(ob.state == ZONE_FRESH)
      score += 0.15;
   if(ob.age < 20)
      score += 0.15;

   return MathMin(1.0, score);
  }

//+------------------------------------------------------------------+
void CSmcOrderBlock::DrawOrderBlocks()
  {
   //--------------------------------------------------------------------
   // Anti-flicker strategy:
   //   - New bar  → full delete+redraw (m_needsFullRedraw == true)
   //   - Every tick → only extend FRESH zone right edges (cheap, no flicker)
   //
   // Draw order: i=0 is NEWEST OB (closest bar), i=count-1 is OLDEST.
   // Draw ALL valid OBs — no maxDrawOBs cap (let the array size be the limit).
   //--------------------------------------------------------------------

   if(m_needsFullRedraw)
     {
      CSmcDrawing::DeleteObjectsByPrefix(m_prefix);

      // Draw all valid bullish OBs (newest first = index 0)
      for(int i = 0; i < m_bullishCount; i++)
        {
         if(!m_bullishOBs[i].isValid) continue;
         if(m_bullishOBs[i].state == ZONE_BROKEN) continue;

         bool     isFresh   = m_bullishOBs[i].IsFresh();
         datetime rightEdge = isFresh ? TimeCurrent() : m_bullishOBs[i].mitigationTime;
         color    clr       = m_colorBullish;
         string   name      = m_prefix + "BULL_" + IntegerToString(i);
         string   label     = m_prefix + "BULL_L_" + IntegerToString(i);
         string   tag       = isFresh ? "OB+" : "OB+(t)";

         CSmcDrawing::DrawZone(name, m_bullishOBs[i].formationTime, m_bullishOBs[i].topPrice,
                               rightEdge, m_bullishOBs[i].bottomPrice, clr, 20, isFresh,
                               isFresh ? STYLE_SOLID : STYLE_DOT);
         CSmcDrawing::DrawText(label, m_bullishOBs[i].formationTime,
                               m_bullishOBs[i].topPrice, tag, clr, 7);
        }

      // Draw all valid bearish OBs
      for(int i = 0; i < m_bearishCount; i++)
        {
         if(!m_bearishOBs[i].isValid) continue;
         if(m_bearishOBs[i].state == ZONE_BROKEN) continue;

         bool     isFresh   = m_bearishOBs[i].IsFresh();
         datetime rightEdge = isFresh ? TimeCurrent() : m_bearishOBs[i].mitigationTime;
         color    clr       = m_colorBearish;
         string   name      = m_prefix + "BEAR_" + IntegerToString(i);
         string   label     = m_prefix + "BEAR_L_" + IntegerToString(i);
         string   tag       = isFresh ? "OB-" : "OB-(t)";

         CSmcDrawing::DrawZone(name, m_bearishOBs[i].formationTime, m_bearishOBs[i].topPrice,
                               rightEdge, m_bearishOBs[i].bottomPrice, clr, 20, isFresh,
                               isFresh ? STYLE_SOLID : STYLE_DOT);
         CSmcDrawing::DrawText(label, m_bearishOBs[i].formationTime,
                               m_bearishOBs[i].topPrice, tag, clr, 7);
        }

      m_needsFullRedraw = false;
      CSmcDrawing::Redraw();
     }
   else
     {
      // Tick update: only extend right edge of FRESH zones — zero flicker
      bool anyExtended = false;
      for(int i = 0; i < m_bullishCount; i++)
        {
         if(!m_bullishOBs[i].isValid || !m_bullishOBs[i].IsFresh()) continue;
         string name = m_prefix + "BULL_" + IntegerToString(i);
         CSmcDrawing::ExtendZone(name, TimeCurrent());
         anyExtended = true;
        }
      for(int i = 0; i < m_bearishCount; i++)
        {
         if(!m_bearishOBs[i].isValid || !m_bearishOBs[i].IsFresh()) continue;
         string name = m_prefix + "BEAR_" + IntegerToString(i);
         CSmcDrawing::ExtendZone(name, TimeCurrent());
         anyExtended = true;
        }
      if(anyExtended)
         CSmcDrawing::Redraw();
     }
  }

#endif // __SMC_ORDER_BLOCK_MQH__
//+------------------------------------------------------------------+
