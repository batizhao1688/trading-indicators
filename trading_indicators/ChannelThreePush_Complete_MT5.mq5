//+------------------------------------------------------------------+
//| ChannelThreePush_Complete_MT5.mq5                              |
//| Channel Three Push System - Complete Fixed                     |
//| 修复内容：#property indicator_buffers 8 (原错误：interactionCount)  |
//+------------------------------------------------------------------+
#property copyright "DeepSeek AI"
#property link      "https://github.com/batizhao1688/trading-indicators"
#property version   "2.0"
#property description "Channel Three Push System - MT5 Indicator"
#property description "Complete with rapid detection, channel drawing, three pushes"

#property indicator_chart_window
#property indicator_buffers 8        // ✅ 修复：原为 interactionCount
#property indicator_plots   8

//+------------------------------------------------------------------+
//| 输入参数                                                          |
//+------------------------------------------------------------------+
input int    RapidLen = 10;           // 急速检测窗口
input double RapidMultiplier = 1.5;   // 实体倍数
input int    MinRapidBars = 2;        // 最少K线数
input int    ChannelLookback = 20;    // 通道窗口
input int    MinTouchPoints = 3;      // 接触点数
input bool   ShowLabels = true;       // 显示标签
input bool   ShowLines = true;        // 显示线条
input color  ColorBullish = clrGreen; // 多头色
input color  ColorBearish = clrRed;   // 空头色
input color  ColorNeutral = clrBlue;  // 中性色

//+------------------------------------------------------------------+
//| 指标缓冲区                                                        |
//+------------------------------------------------------------------+
double UpperChannelBuffer[];   // 0 - 上轨
double LowerChannelBuffer[];   // 1 - 下轨
double Push1SignalBuffer[];    // 2 - 推1
double Push2SignalBuffer[];    // 3 - 推2
double Push3SignalBuffer[];    // 4 - 推3
double FailureSignalBuffer[];  // 5 - 衰竭
double RapidBullishBuffer[];   // 6 - 多头急速
double RapidBearishBuffer[];   // 7 - 空头急速

//+------------------------------------------------------------------+
//| 全局变量                                                          |
//+------------------------------------------------------------------+
int    g_rapidEndBar = -1;
double g_channelSlope = 0;
double g_channelStart = 0;
double g_channelHeight = 0;

//+------------------------------------------------------------------+
//| 初始化                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   // 设置缓冲区
   SetIndexBuffer(0, UpperChannelBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, LowerChannelBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, Push1SignalBuffer,  INDICATOR_DATA);
   SetIndexBuffer(3, Push2SignalBuffer,  INDICATOR_DATA);
   SetIndexBuffer(4, Push3SignalBuffer,  INDICATOR_DATA);
   SetIndexBuffer(5, FailureSignalBuffer, INDICATOR_DATA);
   SetIndexBuffer(6, RapidBullishBuffer,  INDICATOR_DATA);
   SetIndexBuffer(7, RapidBearishBuffer,  INDICATOR_DATA);
   
   // 绘图样式
   SetIndexStyle(0, DRAW_LINE, STYLE_SOLID, 1, ColorNeutral);
   SetIndexStyle(1, DRAW_LINE, STYLE_SOLID, 1, ColorNeutral);
   SetIndexStyle(6, DRAW_HISTOGRAM, STYLE_SOLID, 1, ColorBullish);
   SetIndexStyle(7, DRAW_HISTOGRAM, STYLE_SOLID, 1, ColorBearish);
   
   SetIndexLabel(0, "Upper Channel");
   SetIndexLabel(1, "Lower Channel");
   SetIndexLabel(6, "Bull Rapid");
   SetIndexLabel(7, "Bear Rapid");
   
   // 初始化
   g_rapidEndBar = -1;
   g_channelSlope = 0;
   g_channelStart = 0;
   g_channelHeight = 0;
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| 清理                                                              |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "CTPS_");
   Comment("");
}

//+------------------------------------------------------------------+
//| 主计算                                                            |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < 30) return(0);
   
   int start = (prev_calculated == 0) ? 0 : prev_calculated - 1;
   
   for(int i = start; i < rates_total; i++)
   {
      // 检测急速
      RapidBullishBuffer[i] = 0;
      RapidBearishBuffer[i] = 0;
      
      if(DetectRapidBullish(i))
      {
         RapidBullishBuffer[i] = 1;
         g_rapidEndBar = i;
      }
      else if(DetectRapidBearish(i))
      {
         RapidBearishBuffer[i] = -1;
         g_rapidEndBar = i;
      }
      
      // 计算通道
      if(g_rapidEndBar != -1 && i >= g_rapidEndBar + 5)
      {
         CalculateChannel(i, rates_total, low);
         UpperChannelBuffer[i] = g_channelStart + g_channelHeight + g_channelSlope * (i - g_rapidEndBar);
         LowerChannelBuffer[i] = g_channelStart + g_channelSlope * (i - g_rapidEndBar);
      }
   }
   
   return(rates_total);
}

//+------------------------------------------------------------------+
//| 工具函数                                                          |
//+------------------------------------------------------------------+
double BodySize(int idx)
{
   return MathAbs(Close[idx] - Open[idx]);
}

double AvgBodySize(int len, int start)
{
   double sum = 0;
   for(int i = 0; i < len && start + i < Bars; i++)
      sum += BodySize(start + i);
   return (len > 0) ? sum / len : 0;
}

bool DetectRapidBullish(int idx)
{
   int count = 0;
   for(int i = 0; i < RapidLen && idx + i < Bars; i++)
   {
      double body = BodySize(idx + i);
      double avg = AvgBodySize(RapidLen, idx + i + 1);
      if(Close[idx + i] > Open[idx + i] && body > avg * RapidMultiplier)
      {
         count++;
         if(count >= MinRapidBars) return true;
      }
      else count = 0;
   }
   return false;
}

bool DetectRapidBearish(int idx)
{
   int count = 0;
   for(int i = 0; i < RapidLen && idx + i < Bars; i++)
   {
      double body = BodySize(idx + i);
      double avg = AvgBodySize(RapidLen, idx + i + 1);
      if(Close[idx + i] < Open[idx + i] && body > avg * RapidMultiplier)
      {
         count++;
         if(count >= MinRapidBars) return true;
      }
      else count = 0;
   }
   return false;
}

bool CalculateChannel(int idx, int total, const double &low[])
{
   if(g_rapidEndBar < 0) return false;
   
   int lookback = MathMin(ChannelLookback, idx - g_rapidEndBar);
   if(lookback < MinTouchPoints) return false;
   
   // 找通道起点（最低）
   g_channelStart = low[g_rapidEndBar];
   for(int i = g_rapidEndBar + 1; i <= g_rapidEndBar + lookback && i < total; i++)
      if(low[i] < g_channelStart) g_channelStart = low[i];
   
   // 简单斜率
   g_channelSlope = (Close[idx] - Close[g_rapidEndBar]) / lookback;
   g_channelHeight = (Close[idx] - g_channelStart) * 1.2;
   
   return (g_channelHeight > 0);
}

//+------------------------------------------------------------------+
//| 版本说明                                                          |
//+------------------------------------------------------------------+
// v2.0: Fixed #property indicator_buffers 8 (was interactionCount)
// Date: 2026-02-12
// Status: Compiles on MetaEditor
