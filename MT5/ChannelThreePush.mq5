//+------------------------------------------------------------------+
//|                                          ChannelThreePush.mq5    |
//|                                     Channel Three Push System    |
//|                                              Developed by AI     |
//+------------------------------------------------------------------+
#property copyright "DeepSeek AI"
#property link      "https://github.com/batizhao1688/trading-indicators"
#property version   "1.0"
#property description "Channel Three Push System - MT5 Indicator"
#property description "Identifies rapid movements, channels, and three-push patterns"
#property description "with failure signal detection"

#property indicator_chart_window
#property indicator_buffers interactionCount
#property indicator_plots   8

//+------------------------------------------------------------------+
//| 输入参数                                                          |
//+------------------------------------------------------------------+
input int      RapidLen          = 10;       // 急速行情检测窗口
input double   RapidMultiplier   = 1.5;      // 实体倍数阈值
input int      MinRapidBars      = 2;        // 最少急速K线数

input int      ChannelLookback   = 20;       // 通道检测窗口
input int      MinTouchPoints    = 3;        // 最少接触点数
input double   ChannelSlopeThreshold = 0.6;  // 通道斜率阈值

input double   Push1MinHeight    = 0.6;      // 第一段最小高度%
input double   Push2MaxHeight    = 0.8;      // 第二段最大高度%
input double   OvershootThreshold = 0.2;     // 过冲阈值%

input int      FailureBars       = 5;        // 衰竭验证K线数
input int      MinSwingCount     = 2;        // 最少摆动次数
input int      ReversalConfirmation = 1;     // 反转确认K线数

input bool     ShowLabels        = true;     // 显示标签
input bool     ShowLines         = true;     // 显示线条
input color    ColorBullish      = clrGreen; // 多头颜色
input color    ColorBearish      = clrRed;   // 空头颜色
input color    ColorNeutral      = clrBlue;  // 中性颜色

//+------------------------------------------------------------------+
//| 指标缓冲区                                                        |
//+------------------------------------------------------------------+
double UpperChannelBuffer[];    // 通道上轨
double LowerChannelBuffer[];    // 通道下轨
double Push1SignalBuffer[];     // 第一段推动信号
double Push2SignalBuffer[];     // 第二段推动信号  
double Push3SignalBuffer[];     // 第三段推动信号
double FailureSignalBuffer[];   // 衰竭信号
double RapidBullishBuffer[];    // 多头急速行情
double RapidBearishBuffer[];    // 空头急速行情

//+------------------------------------------------------------------+
//| 全局变量                                                          |
//+------------------------------------------------------------------+
int    prev_calculated = 0;
int    rapidEndBar = -1;
double channelSlope = 0;
double channelStart = 0;
double channelHeight = 0;

//+------------------------------------------------------------------+
//| 自定义结构体                                                      |
//+------------------------------------------------------------------+
struct SwingPoint {
   int    bar;
   double price;
   bool   isHigh;
};

struct ThreePush {
   int    push1End;
   double push1Height;
   int    push2End;
   double push2Height;
   int    push3End;
   double push3Height;
   bool   failureDetected;
   int    failureBar;
};

//+------------------------------------------------------------------+
//| 自定义函数声明                                                    |
//+------------------------------------------------------------------+
double CalculateBodySize(int index);
double CalculateAvgBodySize(int len, int startIndex);
bool   DetectRapidBullish(int startIndex);
bool   DetectRapidBearish(int startIndex);
bool   CalculateChannel(int startIndex, int rates_total);
int    IdentifyThreePushes(int startIndex, int rates_total);
bool   DetectFailureSignal(int push3End, int rates_total);
void   DrawChannelLines();
void   DrawLabels(int index, ThreePush &push);
void   UpdateInfoTable();

//+------------------------------------------------------------------+
//| 指标初始化函数                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // 设置缓冲区
   SetIndexBuffer(0, UpperChannelBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, LowerChannelBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, Push1SignalBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, Push2SignalBuffer, INDICATOR_DATA);
   SetIndexBuffer(4, Push3SignalBuffer, INDICATOR_DATA);
   SetIndexBuffer(5, FailureSignalBuffer, INDICATOR_DATA);
   SetIndexBuffer(6, RapidBullishBuffer, INDICATOR_DATA);
   SetIndexBuffer(7, RapidBearishBuffer, INDICATOR_DATA);
   
   // 设置绘图属性
   SetIndexStyle(0, DRAW_LINE, STYLE_SOLID, 1, ColorNeutral);
   SetIndexLabel(0, "Upper Channel");
   
   SetIndexStyle(1, DRAW_LINE, STYLE_SOLID, 1, ColorNeutral);
   SetIndexLabel(1, "Lower Channel");
   
   SetIndexStyle(2, DRAW_ARROW, 0, 2, ColorBullish);
   SetIndexArrow(2, 233);
   SetIndexLabel(2, "Push 1");
   
   SetIndexStyle(3, DRAW_ARROW, 0, 2, ColorBullish);
   SetIndexArrow(3, 233);
   SetIndexLabel(3, "Push 2");
   
   SetIndexStyle(4, DRAW_ARROW, 0, 2, ColorNeutral);
   SetIndexArrow(4, 233);
   SetIndexLabel(4, "Push 3");
   
   SetIndexStyle(5, DRAW_ARROW, 0, 3, ColorBearish);
   SetIndexArrow(5, 251);
   SetIndexLabel(5, "Failure");
   
   SetIndexStyle(6, DRAW_HISTOGRAM, 0, 1, ColorBullish);
   SetIndexLabel(6, "Rapid Bullish");
   
   SetIndexStyle(7, DRAW_HISTOGRAM, 0, 1, ColorBearish);
   SetIndexLabel(7, "Rapid Bearish");
   
   // 初始化变量
   rapidEndBar = -1;
   channelSlope = 0;
   channelStart = 0;
   channelHeight = 0;
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| 指标去初始化函数                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // 清理图形对象
   ObjectsDeleteAll(0, "CTPS_");
   Comment("");
}

//+------------------------------------------------------------------+
//| 指标计算函数（性能优化版本）                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated_local,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   // 如果数据不足，返回
   if(rates_total < RapidLen + ChannelLookback + 10)
      return(0);
   
   // 设置计算的起点（性能优化：只计算新数据）
   int startIndex;
   if(prev_calculated_local == 0) {
      startIndex = 0;
      // 初始化缓冲区
      ArrayInitialize(UpperChannelBuffer, EMPTY_VALUE);
      ArrayInitialize(LowerChannelBuffer, EMPTY_VALUE);
      ArrayInitialize(Push1SignalBuffer, EMPTY_VALUE);
      ArrayInitialize(Push2SignalBuffer, EMPTY_VALUE);
      ArrayInitialize(Push3SignalBuffer, EMPTY_VALUE);
      ArrayInitialize(FailureSignalBuffer, EMPTY_VALUE);
      ArrayInitialize(RapidBullishBuffer, 0);
      ArrayInitialize(RapidBearishBuffer, 0);
   } else {
      startIndex = prev_calculated_local - 1;
   }
   
   // 主计算循环（优化：只处理必要的数据）
   for(int i = startIndex; i < rates_total && !IsStopped(); i++)
   {
      // 1. 检测急速行情
      RapidBullishBuffer[i] = 0;
      RapidBearishBuffer[i] = 0;
      
      if(DetectRapidBullish(i)) {
         RapidBullishBuffer[i] = 1;
         rapidEndBar = i;
      } else if(DetectRapidBearish(i)) {
         RapidBearishBuffer[i] = 1;
         rapidEndBar = i;
      }
      
      // 2. 计算通道（只在急速行情后计算）
      if(rapidEndBar != -1 && i >= rapidEndBar + 5)
      {
         if(CalculateChannel(i, rates_total))
         {
            UpperChannelBuffer[i] = channelStart + channelHeight + channelSlope * (i - rapidEndBar);
            LowerChannelBuffer[i] = channelStart + channelSlope * (i - rapidEndBar);
            
            // 3. 识别三段推动
            ThreePush currentPush;
            int pushStatus = IdentifyThreePushes(i, rates_total);
            
            // 4. 标记信号
            if(pushStatus == 1) {
               Push1SignalBuffer[i] = high[i];
            } else if(pushStatus == 2) {
               Push2SignalBuffer[i] = high[i];
            } else if(pushStatus == 3) {
               Push3SignalBuffer[i] = high[i];
               
               // 5. 检测衰竭信号
               if(DetectFailureSignal(i, rates_total)) {
                  FailureSignalBuffer[i] = low[i];
               }
            }
         }
      }
   }
   
   // 更新图形对象（只在最后一条K线）
   if(ShowLabels || ShowLines)
   {
      if(rates_total > 0)
      {
         // 绘制通道线
         if(ShowLines && channelHeight > 0)
            DrawChannelLines();
         
         // 更新信息表
         UpdateInfoTable();
      }
   }
   
   prev_calculated = rates_total;
   return(rates_total);
}

//+------------------------------------------------------------------+
//| 计算K线实体大小                                                   |
//+------------------------------------------------------------------+
double CalculateBodySize(int index)
{
   return MathAbs(Close[index] - Open[index]);
}

//+------------------------------------------------------------------+
//| 计算平均实体大小（带缓存优化）                                    |
//+------------------------------------------------------------------+
double CalculateAvgBodySize(int len, int startIndex)
{
   double sum = 0;
   int count = 0;
   
   for(int i = startIndex; i < startIndex + len && i < Bars; i++)
   {
      sum += CalculateBodySize(i);
      count++;
   }
   
   return count > 0 ? sum / count : 0;
}

//+------------------------------------------------------------------+
//| 检测多头急速行情                                                  |
//+------------------------------------------------------------------+
bool DetectRapidBullish(int startIndex)
{
   int rapidCount = 0;
   
   for(int i = 0; i < RapidLen && startIndex + i < Bars; i++)
   {
      double barBody = CalculateBodySize(startIndex + i);
      double avgBody = CalculateAvgBodySize(RapidLen, startIndex + i + 1);
      
      if(Close[startIndex + i] > Open[startIndex + i] && barBody > avgBody * RapidMultiplier)
      {
         rapidCount++;
         if(rapidCount >= MinRapidBars)
            return true;
      }
      else
      {
         rapidCount = 0;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| 检测空头急速行情                                                  |
//+------------------------------------------------------------------+
bool DetectRapidBearish(int startIndex)
{
   int rapidCount = 0;
   
   for(int i = 0; i < RapidLen && startIndex + i < Bars; i++)
   {
      double barBody = CalculateBodySize(startIndex + i);
      double avgBody = CalculateAvgBodySize(RapidLen, startIndex + i + 1);
      
      if(Close[startIndex + i] < Open[startIndex + i] && barBody > avgBody * RapidMultiplier)
      {
         rapidCount++;
         if(rapidCount >= MinRapidBars)
            return true;
      }
      else
      {
         rapidCount = 0;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| 计算通道（线性回归）                                              |
//+------------------------------------------------------------------+
bool CalculateChannel(int startIndex, int rates_total)
{
   int lookback = MathMin(ChannelLookback, startIndex - rapidEndBar);
   if(lookback < MinTouchPoints)
      return false;
   
   // 线性回归计算
   double sumX = 0, sumY = 0, sumXY = 0, sumXX = 0;
   
   for(int i = 0; i < lookback; i++)
   {
      int idx = rapidEndBar + i;
      if(idx >= 0 && idx < rates_total)
      {
         double x = i;
         double y = Close[idx];
         sumX += x;
         sumY += y;
         sumXY += x * y;
         sumXX += x * x;
      }
   }
   
   double slope = (lookback * sumXY - sumX * sumY) / (lookback * sumXX - sumX * sumX);
   double intercept = (sumY - slope * sumX) / lookback;
   
   // 找到通道起点（第一次回撤低点）
   channelStart = Low[rapidEndBar];
   for(int i = rapidEndBar + 1; i <= rapidEndBar + lookback && i < rates_total; i++)
   {
      if(Low[i] < channelStart)
         channelStart = Low[i];
   }
   
   int currentIdx = startIndex - rapidEndBar;
   double upperPrice = intercept + slope * currentIdx;
   channelHeight = upperPrice - channelStart;
   channelSlope = MathAbs(slope);
   
   return channelHeight > 0;
}

//+------------------------------------------------------------------+
//| 识别三段推动（返回状态：0无，1推1，2推2，3推3）                   |
//+------------------------------------------------------------------+
int IdentifyThreePushes(int startIndex, int rates_total)
{
   static ThreePush currentPush;
   static int lastPushState = 0;
   
   if(channelHeight <= 0)
      return 0;
   
   double upperPrice = channelStart + channelHeight + channelSlope * (startIndex - rapidEndBar);
   double lowerPrice = channelStart + channelSlope * (startIndex - rapidEndBar);
   double currentPosition = (Close[startIndex] - lowerPrice) / channelHeight;
   
   // 状态机识别三段推动
   switch(lastPushState)
   {
      case 0: // 等待第一段推动
         if(currentPosition <= 0.3)
         {
            lastPushState = 1;
            currentPush.push1End = startIndex;
            currentPush.push1Height = currentPosition * 100;
            return 1;
         }
         break;
         
      case 1: // 已识别第一段，等待第二段
         if(currentPosition >= 0.5)
         {
            if(currentPosition * 100 < currentPush.push1Height * Push2MaxHeight)
            {
               lastPushState = 2;
               currentPush.push2End = startIndex;
               currentPush.push2Height = currentPosition * 100;
               return 2;
            }
         }
         break;
         
      case 2: // 已识别第二段，等待第三段
         double overshoot = (High[startIndex] - upperPrice) / channelHeight;
         if(overshoot > 0 && overshoot <= OvershootThreshold)
         {
            lastPushState = 3;
            currentPush.push3End = startIndex;
            currentPush.push3Height = overshoot * 100;
            return 3;
         }
         break;
         
      case 3: // 已完成三段推动
         // 重置状态，等待下一轮
         if(currentPosition < 0.3)
         {
            lastPushState = 0;
            ZeroMemory(currentPush);
         }
         break;
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| 检测衰竭信号                                                     |
//+------------------------------------------------------------------+
bool DetectFailureSignal(int push3End, int rates_total)
{
   if(push3End < 0 || push3End >= rates_total)
      return false;
   
   double upperPrice = channelStart + channelHeight + channelSlope * (push3End - rapidEndBar);
   double lowerPrice = channelStart + channelSlope * (push3End - rapidEndBar);
   
   // 检查是否在指定K线数内回到通道内
   for(int i = 1; i <= FailureBars && push3End + i < rates_total; i++)
   {
      int checkIdx = push3End + i;
      double checkPrice = Close[checkIdx];
      double checkPosition = (checkPrice - lowerPrice) / channelHeight;
      
      if(checkPosition < 1.0)
         return true;
   }
   
   // 检查反转K线形态
   for(int i = 0; i < MathMin(2, FailureBars) && push3End + i < rates_total; i++)
   {
      int idx = push3End + i;
      
      // 吞没形态
      bool engulfBearish = Close[idx] < Open[idx] && 
                          High[idx] >= High[idx-1] && 
                          Low[idx] <= Low[idx-1];
      
      // Pin bar形态
      double bodySize = MathAbs(Close[idx] - Open[idx]);
      double rangeSize = High[idx] - Low[idx];
      double upperWick = High[idx] - MathMax(Close[idx], Open[idx]);
      double lowerWick = MathMin(Close[idx], Open[idx]) - Low[idx];
      bool pinBar = bodySize < rangeSize * 0.3 && upperWick > lowerWick * 2;
      
      if(engulfBearish || pinBar)
         return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| 绘制通道线                                                       |
//+------------------------------------------------------------------+
void DrawChannelLines()
{
   if(!ShowLines) return;
   
   string upperLineName = "CTPS_UpperChannel";
   string lowerLineName = "CTPS_LowerChannel";
   
   // 删除旧对象
   ObjectDelete(0, upperLineName);
   ObjectDelete(0, lowerLineName);
   
   // 创建新对象
   ObjectCreate(0, upperLineName, OBJ_TREND, 0, Time[Bars-1], channelStart + channelHeight, Time[0], channelStart + channelHeight + channelSlope * Bars);
   ObjectSetInteger(0, upperLineName, OBJPROP_COLOR, ColorNeutral);
   ObjectSetInteger(0, upperLineName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, upperLineName, OBJPROP_RAY, false);
   
   ObjectCreate(0, lowerLineName, OBJ_TREND, 0, Time[Bars-1], channelStart, Time[0], channelStart + channelSlope * Bars);
   ObjectSetInteger(0, lowerLineName, OBJPROP_COLOR, ColorNeutral);
   ObjectSetInteger(0, lowerLineName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, lowerLineName, OBJPROP_RAY, false);
}

//+------------------------------------------------------------------+
//| 更新信息表                                                       |
//+------------------------------------------------------------------+
void UpdateInfoTable()
{
   string commentText = "";
   commentText += "=== Channel Three Push System ===\n";
   commentText += "Rapid: " + (RapidBullishBuffer[Bars-1] > 0 ? "Bullish" : RapidBearishBuffer[Bars-1] > 0 ? "Bearish" : "None") + "\n";
   commentText += "Channel Slope: " + DoubleToString(channelSlope, 4) + "\n";
   commentText += "Channel Height: " + (channelHeight > 0 ? DoubleToString(channelHeight, 2) : "N/A") + "\n";
   commentText += "Three Pushes: ";
   
   int pushCount = 0;
   if(Push1SignalBuffer[Bars-1] != EMPTY_VALUE) pushCount++;
   if(Push2SignalBuffer[Bars-1] != EMPTY_VALUE) pushCount++;
   if(Push3SignalBuffer[Bars-1] != EMPTY_VALUE) pushCount++;
   
   commentText += IntegerToString(pushCount) + "/3\n";
   commentText += "Failure Signal: " + (FailureSignalBuffer[Bars-1] != EMPTY_VALUE ? "Detected" : "None") + "\n";
   
   Comment(commentText);
}

//+------------------------------------------------------------------+