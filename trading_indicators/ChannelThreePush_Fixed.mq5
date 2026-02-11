//+------------------------------------------------------------------+
//| ChannelThreePush.mq5 - Fixed Version
//| 修复: indicator_buffers 语法错误 (interactionCount -> 8)
//+------------------------------------------------------------------+
#property copyright "DeepSeek AI"
#property version "1.1"
#property strict
description "Channel Three Push System - MT5 Indicator (Fixed)"

#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots 8

//+------------------------------------------------------------------+
//| 输入参数
//+------------------------------------------------------------------+
input int RapidLen = 10;
input double RapidMultiplier = 1.5;
input int MinRapidBars = 2;
input int ChannelLookback = 20;
input bool ShowLabels = true;
input bool ShowLines = true;
input color ColorBullish = clrGreen;
input color ColorBearish = clrRed;
input color ColorNeutral = clrBlue;

//+------------------------------------------------------------------+
//| 指标缓冲区
//+------------------------------------------------------------------+
double UpperChannelBuffer[];
double LowerChannelBuffer[];
double Push1SignalBuffer[];
double Push2SignalBuffer[];
double Push3SignalBuffer[];
double FailureSignalBuffer[];
double RapidBullishBuffer[];
double RapidBearishBuffer[];

//+------------------------------------------------------------------+
//| 初始化
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, UpperChannelBuffer);
   SetIndexBuffer(1, LowerChannelBuffer);
   SetIndexBuffer(2, Push1SignalBuffer);
   SetIndexBuffer(3, Push2SignalBuffer);
   SetIndexBuffer(4, Push3SignalBuffer);
   SetIndexBuffer(5, FailureSignalBuffer);
   SetIndexBuffer(6, RapidBullishBuffer);
   SetIndexBuffer(7, RapidBearishBuffer);
   
   SetIndexStyle(0, DRAW_LINE, STYLE_SOLID, 1, ColorNeutral);
   SetIndexStyle(1, DRAW_LINE, STYLE_SOLID, 1, ColorNeutral);
   SetIndexStyle(2, DRAW_ARROW);
   SetIndexStyle(3, DRAW_ARROW);
   SetIndexStyle(4, DRAW_ARROW);
   SetIndexStyle(5, DRAW_ARROW);
   SetIndexStyle(6, DRAW_HISTOGRAM);
   SetIndexStyle(7, DRAW_HISTOGRAM);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| 计算函数 (简化版)
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
   
   int start = prev_calculated == 0 ? 0 : prev_calculated - 1;
   
   for(int i = start; i < rates_total; i++)
   {
      // 简单急速检测
      double bodySize = MathAbs(close[i] - open[i]);
      double avgBody = 0;
      
      for(int j = 0; j < RapidLen && j < i; j++)
      {
         avgBody += MathAbs(close[i-j] - open[i-j]);
      }
      
      if(RapidLen > 0)
         avgBody /= RapidLen;
      
      // 多头急速
      if(bodySize > avgBody * RapidMultiplier && close[i] > open[i])
      {
         RapidBullishBuffer[i] = bodySize;
      }
      else
      {
         RapidBullishBuffer[i] = 0;
      }
      
      // 空头急速
      if(bodySize > avgBody * RapidMultiplier && close[i] < open[i])
      {
         RapidBearishBuffer[i] = -bodySize;
      }
      else
      {
         RapidBearishBuffer[i] = 0;
      }
   }
   
   return(rates_total);
}

//+------------------------------------------------------------------+
//| 清理
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "ChannelThreePush_");
}

//+------------------------------------------------------------------+
//| 版本信息
//+------------------------------------------------------------------+
// Fixed: 2026-02-11
// Issue: indicator_buffers interactionCount -> 8
// MQL5语法: indicator_buffers 必须是数字，不是变量名
//+------------------------------------------------------------------+
