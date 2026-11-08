//+------------------------------------------------------------------+
//| 64.165(6) Moving - Tick Analyzer v3.0                            |
//| v165(6): ادامهٔ روند در ماشهٔ ترکیبی + فیلتر SMA/LWMA پریود 4      |
//| Direction: magnitude-weighted + adjacent-tick confirmation +     |
//| spread-based confidence + Order-Flow-Lite (Delta/Divergence)     |
//| Preserves: Group Settings, Objects, Market Behavior Analysis     |
//+------------------------------------------------------------------+
#property copyright "64.00_178.3 (real-low leg origin, origin dot, manual display fib)"
#property version   "178.30"

#property strict

#include <Trade\Trade.mqh>
#define MAX_SAFE_TICK_WINDOW 2000
#define MAX_HISTORY 300        
#define TICK_HUB_SIZE 500
#define DIRECTION_LOOKBACK_TICKS 7   
#define MOMENTUM_LOOKBACK_TICKS 10    
#define POSTENTRY_COOLDOWN_SECONDS 8   
                                       

// ╔══════════════════════════════════════════════════════════════════╗
// ╚══════════════════════════════════════════════════════════════════╝
#define LICENSED_ACCOUNT_NUMBER 0
#define LICENSE_EXPIRY_DATE     "2099-12-31"
#define EnableSymbolGroups true  
//+------------------------------------------------------------------+
class CTickAnalyzerOptimized;

enum EnumTrailingMode { TRAIL_DISABLED, TRAIL_STEP, TRAIL_RISKFREE, TRAIL_RISKFREE_STEP, TRAIL_ADVANCED_ATR, TRAIL_ATR_STEP, TRAIL_HYBRID_ALL, TRAIL_MA, TRAIL_MA_RISKFREE };  

enum EnumSignalSource { SIGNAL_EXTERNAL_INDICATOR, SIGNAL_COMPOSITE_SCORE, SIGNAL_ICHIMOKU_BOX };
enum ENUM_TRADE_STATE {
   TRADE_STATE_IDLE,
   TRADE_STATE_WAITING_CROSS,
   TRADE_STATE_WAITING_OBOS,
   TRADE_STATE_READY_TO_TRADE  };
//+------------------------------------------------------------------+
//| Input Parameters                                                |
//+------------------------------------------------------------------+
input group "1) .                      = Trade Settings ==="
input string Guide_Main = "راهنما: این صفحه (۱) تنظیمات اصلی معامله و فیلترهاست. برای تنظیم رفتار تشخیص بازار به صفحه ۲ (پایین‌تر در همین لیست) بروید.";
input double    AccountBalanceForRisk = 3000 ;
input double    RiskPercentPerTrade   = 0.6 ;
input double    TakeProfit = 10.0;
input double    StopLoss = 4.5 ;

input group "1.5) === حالت پیشنهاد (ارتباط با دیده‌بان) ==="
input bool   SuggestionOnlyMode     = true;   // فقط پیشنهاد بده و هیچ معامله‌ای باز نکن
input bool   ShowSuggestionObjects  = true;   // فلش پیشنهاد روی همین چارت (خرید: سبز رو به بالا زیر کندل، فروش: قرمز رو به پایین بالای کندل)

input group "2) === منبع‌های سیگنال خرید/فروش (چند منبع هم‌زمان) ==="
input bool   UseIndicatorSignal  = true;    // سیگنال اندیکاتور (کراس، رودکراس، موازی و ...)
input bool   UseCompositeSignal  = false;   // ماشهٔ ترکیبی داخلی اکسپرت
input bool   UseBoxSignal        = true;    // باکس ایچیموکو (سیستم اول و دوم)
input bool   UseBoxBreakSignal   = false;   // شکست باکس سیستم اول (سیگنال با شکستِ باکس ثابت‌شده)
input bool   UseBoxBreak2Signal  = false;   // شکست باکس سیستم دوم
// v174: منبعِ در حال پردازش (ورودی نیست؛ حلقهٔ منبع‌ها آن را به‌نوبت تنظیم می‌کند)
EnumSignalSource SignalSource = SIGNAL_EXTERNAL_INDICATOR;

// suggestion validity in minutes (hard-coded)
#define SUGGESTION_VALID_MIN 5


// پارامترهای داخلی مشترک برای ارزهای ماژور و طلا
#define COMPOSITE_DEFAULT_WINDOW         10
#define COMPOSITE_MIN_SAMPLES            8
#define COMPOSITE_MAX_SAMPLES            30
#define COMPOSITE_MAX_AGE_SECONDS        3

#define COMPOSITE_IMBALANCE_WEIGHT       0.45
#define COMPOSITE_FAIR_VALUE_WEIGHT      0.30
#define COMPOSITE_DIRECTION_WEIGHT       0.25

#define COMPOSITE_MIN_EFFICIENCY_HARD    0.20
#define COMPOSITE_MIN_EFFICIENCY_SOFT    0.40

#define COMPOSITE_CONFIRM_TICKS          2
#define COMPOSITE_CONFIRM_MIN_SCORE      58.0
#define COMPOSITE_MAX_RETRACE_PIPS       0.80
#define COMPOSITE_COOLDOWN_SECONDS       3


#define COMPOSITE_MIN_SENSITIVITY        0.80
#define COMPOSITE_MAX_SENSITIVITY        1.20
 input int       SignalExecutionDelay = 0;


#define CompositeTrigger_ImbalanceWindow  COMPOSITE_DEFAULT_WINDOW
#define CompositeTrigger_FairValueWindow  COMPOSITE_DEFAULT_WINDOW

#define CompositeTrigger_BuyThreshold      Composite_GetBuyThreshold()
#define CompositeTrigger_SellThreshold     Composite_GetSellThreshold()
 
input group "2.2) === استراتژی باکس ایچیموکو: سیستم اول (تایم‌فریم چارت) ==="
input int    Box_TenkanBars = 9;               // تعداد کندل باکس کوچک (تنکن‌سن) با احتساب هر دو دیواره
input int    Box_KijunBars  = 26;             // تعداد کندل باکس میانی (کیجن‌سن)
input int    Box_SpanBBars  = 52;             // تعداد کندل باکس بزرگ (اسپن بی) و هدف سود
input int    Box_ChikouShift = 26;            // شیفت چیکو اسپن (= دورهٔ کیجن‌سن مقابل آن در شرط ۲)
input bool   ShowBoxObjects = true;           // رسم باکس‌ها، دات‌های دیواره و خط تراز (سیستم اول)
input double Box_SharedTolPoints = 0.0;       // تلورانس برابری لو/های مشترک (پوینت)؛ ۰ = برابری دقیق
input group "2.3) === استراتژی باکس ایچیموکو: سیستم دوم (تایم‌فریم دوم، مستقل) ==="
input bool            Box2_Enable = true;     // روشن/خاموش کردن سیستم دوم
input ENUM_TIMEFRAMES Box2_Timeframe = PERIOD_M10;   // تایم‌فریم سیستم دوم
input int    Box2_TenkanBars = 45;            // باکس کوچک سیستم دوم
input int    Box2_KijunBars  = 130;           // باکس میانی سیستم دوم
input int    Box2_SpanBBars  = 260;           // باکس بزرگ سیستم دوم
input int    Box2_ChikouShift = 130;          // شیفت چیکو اسپن سیستم دوم
input bool   ShowBox2Objects = true;          // رسم باکس‌ها و خط تراز سیستم دوم
input group "3) .                      = Trailing Stop Settings ==="

input EnumTrailingMode TrailingMode = TRAIL_MA_RISKFREE;
input double    TrailingStep = 3.0 ;
input double    TrailingStart = 3.8 ;
input double    RiskFreeStart  = 2.0 ;
input double    RiskFreeBufferPip = 0.5 ;
input double    TrailingStartMA = 3.5 ;      
input double    MA_TrailDistancePip = 3.0 ;  
//----------------------------------------------------


enum ENUM_POSTENTRY_SENSITIVITY {
   PE_SENS_ULTRA_WEAK = 0,   // خیلی‌ضعیف - آسان‌گیرترین، برای پرنویزترین نمادها
   PE_SENS_VERY_WEAK  = 1,   // بسیارضعیف
   PE_SENS_WEAK       = 2,   // ضعیف (همان مقدار نسخهٔ قبلی)
   PE_SENS_LOW        = 3,   // کم
   PE_SENS_MEDIUM      = 4,   // متوسط (پیش‌فرض)
   PE_SENS_HIGH        = 5    // زیاد - سریع‌ترین واکنش
};

enum ENUM_POSTENTRY_REACTION {
   PE_REACT_TIGHTEN = 0,   // نزدیک‌کردن استاپ (پله‌پله)
   PE_REACT_CLOSE   = 1    // بستن کامل معامله
};


input group ".**********************************************"
input group "7) .                         تشخیص رفتار تیک  ==="

input group "8) .                        TICK ANALYSIS FILTER ==="
input bool      ShowTickAnalysisOnChart = true;

input group "9) .            تنظیم دقت تیک انالیز  ==="
input double MinMomentum = 0.35 ;  
 input group ".**********************************************"

//------------------------------------------
input group "12) === تنظیمات گروه‌بندی نمادها ==="
enum SYMBOL_GROUPS {
    GROUP_XAUUSD,
    GROUP_MAJORS,
    GROUP_CROSSES  };   // v176.7: گروه‌های شاخص/کالا/سایر حذف شدند؛ نماد ناشناخته → گروه را دستی روی طلا بگذارید

input group "13) .                           تنظیم تخصصی هر گروه  و هر ارز ==="

input SYMBOL_GROUPS  ManualSymbolGroup = GROUP_XAUUSD;
input bool          AutoDetectGroup   = true;
bool g_symbolUnknown = false;   // v176.7: در تشخیص خودکار، نماد جزو طلا/ماژور/کراس نیست

input group "14) === تنظیمات XAUUSD (طلا) ==="
input bool   EnableXAUFilter   = false;  
input bool      EnableRegimeRestrictions = false ;    //خاموش=همهٔ محدودیت‌های رژیم بازار (مرده/نویزی/خیلی‌سریع/رنج‌رژیمی/قدرت/نامشخص)
input double XAU_MinRange      = 5.0;
input int    XAU_MinDirection  = 70 ;
input double XAU_MaxSpread     = 30.0;
input double XAU_MaxNoiseSpeed = 3.0 ;
input double XAU_MinEfficiency = 0.30;  

input group "15) === تنظیمات جفت‌ارزهای اصلی (کالیبره‌شده برای M2) ==="
input double MAJ_MinRange       = 0.5 ;  
input int    MAJ_MinDirection   = 47.0;
input double MAJ_MaxSpread      = 2.0 ;
input double MAJ_MaxNoiseSpeed  = 1.9 ;

input double MAJ_MinEfficiency = 0.30;   

input group "16)  "
input double CRS_MinRange       = 1.3;
input int    CRS_MinDirection   = 70.0;
input double CRS_MaxSpread      = 4.0;
input double CRS_MaxNoiseSpeed  = 3.5;
input double CRS_MinEfficiency = 0.30;  

input bool   EnableEfficiencyFilter = false; //تشخیص اسپایک‌که‌سایه‌می‌شود


input group "19) === تشخیص رنج بر پایه کندل (کانال دونچیان) ==="
input bool   EnableCandleRangeFilter = false;  
input int    DonchianPeriod = 7;
input int    DonchianATR_Period = 7;
input double DonchianRangeWidthATRRatio = 2.4;

input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓"
input group "22)   📄         فیلتر های تکمیلی ا"
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓"

input group "37) === فیلتر ابر آلفا (ایچیموکو تک) ==="
input bool      EnableAlphaCloudFilter = true;    // فیلتر ابر آلفا روشن/خاموش
input int       Alpha_Tenkan  = 9;                  // دورهٔ Tenkan
input int       Alpha_Kijun   = 26;                 // دورهٔ Kijun
input int       Alpha_SenkouB = 52;                 // دورهٔ Senkou B
input int       Alpha_Shift   = 26;                 // شیفت رو به جلوی ابر
input double    Alpha_EpsPips = 1.0;                // اطمینان دور لبهٔ ابر (پیپ)

input group "38) === فیلتر تأیید واگرایی MACD (معمولی، پنهان، تایم جاری + M5 + M15) ==="
input bool      EnableDivergenceFilter = false;   // فیلتر تأیید با واگرایی روشن/خاموش (خرید: واگرایی صعودی، فروش: واگرایی نزولی)
input int       DivergenceValidBars    = 20;      // اعتبار واگرایی: تا چند کندل بعد از ایجادش ترید تأیید شود
input int       DivMACD_FastEMA        = 12;      // مکدیِ واگرایی: دورهٔ EMA سریع
input int       DivMACD_SlowEMA        = 26;      // مکدیِ واگرایی: دورهٔ EMA کند
input int       DivMACD_SignalSMA      = 9;       // مکدیِ واگرایی: دورهٔ SMA سیگنال
input ENUM_APPLIED_PRICE DivMACD_AppliedPrice = PRICE_CLOSE;   // مکدیِ واگرایی: قیمت اعمال‌شده
input int       DivSwingBars           = 3;       // حساسیت قله/دره‌ی مکدی: تعداد کندل دو طرف برای تأیید (بزرگ‌تر = فقط قله‌های مهم‌تر)
input int       DivMinPivotDist        = 5;       // کمترین فاصلهٔ دو قله/دره‌ی مکدی (کندل)
input int       DivMaxPivotDist        = 60;      // بیشترین فاصلهٔ دو قله/دره‌ی مکدی (کندل)
enum ENUM_DIV_MACD_SOURCE { DIV_SRC_MAIN = 0,        // خط اصلی MACD
                            DIV_SRC_HISTOGRAM = 1 };  // هیستوگرام MACD (اصلی منهای سیگنال)
input ENUM_DIV_MACD_SOURCE DivMACD_Source = DIV_SRC_MAIN;   // منبع واگرایی: خط اصلی یا هیستوگرام
input bool      EnableHiddenDivergence = true;    // واگرایی پنهان هم تأیید کند (صعودی پنهان → خرید، نزولی پنهان → فروش)
input bool      DivUseHigherTF         = true;    // واگرایی تایم M5 و M15 هم بررسی شود (معتبر در هر کدام → تأیید)

input group "39) === ورود هوشمند بر پایهٔ کیفیت لگ (فوری یا پولبک روی فیبوناچی) ==="
input bool      EnableLegEntry          = true;    // روشن: هر سیگنال بر اساس کیفیت لگ یا فوری وارد می‌شود یا روی فیبوناچی منتظر پولبک می‌ماند (خاموش = همیشه فوری)
input int       Leg_FreshBars           = 3;       // سیگنال تا این تعداد کندل بعد از شروع اندیکاتور «تازه» است (در این مدت مبدأ لگ = قیمت شروع سیگنال)
input double    Leg_BigRangeMult        = 6.0;     // لگ بزرگ: لگ ≥ این ضریب × میانهٔ دامنهٔ ۲۰ کندل ← فقط پولبک (مقدار آزمایشی؛ بعداً تنظیم می‌شود)
input double    Leg_MinEfficiency       = 0.40;    // «تیک قوی»: کارایی حداقل (۰ تا ۱)
input double    Leg_MinImbalance        = 0.20;    // «تیک قوی»: عدم‌توازن هم‌جهت با سیگنال حداقل (۰ تا ۱)
input double    Leg_PullbackPct         = 38.2;    // فیبوی ورود پولبک: لگ بزرگ یا فقط یکی از (تیک قوی، تازگی)
input double    Leg_Fib2Pct             = 50.0;    // فیبوی ورود: لگ کوچک با تیک ضعیف و سیگنال کهنه
input bool      ShowFibOnChart          = true;    // حالت اولیهٔ دکمهٔ FIB (رسم فیبوناچی روی چارت)
input bool      ShowDisplayFib          = true;    // حالت اولیهٔ دکمهٔ «فیبو نمایش» (SHOW/HIDE): فقط نمایش، بدون اثر در تصمیم‌ها
input bool      ShowEntryDecisionDetails = true;   // توضیح مراحل تصمیم روی پنل و کنار کندل؛ برای کم کردن شیءها خاموش کنید


 input group  ". *************************************************************************** "
input group "23) .                      = Stochastic 1 Settings ==="
//  #define STOCHASTIC_METHOD MODE_SMA
input bool      UseStochastic1Confirmation = false;
input int       Stochastic1_K_Period = 9 ;
input int       Stochastic1_D_Period = 5 ;
input int       Stochastic1_Slowing = 5 ;
input double    Stochastic1_Overbought = 85;
input double    Stochastic1_Oversold = 15;
input ENUM_TIMEFRAMES Stochastic1Timeframe = PERIOD_CURRENT;

input group "25) .                      = Stochastic 2 Settings ==="

input bool      UseStochastic2Confirmation = false;
input int       Stochastic2_K_Period = 14;
input int       Stochastic2_D_Period = 9;
input int       Stochastic2_Slowing = 9;
input double    Stochastic2_Overbought = 85;
input double    Stochastic2_Oversold = 15;
input ENUM_TIMEFRAMES Stochastic2Timeframe = PERIOD_CURRENT;

//----------------------------------------------------
input group "26) .            =  تنظیم ساعت کار  در دو مرحله  Session Settings ==="
input int    ManualClockCorrectionMinutes = 0;
input bool      EnableSession1 = true  ;  
input string    StartTime1 = "07:00";
input string    EndTime1 = "23:59";
input bool      EnableSession2 = false;
input string    StartTime2 = "19:10";
input string    EndTime2 = "23:59";

//-------------------------------------------------------
input group "27) .                جلوگیری از ترید در بازار خبری==="
input bool      EnableNewsFilter       = false;  
input string    NewsCalendarURL        = "https:   // nfs.faireconomy.media/ff_calendar_thisweek.json";
input int       NewsRefreshMinutes     = 30;

input int       NewsBlockMinutesBefore = 15;
input int       NewsBlockMinutesAfter  = 15;
input bool      ShowNewsPanel          = true;
input int       NewsPanel_X            = 200 ;
input int       NewsPanel_Y            = 90 ;


input group "28) .         =     جلوگیری از ضرر های پشت سر هم  Loss Management Filter ==="
input bool      EnableLossManagement = false;
input int       MaxConsecutiveLosses = 3;
input int       TradingPauseMinutes = 30;
input bool      ResetOnProfit = false;


//------------------------------------------------------
input group "29) === Manual Position Management ==="
input bool      EnableManualManagement = true;
input bool      Manual_AutoSLTP = true;
input bool      Manual_BlockAutoTrading = true;
input bool      Manual_SendAlerts = true;
input string    Manual_CommentFilter = "MANUAL";
input int       CloseButton_X = 180 ;
input int       CloseButton_Y = 400 ;
input color     CloseButton_Color = clrRed;

input group "31) **************تنظیمات مدیریت ترید روی چارت  ********************"
input group "32) .                      = Auto Trading Toggle ==="
input bool      AutoTradingEnabled = true;
input color     AutoTradeButton_Color_On = clrGreen;
input color     AutoTradeButton_Color_Off = clrRed;

input group "33) .                      = Pause Management Settings ==="
input color     PauseButtonColor_Active = clrBlue;
input color     PauseButtonColor_Paused = clrGray;

input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓"
input group "34)   📍 موقعیت پنل گزارش روی چارت (Tick Analysis Panel)"
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓"
input int       PanelPositionX = 450;
input int       PanelPositionY = 60;
//--------------------------------

input group "10) .REAL STRENGTH FILTER  ==="
input bool   EnableRealStrengthFilter = false ;
input double MinRealStrength          = 35.0;
input double MinAcceleration          = 0.05;
input int    RealStrengthSmoothPeriod = 12;

input group "30) .         تنظیمات پرینت  و ارسال خطا  System Protection ==="
input bool      EnableNotification = false;
input bool      StatusBarEnable = false;
input bool      DebugLogEnable = false;
input bool      OnlyTradeOnNewBar = false;
input bool      ImmediateTradeOnSignal = true;
input int       StochasticCrossLookbackBars = 50;

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+

input group "2.1) === تنظیمات ماشهٔ ترکیبی ==="

input double CompositeTrigger_Sensitivity = 1.00;

input double CompositeTrigger_SignalStrength = 15.0;

//+------------------------------------------------------------------+
//| ثابت‌های کالیبره‌شده — در منو دیده نمی‌شوند؛ فقط در همین کد تغییر می‌کنند |
//+------------------------------------------------------------------+
// ── تنظیمات پنهان (از منو خارج شده‌اند) ──────────────────────────────────
// آشکار کردن: کلمهٔ const را به input تبدیل کنید و خط‌ها را زیر همان عنوان گروه در بخش ورودی‌ها بگذارید.
// توجه: مقدار این خط‌ها پیش‌فرض‌های فایل است، نه مقدارهایی که قبلاً در پنجرهٔ ورودی‌های ترمینال گذاشته بودید.
// گروه منو: «35) = ATR Filter Settings ===»
const bool      EnableATRFilter = false;
const double    MinimalATR = 0.001;
const double    MaximalATR = 999;
const ENUM_TIMEFRAMES ATRTimeframe = PERIOD_M1;
const int       ATRPeriod = 14;
const int       ATR_BestRangeBars = 200;
// گروه منو: «36) = ADX Power Exit Settings ===»
const bool      EnableADXPowerExit = false;
const bool      EnableDMICrossExit = false;
const bool      EnableADXStrengthExit = false;
const ENUM_TIMEFRAMES ADXPowerExit_Timeframe = PERIOD_M5;
const int       ADXPowerExit_Period = 14;
const double    ADXPowerExit_Min = 25.0;
// گروه منو: «4) === مدیریت پیشرفته (فعال با TRAIL_ADVANCED_ATR*) ===»
const ENUM_TIMEFRAMES AdvATR_Timeframe = PERIOD_CURRENT;
const int       AdvATR_Period = 4 ;
const double    AdvATR_TrailMultiplier = 1.5;
const double    AdvATR_MinTrailPips = 2.2 ;
const double    AdvATR_TrailingStart = 5.0;
const bool      AdvATR_SessionPeriodMode = false;
// گروه منو: «5) === نظارت زنده رژیم پس از ورود (لایهٔ دوم) ===» (همراه ورودی‌های حساسیت و واکنشِ همین نظارت)
const bool      EnablePostEntryRegimeMonitor = false ;
const ENUM_POSTENTRY_SENSITIVITY PostEntry_Sensitivity = PE_SENS_MEDIUM;   // حساسیت نظارت زنده
const ENUM_POSTENTRY_REACTION PostEntry_ReactionType = PE_REACT_TIGHTEN;   // نوع واکنش هنگام فعال‌شدن
const double    PostEntry_TightenBufferPip = 1.0;   // فقط وقتی نوع واکنش = نزدیک‌کردن استاپ

// دقت تیک‌آنالیز
const int    TA_LookbackTicks  = 17 ;
#define TA_MIN_CONSISTENCY 80.0
const int    DirectionPersistTicks = 1 ;

// رژیم بازار: طبقه‌بندی پله‌ای / نویزی / روند سریع
const double RegimeSteppingAlternationMin = 0.14;
const double RegimeSteppingMaxDirection   = 32.0;
const double RegimeNoisyOverrideScore      = 19.0;
const double    RegimeFastTrendDirMultiplier = 1.2;  

// رژیم بازار: آستانه‌ها (گروه‌های طلا، اصلی‌ها، کراس‌ها)
const int    RegimePersistCycles   = 2;
const double RegimeLongHorizonMinDirection = 0.0;
const double XAU_Regime_MinRange      = 0.3;
const double XAU_Regime_MinDirection  = 8.0;
const double XAU_Regime_MaxSpread     = 30.0;
const double XAU_Regime_MaxNoiseSpeed = 2.2;

const double MAJ_Regime_MinRange      = 0.35;
const double MAJ_Regime_MinDirection  = 6.0;
const double MAJ_Regime_MaxSpread     = 16.0;
const double MAJ_Regime_MaxNoiseSpeed = 5.0;

const double CRS_Regime_MinRange      = 0.25;
const double CRS_Regime_MinDirection  = 10.0;
const double CRS_Regime_MaxSpread     = 13.0;
const double CRS_Regime_MaxNoiseSpeed = 3.0;

// خط‌مبنای خودتطبیق رژیم
const bool   EnableAdaptiveRegimeBaseline = true;
const int    RegimeBaselineFastMinutes = 20;
const int    RegimeBaselineSlowMinutes = 240;
const double RegimeBaselineMinMultiplier = 0.30;
const double RegimeBaselineMaxMultiplier = 3.00;

//+------------------------------------------------------------------+
struct MarketState {
    double      strength;
    double      quality;  
    int         market_index;
    string      pattern;
    bool        is_trending;
    bool        is_volatile;
    double      confidence;
    string      bias;
    
    MarketState() {
        strength = 0.0;
        quality = 0.0;
        market_index = 0;
        pattern = "Unknown";
        is_trending = false;
        is_volatile = false;
        confidence = 0.0;
        bias = "Neutral";  }  };

    struct MyMqlTick {
    double price;
    datetime time;
    double move;
    bool is_valid;
  MyMqlTick() {
        price = 0.0;
        time = 0;
        move = 0.0;
        is_valid = false; }  };
   
struct EnhancedTickStats {
    int     consecutive_ticks;
    int     current_consecutive_count;
    int     current_consecutive_direction;
    double  consecutive_strength_sum;
    int     direction_changes;
    double  total_power;
    int     positive_ticks;
    double  direction_consistency;
    double  direction_change_ratio;
    string  market_regime_text;
    
    EnhancedTickStats() {
        consecutive_ticks = 0;
        current_consecutive_count = 0;
        current_consecutive_direction = 0;
        consecutive_strength_sum = 0.0;
        direction_changes = 0;
        total_power = 0.0;
        positive_ticks = 0;
        direction_consistency = 0.0;
        direction_change_ratio = 0.0;
        market_regime_text = "Unknown"; }   };

struct MarketStats {
    double rangePips;
    int    directionScore;
    double consistency;
    double avgSpeed;
    double currentSpread;
    int    tickVolume;
    double acceleration;
    double realStrength;
    double speedRatio;
    bool   directionPersistOK;
    // ========== Order-Flow-Lite ==========
    double deltaValue;
    bool   priceDeltaDivergence;
    double orderPressureProxy;
    // =============================
        double alternationRatio;
        double stepPatternRatio;   
        double efficiencyRatio;   // v151: نسبت جابه‌جایی خالص به مسافت کل طی‌شده - برای تشخیص اسپایک‌هایی که به سایه تبدیل می‌شوند
        double tickImbalance;      // v153: (تیک‌های بالا - تیک‌های پایین)/(مجموع) در بازهٔ اخیر، بین -1 و 1
        double fairValueDeviation; // v153: فاصلهٔ قیمت فعلی از میانگین ساده‌ی اخیر، به پیپ (علامت‌دار)
        // =============================
    
    MarketStats() {
        rangePips = 0;
        directionScore = 0;
        consistency = 0;
        avgSpeed = 0;
        currentSpread = 0;
        tickVolume = 0;
        alternationRatio = 0;
        stepPatternRatio = 0;
        efficiencyRatio = 1.0;   // پیش‌فرض خنثی (کاملاً کارا) تا وقتی داده کافی نباشد چیزی رد نشود
        tickImbalance = 0.0;      // v153
        fairValueDeviation = 0.0; // v153
        acceleration = 0;
        realStrength = 0;
        speedRatio = 1.0;
        directionPersistOK = false;
        // ========== Order-Flow-Lite ==========
        deltaValue = 0;
        priceDeltaDivergence = false;
        orderPressureProxy = 0;
        // =============================
    }  };

//+------------------------------------------------------------------+
//| Composite Trigger Helpers / Evaluator                             |
//+------------------------------------------------------------------+

double ClampD(double value, double minv, double maxv)
{
   if(value < minv) return minv;
   if(value > maxv) return maxv;
   return value;
}

double Composite_GetSensitivity()
{
   return MathMax(COMPOSITE_MIN_SENSITIVITY,
                  MathMin(COMPOSITE_MAX_SENSITIVITY, CompositeTrigger_Sensitivity));
}

double Composite_GetBuyThreshold()
{
   double sens = Composite_GetSensitivity();
   double strength = CompositeTrigger_SignalStrength * sens;
   double t = 50.0 + strength;
   return ClampD(t, 55.0, 90.0);
}

double Composite_GetSellThreshold()
{
   double sens = Composite_GetSensitivity();
   double strength = CompositeTrigger_SignalStrength * sens;
   double t = 50.0 - strength;
   return ClampD(t, 10.0, 45.0);
}

bool Composite_GetRecentWindow(double &priceBuffer[],
                              datetime &timeBuffer[],
                              double &speedBuffer[],
                              int &dirBuffer[],
                              double &spreadBuffer[],
                              int &count)
{
   if(g_tick_hub == NULL)
      return false;

count = g_tick_hub.GetTicksForComposite(
   priceBuffer,
   timeBuffer,
   speedBuffer,
   dirBuffer,
   spreadBuffer,
   COMPOSITE_MAX_SAMPLES
);

   if(count < COMPOSITE_MIN_SAMPLES)
      return false;

   datetime nowT = TimeCurrent();
   int validCount = 0;

   for(int i = 0; i < count; i++)
   {
      if((nowT - timeBuffer[i]) <= COMPOSITE_MAX_AGE_SECONDS)
      {
         priceBuffer[validCount]   = priceBuffer[i];
         timeBuffer[validCount]    = timeBuffer[i];
         speedBuffer[validCount]   = speedBuffer[i];
         dirBuffer[validCount]     = dirBuffer[i];
         spreadBuffer[validCount]  = spreadBuffer[i];
         validCount++;
      }
   }

   if(validCount < COMPOSITE_MIN_SAMPLES)
      return false;

   count = validCount;
   return true;
}

double Composite_WeightedImbalance(const double &priceBuffer[],
                                  const int &dirBuffer[],
                                  const double &speedBuffer[],
                                  int count)
{
   double upMove = 0.0;
   double downMove = 0.0;

   for(int i = 1; i < count; i++)
   {
      double movePips = MathAbs(priceBuffer[i] - priceBuffer[i-1]) / GetPip();

      if(dirBuffer[i] > 0)
         upMove += movePips;
      else if(dirBuffer[i] < 0)
         downMove += movePips;
   }

   double total = upMove + downMove;
   if(total <= 0.0)
      return 0.0;

   return (upMove - downMove) / total;  // بین -1 و +1
}

//---------------------
double Composite_ComputeFairValueDeviation(const double &priceBuffer[],
                                           int count,
                                           double &emaOut)
{
   if(count <= 1)
   {
      emaOut = (count > 0) ? priceBuffer[0] : 0.0;
      return 0.0;
   }

   double ema = priceBuffer[0];
   double alpha = 2.0 / ((double)MathMin(10, count) + 1.0);

   for(int i = 1; i < count; i++)
   {
      ema = alpha * priceBuffer[i] + (1.0 - alpha) * ema;
   }

   emaOut = ema;

   // میانگین اندازهٔ حرکت اخیر برحسب پیپ
   double recentVolatilityPips = 0.0;

   for(int i = 1; i < count; i++)
   {
      recentVolatilityPips +=
         MathAbs(priceBuffer[i] - priceBuffer[i - 1]) / GetPip();
   }

   recentVolatilityPips /= (double)(count - 1);

   if(recentVolatilityPips < 0.05)
      recentVolatilityPips = 0.05;

   double currentPrice = priceBuffer[count - 1];

   double deviationPips =
      (currentPrice - ema) / GetPip();

   // انحراف نرمال‌شده نسبت به نوسان اخیر
   return deviationPips / recentVolatilityPips;
}
double Composite_ComputeEfficiency(const double &priceBuffer[],
                                  int count)
{
   if(count <= 2)
      return 1.0;

   double totalDistance = 0.0;
   double netMove = 0.0;

   for(int i = 1; i < count; i++)
   {
      double delta = priceBuffer[i] - priceBuffer[i-1];
      totalDistance += MathAbs(delta);
      netMove += delta;
   }

   if(totalDistance <= 0.0)
      return 1.0;

   double eff = MathAbs(netMove) / totalDistance;
   return ClampD(eff, 0.0, 1.0);
}

double Composite_ComputeDirectionBias(const int &dirBuffer[],
                                     int count)
{
   int up = 0;
   int down = 0;

   for(int i = 0; i < count; i++)
   {
      if(dirBuffer[i] > 0) up++;
      else if(dirBuffer[i] < 0) down++;
   }

   int total = up + down;
   if(total <= 0)
      return 0.0;

   return (double)(up - down) / (double)total;
}

int Composite_EvaluateTrigger(string &reason)
{
   reason = "";

   if(g_tick_hub == NULL)
   {
      reason = "NO_TICK_HUB";
      return 0;
   }

   double priceBuffer[COMPOSITE_MAX_SAMPLES];
   datetime timeBuffer[COMPOSITE_MAX_SAMPLES];
   double speedBuffer[COMPOSITE_MAX_SAMPLES];
   int dirBuffer[COMPOSITE_MAX_SAMPLES];
   double spreadBuffer[COMPOSITE_MAX_SAMPLES];
   int count = 0;

   if(!Composite_GetRecentWindow(priceBuffer, timeBuffer, speedBuffer, dirBuffer, spreadBuffer, count))
   {
      reason = "NOT_ENOUGH_TICKS";
      return 0;
   }

   double imbalance = Composite_WeightedImbalance(priceBuffer, dirBuffer, speedBuffer, count);
   double bias = Composite_ComputeDirectionBias(dirBuffer, count);
   double efficiency = Composite_ComputeEfficiency(priceBuffer, count);

   if(efficiency < COMPOSITE_MIN_EFFICIENCY_HARD)
   {
      reason = "LOW_EFFICIENCY_HARD";
      return 0;
   }

   double ema = 0.0;
   double deviation = Composite_ComputeFairValueDeviation(priceBuffer, count, ema);

   double fairScore = 50.0 + deviation * 2.5;
   fairScore = ClampD(fairScore, 0.0, 100.0);

   double imbalanceScore = 50.0 + imbalance * 45.0;
   double directionScore = 50.0 + bias * 35.0;

   double softPenalty = 1.0;
   if(efficiency < COMPOSITE_MIN_EFFICIENCY_SOFT)
      softPenalty = 0.55 + (efficiency / 0.85);

   double composite = (COMPOSITE_IMBALANCE_WEIGHT * imbalanceScore) +
                      (COMPOSITE_FAIR_VALUE_WEIGHT * fairScore) +
                      (COMPOSITE_DIRECTION_WEIGHT * directionScore);

   composite = 50.0 + (composite - 50.0) * softPenalty;

   double currentSpreadPips = 0.0;
   for(int i = 0; i < count; i++)
      currentSpreadPips = MathMax(currentSpreadPips, spreadBuffer[i] / GetPip());

   double spreadPenalty = 1.0;
   if(currentSpreadPips > 2.0)
      spreadPenalty = MathMax(0.35, 1.0 - (currentSpreadPips - 2.0) * 0.10);

   composite *= spreadPenalty;
   composite = ClampD(composite, 0.0, 100.0);

   double buyThreshold = Composite_GetBuyThreshold();
   double sellThreshold = Composite_GetSellThreshold();

   if(composite >= buyThreshold)
   {
      reason = "BUY_CANDIDATE";
      return 1;
   }

   if(composite <= sellThreshold)
   {
      reason = "SELL_CANDIDATE";
      return -1;
   }

   reason = "WAITING";
   return 0;
}
// +------------------------------------------------------------------+
//| ✅ TICK HUB v1.0 - Centralized Tick Management                   |
//+------------------------------------------------------------------+
struct UnifiedTick {
    double    bid;        
    double    ask;        
    double    last;       
    datetime  time;   
    long      time_msc; 
    long      volume;     
    double    move_bid;   
    double    move_ask;  
    double    move_last;  
    bool      processed_v260;
    bool      processed_v30;
    bool      is_valid;
    
    UnifiedTick() {
        bid = 0.0;
        ask = 0.0;
        last = 0.0;
        time = 0;
        volume = 0;
        move_bid = 0.0;
        move_ask = 0.0;
        move_last = 0.0;
        processed_v260 = false;
        processed_v30 = false;
        is_valid = false;
        }  };
//+------------------------------------------------------------------+
//| ✅ TICK HUB v2.0 - MQL5 Native with BID/ASK/LAST               |
//+------------------------------------------------------------------+
class CTickHub {
private:
    UnifiedTick   m_ticks[TICK_HUB_SIZE];
    int           m_index;
    int           m_count;
    double        m_last_bid;
    double        m_last_ask;
    double        m_last_last;
    long          m_last_tick_time_msc;
    datetime      m_last_tick_time;
    
public:
    CTickHub() {
        m_index = 0;
        m_count = 0;
        m_last_bid = 0.0;
        m_last_ask = 0.0;
        m_last_last = 0.0;
        m_last_tick_time_msc = 0;
        m_last_tick_time = 0;
        
        for(int i = 0; i < TICK_HUB_SIZE; i++) { 
            m_ticks[i].bid = 0.0;
            m_ticks[i].ask = 0.0;
            m_ticks[i].last = 0.0;
            m_ticks[i].time = 0;
            m_ticks[i].volume = 0;
            m_ticks[i].move_bid = 0.0;
            m_ticks[i].move_ask = 0.0;
            m_ticks[i].move_last = 0.0;
            m_ticks[i].processed_v260 = false;
            m_ticks[i].processed_v30 = false;
            m_ticks[i].is_valid = false;  }  }

 bool AddTick(MqlTick &current_tick) {
      if(current_tick.bid <= 0 || current_tick.ask <= 0) return false;
    
     if(current_tick.time_msc == m_last_tick_time_msc) {
  
            if(MathAbs(current_tick.bid - m_last_bid) > 0 || 
           MathAbs(current_tick.ask - m_last_ask) > 0) {
             } else {
            return false;  }}
            
    double time_gap = 0;
    if(m_last_tick_time_msc > 0) {
        time_gap = (current_tick.time_msc - m_last_tick_time_msc) / 1000.0;
    }
  //---------------------------------------------------  
    int idx = m_index;
    m_ticks[idx].bid = current_tick.bid;
    m_ticks[idx].ask = current_tick.ask;
    m_ticks[idx].last = current_tick.last;
    m_ticks[idx].time = current_tick.time;
    m_ticks[idx].volume = (long)current_tick.volume;
    m_ticks[idx].time_msc = current_tick.time_msc;
    m_ticks[idx].is_valid = true;
    
    if(m_last_bid > 0.0) {
        if(time_gap > 1.0) {
            
            m_ticks[idx].move_bid = 0.0;
            m_ticks[idx].move_ask = 0.0;
            m_ticks[idx].move_last = 0.0;
        } else {
            m_ticks[idx].move_bid = current_tick.bid - m_last_bid;
            m_ticks[idx].move_ask = current_tick.ask - m_last_ask;
            m_ticks[idx].move_last = current_tick.last - m_last_last;
        }
    } else {
        m_ticks[idx].move_bid = 0.0;
        m_ticks[idx].move_ask = 0.0;
        m_ticks[idx].move_last = 0.0;
    }
 
m_ticks[idx].processed_v260 = false;
    m_ticks[idx].processed_v30 = false;
    m_index = (m_index + 1) % TICK_HUB_SIZE;
    m_count = MathMin(m_count + 1, TICK_HUB_SIZE);
    
    m_last_bid = current_tick.bid;
    m_last_ask = current_tick.ask;
    m_last_last = current_tick.last;
    m_last_tick_time_msc = current_tick.time_msc;
    m_last_tick_time = current_tick.time;
    
    return true; }      
  
    int GetTicksFor_v260(MyMqlTick &output_ticks[], int max_ticks) {
        int collected = 0;
    int start_idx = (m_index - m_count + TICK_HUB_SIZE) % TICK_HUB_SIZE;  
  
    for(int i = 0; i < m_count && collected < max_ticks; i++) {
    int idx = (start_idx + i) % TICK_HUB_SIZE;
            if(m_ticks[idx].is_valid && !m_ticks[idx].processed_v260) {
                m_ticks[idx].processed_v260 = true;
output_ticks[collected].price = m_ticks[idx].bid;
                output_ticks[collected].time = m_ticks[idx].time;
                output_ticks[collected].move = m_ticks[idx].move_bid;
                output_ticks[collected].is_valid = true;
                
                collected++;  }}
            return collected;  } 
//+------------------------------------------------------------------+
//| GetTicksFor_v30 - OPTIMIZED M2 Version                          |
//+------------------------------------------------------------------+
int GetTicksFor_v30(double &price_buffer[], datetime &time_buffer[], 
                   double &speed_buffer[], int &direction_buffer[], double &spread_buffer[], int max_ticks) {
    int collected = 0;
    int start_idx = (m_index - m_count + TICK_HUB_SIZE) % TICK_HUB_SIZE;
    for(int i = 0; i < m_count && collected < max_ticks; i++) {
      int idx = (start_idx + i) % TICK_HUB_SIZE;
        if(m_ticks[idx].is_valid && !m_ticks[idx].processed_v30) {
            m_ticks[idx].processed_v30 = true;
price_buffer[collected] = m_ticks[idx].bid;
            time_buffer[collected] = m_ticks[idx].time;
            spread_buffer[collected] = MathMax(0.0, m_ticks[idx].ask - m_ticks[idx].bid);
            
            speed_buffer[collected] = 0.0;
            direction_buffer[collected] = 0;
            
                if(i > 0) {
                int prev_idx = (start_idx + i - 1) % 500;
                if(m_ticks[prev_idx].is_valid) {
                
                    double time_diff = (double)(m_ticks[idx].time_msc - m_ticks[prev_idx].time_msc) / 1000.0;
                    double pip = GetPip();
                    
                        if(time_diff > 0) {
                        double price_diff = m_ticks[idx].bid - m_ticks[prev_idx].bid;
                        speed_buffer[collected] = price_diff / pip / time_diff;
                        
                            if(MathAbs(price_diff) / pip >= 0.01) {
                            if(price_diff > 0) direction_buffer[collected] = 1;
                            else if(price_diff < 0) direction_buffer[collected] = -1;
                        }  }   }   }
                        
                 if(direction_buffer[collected] == 0 && collected > 0) {
    if(direction_buffer[collected-1] != 0) {
        double time_gap = (double)(time_buffer[collected] - time_buffer[collected-1]);
        if(time_gap <= 2.0) {
            direction_buffer[collected] = direction_buffer[collected-1];  
        }   }   }
  
                             
            collected++;  }}   
    return collected;  }
//+------------------------------------------------------------------+
//| Composite reader - non-consuming tick access                     |
//+------------------------------------------------------------------+
int GetTicksForComposite(double &price_buffer[],
                         datetime &time_buffer[],
                         double &speed_buffer[],
                         int &direction_buffer[],
                         double &spread_buffer[],
                         int max_ticks)
{
   if(max_ticks <= 0)
      return 0;

   int limit = MathMin(max_ticks, TICK_HUB_SIZE);

   double   temp_price[TICK_HUB_SIZE];
   datetime temp_time[TICK_HUB_SIZE];
   double   temp_spread[TICK_HUB_SIZE];
   long     temp_time_msc[TICK_HUB_SIZE];

   int collected = 0;
   for(int step = 0; step < m_count && collected < limit; step++)
   {
      int idx = (m_index - 1 - step + TICK_HUB_SIZE * 2) % TICK_HUB_SIZE;

      if(!m_ticks[idx].is_valid)
         continue;

temp_price[collected]   = m_ticks[idx].bid;
      temp_time[collected]    = m_ticks[idx].time;
      temp_spread[collected]  = MathMax(0.0, m_ticks[idx].ask - m_ticks[idx].bid);
      temp_time_msc[collected] = m_ticks[idx].time_msc;

      collected++;
   }

   if(collected <= 0)
      return 0;

   // تبدیل به ترتیب قدیمی به جدید و محاسبهٔ جهت/سرعت.
   for(int i = 0; i < collected; i++)
   {
      int src = collected - 1 - i;

      price_buffer[i]    = temp_price[src];
      time_buffer[i]     = temp_time[src];
      spread_buffer[i]   = temp_spread[src];
      speed_buffer[i]    = 0.0;
      direction_buffer[i] = 0;

      if(i > 0)
      {
         int prev = collected - i;

         double price_diff =
            price_buffer[i] - price_buffer[i - 1];

         double time_diff =
            (double)(temp_time_msc[prev] - temp_time_msc[prev + 1]) / 1000.0;

         if(time_diff > 0.0)
            speed_buffer[i] = price_diff / GetPip() / time_diff;

         if(MathAbs(price_diff) / GetPip() >= 0.01)
         {
            if(price_diff > 0.0)
               direction_buffer[i] = 1;
            else if(price_diff < 0.0)
               direction_buffer[i] = -1;
         }
      }
   }

   return collected;
}

//----------------------------------------------
     void CleanOldTicks(int max_age_seconds = 300) {
  for(int i = 0; i < TICK_HUB_SIZE; i++) {
            if(m_ticks[i].is_valid && (TimeCurrent() - m_ticks[i].time) > max_age_seconds) {
                m_ticks[i].is_valid = false;  }}}
    
private:
    double GetPip() {
        double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
        return (digits >= 5 || digits == 3) ? (point * 10.0) : point;  }   };
//+-----------------------------------------------------------------+
struct SystemState {
    bool     systemActive;
    bool     tradingAllowed;
    string   currentGroup;
    string   marketType;
    int      tickCounter;
    datetime lastAnalysisTime;
    double   lastTriggerPrice;
    
    SystemState() {
        systemActive = false;
        tradingAllowed = false;
        currentGroup = "";
        marketType = "";
        tickCounter = 0;
        lastAnalysisTime = 0;
        lastTriggerPrice = 0.0;  }  };
    
struct GroupParams {
    double minRange;
    int    minDirection;
    double maxSpread;
    double maxNoiseSpeed;
    double minRealStrength;  
      double minEfficiency;   // v151: حداقل نسبت کارایی مجاز (زیر این یعنی اسپایک/رفت‌وبرگشت مشکوک)
    bool   enabled;
    
    GroupParams() {
        minRange = 0;
        minDirection = 0;
        maxSpread = 0;
        maxNoiseSpeed = 0;
        minRealStrength = 40.0;
        minEfficiency = 0.30;
        enabled = false;  }  };

struct NewsEvent {
   string   title;
   string   country;
   string   impact;
   datetime timeGMT;
};

NewsEvent g_newsEvents[];
datetime  g_lastNewsFetch      = 0;
datetime  g_lastNewsPanelDraw  = 0;
bool      g_newsWebRequestOK   = false;

struct StochMemory {
   ENUM_TIMEFRAMES timeframe;
   int crossType;
   
   datetime crossTime;
   datetime crossBarTime;
   datetime lastUpdate;
   int barsPassed;
   
   double currentK;
   double currentD;

   int signalState;
   
   StochMemory() {
      timeframe = PERIOD_CURRENT;
      crossType = 0;
      crossTime = 0;
      crossBarTime = 0;
      lastUpdate = 0;
      barsPassed = 0;
      currentK = 50.0;
      currentD = 50.0;
      signalState = 0;
   }
};

   
//+------------------------------------------------------------------+
//| Global Variables                                                |
//+------------------------------------------------------------------+
#define EA_MAGIC_NUMBER 123456
CTrade trade;

static double g_direction_avg = 0.5; 
static double g_direction_avg_slow = 0.0;  
datetime g_lastPositionCheck = 0;
bool g_cachedHasPosition = false;
int g_cachedPositionCount = 0;

CTickAnalyzerOptimized *g_tick_analyzer_opt = NULL;

double sm_strength = 0.0;
double sm_confidence = 0.0;

CTickHub *g_tick_hub = NULL;



double effective_MinTickStrength = 0.0;  

double g_EffectiveMinMomentum   = 1.5;
double g_EffectiveTickStrength  = 4.0;
double g_sessionMultiplier       = 1.0;     
double g_regimeSessionMultiplier = 1.0;
double g_sessionSpreadMultiplier = 1.0;
double g_sessionNoiseMultiplier  = 1.0;
double g_sessionATRPeriodMultiplier = 1.0;  
int    g_EffectiveAdvATR_Period = 7;        


// Loss Management
int consecutiveLossCount = 0;
datetime tradingPauseUntil = 0;
double totalLossToday = 0.0;
//----------------------------------
datetime lastLossTime = 0;
datetime lastBarTime = 0;
int pauseBarsCounter = 0;
ENUM_TIMEFRAMES currentTimeframe = PERIOD_CURRENT;

// Indicators Handles
int atrHandle = INVALID_HANDLE;
int g_atrDonchianHandle = INVALID_HANDLE;
int g_atrTrailHandle = INVALID_HANDLE;
int g_trailMAHandle = INVALID_HANDLE;   // MODE_LWMA period 3 - Trill MA trailing (هیچ ارتباطی به ATR ندارد)
ENUM_TIMEFRAMES g_trailMAHandleTimeframe = PERIOD_CURRENT;
#define TRAILMA_PERIOD 3
#define TRAILMA_METHOD MODE_LWMA
double GetDonchianATR_Pips();
double GetTrailATR_Pips();
double GetTrailMA_Value(bool &ok);
void   UpdateTrailMA();
bool   IsCandleRange(double &channelWidthPip);
double last_atr_value = 0.0, atr_best_min = 0.0, atr_best_max = 0.0, atr_best_avg = 0.0;

int adxPowerExit_Handle = INVALID_HANDLE;
double adxPowerExit_LastValue = 0.0;
double plusDIPowerExit_LastValue = 0.0;
double minusDIPowerExit_LastValue = 0.0;

// Stochastic
int stoch1Handle = INVALID_HANDLE;
int stoch2Handle = INVALID_HANDLE;
double Stochastic1MainBuffer[];
double Stochastic1SignalBuffer[];
double Stochastic2MainBuffer[];
double Stochastic2SignalBuffer[];

// Trading State
int lastSignalUsed = 0;
string lastTradeFailureReason = "";
datetime g_lastSugTime = 0;   // آخرین پیشنهادِ ارسال‌شده به دیده‌بان (برای نمایش در پنل)
int      g_lastSugDir  = 0;
int      g_lastSugMask = 0;

#define MAX_BLOCK_REASONS 30
string g_blockReasons[MAX_BLOCK_REASONS];
int    g_blockReasonCount = 0;

void ResetBlockReasons() {
    g_blockReasonCount = 0;
}

void AddBlockReason(string reason) {
    if(reason == "") return;
    for(int i = 0; i < g_blockReasonCount; i++) {
        if(g_blockReasons[i] == reason) return;
    }
    if(g_blockReasonCount < MAX_BLOCK_REASONS) {
        g_blockReasons[g_blockReasonCount] = reason;
        g_blockReasonCount++;
    }
}

datetime lastPositionCloseTime = 0;
ulong lastClosedDealTicket = 0;
int signalDelayCounter = 0;
int consistentSignalCount = 0;
int lastConsistentSignal = 0;

// Manual Management
bool hasManualPosition = false;
datetime lastManualCheck = 0;
int manualPositionsCount = 0;
double totalManualProfit = 0.0;
bool autoTradingActive = true;
bool managementPaused = false;
bool g_lgShowFib = true;   // LEG v178.0: دکمهٔ FIB
bool g_dfShow = true;      // DISPLAY FIB v178.2: دکمهٔ SHOW/HIDE فیبو نمایش


bool stoch1OK = true, stoch2OK = true;
int crossType1 = 0, crossType2 = 0;

StochMemory stoch1Memory;
StochMemory stoch2Memory;
const int STOCH_MEMORY_SECONDS = 10;

double   tickPriceBuffer[MAX_HISTORY];
datetime tickTimeBuffer[MAX_HISTORY];
double   tickSpeedBuffer[MAX_HISTORY];
double   tickSpreadBuffer[MAX_HISTORY];
int      tickDirectionBuffer[MAX_HISTORY];
int      bufferIndex = 0;
bool     bufferReady = false;

int      currentTickLimit = 0;
SystemState sysState;
GroupParams currentParams;

double g_regimeMinRange      = 7.0;
double g_regimeMinDirection  = 12.0;
double g_regimeMaxSpread     = 22.0;
double g_regimeMaxNoiseSpeed = 1.8;

double   g_regimeBaseline_fast = 0.0;
double   g_regimeBaseline_slow = 0.0;
datetime g_regimeBaseline_lastTime = 0;
double   g_regimeAdaptiveMultiplier = 1.0;

void UpdateRegimeRangeBaseline(double currentRangePips) {
    if(!EnableAdaptiveRegimeBaseline || currentRangePips <= 0.0) return;

    datetime nowT = TimeCurrent();
    if(g_regimeBaseline_lastTime == 0) {
        g_regimeBaseline_fast = currentRangePips;
        g_regimeBaseline_slow = currentRangePips;
        g_regimeBaseline_lastTime = nowT;
        return;
    }

    double dt = (double)(nowT - g_regimeBaseline_lastTime);
    if(dt <= 0) return;
    g_regimeBaseline_lastTime = nowT;

     double tauFast = MathMax(30.0, RegimeBaselineFastMinutes * 60.0);
    double tauSlow = MathMax(tauFast * 1.5, RegimeBaselineSlowMinutes * 60.0);

    double alphaFast = 1.0 - MathExp(-dt / tauFast);
    double alphaSlow = 1.0 - MathExp(-dt / tauSlow);

    g_regimeBaseline_fast = alphaFast * currentRangePips + (1.0 - alphaFast) * g_regimeBaseline_fast;
    g_regimeBaseline_slow = alphaSlow * currentRangePips + (1.0 - alphaSlow) * g_regimeBaseline_slow;

    if(g_regimeBaseline_slow > 0.0001) {
        double raw = g_regimeBaseline_fast / g_regimeBaseline_slow;
        g_regimeAdaptiveMultiplier = MathMax(RegimeBaselineMinMultiplier, MathMin(RegimeBaselineMaxMultiplier, raw));
    }
}

void LoadRegimeParams(SYMBOL_GROUPS group) {
      double rangeMultiplier = EnableAdaptiveRegimeBaseline ? g_regimeAdaptiveMultiplier : g_regimeSessionMultiplier;
    switch(group) {
      case GROUP_XAUUSD:
        g_regimeMinRange      = XAU_Regime_MinRange * rangeMultiplier;
        g_regimeMinDirection  = XAU_Regime_MinDirection;
        g_regimeMaxSpread     = XAU_Regime_MaxSpread;
        g_regimeMaxNoiseSpeed = XAU_Regime_MaxNoiseSpeed;
        break;
      case GROUP_MAJORS:
        g_regimeMinRange      = MAJ_Regime_MinRange * rangeMultiplier;
        g_regimeMinDirection  = MAJ_Regime_MinDirection;
        g_regimeMaxSpread     = MAJ_Regime_MaxSpread;
        g_regimeMaxNoiseSpeed = MAJ_Regime_MaxNoiseSpeed;
        break;
      case GROUP_CROSSES:
        g_regimeMinRange      = CRS_Regime_MinRange * rangeMultiplier;
        g_regimeMinDirection  = CRS_Regime_MinDirection;
        g_regimeMaxSpread     = CRS_Regime_MaxSpread;
        g_regimeMaxNoiseSpeed = CRS_Regime_MaxNoiseSpeed;
        break;
      default:
        g_regimeMinRange      = currentParams.minRange;
        g_regimeMinDirection  = currentParams.minDirection;
        g_regimeMaxSpread     = currentParams.maxSpread;
        g_regimeMaxNoiseSpeed = currentParams.maxNoiseSpeed;
    }
}
string last_filter_decision = "";
int decision_strength_counter = 0;
datetime last_decision_change_time = 0;
//+------------------------------------------------------------------+
//| Utility Functions                                               |
//+------------------------------------------------------------------+
double GetPip() {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digs = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   string symbol = _Symbol;
   
      if(symbol == "XAUUSD" || symbol == "GOLD" || StringFind(symbol, "XAU") >= 0) {
      return 0.10;
   }
   
   if(digs >= 5 || digs == 3) return point * 10.0;

   if(digs == 2) return point * 10.0;

   return point; 
}

int GetPostEntryEffectiveTicks() {
   switch(PostEntry_Sensitivity) {
      case PE_SENS_ULTRA_WEAK: return 32;   // آسان‌گیرترین - مخصوص نمادهای خیلی پرنویز
      case PE_SENS_VERY_WEAK:  return 26;
      case PE_SENS_WEAK:       return 20;
      case PE_SENS_LOW:        return 12;
      case PE_SENS_HIGH:       return 2;    // سریع‌ترین واکنش
      default:                 return 8;    // متوسط (پیش‌فرض)
   }
}
bool GetPostEntryEffectiveClose() {
   return (PostEntry_ReactionType == PE_REACT_CLOSE);
}
double g_lastCompositeScore = 50.0;
double g_lastCompositeImbalance = 0.0;
double g_lastCompositeDeviation = 0.0;
double g_lastCompositeEfficiency = 1.0;

double GetCompositeTriggerScore(const MarketStats &stats) {
    double normDeviation = 0.0;
    if(stats.rangePips > 0.01) normDeviation = MathMax(-1.0, MathMin(1.0, stats.fairValueDeviation / stats.rangePips));

    double trendCombo = (stats.tickImbalance + normDeviation) / 2.0;   // -1..1
    double weighted = trendCombo * stats.efficiencyRatio;              // کارایی به‌عنوان وزن اعتماد

    g_lastCompositeImbalance = stats.tickImbalance;
    g_lastCompositeDeviation = normDeviation;
    g_lastCompositeEfficiency = stats.efficiencyRatio;

    double score = 50.0 + 50.0 * weighted;
    return MathMax(0.0, MathMin(100.0, score));
}
int GetCompositeSignal()
{
    string compositeReason = "";

    int signal = Composite_EvaluateTrigger(compositeReason);

       last_filter_decision = compositeReason;
    if(signal > 0)
        g_lastCompositeScore = Composite_GetBuyThreshold();
    else if(signal < 0)
        g_lastCompositeScore = Composite_GetSellThreshold();
    else
        g_lastCompositeScore = 50.0;

    return signal;
}
int GetBrokerGMTOffsetSeconds() {
   datetime srv = TimeCurrent();
   datetime gmt = TimeGMT();
   return (int)(srv - gmt) - (ManualClockCorrectionMinutes * 60);
}

void ApplySessionMultiplier() {

   datetime brokerTime = TimeCurrent();
   
   int IranOffset = 3 * 3600 + 30 * 60;
   
   int BrokerOffset = GetBrokerGMTOffsetSeconds();
   
   datetime iranTime = brokerTime - BrokerOffset + IranOffset;
   
   MqlDateTime now;
   TimeToStruct(iranTime, now);
   int currentTime = now.hour * 100 + now.min;
   int dayOfWeek = now.day_of_week;

   double multiplier = 1.0;
   double spreadMultiplier = 1.0;
   double noiseMultiplier = 1.0;
   double regimeMultiplier = 1.0;
   double atrPeriodMultiplier = 1.0;  

   if(currentTime >= 300 && currentTime < 700) {
      multiplier = 1 ; spreadMultiplier = 1.0; noiseMultiplier = 1.0; regimeMultiplier = 1 ; atrPeriodMultiplier = 1.0;
   }
   else if(currentTime >= 700 && currentTime < 1000) {
   
      multiplier = 1 ;
       spreadMultiplier = 1.0; noiseMultiplier = 1.0; regimeMultiplier = 1.0; atrPeriodMultiplier = 1.0;
   }
   else if(currentTime >= 1000 && currentTime < 1230) {
      multiplier = 1.0 ; spreadMultiplier = 1.0; noiseMultiplier = 1.0; regimeMultiplier = 1.0; atrPeriodMultiplier = 1.0;
   }
   else if(currentTime >= 1230 && currentTime < 1600) {
      // 
      multiplier = 1.0;
       spreadMultiplier = 1.0; noiseMultiplier = 1.0; regimeMultiplier = 1.0; atrPeriodMultiplier = 1.0;
   }
   else if(currentTime >= 1630 && currentTime < 1730) {
    
       multiplier = 1.0 ;
       spreadMultiplier = 1.0; noiseMultiplier = 1.0; regimeMultiplier = 1.0; atrPeriodMultiplier = 1.0;
   }
   else  if(currentTime >= 1730 && currentTime < 1930) {
      multiplier = 1.0 ; spreadMultiplier = 1.0; noiseMultiplier = 1.0; regimeMultiplier = 1.0; atrPeriodMultiplier = 1.0;
   }
   
   else if(currentTime >= 1930 && currentTime < 2200) {
   
        multiplier = 1.0 ; 
      spreadMultiplier = 1.0; noiseMultiplier = 1.0; regimeMultiplier = 1.0; atrPeriodMultiplier = 1.0;
   }
  else  if(currentTime >= 2200 && currentTime < 2400) {
      multiplier = 1.0;
       spreadMultiplier = 1.0; noiseMultiplier = 1.0; regimeMultiplier = 1.0; atrPeriodMultiplier = 1.0;
   }

   // ============================================================
   double dayFactor = 1.0;
   double spreadDayFactor = 1.0;
/*
   if(dayOfWeek == 5 && currentTime >= 2030) {
      dayFactor = MathMax(0.35, 1.0 - (currentTime - 2030) / 100.0 * 0.05);
      spreadDayFactor = 1.0 / dayFactor;
   }

   if(dayOfWeek == 1 && currentTime < 1030) {
      dayFactor *= 0.75;
      spreadDayFactor *= 1.3;
   }
*/
   multiplier      *= dayFactor;
   noiseMultiplier *= dayFactor;
   regimeMultiplier *= dayFactor;
   spreadMultiplier = MathMin(2.5, spreadMultiplier * spreadDayFactor);


 
   g_EffectiveMinMomentum  = MinMomentum * multiplier;

   effective_MinTickStrength = g_EffectiveTickStrength;
   g_sessionMultiplier = multiplier;
   g_regimeSessionMultiplier = regimeMultiplier;
   g_sessionSpreadMultiplier = spreadMultiplier;
   g_sessionNoiseMultiplier  = noiseMultiplier;

   g_sessionATRPeriodMultiplier = atrPeriodMultiplier;
   int newEffPeriod = AdvATR_SessionPeriodMode
                       ? (int)MathMax(2, MathRound(AdvATR_Period * atrPeriodMultiplier))
                       : AdvATR_Period;
   g_EffectiveAdvATR_Period = newEffPeriod;
}

//+------------------------------------------------------------------+
//| Logging Functions                                               |
//+------------------------------------------------------------------+ 
       void ErrorLog(string message) { 
    if(DebugLogEnable) { 
        Print("❌ خطا: ", TimeToString(TimeCurrent(), TIME_SECONDS), " - ", message); }}
        
void SystemLog(string message) { 
    if(DebugLogEnable) { 
        Print("⚙️ سیستم: ", TimeToString(TimeCurrent(), TIME_SECONDS), " - ", message);  }}
   
void ButtonLog(string message) { 
    if(DebugLogEnable) { 
        Print("🔘 دکمه: ", TimeToString(TimeCurrent(), TIME_SECONDS), " - ", message); }}
 
   void FilterLog(string message) { 
    if(DebugLogEnable) { 
        Print("🔍 فیلتر: ", TimeToString(TimeCurrent(), TIME_SECONDS), " - ", message); 
    }   }
    
void TickAnalysisLog(string message) { 
    if(DebugLogEnable) { 
        Print("📊 تحلیل تیک: ", TimeToString(TimeCurrent(), TIME_SECONDS), " - ", message); }}
//+------------------------------------------------------------------+
//| LOGCLEAN: لاگِ «رد شدن سیگنال» بدون تکرار                          |
//| برای هر برچسب، پیام فقط وقتی چاپ می‌شود که دلیل (بدون رقم‌ها) عوض     |
//| شده باشد یا کندل جدید باز شده باشد                                  |
//+------------------------------------------------------------------+
string   g_rejTag[8];
string   g_rejKeys[32];   // به ازای هر برچسب تا ۴ دلیلِ متفاوت در هر کندل
int      g_rejCnt[8];
datetime g_rejBar[8];

string Rej_StripDigits(const string s)
{
   string r = "";
   const int n = StringLen(s);
   for(int i = 0; i < n; i++)
   {
      const ushort ch = StringGetCharacter(s, i);
      if(ch >= '0' && ch <= '9') continue;
      r += ShortToString(ch);
   }
   return r;
}

void RejectLog(const string prefix, const string reason)
{
   if(!DebugLogEnable) return;
   const datetime bar = iTime(_Symbol, _Period, 0);
   const string key = Rej_StripDigits(reason);
   int slot = -1;
   for(int i = 0; i < 8; i++)
   {
      if(g_rejTag[i] == prefix) { slot = i; break; }
      if(slot < 0 && g_rejTag[i] == "") slot = i;
   }
   if(slot < 0) slot = 0;
   if(g_rejTag[slot] != prefix || g_rejBar[slot] != bar)
   {
      g_rejTag[slot] = prefix;
      g_rejBar[slot] = bar;
      g_rejCnt[slot] = 0;
   }
   for(int k = 0; k < g_rejCnt[slot]; k++)
      if(g_rejKeys[slot * 4 + k] == key) return;
   if(g_rejCnt[slot] >= 4) return;
   g_rejKeys[slot * 4 + g_rejCnt[slot]] = key;
   g_rejCnt[slot]++;
   FilterLog(prefix + " rejected by filters: " + reason);
}
//+------------------------------------------------------------------+
//| === SMART CACHE SYSTEM ===                                      |
//+------------------------------------------------------------------+
struct SymbolCache {
    double bid;
    double ask;
    long spread;
    double point;
    double pip;
    int digits;
    datetime lastUpdate;
    ulong lastUpdateMicros;
};

SymbolCache g_cache;

#define CURRENT_BID()      g_cache.bid
#define CURRENT_ASK()      g_cache.ask
#define CURRENT_SPREAD()   g_cache.spread
#define CURRENT_PIP()      g_cache.pip
#define CURRENT_POINT()    g_cache.point
//+------------------------------------------------------------------+
//| Optimized Tick Analyzer Class (v3.0)                            |
//+------------------------------------------------------------------+
class CTickAnalyzerOptimized {
private:
    MarketStats m_stats;
    datetime    m_lastUpdate;
    int         m_lookbackTicks;
    int         m_consecutiveCount;
    int         m_lastDirection;
    int         m_minDirection;
    double      m_prev_speed;
    ulong       m_prev_time_ms;   

    double      m_avgMagBaseline;
    double      m_avgRangeMoveBaseline;  
                                           
    double      m_avgSpreadBaseline;
    int         m_dirStreak;
    int         m_dirStreakSign;
    double      m_recentPriceHigh;
    double      m_recentPriceLow;
    double      m_deltaAtPriceHigh;
    double      m_deltaAtPriceLow;
    int         m_divergenceCooldown;
    int         m_resetCounter;
    double      m_accHistory[50];
    int         m_accIdx;
    double      m_avgAcc;
    int         m_currentDirSign;
    double      m_erHistSigned[3];
    double      m_erHistAbs[3];
    int         m_erHistUp[3];
    int         m_erHistDown[3];
    int         m_erHistN[3];
    int         m_erHistIdx;
    double      m_ER_smoothed;
    // ======================================================================================

public:
    CTickAnalyzerOptimized() {
        m_lastUpdate = 0;
        m_lookbackTicks = MathMax(TA_LookbackTicks, MathMax(6, DIRECTION_LOOKBACK_TICKS));
        m_consecutiveCount = 0;
        m_lastDirection = 0;
        m_minDirection = 45;
        m_prev_speed = 0;
        m_prev_time_ms = 0;
        m_avgMagBaseline = 1.0;
        m_avgRangeMoveBaseline = 0.0;  // v147 fix #10
        m_avgSpreadBaseline = 0.0;
        m_dirStreak = 0;
        m_dirStreakSign = 0;
        m_recentPriceHigh = -1e10;
        m_recentPriceLow = 1e10;
        m_deltaAtPriceHigh = 0;
        m_deltaAtPriceLow = 0;
        m_divergenceCooldown = 0;
        m_resetCounter = 0;
        ArrayInitialize(m_accHistory, 0.0);
        m_accIdx = 0;
        m_avgAcc = 1.0;
        m_currentDirSign = 0;
        ArrayInitialize(m_erHistSigned, 0.0);
        ArrayInitialize(m_erHistAbs, 0.0);
        ArrayInitialize(m_erHistUp, 0);
        ArrayInitialize(m_erHistDown, 0);
        ArrayInitialize(m_erHistN, 0);
        m_erHistIdx = 0;
        m_ER_smoothed = 0.0;
        ResetStats();
    }
    
    void SetMinDirection(int value) {
        m_minDirection = value;
    }
    
    int GetMinDirection() const {
        return m_minDirection;
    }
    
    void ResetStats() {
        m_stats.rangePips = 0;
        m_stats.directionScore = 0;
        m_stats.consistency = 0;
        m_stats.avgSpeed = 0;
        m_stats.currentSpread = 0;
        m_stats.tickVolume = 0;
        m_stats.acceleration = 0;
        m_stats.realStrength = 0;
        m_consecutiveCount = 0;
        m_lastDirection = 0;
        sm_strength = 0.0;
        sm_confidence = 0.0;
    }
    
    void ProcessTick() {
        m_lastUpdate = TimeCurrent();
        
        if(g_tick_hub == NULL) {
            return;
        }
        
        double price_buffer[50];
        datetime time_buffer[50];
        double speed_buffer[50];
        int direction_buffer[50];
        double spread_buffer[50];
        
        int count = g_tick_hub.GetTicksFor_v30(price_buffer, time_buffer, 
                                              speed_buffer, direction_buffer, spread_buffer, 50);
        
        if(count > 0) {
            ProcessTicksFromHub(price_buffer, time_buffer, 
                               speed_buffer, direction_buffer, spread_buffer, count);
        }
        
        int currentDir = GetCurrentDirection();
        if(currentDir != 0) {
            if(currentDir == m_lastDirection) {
                m_consecutiveCount++;
            } else {
                m_consecutiveCount = 1;
                m_lastDirection = currentDir;
            }
        } else {
            m_consecutiveCount = 0;
        }
        
        sysState.marketType = AnalyzeMarketCondition();
    }
    
    void ProcessTicksFromHub(double &price[], datetime &time[], 
                            double &speed[], int &direction[], double &spread[], int count) {
        if(count <= 0) return;
        
        for(int i = 0; i < count; i++) {
            int idx = (bufferIndex + i) % MAX_HISTORY;
            tickPriceBuffer[idx] = price[i];
            tickTimeBuffer[idx] = time[i];
            tickSpeedBuffer[idx] = speed[i];
            tickDirectionBuffer[idx] = direction[i];
            tickSpreadBuffer[idx] = spread[i];
        }
        
        bufferIndex = (bufferIndex + count) % MAX_HISTORY;
        if(count > 0) {
            bufferReady = true;
        }
        
        m_stats = CollectMarketStats(m_lookbackTicks);
    }
    
    MarketStats CollectMarketStats(int lookbackTicks = 25) {
        MarketStats stats;
        
        if(lookbackTicks <= 0 || lookbackTicks > MAX_HISTORY) {
            lookbackTicks = m_lookbackTicks; 
        }
        
        if(!bufferReady && bufferIndex < lookbackTicks) {
            return stats; 
        }
        
        double maxPrice = -1e10;
        double minPrice = 1e10;
        double upCount = 0, downCount = 0, totalCount = 0;
        double directionTotalCount = 0;   // v145: نسخه‌ی مخصوص Direction - فقط ۱۰ تیک اول
        double directionActiveTickCount = 0;   // v145: نسخه‌ی مخصوص Direction برای sampleQuality
        double activeTickCount = 0;
        double speedSum = 0;
        double consistencySum = 0;
        double lastValidSpeed = -1;
        double validTicks = 0;
        double signedSpeedSum = 0;
        double absSpeedSum = 0;      
        int    nextTickSign = 0;
        double spreadSpikeCount = 0;
        double pip = GetPip();
        double prevPriceForRangeMove = -1.0;
        double rangeMoveSum = 0.0;
        int    rangeMoveCount = 0;

        double effEndPrice = -1.0;     
        double effStartPrice = -1.0;  
        double effTotalDistance = 0.0; 
        double compImbalanceUp = 0, compImbalanceDown = 0, compImbalanceTotal = 0;
        double compFairValueSum = 0.0;
        int    compFairValueCount = 0;
        
         double stepMoves[64];
        int stepMoveCount = 0;
        
        for(int i = 0; i < lookbackTicks; i++) {
            int idx = (bufferIndex - i - 1 + MAX_HISTORY) % MAX_HISTORY;
            
            if(tickPriceBuffer[idx] <= 0) continue;
            
            validTicks++;
            
            double tickMoveForRange = (prevPriceForRangeMove > 0.0)
                                       ? MathAbs(prevPriceForRangeMove - tickPriceBuffer[idx]) / pip
                                       : 0.0;
            bool isRangeOutlier = (prevPriceForRangeMove > 0.0) &&
                                  (m_avgRangeMoveBaseline > 0.0001) &&
                                  (tickMoveForRange > 8.0 * m_avgRangeMoveBaseline);
            if(!isRangeOutlier) {
                if(tickPriceBuffer[idx] > maxPrice) maxPrice = tickPriceBuffer[idx];
                if(tickPriceBuffer[idx] < minPrice) minPrice = tickPriceBuffer[idx];
                if(prevPriceForRangeMove > 0.0) { rangeMoveSum += tickMoveForRange; rangeMoveCount++; }
            }

            if(effEndPrice < 0.0) effEndPrice = tickPriceBuffer[idx];
            effStartPrice = tickPriceBuffer[idx];
            if(prevPriceForRangeMove > 0.0) effTotalDistance += tickMoveForRange;

                if(i < CompositeTrigger_ImbalanceWindow) {
                compImbalanceTotal++;
                if(tickDirectionBuffer[idx] == +1) compImbalanceUp++;
                else if(tickDirectionBuffer[idx] == -1) compImbalanceDown++;
            }
            if(i < CompositeTrigger_FairValueWindow) {
                compFairValueSum += tickPriceBuffer[idx];
                compFairValueCount++;
            }

            prevPriceForRangeMove = tickPriceBuffer[idx];
            
            
            if(i < DIRECTION_LOOKBACK_TICKS) {
    if(tickDirectionBuffer[idx] == +1) upCount++;
    else if(tickDirectionBuffer[idx] == -1) downCount++;
    directionTotalCount++;
}
            
            
            if(stepMoveCount < 64) {
                stepMoves[stepMoveCount] = tickSpeedBuffer[idx];
                stepMoveCount++;
            }
            
            double speed = MathAbs(tickSpeedBuffer[idx]);
            if(speed > 0) {
                speedSum += speed;
                activeTickCount++;   // ✅ v124
                if(i < DIRECTION_LOOKBACK_TICKS) directionActiveTickCount++;   // v145
                
                double effSpeed = speed;
            
                bool isLarge = (m_avgMagBaseline > 0.0001) && (speed > 5.0 * m_avgMagBaseline);
                if(isLarge) {
                    if(nextTickSign != 0 && nextTickSign != tickDirectionBuffer[idx]) {
                        effSpeed *= 0.35;
                    } else if(i == 0) {
                        effSpeed *= 0.65;
                    }
                }
                nextTickSign = tickDirectionBuffer[idx];
               
                double thisSpread = tickSpreadBuffer[idx];
                if(m_avgSpreadBaseline > 0.0000001 && thisSpread > 0) {
                    double spreadRatio = thisSpread / m_avgSpreadBaseline;
                    if(spreadRatio > 1.8) {
                        double spreadConfidence = MathMax(0.15, 1.8 / spreadRatio);
                        effSpeed *= spreadConfidence;
                        spreadSpikeCount++;
                    }
                }
                
                if(i < DIRECTION_LOOKBACK_TICKS) {
                absSpeedSum += effSpeed;
                signedSpeedSum += tickDirectionBuffer[idx] * effSpeed;
                }
                
                if(lastValidSpeed >= 0) {
                    double change = MathAbs(speed - lastValidSpeed);
                    consistencySum += change;
                }
                lastValidSpeed = speed;
            }
            
            totalCount++;
        }
        
              if(totalCount > 0) {
            double thisCycleAvgMag = (activeTickCount > 0) ? speedSum / activeTickCount : 0.0;
            if(thisCycleAvgMag > 0.0001) {
                m_avgMagBaseline = 0.1 * thisCycleAvgMag + 0.9 * m_avgMagBaseline;
            }
            double thisCycleAvgRangeMove = (rangeMoveCount > 0) ? rangeMoveSum / rangeMoveCount : 0.0;
            if(thisCycleAvgRangeMove > 0.0001) {
                m_avgRangeMoveBaseline = (m_avgRangeMoveBaseline <= 0.0001) ? thisCycleAvgRangeMove
                                          : (0.1 * thisCycleAvgRangeMove + 0.9 * m_avgRangeMoveBaseline);
            }
            double spreadSumCycle = 0; int spreadCountCycle = 0;
            for(int i2 = 0; i2 < lookbackTicks; i2++) {
                int idx2 = (bufferIndex - i2 - 1 + MAX_HISTORY) % MAX_HISTORY;
                if(tickPriceBuffer[idx2] > 0 && tickSpreadBuffer[idx2] > 0) {
                    spreadSumCycle += tickSpreadBuffer[idx2]; spreadCountCycle++;
                }
            }
            if(spreadCountCycle > 0) {
                double thisCycleAvgSpread = spreadSumCycle / spreadCountCycle;
                m_avgSpreadBaseline = (m_avgSpreadBaseline < 0.0000001) ? thisCycleAvgSpread
                                      : (0.1 * thisCycleAvgSpread + 0.9 * m_avgSpreadBaseline);
            }
        }
        
        if(validTicks > 0) {
             stats.rangePips = (maxPrice > -1e9 && minPrice < 1e9) ? (maxPrice - minPrice) / pip : 0.0;

            if(effTotalDistance > 0.5) {
                double netDisplacementPips = (effEndPrice > 0.0 && effStartPrice > 0.0)
                                              ? MathAbs(effEndPrice - effStartPrice) / pip : 0.0;
                stats.efficiencyRatio = MathMax(0.0, MathMin(1.0, netDisplacementPips / effTotalDistance));
            } else {
                stats.efficiencyRatio = 1.0;
            }

             stats.tickImbalance = (compImbalanceTotal > 0) ? (compImbalanceUp - compImbalanceDown) / compImbalanceTotal : 0.0;
            if(compFairValueCount > 0 && effEndPrice > 0.0) {
                double fairValue = compFairValueSum / compFairValueCount;
                stats.fairValueDeviation = (effEndPrice - fairValue) / pip;
            } else {
                stats.fairValueDeviation = 0.0;
            }
                 {
                double acNum = 0, acDen = 0;
                for(int k = 1; k < stepMoveCount; k++) acNum += stepMoves[k] * stepMoves[k-1];
                for(int k = 0; k < stepMoveCount; k++) acDen += stepMoves[k] * stepMoves[k];
                stats.alternationRatio = (acDen > 0) ? acNum / acDen : 0.0;

                int stepPatterns = 0;
                for(int k = 2; k < stepMoveCount; k++) {
                    if((stepMoves[k] > 0 && stepMoves[k-1] < 0 && stepMoves[k-2] > 0) ||
                       (stepMoves[k] < 0 && stepMoves[k-1] > 0 && stepMoves[k-2] < 0)) {
                        stepPatterns++;
                    }
                }
                stats.stepPatternRatio = (stepMoveCount > 0) ? (double)stepPatterns / stepMoveCount : 0.0;
            }
          
           
            double raw_direction = 0.0;
            if(directionTotalCount >= 3) {
                if(absSpeedSum > 0.0000001) {
                    raw_direction = signedSpeedSum / absSpeedSum;
                } else {
                    raw_direction = (double)(upCount - downCount) / MathMax(1.0, directionTotalCount);
                }
                if(raw_direction > 1.0) raw_direction = 1.0;
                if(raw_direction < -1.0) raw_direction = -1.0;

                m_erHistSigned[m_erHistIdx] = signedSpeedSum;
                m_erHistAbs[m_erHistIdx]    = absSpeedSum;
                m_erHistUp[m_erHistIdx]     = upCount;
                m_erHistDown[m_erHistIdx]   = downCount;
                m_erHistN[m_erHistIdx]      = (int)directionTotalCount;
                m_erHistIdx = (m_erHistIdx + 1) % 3;

                double winSigned = m_erHistSigned[0] + m_erHistSigned[1] + m_erHistSigned[2];
                double winAbs    = m_erHistAbs[0]    + m_erHistAbs[1]    + m_erHistAbs[2];
                int    winUp     = m_erHistUp[0]     + m_erHistUp[1]     + m_erHistUp[2];
                int    winDown   = m_erHistDown[0]   + m_erHistDown[1]   + m_erHistDown[2];
                int    winN      = m_erHistN[0]      + m_erHistN[1]      + m_erHistN[2];

                double ER_wide = (winAbs > 0.0000001) ? MathAbs(winSigned / winAbs)
                                                        : (winN > 0 ? MathAbs((double)(winUp - winDown) / winN) : 0.0);

                double z = (winN > 0) ? MathAbs((double)(winUp - winDown)) / MathSqrt((double)winN) : 0.0;
                double significance = MathMin(1.0, z / 2.5);

                double sampleQuality = MathMin(1.0, directionActiveTickCount / MathMax(1.0, (double)DIRECTION_LOOKBACK_TICKS*0.5));
                double ER_effective = ER_wide * significance * sampleQuality;

                const double FAST_SC = 2.0 / (2.0 + 1.0);
                const double SLOW_SC = 2.0 / (30.0 + 1.0);
                double SC = MathPow(ER_effective * (FAST_SC - SLOW_SC) + SLOW_SC, 2);

                g_direction_avg = SC * raw_direction + (1.0 - SC) * g_direction_avg;
                if(g_direction_avg > 1.0) g_direction_avg = 1.0;
                if(g_direction_avg < -1.0) g_direction_avg = -1.0;

                const double SLOW_HORIZON_ALPHA = 0.03;
                g_direction_avg_slow = SLOW_HORIZON_ALPHA * raw_direction + (1.0 - SLOW_HORIZON_ALPHA) * g_direction_avg_slow;
                if(g_direction_avg_slow > 1.0) g_direction_avg_slow = 1.0;
                if(g_direction_avg_slow < -1.0) g_direction_avg_slow = -1.0;
            }

            const double enterTh = 0.20;
            const double exitTh  = 0.10;
            int currentSign;
            if(m_currentDirSign == 0) {
                currentSign = (g_direction_avg > enterTh) ? 1 : (g_direction_avg < -enterTh ? -1 : 0);
            } else if(m_currentDirSign == 1) {
                currentSign = (g_direction_avg < -enterTh) ? -1 : (g_direction_avg < exitTh ? 0 : 1);
            } else { // m_currentDirSign == -1
                currentSign = (g_direction_avg > enterTh) ? 1 : (g_direction_avg > -exitTh ? 0 : -1);
            }
            m_currentDirSign = currentSign;

            int s_dirStreak = m_dirStreak;
            int s_dirStreakSign = m_dirStreakSign;
            if(currentSign != 0 && currentSign == s_dirStreakSign) {
                s_dirStreak++;
            } else if(currentSign == 0) {
                s_dirStreak = (int)MathFloor(s_dirStreak / 2.0);
                s_dirStreakSign = 0;
            } else {
                s_dirStreak = 1;
                s_dirStreakSign = currentSign;
            }
            m_dirStreak = s_dirStreak;
            m_dirStreakSign = s_dirStreakSign;
            int persistNeeded = DirectionPersistTicks;
            stats.directionPersistOK = (s_dirStreak >= persistNeeded);
            
            stats.directionScore = (int)(g_direction_avg * 100.0);
            
            stats.deltaValue = signedSpeedSum;
            
            double curPrice = (validTicks > 0) ? maxPrice : 0;
            bool newHigh = false, newLow = false;
            if(maxPrice > m_recentPriceHigh) { m_recentPriceHigh = maxPrice; m_deltaAtPriceHigh = stats.deltaValue; newHigh = true; }
            if(minPrice < m_recentPriceLow)  { m_recentPriceLow  = minPrice; m_deltaAtPriceLow  = stats.deltaValue; newLow = true; }
            
            stats.priceDeltaDivergence = false;
            if(m_divergenceCooldown <= 0) {
                if(newHigh && stats.deltaValue < m_deltaAtPriceHigh * 0.7 && stats.deltaValue < absSpeedSum*0.1) {
                    stats.priceDeltaDivergence = true;
                    m_divergenceCooldown = 10;
                } else if(newLow && stats.deltaValue > m_deltaAtPriceLow * 0.7 && stats.deltaValue > -absSpeedSum*0.1) {
                    stats.priceDeltaDivergence = true;
                    m_divergenceCooldown = 10;
                }
            } else {
                m_divergenceCooldown--;
            }
            m_resetCounter++;
            if(m_resetCounter > 300) { m_recentPriceHigh=-1e10; m_recentPriceLow=1e10; m_resetCounter=0; }
           
            stats.orderPressureProxy = MathMin(100.0, s_dirStreak * MathAbs(g_direction_avg) * 20.0);
            // =============================
            stats.avgSpeed = (activeTickCount > 0) ? speedSum / activeTickCount : 0.0;
            stats.tickVolume = (int)totalCount;
            
            if(m_prev_time_ms > 0 && m_prev_speed > 0 && stats.avgSpeed > 0) {
                 double time_diff = (double)(GetTickCount64() - m_prev_time_ms) / 1000.0;
                if(time_diff > 0.001 && time_diff < 10) {
double raw_acc = (stats.avgSpeed - m_prev_speed) / time_diff;
m_accHistory[m_accIdx] = MathAbs(raw_acc);
m_accIdx = (m_accIdx + 1) % 50;

double sum = 0;
int count = 0;
for(int i = 0; i < 50; i++) {
    if(m_accHistory[i] > 0) { sum += m_accHistory[i]; count++; }
}
if(count > 0) m_avgAcc = sum / count;
if(m_avgAcc < 0.1) m_avgAcc = 0.1;

stats.acceleration = raw_acc / m_avgAcc;
stats.acceleration = MathMax(-2.0, MathMin(2.0, stats.acceleration));

static double s_smoothedAcceleration = -999;
if(s_smoothedAcceleration < -998) s_smoothedAcceleration = stats.acceleration;
else s_smoothedAcceleration = (s_smoothedAcceleration * (RealStrengthSmoothPeriod - 1) + stats.acceleration) / RealStrengthSmoothPeriod;
stats.acceleration = s_smoothedAcceleration;
               
                } else {
                    stats.acceleration = 0;
                }
            } else {
                stats.acceleration = 0;
            }
            
            m_prev_speed = stats.avgSpeed;
            m_prev_time_ms = GetTickCount64();
         
            static double speed_history[50] = {0};
            static int speed_idx = 0;
            static double avg_speed_recent = 0.0;

            if(stats.avgSpeed > 0) {
                speed_history[speed_idx] = stats.avgSpeed;
                speed_idx = (speed_idx + 1) % 50;
                double sSum = 0; int sCount = 0;
                for(int si = 0; si < 50; si++) {
                    if(speed_history[si] > 0) { sSum += speed_history[si]; sCount++; }
                }
                if(sCount > 0) avg_speed_recent = sSum / sCount;
            }
            if(avg_speed_recent < 0.0001) avg_speed_recent = MathMax(0.0001, stats.avgSpeed);

            double speedRatio = stats.avgSpeed / avg_speed_recent;
            stats.speedRatio = speedRatio;
            double normal_speed = MathMin(1.0, speedRatio / 2.0);
            double normal_accel = MathMax(-1.0, MathMin(1.0, stats.acceleration / (MathMax(0.5, speedRatio) / 2)));
            
            stats.realStrength = normal_speed * (1.0 + normal_accel) * 100;
            stats.realStrength = MathMax(0, MathMin(100, stats.realStrength));
            static double s_smoothedRealStrength = -1;
            if(s_smoothedRealStrength < 0) s_smoothedRealStrength = stats.realStrength;
            else s_smoothedRealStrength = (s_smoothedRealStrength * (RealStrengthSmoothPeriod - 1) + stats.realStrength) / RealStrengthSmoothPeriod;
            stats.realStrength = s_smoothedRealStrength;
            // ==================================================           
            
            if(totalCount > 1 && stats.avgSpeed > 0.01) {
                double avgChange = consistencySum / (totalCount - 1);
                double changeRatio = MathMin(1.0, avgChange / (stats.avgSpeed * 2.0));
                stats.consistency = (int)(100.0 * (1.0 - changeRatio));
                stats.consistency = MathMax(0, MathMin(100, stats.consistency));
            } else {
                stats.consistency = 50;
            }
        }
        stats.currentSpread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - 
                               SymbolInfoDouble(_Symbol, SYMBOL_BID)) / pip;
        
        return stats;
    }
    
    string AnalyzeMarketCondition() {
        if(!bufferReady) return "UNKNOWN";
  
        if(m_stats.currentSpread > g_regimeMaxSpread) {
            return "SPREAD_HIGH";
        }
        
        string candidate = "UNKNOWN_CONDITION";
      
        if(m_stats.stepPatternRatio > RegimeSteppingAlternationMin && MathAbs(m_stats.directionScore) < RegimeSteppingMaxDirection) {
            candidate = "STEPPING_MARKET";
        }
        else if(m_stats.rangePips < g_regimeMinRange) {
            candidate = "DEAD_MARKET";
        }
        else {
            double minDirForCheck = g_regimeMinDirection;
            if(MathAbs(m_stats.directionScore) < minDirForCheck) {
                candidate = "NOISY_MARKET";
            }
            else if(MathAbs(g_direction_avg_slow * 100) < RegimeLongHorizonMinDirection)
               {
                candidate = "NOISY_MARKET";
            }
            else {
                // ============================================================
                static datetime s_lockUntil = 0;
                static datetime s_lastBar = 0;
                datetime barTime = iTime(_Symbol, _Period, 0);
                             
                if(barTime != s_lastBar) {
                    s_lastBar = barTime;
                    s_lockUntil = 0;
                }
                
                double currentSpeed = m_stats.speedRatio;
                double speedThreshold = g_regimeMaxNoiseSpeed; 
                bool speedHandled = false;
                
                if(currentSpeed > speedThreshold) {
                    if(MathAbs(m_stats.directionScore) > g_regimeMinDirection * RegimeFastTrendDirMultiplier) {
                     
                        return "TOO_FAST";
                    } else {
                     
                        const int NOISY_LOCK_SECONDS = 2;
                        if(s_lockUntil == 0) {
                            s_lockUntil = TimeCurrent() + NOISY_LOCK_SECONDS;
                        }
                        candidate = "NOISY_MARKET";
                        speedHandled = true;
                    }
                }
                
                if(!speedHandled) {
                    if(s_lockUntil > 0 && TimeCurrent() < s_lockUntil) {
                        candidate = "NOISY_MARKET";
                    }
                    else {
                     
                        if(s_lockUntil > 0 && TimeCurrent() >= s_lockUntil) {
                            s_lockUntil = 0;
                        }
                    
                        if(m_stats.directionScore >= g_regimeMinDirection && 
                           m_stats.speedRatio >= 0.05 && m_stats.speedRatio <= g_regimeMaxNoiseSpeed &&
                           m_stats.directionPersistOK) {
                            candidate = "STEADY_TREND";
                        } else {
                            candidate = "UNKNOWN_CONDITION";  }}}}}
               
        // ============================================================
        static string s_lastCandidate = "UNKNOWN_CONDITION";
        static string s_stableRegime  = "UNKNOWN_CONDITION";
        static int    s_regimeStreak  = 0;
        
        if(candidate == s_lastCandidate) {
            s_regimeStreak++;
        } else {
            s_regimeStreak = 1;
            s_lastCandidate = candidate;
        }
        
        if(s_regimeStreak >= MathMax(1, RegimePersistCycles)) {
            s_stableRegime = candidate;
        }
        
        return s_stableRegime;
    }
    
    MarketStats GetMarketStats() const { 
        return m_stats; 
    }
    
    bool IsMarketDataValid(int min_ticks = 10) const { 
        return (m_stats.tickVolume >= min_ticks); 
    }
    
    int GetTickCount() const { 
        return m_stats.tickVolume; 
    }
    
    double GetAverageStrength() const { 
        return m_stats.avgSpeed; 
    }
    
    int GetCurrentDirection() const { 
        return (m_stats.directionScore > 0) ? 1 : 
               (m_stats.directionScore < 0) ? -1 : 0; 
    }
    
    double GetDirectionConsistency() const { 
        return m_stats.consistency / 100.0; 
    }
    
    double GetDirectionChangeRatio() const { 
        return 1.0 - (m_stats.consistency / 100.0); 
    }
    
    string GetMarketRegimeText() const { 
        return sysState.marketType; 
    }
    
    int GetMarketIndex() const {
        int index = 0;
        index += (int)(m_stats.consistency * 0.7);
        index += (int)(MathAbs(m_stats.directionScore) * 0.5);
        return MathMin(100, index);
    }
    
    MarketState GetMarketState() const {
        MarketState state;
        state.strength = m_stats.avgSpeed;
        state.quality = m_stats.directionScore / 10.0;
        state.market_index = GetMarketIndex();
        state.pattern = sysState.marketType;
        state.is_trending = (sysState.marketType == "STEADY_TREND" || sysState.marketType == "STRONG_TREND" || sysState.marketType == "ACCELERATING_TREND");
        state.is_volatile = (m_stats.speedRatio > 1.4);
        state.confidence = m_stats.consistency;
        state.bias = (m_stats.directionScore > 0) ? "Bullish" : (m_stats.directionScore < 0) ? "Bearish" : "Neutral";
        return state;
    }
    
    int GetCurrentConsecutiveCount() const { 
        return m_consecutiveCount; 
    }
};

//+------------------------------------------------------------------+
//| Check Tick Analysis Filter WITH MOMENTUM                         |
//+------------------------------------------------------------------+
double g_lastCandleChannelWidthPip = 0.0;
bool   g_lastCandleRangeVote = false;

bool CheckTickAnalysisFilter() {
    
    ResetBlockReasons();
    RefreshDirectionSettings();
    if(g_tick_analyzer_opt == NULL) {
        return false;
    }
    
    SYMBOL_GROUPS detectedGroup = AutoDetectGroup ? DetectSymbolGroup() : ManualSymbolGroup;
    currentParams = LoadGroupParams(detectedGroup);
   LoadRegimeParams(detectedGroup);
    sysState.currentGroup = (AutoDetectGroup && g_symbolUnknown) ? "Unknown symbol" : GetGroupName(detectedGroup);

    if(AutoDetectGroup && g_symbolUnknown) {   // v176.7: نماد ناشناخته
        ResetBlockReasons();
        string unkReason = "Unknown symbol: turn off AutoDetectGroup and set the group manually (Gold)";
        AddBlockReason(unkReason);
        lastTradeFailureReason = unkReason;
        return false;
    }

    if(!currentParams.enabled) {
        ResetBlockReasons();
        string grpDisabledReason = "Group filter disabled by menu: " + sysState.currentGroup;
        AddBlockReason(grpDisabledReason);
        lastTradeFailureReason = grpDisabledReason;
        return false;
    }
    
    if(g_tick_analyzer_opt != NULL) {
        g_tick_analyzer_opt.SetMinDirection(currentParams.minDirection);
    }
    
    
    MarketStats stats_v30 = g_tick_analyzer_opt.GetMarketStats();
    string marketRegime_v30 = g_tick_analyzer_opt.GetMarketRegimeText();     
    
    UpdateRegimeRangeBaseline(stats_v30.rangePips);

    
    string rejectionReason = "";
    bool isMajor = (sysState.currentGroup == "Major Pairs");   
    
    // ==========  (MOMENTUM FILTER) ==========
    bool okMomentum = true;
    double currentMomentum = 0;
    if(g_EffectiveMinMomentum > 0) {
        currentMomentum = GetMomentum(MOMENTUM_LOOKBACK_TICKS);
        double momentumFloor = g_EffectiveMinMomentum;
        
        if(MathAbs(currentMomentum) < momentumFloor) {
            rejectionReason = StringFormat("Momentum too low: %.2f < %.2f (floor)", 
                                          currentMomentum, momentumFloor);
            AddBlockReason(rejectionReason);
            lastTradeFailureReason = rejectionReason;
            okMomentum = false;
        }
    }  
    // ============================================================
  
    bool okDead, okUnknown, okNoisy, okPower, okRangeRegime, okTooFast;
    double candleChannelWidthPip = 0.0;
    bool candleRangeVote = IsCandleRange(candleChannelWidthPip);   
    g_lastCandleChannelWidthPip = candleChannelWidthPip;
    g_lastCandleRangeVote = candleRangeVote;

    if(EnableRegimeRestrictions) {
        okDead        = Check_DeadMarket(marketRegime_v30, stats_v30, rejectionReason);
        okUnknown     = Check_UnknownRegime(marketRegime_v30, rejectionReason);   // v155 item #1
        okNoisy       = Check_NoisyMarket(marketRegime_v30, stats_v30, currentParams.maxNoiseSpeed, rejectionReason);   // v155 item #2/#4: از حالا MaxNoiseSpeed واقعاً به‌عنوان آستانهٔ فیلتر استفاده می‌شود (NoisyGateMaxSpeed حذف شد)
        okPower       = Check_PowerLevel(sysState.currentGroup, stats_v30, rejectionReason);
        okRangeRegime = Check_RangeRegime(candleRangeVote, rejectionReason);
        okTooFast     = Check_TooFastMarket(marketRegime_v30, stats_v30, rejectionReason);
    } else {
        okDead = okUnknown = okNoisy = okPower = okRangeRegime = okTooFast = true;
    }
    bool okRealStrength = Check_RealStrengthFilter(stats_v30, currentParams.minRealStrength, rejectionReason);
    bool okRange    = Check_RangeFilter(stats_v30, currentParams.minRange, rejectionReason);
    bool okEfficiency = Check_EfficiencyFilter(stats_v30, currentParams.minEfficiency, currentParams.minDirection, rejectionReason);   // v151
    
    bool marketConditionGood = (okDead && okUnknown && okNoisy && okPower && okRangeRegime && okTooFast && okRealStrength && okRange && okEfficiency);
    
    // =============================================
    // 6. FINAL DECISION WITH MOMENTUM CHECK
    // =============================================
    if(marketConditionGood) {
        if(DebugLogEnable) {
               }}

    lastTradeFailureReason = rejectionReason;    
    // =============================================
    // 7. DIRECTION SCORE FINAL CHECK
    // =============================================
    RefreshDirectionSettings();   
    MarketStats final_stats = g_tick_analyzer_opt.GetMarketStats();

    double dir_score = MathAbs(g_direction_avg * 100);

    if(dir_score < 0.1 && final_stats.directionScore != 0) {
        dir_score = MathAbs(final_stats.directionScore);
    }

    double req_dir = currentParams.minDirection;
    double dirFloor = req_dir;
    
    if(dir_score < dirFloor) {
        marketConditionGood = false;
        rejectionReason = StringFormat("Dir %.0f%% < Req %.0f%% (floor)", dir_score, dirFloor);
        AddBlockReason(rejectionReason);
        lastTradeFailureReason = rejectionReason;
    }

    if(marketConditionGood) {
       
        double combinedScore     = MathAbs(currentMomentum) * 100.0 + stats_v30.rangePips * 10.0 + dir_score;
        double combinedThreshold = g_EffectiveMinMomentum * 100.0 + currentParams.minRange * 10.0 + req_dir;
        if(combinedScore < combinedThreshold) {
            marketConditionGood = false;
            rejectionReason = StringFormat("Combined Score %.1f < %.1f", combinedScore, combinedThreshold);
            AddBlockReason(rejectionReason);
            lastTradeFailureReason = rejectionReason;
        }
    }

   
    if(!final_stats.directionPersistOK) {
        marketConditionGood = false;
        rejectionReason = StringFormat("Direction not persistent yet (need %d consecutive ticks)", DirectionPersistTicks);
        AddBlockReason(rejectionReason);
        lastTradeFailureReason = rejectionReason;
    }
    
    if(!okMomentum) marketConditionGood = false;
 
    return marketConditionGood;
}
//========================================================
// 1. DEAD MARKET
bool Check_UnknownRegime(const string &marketRegime_v30, string &rejectionReason) {
    if(marketRegime_v30 != "UNKNOWN" && marketRegime_v30 != "UNKNOWN_CONDITION") return true;

    rejectionReason = "Unknown Regime (" + marketRegime_v30 + ") - blocked by regime restrictions";
    AddBlockReason("Unknown Regime");
    return false;
}

bool Check_DeadMarket(const string &marketRegime_v30, const MarketStats &stats_v30, string &rejectionReason) {
    if(marketRegime_v30 != "DEAD_MARKET") return true;
//  double deadThreshold = 0.01;
    double deadThreshold = 0.03;
    if(stats_v30.tickVolume > 8 && stats_v30.rangePips < deadThreshold) {
        rejectionReason = "Dead Market (Range < 0.5 pip)";
        AddBlockReason(rejectionReason);
        return false;
    }
    return true;
}

// 2. NOISY MARKET
bool Check_NoisyMarket(const string &marketRegime_v30,
                        const MarketStats &stats_v30, double groupMaxNoiseSpeed, string &rejectionReason) {
    if(marketRegime_v30 != "NOISY_MARKET") return true;

    double speedRatio = stats_v30.speedRatio;
    double consistency = stats_v30.consistency;
    double directionScore = MathAbs(stats_v30.directionScore);

    bool isStrongTrend = (directionScore > RegimeNoisyOverrideScore);

    if(isStrongTrend) {
        return true; }
    
    double speedRatioThreshold = groupMaxNoiseSpeed;
     double consistencyThreshold = TA_MIN_CONSISTENCY;
// sari    double minDirectionScore = 12;
    double minDirectionScore =   0.6  ;

    bool isVeryNoisy = (speedRatio > speedRatioThreshold && consistency < consistencyThreshold) ||
                       (directionScore < minDirectionScore && stats_v30.tickVolume > 15);

    if(isVeryNoisy) {
        rejectionReason = "Very Noisy Market in M2";
        AddBlockReason(rejectionReason);
        return false;
    }
    return true;
}

// 3. POWER CHECK
bool Check_PowerLevel(const string &currentGroup, const MarketStats &stats_v30, string &rejectionReason) {
     double marketSpeedRatio = stats_v30.speedRatio;
    double marketRange = stats_v30.rangePips;
    double minSpeedRatioRequired = 0.15;
    double minRangeRequired;

    if(currentGroup == "Major Pairs") {
        minRangeRequired = 0.04;
    } else if(currentGroup == "XAUUSD (Gold)") {
        minRangeRequired = 0.12;
    } else {
        minRangeRequired = 0.10;
    }

    if(marketSpeedRatio < minSpeedRatioRequired && marketRange < minRangeRequired) {
        rejectionReason = "Very Slow Market";
        AddBlockReason(rejectionReason);
        return false;
    }
    return true;
}
// 4. TREND

bool Check_RangeRegime(bool candleRangeVote, string &rejectionReason) {
    if(!candleRangeVote) return true;

    rejectionReason = "Range Market - blocked (Donchian)";

    AddBlockReason(rejectionReason);
    return false;
}


bool Check_TooFastMarket(const string &marketRegime_v30, const MarketStats &stats_v30, string &rejectionReason) {
    if(marketRegime_v30 != "TOO_FAST") return true;

    bool strongAndPersistent = (MathAbs(stats_v30.directionScore) > RegimeNoisyOverrideScore) && stats_v30.directionPersistOK;
    if(strongAndPersistent) {
        return true;
    }

    rejectionReason = "Too Fast Market (speed spike above MaxNoiseSpeed, possible news candle)";
    AddBlockReason(rejectionReason);
    return false;
}


bool Check_EfficiencyFilter(const MarketStats &stats_v30, double groupMinEfficiency, double groupMinDirection, string &rejectionReason) {
    if(!EnableEfficiencyFilter) return true;

    double exemptionBar = groupMinDirection * 0.90;
    if(stats_v30.directionPersistOK && MathAbs(stats_v30.directionScore) > exemptionBar) {
        return true;
    }

    if(stats_v30.efficiencyRatio < groupMinEfficiency) {
        rejectionReason = StringFormat("Low Efficiency Spike (%.2f < %.2f) - likely wick-forming move", stats_v30.efficiencyRatio, groupMinEfficiency);
        AddBlockReason("Efficiency Ratio");
        return false;
    }
    return true;
}

bool Check_RealStrengthFilter(const MarketStats &stats_v30, double groupMinRealStrength, string &rejectionReason) {
    if(!EnableRealStrengthFilter) return true;

    if(stats_v30.realStrength < groupMinRealStrength) {
        rejectionReason = StringFormat("Real Strength too low: %.0f < %.0f",
                                      stats_v30.realStrength, groupMinRealStrength);
        AddBlockReason(rejectionReason);
        return false;
    }

    double accelerationMagnitude = MathAbs(stats_v30.acceleration);
    if(MinAcceleration != 0.0 && accelerationMagnitude < MinAcceleration) {
        rejectionReason = StringFormat("Acceleration too low: %.2f < %.2f",
                                      accelerationMagnitude, MinAcceleration);
        AddBlockReason(rejectionReason);
        return false;
    }

    return true;
}

bool Check_RangeFilter(const MarketStats &stats_v30, double groupMinRange, string &rejectionReason) {
    if(groupMinRange <= 0) return true;

    double rangeFloor = groupMinRange;
    if(stats_v30.rangePips < rangeFloor) {
        rejectionReason = StringFormat("Range too low: %.2f < %.2f pip (floor)",
                                      stats_v30.rangePips, rangeFloor);
        AddBlockReason(rejectionReason);
        return false;
    }
    return true;
}
//+------------------------------------------------------------------+
void DisplayEffectiveThresholds() {
    string grp = sysState.currentGroup;

    double minStepStrength = 0.01;
    if(grp == "MAJ") minStepStrength = 0.005;
    else if(grp == "XAU") minStepStrength = 0.02;

    double minRangeRequired = 0.25;
    if(grp == "MAJ") minRangeRequired = 0.075;
    else if(grp == "XAU") minRangeRequired = 0.3;

}

//+------------------------------------------------------------------+
//| Integrated Filter System (Tick Analysis)                        |
//+------------------------------------------------------------------+
bool CheckIntegratedFilters() {
    
    bool tickFilterOK = CheckTickAnalysisFilter();
    return tickFilterOK;
}

//+------------------------------------------------------------------+
//| Symbol Group Management Functions                               |
//+------------------------------------------------------------------+

SYMBOL_GROUPS DetectSymbolGroup() {
    g_symbolUnknown = false;
    string symbol = Symbol();
    
    if(StringFind(symbol, "XAUUSD") == 0 || StringFind(symbol, "GOLD") == 0) {
        return GROUP_XAUUSD;
    }
    
    // Major Pairs
    string majors[7] = {"EURUSD", "GBPUSD", "USDCHF", 
                        "AUDUSD", "USDCAD", "NZDUSD"};
    
    for(int i = 0; i < 6 ; i++) {
        if(StringFind(symbol, majors[i]) == 0) {
            return GROUP_MAJORS;   }}
      
    // Crosses
string crosses[10] = {"EURGBP", "EURJPY", "GBPJPY", "EURCHF", 
                     "EURCAD", "EURAUD", "GBPCAD", "AUDJPY",
                     "GBPCHF", "USDJPY"};

for(int i = 0; i < 10; i++) {
    if(StringFind(symbol, crosses[i]) == 0) {
        return GROUP_CROSSES;
    }
}  

    // v176.7: نماد ناشناخته — فقط جای‌نگه‌دار؛ معامله در فیلتر تحلیل تیک مسدود می‌شود
    g_symbolUnknown = true;
    return GROUP_XAUUSD;    }
    
//+------------------------------------------------------------------+
//| Symbol Group Management Functions          |
//+------------------------------------------------------------------+
GroupParams LoadGroupParams(SYMBOL_GROUPS group) {
    GroupParams params;
    
    switch(group) {
      case GROUP_XAUUSD:
    params.minRange      = XAU_MinRange;
    params.minDirection  = XAU_MinDirection;
    params.maxSpread     = XAU_MaxSpread;
    params.maxNoiseSpeed = XAU_MaxNoiseSpeed;
    // v155 item #4: XAU_NoisyGateMaxSpeed حذف شد (دیگر لازم نیست، MaxNoiseSpeed جایگزینش شد)
    params.minEfficiency = XAU_MinEfficiency;   // v151
    params.minRealStrength = MinRealStrength;
    params.enabled       = EnableXAUFilter;  
    break;
    
    
    case GROUP_MAJORS:
    params.minRange      = MAJ_MinRange;     
    params.minDirection  = MAJ_MinDirection;
    params.maxSpread     = MAJ_MaxSpread;
    params.maxNoiseSpeed = MAJ_MaxNoiseSpeed;
    // v155 item #4: MAJ_NoisyGateMaxSpeed حذف شد
    params.minEfficiency = MAJ_MinEfficiency;   // v151
    params.minRealStrength = MinRealStrength;
    params.enabled       = true;
    break;
   
      case GROUP_CROSSES:
    params.minRange      = CRS_MinRange;
    params.minDirection  = CRS_MinDirection;
    params.maxSpread     = CRS_MaxSpread;
    params.maxNoiseSpeed = CRS_MaxNoiseSpeed;
    // v155 item #4: CRS_NoisyGateMaxSpeed حذف شد
    params.minEfficiency = CRS_MinEfficiency;   // v151
    params.minRealStrength = MinRealStrength;
    params.enabled       = true;
    break;
            
        default: // v176.7: مقدار نامعتبر (مثلاً از تنظیمات ذخیره‌شدهٔ قدیمی) → غیرفعال
            params.minRange      = 5.0;
            params.minDirection  = 42;  
            params.maxSpread     = 25.0;
            params.maxNoiseSpeed = 6.0;
            params.minRealStrength = MinRealStrength;
            params.enabled       = false;   
    }
     

   params.minRange       *= g_sessionMultiplier;
   params.minDirection    = (int)MathRound(params.minDirection * g_sessionMultiplier);
   params.maxSpread      *= g_sessionSpreadMultiplier;
   params.maxNoiseSpeed  *= g_sessionNoiseMultiplier;
  
    if(g_tick_analyzer_opt != NULL) {
        g_tick_analyzer_opt.SetMinDirection(currentParams.minDirection);
    }

    return params;
}
    

string GetGroupName(SYMBOL_GROUPS group) {
    switch(group) {
        case GROUP_XAUUSD:   return "XAUUSD (Gold)";
        case GROUP_MAJORS:   return "Major Pairs";
        case GROUP_CROSSES:  return "Crosses";
        default:             return "Unknown symbol";   }}
//+------------------------------------------------------------------+
//|      REFRESH DIRECTION SETTINGS          |
//+------------------------------------------------------------------+
void RefreshDirectionSettings() {
    SYMBOL_GROUPS detectedGroup;
    if(AutoDetectGroup) {
        detectedGroup = DetectSymbolGroup();
    } else {
        detectedGroup = ManualSymbolGroup;
    }
    
    currentParams = LoadGroupParams(detectedGroup);
   LoadRegimeParams(detectedGroup);
    sysState.currentGroup = (AutoDetectGroup && g_symbolUnknown) ? "Unknown symbol" : GetGroupName(detectedGroup);
    
    if(g_tick_analyzer_opt != NULL) {
        g_tick_analyzer_opt.SetMinDirection(currentParams.minDirection);
    }
    
    if(DebugLogEnable) {
    }  }
//+------------------------------------------------------------------+
//| === SMART OBJECT MANAGER v4.0 ===                               |
//+------------------------------------------------------------------+
class SmartObjectManager {
private:
    struct ObjectInfo {
        string name;
        string lastText;
        color lastColor;
        datetime lastUpdate;
        bool needsUpdate;
    };
    
    ObjectInfo m_objects[20];
    int m_objectCount;
    datetime m_lastCleanup;
    
public:
    SmartObjectManager() {
        m_objectCount = 0;
        m_lastCleanup = TimeCurrent();
        for(int i = 0; i < 20; i++) {
            m_objects[i].name = "";
            m_objects[i].lastText = "";
            m_objects[i].lastColor = clrWhite;
            m_objects[i].lastUpdate = 0;
            m_objects[i].needsUpdate = false;
        }   }
    
    bool CreateOrUpdateLabelSmart(string name, string text, int x, int y, color clr, 
                                 int fontSize = 10, string font = "Arial") {
        int index = -1;
        for(int i = 0; i < m_objectCount; i++) {
            if(m_objects[i].name == name) {
                index = i;
                break;
            }   }
        
        if(index < 0) {
            if(m_objectCount >= 20) {
                CleanupOldObjects();
            }
            index = m_objectCount;
            m_objects[index].name = name;
            m_objects[index].lastText = "";
            m_objects[index].lastColor = clrWhite;
            m_objects[index].needsUpdate = true;
            m_objectCount++;
        }
        
        bool needsUpdate = m_objects[index].needsUpdate ||
                          m_objects[index].lastText != text ||
                          m_objects[index].lastColor != clr;
        
        if(!needsUpdate) {
            return true;
        }
        
        if(ObjectFind(0, name) < 0) {
            if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) {
                return false;
            }
            ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
            ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
            ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
            ObjectSetString(0, name, OBJPROP_FONT, font);
            ObjectSetInteger(0, name, OBJPROP_BACK, false);
            ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        }
        
        ObjectSetString(0, name, OBJPROP_TEXT, text);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        
        m_objects[index].lastText = text;
        m_objects[index].lastColor = clr;
        m_objects[index].lastUpdate = TimeCurrent();
        m_objects[index].needsUpdate = false;
        
        return true;
    }
    
    void CleanupOldObjects() {
        if(TimeCurrent() - m_lastCleanup < 300) return;
        
        for(int i = m_objectCount - 1; i >= 0; i--) {
            if(ObjectFind(0, m_objects[i].name) < 0) {
                for(int j = i; j < m_objectCount - 1; j++) {
                    m_objects[j] = m_objects[j + 1];
                }
                m_objectCount--;
            }   }
        m_lastCleanup = TimeCurrent(); 
    }
    
    void ForceUpdateAll() {
        for(int i = 0; i < m_objectCount; i++) {
            m_objects[i].needsUpdate = true;
        }   }   };

SmartObjectManager g_objectManager;

#define STATUS_PANEL_MAX_LINES 34
int g_statusPanelActiveLines = 0; 

void CreateStatusPanel() {
    for(int i = 0; i < STATUS_PANEL_MAX_LINES; i++) {
        string labelName = "StatusPanel_" + IntegerToString(i);
        if(ObjectFind(0, labelName) < 0) {
            ObjectCreate(0, labelName, OBJ_LABEL, 0, 0, 0);
            ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, PanelPositionX);
            ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, PanelPositionY + i * 20);
            ObjectSetInteger(0, labelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(0, labelName, OBJPROP_COLOR, clrLime);
            ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 10);
            ObjectSetString(0, labelName, OBJPROP_FONT, "Arial");
            ObjectSetInteger(0, labelName, OBJPROP_BACK, false);
            ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
            ObjectSetString(0, labelName, OBJPROP_TEXT, "");
        }  }}

void UpdateStatusText(string text, int line, color clr) {
    string labelName = "StatusPanel_" + IntegerToString(line);
    if(ObjectFind(0, labelName) >= 0) {
        ObjectSetString(0, labelName, OBJPROP_TEXT, text);
        ObjectSetInteger(0, labelName, OBJPROP_COLOR, clr);
    }  }
string g_panelLines[STATUS_PANEL_MAX_LINES];
color  g_panelColors[STATUS_PANEL_MAX_LINES];
int    g_panelLineCount = 0;

void PanelReset() { g_panelLineCount = 0; }

void PanelAddLine(string text, color clr) {
    if(g_panelLineCount >= STATUS_PANEL_MAX_LINES) return;
    g_panelLines[g_panelLineCount] = text;
    g_panelColors[g_panelLineCount] = clr;
    g_panelLineCount++;
}

void PanelFlush() {
    for(int i = 0; i < g_panelLineCount; i++) {
        UpdateStatusText(g_panelLines[i], i, g_panelColors[i]);
    }
    for(int i = g_panelLineCount; i < STATUS_PANEL_MAX_LINES; i++) {
        UpdateStatusText("", i, clrGray);
    }
    g_statusPanelActiveLines = g_panelLineCount;
}

void ClearStatusDisplay() {
    string baseName = "StatusPanel_";
    for(int i = 0; i < STATUS_PANEL_MAX_LINES; i++) {
        string labelName = baseName + IntegerToString(i);
        if(ObjectFind(0, labelName) >= 0) {
            ObjectDelete(0, labelName);
        }   }  }
//+------------------------------------------------------------------+
//| Enhanced Tick Analysis Display                                  |
//+------------------------------------------------------------------+
void DisplayEnhancedTickAnalysis() {
   if(!ShowTickAnalysisOnChart) return;
   
   if(g_tick_analyzer_opt != NULL) {
      g_tick_analyzer_opt.ProcessTick();
   }
   
   
   MarketStats stats_v30;
   string marketRegime_v30 = "NOT INIT";
   if(g_tick_analyzer_opt != NULL) {
      stats_v30 = g_tick_analyzer_opt.GetMarketStats();
      marketRegime_v30 = g_tick_analyzer_opt.GetMarketRegimeText();
   }
   
   SYMBOL_GROUPS detectedGroup;
   if(AutoDetectGroup) {
       detectedGroup = DetectSymbolGroup();
   } else {
       detectedGroup = ManualSymbolGroup;
   }
   
   currentParams = LoadGroupParams(detectedGroup);
   LoadRegimeParams(detectedGroup);
   sysState.currentGroup = (AutoDetectGroup && g_symbolUnknown) ? "Unknown symbol" : GetGroupName(detectedGroup);
 
   if(g_tick_analyzer_opt == NULL) {
      if(DebugLogEnable) {
      }    return;   } 
   
   if(g_tick_analyzer_opt != NULL) {
      g_tick_analyzer_opt.SetMinDirection(currentParams.minDirection);
   } 
   
   // ارزیابی نمایشیِ فیلترها برای «سیگنال واقعی» (نه حدس جهت)؛ وضعیت مسیر معاملهٔ واقعی را تغییر نمی‌دهد
   string panelSavedReason = lastTradeFailureReason;
   string panelSavedBlocks[MAX_BLOCK_REASONS];
   int    panelSavedCount = g_blockReasonCount;
   for(int pb0 = 0; pb0 < panelSavedCount; pb0++) panelSavedBlocks[pb0] = g_blockReasons[pb0];
   bool overall_filters_passed = CheckOtherFiltersEnhanced(lastSignalUsed);
   string panelReason = lastTradeFailureReason;
   string panelBlocks[MAX_BLOCK_REASONS];
   int    panelBlockCount = g_blockReasonCount;
   for(int pb1 = 0; pb1 < panelBlockCount; pb1++) panelBlocks[pb1] = g_blockReasons[pb1];
   lastTradeFailureReason = panelSavedReason;
   g_blockReasonCount = panelSavedCount;
   for(int pb2 = 0; pb2 < panelSavedCount; pb2++) g_blockReasons[pb2] = panelSavedBlocks[pb2];
   GlobalVariableSet("DualIchimokuSignal_" + _Symbol + "_" + string(_Period), 0.0);   
      string decision_result = "🟡 Waiting For Signal";
   int displaySignalValue = lastSignalUsed;
   string processed_signal_type = (displaySignalValue == 1) ? "BUY" : (displaySignalValue == -1 ? "SELL" : "NONE");
   
   if(displaySignalValue == 0) {
      decision_result = "⏳ Signal: NONE";
   }
   else if(panelReason != "") {
      string signal_type_text = (displaySignalValue == 1) ? "BUY" : (displaySignalValue == -1 ? "SELL" : "UNKNOWN");
      decision_result = signal_type_text + " Rejected ❌";
   } else if(displaySignalValue != 0) {
      decision_result = "✅ Processing " + processed_signal_type + " Signal";
   }
     string pattern_display = "Regime: " + marketRegime_v30;
   color pattern_color = clrYellow;
   
   if(marketRegime_v30 == "DEAD_MARKET") {
      pattern_display += " ⚠️ (Dead)";
      pattern_color = clrGray;
   } else if(marketRegime_v30 == "ACCELERATING_TREND") {
      pattern_display += " 🔥 (Accelerating Trend)";
      pattern_color = clrHotPink;
   } else if(marketRegime_v30 == "STRONG_TREND") {
      pattern_display += " ⚡ (Strong Trend)";
      pattern_color = clrLime;
   } else if(marketRegime_v30 == "STEADY_TREND") {
      pattern_display += " ✅ (Steady Trend)";
      pattern_color = clrYellow;
   } else if(marketRegime_v30 == "TOO_FAST") {
      pattern_display += " 🚨 (Too Fast)";
      pattern_color = clrRed;
   } else if(marketRegime_v30 == "NOISY_MARKET") {
      pattern_display += " ⚡ (Noisy)";
      pattern_color = clrRed;
   }
 
   bool tick_filter_passed = overall_filters_passed;
   string tick_rejection_reason = panelReason;
   
   color green_color = clrLime;
   color red_color = clrRed;
   color yellow_color = clrYellow;
   
   double momentum_value = 0;
   int direction_value = 0;
   int valid_ticks = 0;
   
   if(g_tick_analyzer_opt != NULL) {
       MarketStats stats = g_tick_analyzer_opt.GetMarketStats();
       direction_value = stats.directionScore;
       
       int start_idx = (bufferIndex - 30 + MAX_HISTORY) % MAX_HISTORY;
       for(int i = 0; i < 30; i++) {
           int idx = (start_idx + i) % MAX_HISTORY;
           if(tickPriceBuffer[idx] > 0 && tickTimeBuffer[idx] > 0) valid_ticks++;
       }
    
       momentum_value = GetMomentum(MOMENTUM_LOOKBACK_TICKS);
   }

   int display_min_dir = currentParams.minDirection;
   double mom_threshold = g_EffectiveMinMomentum; 
 
   bool momentumOK  = (MathAbs(momentum_value) >= mom_threshold);
   bool directionOK = (MathAbs(direction_value) >= display_min_dir);
   bool rangeOK     = (stats_v30.rangePips >= currentParams.minRange);
   color status_color;
   if(valid_ticks < 4) status_color = clrGray;           
   else if(momentumOK && directionOK && rangeOK) status_color = clrLime;
   else if(!momentumOK && !directionOK && !rangeOK) status_color = clrRed;
   else status_color = clrYellow;
   
 
    double dir_score_display = MathAbs(g_direction_avg * 100);
   if(dir_score_display < 0.1 && stats_v30.directionScore != 0) {
      dir_score_display = MathAbs(stats_v30.directionScore);
   }
   double req_dir_display = currentParams.minDirection;
   bool dirGateOK = (dir_score_display >= req_dir_display) && stats_v30.directionPersistOK;
   
   PanelReset();
   // v149 fix #1: هشدار پررنگ وقتی نظارت زنده/تریل عملاً متوقف است، تا این حالت دیگر گم نشود.
   if(managementPaused) {
      PanelAddLine("⛔ مدیریت پوزیشن (تریل + نظارت زنده) کاملاً متوقف است - دکمهٔ MGMT را بزن", clrRed);
   }
   PanelAddLine("══════════════════════════════════", green_color);
   PanelAddLine("    PROFESSIONAL TICK ANALYSIS", green_color);
   PanelAddLine("══════════════════════════════════", green_color);
   string sourceLabel = "";
   if(UseIndicatorSignal)  sourceLabel += "اندیکاتور+";
   if(UseCompositeSignal)  sourceLabel += "ماشهٔ ترکیبی+";
   if(UseBoxSignal)        sourceLabel += "باکس+";
   if(UseBoxBreakSignal || UseBoxBreak2Signal) sourceLabel += "شکست باکس+";   // BOXBREAK
   if(sourceLabel == "") sourceLabel = "بدون منبع";
   else sourceLabel = StringSubstr(sourceLabel, 0, StringLen(sourceLabel) - 1);
   PanelAddLine(sourceLabel + ": " + processed_signal_type + " | Decision: " + decision_result, panelReason == "" ? green_color : red_color);
   PanelAddLine(pattern_display, pattern_color);
   
    string dirSign = (direction_value > 0) ? "+" : (direction_value < 0) ? "-" : "";
  
   PanelAddLine(StringFormat("%s | Mom:%.2fpip/%.2fpip | Dir:%s%d/%d(%s) | Rng:%.1f/%.1f",
                  sysState.currentGroup, momentum_value, g_EffectiveMinMomentum,
                  dirSign, MathAbs(direction_value), display_min_dir,
                  stats_v30.directionPersistOK ? "✓" : "⏳",
                  stats_v30.rangePips, currentParams.minRange),
                  status_color);
 
// v177.1 removed: PanelAddLine(StringFormat("ATR(Donchian): %.1f pip (M%d) | ATR(Trail): %.1f pip%s",
// v177.1 removed: GetDonchianATR_Pips(), (int)PeriodSeconds(PERIOD_CURRENT)/60, GetTrailATR_Pips(),
// v177.1 removed: g_atrFrozenWarning ? " ⚠️[دریافت داده متوقف - در حال بازسازی]" : ""),
// v177.1 removed: g_atrFrozenWarning ? clrRed : clrSilver);

// v177.1 removed: PanelAddLine(StringFormat("پریود ATR تریل: %s | فعلی=%d (پایه=%d × ضریب سشن=%.2f) | شروع تریل ATR=%.
// v177.1 removed: AdvATR_SessionPeriodMode ? "سشن‌محور" : "ثابت (معمولی)",
// v177.1 removed: g_EffectiveAdvATR_Period, AdvATR_Period, g_sessionATRPeriodMultiplier, AdvATR_TrailingStart),
// v177.1 removed: clrSilver);

// v177.1 removed: if(TrailingMode == TRAIL_ADVANCED_ATR || TrailingMode == TRAIL_ATR_STEP || TrailingMode == TRAIL_HYB
// v177.1 removed: double liveTrailATR = GetTrailATR_Pips();
// v177.1 removed: double liveTrailDist = MathMax(AdvATR_MinTrailPips, liveTrailATR * AdvATR_TrailMultiplier);
// v177.1 removed: string hybridNote = (TrailingMode == TRAIL_HYBRID_ALL)
// v177.1 removed: ? StringFormat("  |  گام ثابت=%.1f پیپ (TrailingStep) - هرکدام محافظتی‌تر بود انتخاب می‌شود", Traili
// v177.1 removed: : "";
// v177.1 removed: PanelAddLine(StringFormat("راهنما: فاصلهٔ تریل ATR الان = %.1f پیپ  (ATR=%.1f × ضریب=%.1f، کف=%.1f)%
// v177.1 removed: liveTrailDist, liveTrailATR, AdvATR_TrailMultiplier, AdvATR_MinTrailPips, hybridNote), clrYellow);
// v177.1 removed: }
   string donchianStatusNote = "";
   if(g_donchianStatus == 1) donchianStatusNote = " [خاموش]";
   else if(g_donchianStatus == 2) donchianStatusNote = " [تاریخچهٔ کندل ناکافی]";
   else if(g_donchianStatus == 3) donchianStatusNote = " [ATR هنوز آماده نیست]";
   PanelAddLine(StringFormat("Donchian: Channel=%.1fpip%s", g_lastCandleChannelWidthPip, donchianStatusNote), clrSilver);
   PanelAddLine(StringFormat("Donchian: Threshold=%.1fpip (ATR=%.1f x%.1f) | %s",
                 GetDonchianATR_Pips()*DonchianRangeWidthATRRatio, GetDonchianATR_Pips(), DonchianRangeWidthATRRatio,
                 g_lastCandleRangeVote ? "Reng" : "No Renge"), g_lastCandleRangeVote ? clrOrange : clrSilver);
   
   PanelAddLine("Tick Filter: " + (tick_filter_passed ? "✅ Pass" : "❌ Rejected"),
                   tick_filter_passed ? green_color : red_color);
   if(EnableDivergenceFilter) {
      for(int dvs = 0; dvs < Div_SlotCount(); dvs++) {
         color dvClr = clrSilver;
         string dvTxt = Div_SlotStatus(dvs, dvClr);
         PanelAddLine(dvTxt, dvClr);
      }
   }
   if(EnableLegEntry) {   // LEG v178.0
      color lgClr = clrSilver;
      string lgTxt = LG_StatusText(lgClr);
      PanelAddLine(lgTxt, lgClr);
      for(int lk = 0; lk < 6; lk++) {
         color lkClr = clrSilver;
         string lkTxt = LG_DetailText(lk, lkClr);
         if(lkTxt != "") PanelAddLine(lkTxt, lkClr);
      }
   }
   if(g_lastSugTime > 0) {
      const int sugAgeMin = (int)((TimeCurrent() - g_lastSugTime) / 60);
      PanelAddLine(StringFormat("آخرین پیشنهاد ارسال‌شده: %s | %s | %s | %d دقیقه پیش | از همهٔ فیلترها گذشت",
                   (g_lastSugDir > 0 ? "خرید" : "فروش"), Sug_MaskNames(g_lastSugMask),
                   TimeToString(g_lastSugTime, TIME_SECONDS), sugAgeMin), clrAqua);
   }

if(EnablePostEntryRegimeMonitor) {
   int posTotal2 = PositionsTotal();
   bool foundAnyPos = false;
   for(int pi = 0; pi < posTotal2; pi++) {
      ulong pTicket = PositionGetTicket(pi);
      if(pTicket <= 0 || !PositionSelectByTicket(pTicket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      foundAnyPos = true;

      double curAdverseSeconds = 0.0;
      int    curTightenStep = 0;
      string curReason = "";
      bool   curSucceeded = false;
      datetime curSuccessTime = 0;
      for(int si = 0; si < ArraySize(g_postEntryStates); si++) {
         if(g_postEntryStates[si].ticket == pTicket) {
            curAdverseSeconds = g_postEntryStates[si].adverseSeconds;
            curTightenStep    = g_postEntryStates[si].tightenCount;
            curReason         = g_postEntryStates[si].lastReason;
            curSucceeded      = g_postEntryStates[si].lastActionSucceeded;
            curSuccessTime    = g_postEntryStates[si].lastSuccessTime;
            break;  }}
         
      double pct = (g_postEntry_thresholdSeconds > 0.0001) ? (curAdverseSeconds / g_postEntry_thresholdSeconds * 100.0) : 0.0;
      pct = MathMax(0.0, MathMin(100.0, pct));
      bool recentlySucceeded = curSucceeded && curSuccessTime > 0 && ((TimeCurrent() - curSuccessTime) < POSTENTRY_COOLDOWN_SECONDS);
      string actionWord = GetPostEntryEffectiveClose() ? "معامله بسته شد" : "استاپ نزدیک‌تر شد";

      string line;
      color  clr;
      if(recentlySucceeded) {
         line = StringFormat("PostEntry(تیکت %d): 🔴 %s (دلیل: %s)", pTicket, actionWord, (curReason != "" ? curReason : "-"));
         clr = red_color;
      } else if(pct > 0.0001) {
         line = StringFormat("PostEntry(تیکت %d): 🟡 در حال بررسی (%.0f%% تا واکنش) - %s", pTicket, pct, (curReason != "" ? curReason : "-"));
         clr = clrYellow;
      } else {
         line = StringFormat("PostEntry(تیکت %d): 🟢 وضعیت عادی", pTicket);
         clr = clrLimeGreen;
      }
      if(curTightenStep > 0) line += StringFormat(" | پله تنگ‌سازی=%d", curTightenStep);
      PanelAddLine(line, clr);
   }
   if(!foundAnyPos)
      PanelAddLine("PostEntry: 🟢 معاملهٔ باز نیست", clrSilver);
}

//---------------------------------
   

 
   bool speedOK  = (stats_v30.speedRatio <= currentParams.maxNoiseSpeed);
   bool spreadOK = (stats_v30.currentSpread <= currentParams.maxSpread);
   color speedSpreadColor = (speedOK && spreadOK) ? green_color : (speedOK || spreadOK) ? clrOrange : red_color;
   PanelAddLine(StringFormat("Speed: %.1f / %.1f  |  Spread: %.1f / %.1f pip",
                  stats_v30.speedRatio, currentParams.maxNoiseSpeed,
                  stats_v30.currentSpread, currentParams.maxSpread),
                  speedSpreadColor);
   
   if(g_tick_analyzer_opt != NULL) {
      MarketStats stats = g_tick_analyzer_opt.GetMarketStats();
      if(EnableRealStrengthFilter) PanelAddLine(StringFormat("RealStr(هموارشده):%.0f/%.0f | Acc(هموارشده،فقط‌اندازه):%.2f/%.2f", 
                      stats.realStrength, currentParams.minRealStrength,
                      MathAbs(stats.acceleration), MinAcceleration), clrCyan);

      if(EnableEfficiencyFilter) {
         bool effStrongTrendException = stats.directionPersistOK && MathAbs(stats.directionScore) > (currentParams.minDirection * 0.90);   // v152 item #1: synced with Check_EfficiencyFilter's real exemption bar
         bool effPass = effStrongTrendException || (stats.efficiencyRatio >= currentParams.minEfficiency);
         color effColor = effPass ? clrLimeGreen : red_color;
         string effNote;
         if(effStrongTrendException)
            effNote = "روند قوی و پایدار - این فیلتر نادیده گرفته می‌شود";
         else if(effPass)
            effNote = "حرکت یک‌طرفه و قابل‌اعتماد";
         else
            effNote = "رفت‌وبرگشت زیاد - شبیه اسپایکی که به سایه تبدیل می‌شود، سیگنال رد می‌شود";
         PanelAddLine(StringFormat("کارایی حرکت (Efficiency): %.2f / %.2f  →  %s",
                       stats.efficiencyRatio, currentParams.minEfficiency, effNote), effColor);
      }

      if(UseCompositeSignal) {
         double compScore = GetCompositeTriggerScore(stats);
         string compVerdict;
         color compColor;
         if(compScore >= CompositeTrigger_BuyThreshold)      { compVerdict = "سیگنال خرید"; compColor = clrLimeGreen; }
         else if(compScore <= CompositeTrigger_SellThreshold) { compVerdict = "سیگنال فروش"; compColor = red_color; }
         else                                                  { compVerdict = "خنثی - منتظر"; compColor = clrSilver; }
         PanelAddLine(StringFormat("ماشهٔ ترکیبی: امتیاز=%.0f/100 (خرید≥%.0f، فروش≤%.0f) → %s",
                       compScore, CompositeTrigger_BuyThreshold, CompositeTrigger_SellThreshold, compVerdict), compColor);
         PanelAddLine(StringFormat("  اجزا → فشار جریان تیک=%.2f | انحراف از ارزش منصفانه=%.2f | کارایی(وزن)=%.2f",
                       g_lastCompositeImbalance, g_lastCompositeDeviation, g_lastCompositeEfficiency), clrSilver);
      }

      // v157: توضیح فیلتر ابر آلفا برای کاربر - وضعیت فعلی قیمت نسبت به ابر و نتیجه (محاسبهٔ دستی)
// v177.1 removed: if(EnableAlphaCloudFilter) {
// v177.1 removed: // v177.1 removed: double cTop, cBottom;
// v177.1 removed: // v177.1 removed: if(AlphaCloud_GetTodayCloud(cTop, cBottom)) {
// v177.1 removed: // v177.1 removed: double cPip = GetPip();
// v177.1 removed: // v177.1 removed: double cPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
// v177.1 removed: // v177.1 removed: double cEps = Alpha_EpsPips * cPip;
// v177.1 removed: // v177.1 removed: string cloudVerdict; color cloudColor;
// v177.1 removed: // v177.1 removed: if(cPrice > cTop + cEps)      { cloudVerdict = "بالای ابر - فقط خرید مجاز"; cloudColor = clrLimeGree
// v177.1 removed: // v177.1 removed: else if(cPrice < cBottom - cEps) { cloudVerdict = "پایین ابر - فقط فروش مجاز"; cloudColor = red_colo
// v177.1 removed: // v177.1 removed: else                            { cloudVerdict = "داخل ابر - همه سیگنال‌ها بلاک"; cloudColor = clrSi
// v177.1 removed: // v177.1 removed: PanelAddLine(StringFormat("ابر آلفا: سقف=%.5f کف=%.5f قیمت=%.5f (حاشیه=%.1f پیپ) → %s",
// v177.1 removed: // v177.1 removed: cTop, cBottom, cPrice, Alpha_EpsPips, cloudVerdict), cloudColor);
// v177.1 removed: }
// v177.1 removed: }
   }
 
   DisplayEffectiveThresholds();
   if(panelBlockCount > 0) {
      for(int bi = 0; bi < panelBlockCount; bi++) {
         string reasonLine = panelBlocks[bi];
         if(StringLen(reasonLine) > 40) reasonLine = StringSubstr(reasonLine, 0, 40) + "...";
         PanelAddLine(StringFormat("⛔ %s", reasonLine), red_color);
      }
   }
   
   PanelFlush();
}
//+------------------------------------------------------------------+
//| Trading State Management System                                 |
//+------------------------------------------------------------------+
ENUM_TRADE_STATE tradeState_v260 = TRADE_STATE_IDLE;
int pendingSignal_v260 = 0;
datetime lastCheckTime_v260 = 0;
int waitBarsCounter_v260 = 0;

void ProcessIdleState() {
   
   UpdateStoch1Memory();
   UpdateStoch2Memory();
   
   bool crossOK = CheckCrossMemory(pendingSignal_v260);
   
   if(crossOK) {
      tradeState_v260 = TRADE_STATE_WAITING_OBOS;
   } else {
      tradeState_v260 = TRADE_STATE_WAITING_CROSS;
        }
   
   waitBarsCounter_v260 = 0;  }

void ProcessWaitingCrossState() {
   waitBarsCounter_v260++;
   UpdateStoch1Memory();
   UpdateStoch2Memory();
   
   bool crossOK = CheckCrossMemory(pendingSignal_v260);
   
   if(crossOK) {
      tradeState_v260 = TRADE_STATE_WAITING_OBOS;
      waitBarsCounter_v260 = 0;
   } else {
      
      if(waitBarsCounter_v260 > 20) {
         tradeState_v260 = TRADE_STATE_IDLE;
             }}}

void ProcessWaitingObOsState() {
   waitBarsCounter_v260++;
   bool obosOK = CheckObOsConditions(pendingSignal_v260);
   
   if(obosOK) {
      tradeState_v260 = TRADE_STATE_READY_TO_TRADE;
      waitBarsCounter_v260 = 0;
   } else {
      bool crossStillValid = CheckCrossMemory(pendingSignal_v260);
      if(!crossStillValid) {
         tradeState_v260 = TRADE_STATE_WAITING_CROSS;
         return;} 
     
      
      if(waitBarsCounter_v260 > 15) {
         tradeState_v260 = TRADE_STATE_IDLE;
            }}}

void ProcessReadyToTradeState() {
   bool crossOK = CheckCrossMemory(pendingSignal_v260);
   bool obosOK = CheckObOsConditions(pendingSignal_v260);
   bool otherFiltersOK = CheckOtherFiltersEnhanced(pendingSignal_v260);
   
   if(crossOK && obosOK && otherFiltersOK) {
      ExecuteTrade(pendingSignal_v260);
      tradeState_v260 = TRADE_STATE_IDLE;
      pendingSignal_v260 = 0;
      FilterLog("✅ معامله با موفقیت اجرا شد (استیت‌ماشین v2.60)");
   } else {
      tradeState_v260 = TRADE_STATE_IDLE;
      if(!otherFiltersOK) {
         FilterLog("❌ Final conditions rejected: " + lastTradeFailureReason);
      } else {
            }}}

bool CheckCrossMemory(int signal) {
   bool stoch1OK_local = true;
   bool stoch2OK_local = true;
   
   if(UseStochastic1Confirmation) {
      if(IsStochMemoryValid(stoch1Memory)) {
         stoch1OK_local = (stoch1Memory.crossType == signal);
      } else {
         stoch1OK_local = false;
           }}
   
   if(UseStochastic2Confirmation) {
      if(IsStochMemoryValid(stoch2Memory)) {
         stoch2OK_local = (stoch2Memory.crossType == signal);
      } else {
         stoch2OK_local = false;
          }}
    
   bool result = (stoch1OK_local && stoch2OK_local);
   if(result && DebugLogEnable) {
   } else if(!result) {
      if(!stoch1OK_local && !stoch2OK_local) lastTradeFailureReason = "Stochastic 1 & 2: No valid cross";
      else if(!stoch1OK_local) lastTradeFailureReason = "Stochastic 1: No valid/matching cross";
      else lastTradeFailureReason = "Stochastic 2: No valid/matching cross";
      if(!stoch1OK_local) AddBlockReason("Stochastic 1: No valid/matching cross");
      if(!stoch2OK_local) AddBlockReason("Stochastic 2: No valid/matching cross");
   }
   return result; }

double AlphaCloud_HighestOverRange(int period, int startShift) {
    double h = -1.0;
    for(int i = startShift; i < startShift + period; i++) {
        double v = iHigh(_Symbol, PERIOD_CURRENT, i);
        if(v > h) h = v;
    }
    return h;
}

double AlphaCloud_LowestOverRange(int period, int startShift) {
    double l = -1.0;
    for(int i = startShift; i < startShift + period; i++) {
        double v = iLow(_Symbol, PERIOD_CURRENT, i);
        if(l < 0 || v < l) l = v;
    }
    return l;
}

bool AlphaCloud_GetTodayCloud(double &topOut, double &bottomOut) {
    int neededBars = Alpha_Shift + Alpha_SenkouB + 2;
    if(Bars(_Symbol, PERIOD_CURRENT) < neededBars) return false;   // تاریخچهٔ کافی نیست

    double tenkanShift = (AlphaCloud_HighestOverRange(Alpha_Tenkan, Alpha_Shift) + AlphaCloud_LowestOverRange(Alpha_Tenkan, Alpha_Shift)) / 2.0;
    double kijunShift   = (AlphaCloud_HighestOverRange(Alpha_Kijun, Alpha_Shift) + AlphaCloud_LowestOverRange(Alpha_Kijun, Alpha_Shift)) / 2.0;
    double senkouA_today = (tenkanShift + kijunShift) / 2.0;
    double senkouB_today = (AlphaCloud_HighestOverRange(Alpha_SenkouB, Alpha_Shift) + AlphaCloud_LowestOverRange(Alpha_SenkouB, Alpha_Shift)) / 2.0;

    topOut = MathMax(senkouA_today, senkouB_today);
    bottomOut = MathMin(senkouA_today, senkouB_today);
    return true;
}

bool Check_AlphaCloudFilter(int signal, string &rejectionReason) {
    if(!EnableAlphaCloudFilter) return true;
    if(signal == 0) return true;

    double top, bottom;
    if(!AlphaCloud_GetTodayCloud(top, bottom)) return true;   // fail-open: تاریخچهٔ کافی نیست

    double eps = Alpha_EpsPips * GetPip();
    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    bool isBuySignal = (signal > 0);

    if(price > top + eps) {
        if(!isBuySignal) {
            rejectionReason = "Alpha Cloud: SELL not allowed (price above cloud)";
            return false;
        }
    } else if(price < bottom - eps) {
        if(isBuySignal) {
            rejectionReason = "Alpha Cloud: BUY not allowed (price below cloud)";
            return false;
        }
    } else {
        rejectionReason = "Alpha Cloud: No signal (price inside cloud)";
        return false;
    }
    return true;
}

bool Check_Stochastic1Confirmation(int signal, string &rejectionReason) {
    if(signal == 0) return true;
    if(!UseStochastic1Confirmation) return true;

    bool ok = (signal == 1 && stoch1Memory.signalState == 2) ||
              (signal == -1 && stoch1Memory.signalState == 4);
    if(!ok) {
        string stateNames[] = {"NONE", "PENDING_BUY(در انتظار خروج از اشباع فروش)", "CONFIRMED_BUY",
                                "PENDING_SELL(در انتظار خروج از اشباع خرید)", "CONFIRMED_SELL"};
        int st = stoch1Memory.signalState;
        string stName = (st >= 0 && st <= 4) ? stateNames[st] : "?";
        rejectionReason = StringFormat("Stoch1: %s not confirmed (state=%s, K=%.1f D=%.1f)",
                              (signal == 1 ? "BUY" : "SELL"), stName, stoch1Memory.currentK, stoch1Memory.currentD);
        AddBlockReason(rejectionReason);
        return false;
    }
    return true;
}

bool Check_Stochastic2Confirmation(int signal, string &rejectionReason) {
    if(signal == 0) return true;
    if(!UseStochastic2Confirmation) return true;

    bool ok = (signal == 1 && stoch2Memory.signalState == 2) ||
              (signal == -1 && stoch2Memory.signalState == 4);
    if(!ok) {
        string stateNames[] = {"NONE", "PENDING_BUY(در انتظار خروج از اشباع فروش)", "CONFIRMED_BUY",
                                "PENDING_SELL(در انتظار خروج از اشباع خرید)", "CONFIRMED_SELL"};
        int st = stoch2Memory.signalState;
        string stName = (st >= 0 && st <= 4) ? stateNames[st] : "?";
        rejectionReason = StringFormat("Stoch2: %s not confirmed (state=%s, K=%.1f D=%.1f)",
                              (signal == 1 ? "BUY" : "SELL"), stName, stoch2Memory.currentK, stoch2Memory.currentD);
        AddBlockReason(rejectionReason);
        return false;
    }
    return true;
}

bool CheckObOsConditions(int signal) {
   string tmpReason = "";
   bool stoch1OK_local = Check_Stochastic1Confirmation(signal, tmpReason);
   bool stoch2OK_local = Check_Stochastic2Confirmation(signal, tmpReason);

   bool result = (stoch1OK_local && stoch2OK_local);
   if(result && DebugLogEnable) {
   } else if(!result) {
      if(!stoch1OK_local && !stoch2OK_local) lastTradeFailureReason = "Stochastic 1 & 2: Wrong OB/OS zone";
      else if(!stoch1OK_local) lastTradeFailureReason = "Stochastic 1: Wrong OB/OS zone";
      else lastTradeFailureReason = "Stochastic 2: Wrong OB/OS zone";
   }
   return result; }
//+------------------------------------------------------------------+
//| DIVFILTER (v176.7): فیلتر تأیید با واگرایی قیمت و MACD             |
//| - واگرایی معمولی (برگشتی) و پنهان (ادامه‌دار)؛ هر نوع وضعیت جدا دارد |
//|   صعودی (معمولی/پنهان) فقط خرید را تأیید می‌کند، نزولی فقط فروش.    |
//| - منبع MACD از منو: خط اصلی یا هیستوگرام (اصلی منهای سیگنال).       |
//| - رد واگرایی اگر خود MACD از خط وصل‌کنندهٔ دو قله/دره عبور کند.      |
//| - باطل شدن با شکستن کف/سقف دوم (کندل بسته یا کندل در حال تشکیل).    |
//| - تایم جاری + M5 + M15؛ واگرایی معتبرِ هم‌جهت در هر کدام = تأیید.   |
//+------------------------------------------------------------------+
#define DIV_PREFIX          "DIVF_"
#define DIV_PRICE_WINDOW    2       // سقف/کف قیمت در بازه‌ی ±این‌تعداد کندل از قله/دره‌ی مکدی
#define DIV_HISTORY_BARS    400     // تعداد کندلِ گذشته که هنگام شروع بازسازی می‌شود (برای هر تایم‌فریم)
#define DIV_MAX_STORED      24      // تعداد قله/دره‌ی اخیر که برای هر تایم‌فریم نگه داشته می‌شود
#define DIV_MAX_SLOTS       3       // تایم جاری + M5 + M15
#define DIV_TYPES           4       // 0=معمولی صعودی 1=معمولی نزولی 2=پنهان صعودی 3=پنهان نزولی

struct DivPivot
{
   bool     valid;
   datetime macdTime;      // زمان کندلِ قله/دره‌ی مکدی
   double   macdValue;     // مقدار مکدی در آن کندل
   datetime anchorTime;    // زمان کندلِ سقف/کفِ متناظر روی قیمت
   double   anchorPrice;   // سقف یا کفِ آن کندل
};

int      g_divFast = 12, g_divSlow = 26, g_divSig = 9;            // مقدارهای نهایی مکدی (بعد از اصلاح ورودی‌ها)
int      g_divS = 3, g_divMinD = 5, g_divMaxD = 60, g_divW = 2;    // حساسیت قله و فاصله‌ی مجاز
int             g_divSlotCount = 0;
ENUM_TIMEFRAMES g_divTF[3];
int             g_divHandle[3]      = {INVALID_HANDLE, INVALID_HANDLE, INVALID_HANDLE};
bool            g_divReady[3];
datetime        g_divLastClosed[3];
uint            g_divLastTry[3];
DivPivot        g_divHighs[72];      // [اسلات*24 + k]؛ k=0 جدیدترین
DivPivot        g_divLows[72];
int             g_divHighCnt[3];
int             g_divLowCnt[3];
datetime        g_divCreated[12];    // [اسلات*4 + نوع]: زمان کندل ایجاد (۰ = فعال نیست)
double          g_divLevel[12];      // کف/سقف دوم؛ شکستنش واگرایی را باطل می‌کند
bool            g_divReplaying = false;

bool Div_ValidNum(const double v)
{
   return (MathIsValidNumber(v) && MathAbs(v) < 1.0e10);
}

string Div_TFName(const ENUM_TIMEFRAMES tf)
{
   string s = EnumToString(tf);
   if(StringFind(s, "PERIOD_") == 0) s = StringSubstr(s, 7);
   return s;
}

string Div_TypeName(const int t)
{
   switch(t)
   {
      case 0: return "معمولی صعودی";
      case 1: return "معمولی نزولی";
      case 2: return "پنهان صعودی";
      case 3: return "پنهان نزولی";
   }
   return "";
}

void Div_ResetSlot(const int slot)
{
   g_divHighCnt[slot] = 0;
   g_divLowCnt[slot]  = 0;
   g_divLastClosed[slot] = 0;
   for(int t = 0; t < DIV_TYPES; t++)
   {
      g_divCreated[slot * DIV_TYPES + t] = 0;
      g_divLevel[slot * DIV_TYPES + t]   = 0.0;
   }
}

// پیدا کردن اندیسِ (شیفت) یک زمان در آرایه‌ی زمان‌ها؛ -1 اگر نبود
int Div_FindIndex(const datetime &tm[], const int from, const int to, const datetime t)
{
   for(int i = from; i <= to; i++)
      if(tm[i] == t) return i;
   return -1;
}

// مقدار خطِ وصل‌کنندهٔ دو نقطه (iNew جدیدتر، iOld قدیمی‌تر) در اندیس k
double Div_LineAt(const int k, const int iNew, const double vNew, const int iOld, const double vOld)
{
   if(iOld == iNew) return vNew;
   return vOld + (vNew - vOld) * (double)(iOld - k) / (double)(iOld - iNew);
}

void Div_PushPivot(const int slot, const bool isHigh, const DivPivot &p)
{
   const int base = slot * DIV_MAX_STORED;
   int cnt = isHigh ? g_divHighCnt[slot] : g_divLowCnt[slot];
   const int n = MathMin(cnt, DIV_MAX_STORED - 1);
   for(int k = n; k > 0; k--)
   {
      if(isHigh) g_divHighs[base + k] = g_divHighs[base + k - 1];
      else       g_divLows[base + k]  = g_divLows[base + k - 1];
   }
   if(isHigh) g_divHighs[base] = p; else g_divLows[base] = p;
   cnt = n + 1;
   if(isHigh) g_divHighCnt[slot] = cnt; else g_divLowCnt[slot] = cnt;
}

void Div_DrawLine(const int slot, const int type, const datetime t1, const double p1, const datetime t2, const double p2)
{
   const bool bull   = (type == 0 || type == 2);
   const bool hidden = (type >= 2);
   string name = DIV_PREFIX + Div_TFName(g_divTF[slot]) + "_" + IntegerToString(type) + "_" + IntegerToString((long)t2);
   if(ObjectFind(0, name) >= 0) return;
   if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2))
   {
      ErrorLog("ساخت خط واگرایی شکست خورد: " + IntegerToString(GetLastError()));
      return;
   }
   color clr;
   if(slot == 0) clr = bull ? clrLimeGreen : clrOrangeRed;
   else          clr = bull ? clrDodgerBlue : clrMagenta;
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, hidden ? STYLE_DOT : STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, hidden ? 1 : (slot == 0 ? 2 : 3));
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, "واگرایی " + Div_TypeName(type) + " (" + Div_TFName(g_divTF[slot]) + ")");
}

// خود مکدی بین دو قله/دره از خطِ وصل‌کنندهٔ آن‌ها عبور نکرده باشد
bool Div_MacdLineClean(const bool isHigh, const int p, const double vNew, const int jp, const double vOld, const double &macd[])
{
   for(int k = p + 1; k < jp; k++)
   {
      if(!Div_ValidNum(macd[k])) return false;
      const double lv = Div_LineAt(k, p, vNew, jp, vOld);
      if(isHigh  && macd[k] > lv) return false;
      if(!isHigh && macd[k] < lv) return false;
   }
   return true;
}

// از کندل بعد از نقطهٔ دوم تا کندل ایجاد، قیمت از نقطهٔ دوم عبور نکرده باشد
bool Div_NotBrokenSinceAnchor(const bool isHigh, const int idx, const int cs, const double level, const double &hi[], const double &lo[])
{
   for(int i = idx - 1; i >= cs; i--)
   {
      if(isHigh  && hi[i] > level) return false;
      if(!isHigh && lo[i] < level) return false;
   }
   return true;
}

void Div_Create(const int slot, const int type, const int cs, const datetime &tm[], const DivPivot &pr, const DivPivot &cur)
{
   g_divCreated[slot * DIV_TYPES + type] = tm[cs];
   g_divLevel[slot * DIV_TYPES + type]   = cur.anchorPrice;
   Div_DrawLine(slot, type, pr.anchorTime, pr.anchorPrice, cur.anchorTime, cur.anchorPrice);
   if(!g_divReplaying)
      FilterLog(StringFormat("واگرایی %s ایجاد شد (%s): MACD %.6f→%.6f | قیمت %.5f→%.5f",
                Div_TypeName(type), Div_TFName(g_divTF[slot]), pr.macdValue, cur.macdValue, pr.anchorPrice, cur.anchorPrice));
}

// قله (isHigh) یا دره‌ی تأییدشده‌ی مکدی در شیفت p
void Div_HandlePivot(const int slot, const bool isHigh, const int cs, const int p, const int total, const double mp,
                     const double &macd[], const double &hi[], const double &lo[], const datetime &tm[])
{
   // کندل متناظر روی قیمت (فقط کندل‌های بسته)
   const int iNew = MathMax(cs, p - g_divW);
   const int iOld = MathMin(total - 1, p + g_divW);
   int idx = p;
   if(isHigh)
   {
      double bestH = hi[idx];
      for(int i = iOld; i >= iNew; i--)
         if(hi[i] >= bestH) { bestH = hi[i]; idx = i; }
   }
   else
   {
      double bestL = lo[idx];
      for(int i = iOld; i >= iNew; i--)
         if(lo[i] <= bestL) { bestL = lo[i]; idx = i; }
   }

   DivPivot cur;
   cur.valid = true;
   cur.macdTime = tm[p];
   cur.macdValue = mp;
   cur.anchorTime = tm[idx];
   cur.anchorPrice = isHigh ? hi[idx] : lo[idx];

   const int base = slot * DIV_MAX_STORED;
   const int cnt  = isHigh ? g_divHighCnt[slot] : g_divLowCnt[slot];
   const int searchTo  = MathMin(total - 1, p + g_divMaxD + g_divW + 1);
   const int anchorTo  = MathMin(total - 1, p + g_divMaxD + 2 * g_divW + 2);

   // ── واگرایی معمولی: نزدیک‌ترین قله/دره‌ی مهم‌ترِ قبلی (MACD قوی‌تر) ──
   for(int q = 0; q < cnt; q++)
   {
      DivPivot pr;
      if(isHigh) pr = g_divHighs[base + q]; else pr = g_divLows[base + q];
      const int jp = Div_FindIndex(tm, p + 1, searchTo, pr.macdTime);
      if(jp < 0) break;
      const int dist = jp - p;
      if(dist > g_divMaxD) break;
      if(dist < g_divMinD) continue;
      const bool stronger = isHigh ? (pr.macdValue > cur.macdValue) : (pr.macdValue < cur.macdValue);
      if(!stronger) continue;

      const bool priceDiverges = isHigh ? (cur.anchorPrice > pr.anchorPrice) : (cur.anchorPrice < pr.anchorPrice);
      if(priceDiverges)
      {
         const int ja = Div_FindIndex(tm, idx + 1, anchorTo, pr.anchorTime);
         if(ja > 0)
         {
            bool clean = true;     // بین دو نقطه، قیمت از نقطه‌ی جدید فراتر نرفته باشد
            for(int i = idx + 1; i < ja; i++)
            {
               if(isHigh) { if(hi[i] > cur.anchorPrice) { clean = false; break; } }
               else       { if(lo[i] < cur.anchorPrice) { clean = false; break; } }
            }
            if(clean && Div_MacdLineClean(isHigh, p, cur.macdValue, jp, pr.macdValue, macd)
                     && Div_NotBrokenSinceAnchor(isHigh, idx, cs, cur.anchorPrice, hi, lo))
               Div_Create(slot, isHigh ? 1 : 0, cs, tm, pr, cur);
         }
      }
      break;
   }

   // ── واگرایی پنهان: نزدیک‌ترین قله/دره‌ی قبلی؛ قیمت ضعیف‌تر و MACD قوی‌تر ──
   if(EnableHiddenDivergence)
   {
      for(int q = 0; q < cnt; q++)
      {
         DivPivot pr;
         if(isHigh) pr = g_divHighs[base + q]; else pr = g_divLows[base + q];
         const int jp = Div_FindIndex(tm, p + 1, searchTo, pr.macdTime);
         if(jp < 0) break;
         const int dist = jp - p;
         if(dist > g_divMaxD) break;
         if(dist < g_divMinD) continue;

         // نزولی پنهان: سقف قیمت پایین‌تر + قله‌ی MACD بالاتر ؛ صعودی پنهان: کف قیمت بالاتر + دره‌ی MACD پایین‌تر
         const bool hiddenOK = isHigh ? (cur.anchorPrice < pr.anchorPrice && cur.macdValue > pr.macdValue)
                                      : (cur.anchorPrice > pr.anchorPrice && cur.macdValue < pr.macdValue);
         if(hiddenOK)
         {
            const int ja = Div_FindIndex(tm, idx + 1, anchorTo, pr.anchorTime);
            if(ja > 0)
            {
               bool clean = true;   // قیمت بین دو نقطه از خط وصل‌کننده‌شان عبور نکرده باشد
               for(int i = idx + 1; i < ja; i++)
               {
                  const double lv = Div_LineAt(i, idx, cur.anchorPrice, ja, pr.anchorPrice);
                  if(isHigh) { if(hi[i] > lv) { clean = false; break; } }
                  else       { if(lo[i] < lv) { clean = false; break; } }
               }
               if(clean && Div_MacdLineClean(isHigh, p, cur.macdValue, jp, pr.macdValue, macd)
                        && Div_NotBrokenSinceAnchor(isHigh, idx, cs, cur.anchorPrice, hi, lo))
                  Div_Create(slot, isHigh ? 3 : 2, cs, tm, pr, cur);
            }
         }
         break;   // فقط نزدیک‌ترین قله/دره‌ی قبلی
      }
   }

   Div_PushPivot(slot, isHigh, cur);
}

// پردازش یک کندلِ تازه‌بسته (cs = شیفت سری آن). فقط کندل‌های با شیفت >= cs خوانده می‌شوند.
void Div_ProcessClosed(const int slot, const int cs, const int total, const double &macd[], const double &hi[], const double &lo[], const datetime &tm[])
{
   // ۱) باطل شدن: شکستن کف/سقف دوم در این کندل بسته
   for(int t = 0; t < DIV_TYPES; t++)
   {
      const int k = slot * DIV_TYPES + t;
      if(g_divCreated[k] == 0 || tm[cs] <= g_divCreated[k]) continue;
      const bool bull = (t == 0 || t == 2);
      if((bull && lo[cs] < g_divLevel[k]) || (!bull && hi[cs] > g_divLevel[k]))
      {
         g_divCreated[k] = 0;
         if(!g_divReplaying)
            FilterLog("واگرایی " + Div_TypeName(t) + " (" + Div_TFName(g_divTF[slot]) + ") با شکستن " + (bull ? "کف" : "سقف") + " دوم باطل شد");
      }
   }

   // ۲) قله/دره‌ی تازه‌تأییدشده‌ی مکدی
   const int S = g_divS;
   const int p = cs + S;
   if(p + S > total - 1) return;
   const double mp = macd[p];
   if(!Div_ValidNum(mp)) return;

   bool isHigh = true, isLow = true;
   for(int k = 1; k <= S; k++)
   {
      const double older = macd[p + k];
      const double newer = macd[p - k];
      if(!Div_ValidNum(older) || !Div_ValidNum(newer)) return;
      if(!(mp > older && mp >= newer)) isHigh = false;
      if(!(mp < older && mp <= newer)) isLow  = false;
   }
   if(!isHigh && !isLow) return;
   Div_HandlePivot(slot, isHigh, cs, p, total, mp, macd, hi, lo, tm);
}

// کپی داده‌ی یک تایم‌فریم و پردازش کندل‌های بسته از شیفت top تا ۱
bool Div_Run(const int slot, const int top)
{
   const ENUM_TIMEFRAMES tf = g_divTF[slot];
   const int need = top + 2 * g_divS + g_divMaxD + 2 * g_divW + 10;

   if(g_divHandle[slot] == INVALID_HANDLE) return false;
   if(Bars(_Symbol, tf) < need + g_divSlow + g_divSig) return false;
   if(BarsCalculated(g_divHandle[slot]) < need) return false;

   double   macd[], sig[], hi[], lo[];
   datetime tm[];
   ArraySetAsSeries(macd, true);
   ArraySetAsSeries(sig, true);
   ArraySetAsSeries(hi, true);
   ArraySetAsSeries(lo, true);
   ArraySetAsSeries(tm, true);

   if(CopyBuffer(g_divHandle[slot], 0, 0, need, macd) != need) return false;
   if(DivMACD_Source == DIV_SRC_HISTOGRAM)
   {
      if(CopyBuffer(g_divHandle[slot], 1, 0, need, sig) != need) return false;
      for(int i = 0; i < need; i++)
         macd[i] = (Div_ValidNum(macd[i]) && Div_ValidNum(sig[i])) ? (macd[i] - sig[i]) : EMPTY_VALUE;
   }
   if(CopyHigh(_Symbol, tf, 0, need, hi) != need) return false;
   if(CopyLow(_Symbol, tf, 0, need, lo) != need) return false;
   if(CopyTime(_Symbol, tf, 0, need, tm) != need) return false;

   g_divReplaying = (top > 3);
   for(int cs = top; cs >= 1; cs--)
      Div_ProcessClosed(slot, cs, need, macd, hi, lo, tm);
   g_divReplaying = false;

   g_divLastClosed[slot] = tm[1];
   return true;
}

// بازسازی کامل یک تایم‌فریم از تاریخچه
bool Div_Rebuild(const int slot)
{
   g_divReady[slot] = false;
   ObjectsDeleteAll(0, DIV_PREFIX + Div_TFName(g_divTF[slot]) + "_");
   Div_ResetSlot(slot);
   if(!Div_Run(slot, DIV_HISTORY_BARS)) return false;
   g_divReady[slot] = true;
   return true;
}

void Div_Deinit()
{
   for(int s = 0; s < DIV_MAX_SLOTS; s++)
   {
      if(g_divHandle[s] != INVALID_HANDLE) IndicatorRelease(g_divHandle[s]);
      g_divHandle[s] = INVALID_HANDLE;
      g_divReady[s]  = false;
      g_divLastTry[s] = 0;
      Div_ResetSlot(s);
   }
   g_divSlotCount = 0;
   ObjectsDeleteAll(0, DIV_PREFIX);
}

void Div_AddSlot(const ENUM_TIMEFRAMES tf)
{
   for(int s = 0; s < g_divSlotCount; s++)
      if(g_divTF[s] == tf) return;          // اگر تایم جاری خودش M5/M15 است، یک بار حساب شود
   if(g_divSlotCount >= DIV_MAX_SLOTS) return;
   g_divTF[g_divSlotCount] = tf;
   g_divSlotCount++;
}

void Div_Init()
{
   Div_Deinit();
   if(!EnableDivergenceFilter) return;

   g_divFast = MathMax(1, DivMACD_FastEMA);
   g_divSlow = MathMax(1, DivMACD_SlowEMA);
   g_divSig  = MathMax(1, DivMACD_SignalSMA);
   if(g_divFast >= g_divSlow)
      SystemLog("هشدار فیلتر واگرایی: دورهٔ EMA سریع باید کوچک‌تر از EMA کند باشد (سریع=" + IntegerToString(g_divFast) + "، کند=" + IntegerToString(g_divSlow) + ")");
   g_divS    = MathMin(10, MathMax(1, DivSwingBars));
   g_divMinD = MathMax(2, DivMinPivotDist);
   g_divMaxD = MathMin(200, MathMax(g_divMinD + 1, DivMaxPivotDist));
   g_divW    = MathMin(DIV_PRICE_WINDOW, g_divS);

   Div_AddSlot((ENUM_TIMEFRAMES)_Period);
   if(DivUseHigherTF)
   {
      Div_AddSlot(PERIOD_M5);
      Div_AddSlot(PERIOD_M15);
   }

   string names = "";
   for(int s = 0; s < g_divSlotCount; s++)
   {
      g_divHandle[s] = iMACD(_Symbol, g_divTF[s], g_divFast, g_divSlow, g_divSig, DivMACD_AppliedPrice);
      if(g_divHandle[s] == INVALID_HANDLE)
      {
         ErrorLog("ساخت MACD برای فیلتر واگرایی شکست خورد (" + Div_TFName(g_divTF[s]) + "): " + IntegerToString(GetLastError()));
         continue;
      }
      Div_Rebuild(s);
      names += (names == "" ? "" : "، ") + Div_TFName(g_divTF[s]) + (g_divReady[s] ? "" : " (منتظر داده)");
   }
   SystemLog("فیلتر واگرایی: MACD " + IntegerToString(g_divFast) + "," + IntegerToString(g_divSlow) + "," + IntegerToString(g_divSig)
             + (DivMACD_Source == DIV_SRC_HISTOGRAM ? " (هیستوگرام)" : " (خط اصلی)")
             + (EnableHiddenDivergence ? " + پنهان" : "") + " | تایم‌ها: " + names);
}

// هر تیک صدا زده می‌شود: کندل‌های تازه‌بستهٔ هر تایم‌فریم را به ترتیب پردازش می‌کند
void Div_OnTick()
{
   if(!EnableDivergenceFilter) return;
   for(int s = 0; s < g_divSlotCount; s++)
   {
      if(g_divHandle[s] == INVALID_HANDLE) continue;
      if(!g_divReady[s])
      {
         const uint nowMs = GetTickCount();
         if(nowMs - g_divLastTry[s] > 3000) { g_divLastTry[s] = nowMs; Div_Rebuild(s); }
         continue;
      }
      const datetime t1 = iTime(_Symbol, g_divTF[s], 1);
      if(t1 == 0 || t1 == g_divLastClosed[s]) continue;
      const int sh = iBarShift(_Symbol, g_divTF[s], g_divLastClosed[s], false);
      if(sh < 0 || sh > DIV_HISTORY_BARS) { Div_Rebuild(s); continue; }
      Div_Run(s, (sh > 1) ? (sh - 1) : 1);
   }
}

// سنِ واگرایی (کندل ایجاد = ۱) در تایم‌فریم خودش؛ -1 اگر فعال نیست. شکستن در کندل جاری هم باطلش می‌کند.
int Div_Age(const int slot, const int type)
{
   const int k = slot * DIV_TYPES + type;
   const datetime created = g_divCreated[k];
   if(created == 0) return -1;
   const ENUM_TIMEFRAMES tf = g_divTF[slot];
   const int age = iBarShift(_Symbol, tf, created, false);
   if(age < 0 || age > MathMax(1, DivergenceValidBars)) return -1;
   const bool bull = (type == 0 || type == 2);
   const double curLo = iLow(_Symbol, tf, 0), curHi = iHigh(_Symbol, tf, 0);
   if((bull && curLo > 0 && curLo < g_divLevel[k]) || (!bull && curHi > 0 && curHi > g_divLevel[k]))
   {
      g_divCreated[k] = 0;   // شکستن کف/سقف دوم در کندل جاری
      return -1;
   }
   return age;
}

bool Div_SlotHasDirection(const int slot, const bool bull)
{
   if(!g_divReady[slot]) return false;
   if(Div_Age(slot, bull ? 0 : 1) >= 0) return true;
   if(EnableHiddenDivergence && Div_Age(slot, bull ? 2 : 3) >= 0) return true;
   return false;
}

int Div_SlotCount() { return g_divSlotCount; }

// متن وضعیت یک تایم‌فریم برای پنل روی چارت
string Div_SlotStatus(const int slot, color &clr)
{
   const string tfn = Div_TFName(g_divTF[slot]);
   if(!g_divReady[slot]) { clr = clrOrange; return "واگرایی " + tfn + ": داده‌ی مکدی هنوز آماده نیست"; }
   const int vb = MathMax(1, DivergenceValidBars);
   string sBull = "ندارد", sBear = "ندارد";
   const int r0 = Div_Age(slot, 0), r1 = Div_Age(slot, 1);
   const int h2 = EnableHiddenDivergence ? Div_Age(slot, 2) : -1;
   const int h3 = EnableHiddenDivergence ? Div_Age(slot, 3) : -1;
   if(r0 >= 0)      sBull = StringFormat("معمولی %d/%d", r0, vb);
   else if(h2 >= 0) sBull = StringFormat("پنهان %d/%d", h2, vb);
   if(r1 >= 0)      sBear = StringFormat("معمولی %d/%d", r1, vb);
   else if(h3 >= 0) sBear = StringFormat("پنهان %d/%d", h3, vb);
   clr = (r0 >= 0 || r1 >= 0 || h2 >= 0 || h3 >= 0) ? clrLimeGreen : clrSilver;
   return "واگرایی " + tfn + ": صعودی " + sBull + " | نزولی " + sBear;
}

bool Check_DivergenceFilter(int signal, string &rejectionReason)
{
   if(!EnableDivergenceFilter) return true;
   if(signal == 0) return true;

   int readyCount = 0;
   for(int s = 0; s < g_divSlotCount; s++)
   {
      if(!g_divReady[s] && g_divHandle[s] != INVALID_HANDLE)
      {
         const uint nowMs = GetTickCount();
         if(nowMs - g_divLastTry[s] > 3000) { g_divLastTry[s] = nowMs; Div_Rebuild(s); }
      }
      if(g_divReady[s]) readyCount++;
   }
   if(readyCount == 0)
   {
      rejectionReason = "Divergence: MACD data not ready";
      return false;
   }

   const bool isBuy = (signal > 0);
   string tfs = "";
   for(int s = 0; s < g_divSlotCount; s++)
   {
      if(Div_SlotHasDirection(s, isBuy)) return true;
      tfs += (tfs == "" ? "" : "/") + Div_TFName(g_divTF[s]);
   }
   rejectionReason = StringFormat("Divergence: no active %s divergence for %s (%s, valid %d bars)",
                                  isBuy ? "bullish" : "bearish", isBuy ? "BUY" : "SELL", tfs, MathMax(1, DivergenceValidBars));
   return false;
}

//+------------------------------------------------------------------+
//| Check Other Filters (Enhanced)                                   |
//+------------------------------------------------------------------+

// v171: وضعیت سیستم باکسی که همین الان در حال بررسی/معامله است
bool   g_boxCtxActive = false;
string g_boxCtxTag    = "";
double g_boxCtxTP     = 0.0;
bool   g_lastExecOK   = false;

// فیلتر «پوزیشن باز»: در حالت باکس هر سیستم فقط پوزیشن‌های خودش را می‌بیند
bool Box_HasOpenPositionCtx() {
   return HasOpenPosition();   // ONETRADE v177.0: یک معامله برای هر نماد؛ معاملهٔ هر باکس دیگر جدا حساب نمی‌شود
}

bool CheckOtherFiltersEnhanced(int signal = 0) {
    RefreshDirectionSettings();
  
    string stochReason1 = "", stochReason2 = "", alphaCloudReason = "", divReason = "";
    string checkNames[] = {
        "Session Time",
        "Symbol/Integrated Filter",
        "Spread Too High",
        "ATR Filter",
        "Position Already Open",
        "News Filter",
        "Stochastic 1 Confirmation",
        "Stochastic 2 Confirmation",
        "Direction Sign Mismatch",
        "Alpha Cloud Filter",
        "Divergence Filter"
    };

    bool directionSignOK = (signal == 0) ||
                            (signal > 0 && g_direction_avg >= 0) ||
                            (signal < 0 && g_direction_avg <= 0);
    bool checks[] = {
        IsSessionTimeAllowed(),
        CheckIntegratedFilters(),
        CheckSpread(),
        (!EnableATRFilter || ATRAllowedToTrade()),
        !Box_HasOpenPositionCtx(),
        (!EnableNewsFilter || !IsNewsTimeBlocked()),
        Check_Stochastic1Confirmation(signal, stochReason1),
        Check_Stochastic2Confirmation(signal, stochReason2),
        directionSignOK,
        Check_AlphaCloudFilter(signal, alphaCloudReason),   // v154
        Check_DivergenceFilter(signal, divReason)          // DIVFILTER
    };
    
    bool allPassed = true;
    for(int i = 0; i < ArraySize(checks); i++) {
        if(!checks[i]) {
           
            if(i == 1) { allPassed = false; continue; }

            if(i == 6 && stochReason1 != "") lastTradeFailureReason = stochReason1;
            else if(i == 7 && stochReason2 != "") lastTradeFailureReason = stochReason2;
            else if(i == 8) lastTradeFailureReason = StringFormat("Direction Sign Mismatch: signal=%d but g_direction_avg=%.2f", signal, g_direction_avg);
            else if(i == 9 && alphaCloudReason != "") lastTradeFailureReason = alphaCloudReason;   // v154
            else if(i == 10 && divReason != "") lastTradeFailureReason = divReason;   // DIVFILTER
            else lastTradeFailureReason = checkNames[i] + " blocked the signal";
            AddBlockReason(checkNames[i]);
            allPassed = false;
        }
    }
 
    return allPassed;
}
//+------------------------------------------------------------------+
//| Button Management Functions                                      |
//+------------------------------------------------------------------+
void CreateCloseAllButton() {
   if(ObjectFind(0, "CloseAllBtn") < 0) {
      if(!ObjectCreate(0, "CloseAllBtn", OBJ_BUTTON, 0, 0, 0)) {
         ErrorLog("ساخت دکمهٔ بستن‌همه شکست خورد: " + IntegerToString(GetLastError()));
         return;  }
              
      ObjectSetInteger(0, "CloseAllBtn", OBJPROP_XDISTANCE, CloseButton_X);
      ObjectSetInteger(0, "CloseAllBtn", OBJPROP_YDISTANCE, CloseButton_Y);
      ObjectSetInteger(0, "CloseAllBtn", OBJPROP_XSIZE, 80);
      ObjectSetInteger(0, "CloseAllBtn", OBJPROP_YSIZE, 25);
      ObjectSetInteger(0, "CloseAllBtn", OBJPROP_BGCOLOR, CloseButton_Color);
      ObjectSetInteger(0, "CloseAllBtn", OBJPROP_COLOR, clrWhite);
      ObjectSetString(0, "CloseAllBtn", OBJPROP_TEXT, "CLOSE ALL");
      ObjectSetInteger(0, "CloseAllBtn", OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, "CloseAllBtn", OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, "CloseAllBtn", OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, "CloseAllBtn", OBJPROP_SELECTED, false);   }}
   
void CreateAutoTradeButton() {
   string buttonName = "AutoTradeBtn";
   if(ObjectFind(0, buttonName) < 0) {
      if(!ObjectCreate(0, buttonName, OBJ_BUTTON, 0, 0, 0)) {
         ErrorLog("ساخت دکمهٔ معاملهٔ خودکار شکست خورد: " + IntegerToString(GetLastError()));
         return;  }
            
      ObjectSetInteger(0, buttonName, OBJPROP_XDISTANCE, CloseButton_X + 85);
      ObjectSetInteger(0, buttonName, OBJPROP_YDISTANCE, CloseButton_Y + 30);
      ObjectSetInteger(0, buttonName, OBJPROP_XSIZE, 80);
      ObjectSetInteger(0, buttonName, OBJPROP_YSIZE, 25);
      
      color btnColor = autoTradingActive ? AutoTradeButton_Color_On : AutoTradeButton_Color_Off;
      ObjectSetInteger(0, buttonName, OBJPROP_BGCOLOR, btnColor);
      ObjectSetInteger(0, buttonName, OBJPROP_COLOR, clrWhite);
      
      string buttonText = autoTradingActive ? "AUTO: ON" : "AUTO: OFF";
      ObjectSetString(0, buttonName, OBJPROP_TEXT, buttonText);
      ObjectSetInteger(0, buttonName, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, buttonName, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, buttonName, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, buttonName, OBJPROP_SELECTED, false);   }}
   
void UpdateAutoTradeButton() {
   string buttonName = "AutoTradeBtn";
   if(ObjectFind(0, buttonName) >= 0) {
      color btnColor = autoTradingActive ? AutoTradeButton_Color_On : AutoTradeButton_Color_Off;
      string buttonText = autoTradingActive ? "AUTO: ON" : "AUTO: OFF";
      
      ObjectSetInteger(0, buttonName, OBJPROP_BGCOLOR, btnColor);
      ObjectSetString(0, buttonName, OBJPROP_TEXT, buttonText);   }}
   
void CreatePauseManagementButton() {
   string buttonName = "PauseManagementBtn";
   if(ObjectFind(0, buttonName) < 0) {
      if(!ObjectCreate(0, buttonName, OBJ_BUTTON, 0, 0, 0)) {
         ErrorLog("ساخت دکمهٔ توقف مدیریت شکست خورد: " + IntegerToString(GetLastError()));
         return;   }
           
      ObjectSetInteger(0, buttonName, OBJPROP_XDISTANCE, CloseButton_X + 85);
      ObjectSetInteger(0, buttonName, OBJPROP_YDISTANCE, CloseButton_Y);
      ObjectSetInteger(0, buttonName, OBJPROP_XSIZE, 80);
      ObjectSetInteger(0, buttonName, OBJPROP_YSIZE, 25);
      
      color btnColor = managementPaused ? PauseButtonColor_Paused : PauseButtonColor_Active;
      ObjectSetInteger(0, buttonName, OBJPROP_BGCOLOR, btnColor);
      ObjectSetInteger(0, buttonName, OBJPROP_COLOR, clrWhite);
      
      string buttonText = managementPaused ? "MGMT: OFF" : "MGMT: ON";
      ObjectSetString(0, buttonName, OBJPROP_TEXT, buttonText);
      ObjectSetInteger(0, buttonName, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, buttonName, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, buttonName, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, buttonName, OBJPROP_SELECTED, false);  }}

void UpdatePauseManagementButton() {
   string buttonName = "PauseManagementBtn";
   if(ObjectFind(0, buttonName) >= 0) {
      color btnColor = managementPaused ? PauseButtonColor_Paused : PauseButtonColor_Active;
      string buttonText = managementPaused ? "MGMT: OFF" : "MGMT: ON";
      
      ObjectSetInteger(0, buttonName, OBJPROP_BGCOLOR, btnColor);
      ObjectSetString(0, buttonName, OBJPROP_TEXT, buttonText);   }}

void CreateFibButton() {
   string buttonName = "FibBtn";
   if(ObjectFind(0, buttonName) < 0) {
      if(!ObjectCreate(0, buttonName, OBJ_BUTTON, 0, 0, 0)) {
         ErrorLog("ساخت دکمهٔ فیبوناچی شکست خورد: " + IntegerToString(GetLastError()));
         return;   }

      ObjectSetInteger(0, buttonName, OBJPROP_XDISTANCE, CloseButton_X);
      ObjectSetInteger(0, buttonName, OBJPROP_YDISTANCE, CloseButton_Y + 30);
      ObjectSetInteger(0, buttonName, OBJPROP_XSIZE, 80);
      ObjectSetInteger(0, buttonName, OBJPROP_YSIZE, 25);

      color btnColor = g_lgShowFib ? AutoTradeButton_Color_On : AutoTradeButton_Color_Off;
      ObjectSetInteger(0, buttonName, OBJPROP_BGCOLOR, btnColor);
      ObjectSetInteger(0, buttonName, OBJPROP_COLOR, clrWhite);
      ObjectSetString(0, buttonName, OBJPROP_TEXT, g_lgShowFib ? "FIB: ON" : "FIB: OFF");
      ObjectSetInteger(0, buttonName, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, buttonName, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, buttonName, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, buttonName, OBJPROP_SELECTED, false);  }}

void UpdateFibButton() {
   string buttonName = "FibBtn";
   if(ObjectFind(0, buttonName) >= 0) {
      color btnColor = g_lgShowFib ? AutoTradeButton_Color_On : AutoTradeButton_Color_Off;
      ObjectSetInteger(0, buttonName, OBJPROP_BGCOLOR, btnColor);
      ObjectSetString(0, buttonName, OBJPROP_TEXT, g_lgShowFib ? "FIB: ON" : "FIB: OFF");   }}

void CreateDispFibButton() {   // DISPLAY FIB v178.2
   string buttonName = "DispFibBtn";
   if(ObjectFind(0, buttonName) < 0) {
      if(!ObjectCreate(0, buttonName, OBJ_BUTTON, 0, 0, 0)) {
         ErrorLog("ساخت دکمهٔ فیبو نمایش شکست خورد: " + IntegerToString(GetLastError()));
         return;   }

      ObjectSetInteger(0, buttonName, OBJPROP_XDISTANCE, CloseButton_X + 170);
      ObjectSetInteger(0, buttonName, OBJPROP_YDISTANCE, CloseButton_Y);
      ObjectSetInteger(0, buttonName, OBJPROP_XSIZE, 90);
      ObjectSetInteger(0, buttonName, OBJPROP_YSIZE, 25);

      color btnColor = g_dfShow ? AutoTradeButton_Color_On : AutoTradeButton_Color_Off;
      ObjectSetInteger(0, buttonName, OBJPROP_BGCOLOR, btnColor);
      ObjectSetInteger(0, buttonName, OBJPROP_COLOR, clrWhite);
      ObjectSetString(0, buttonName, OBJPROP_TEXT, g_dfShow ? "FIB2: SHOW" : "FIB2: HIDE");
      ObjectSetInteger(0, buttonName, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, buttonName, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, buttonName, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, buttonName, OBJPROP_SELECTED, false);  }}

void UpdateDispFibButton() {
   string buttonName = "DispFibBtn";
   if(ObjectFind(0, buttonName) >= 0) {
      color btnColor = g_dfShow ? AutoTradeButton_Color_On : AutoTradeButton_Color_Off;
      ObjectSetInteger(0, buttonName, OBJPROP_BGCOLOR, btnColor);
      ObjectSetString(0, buttonName, OBJPROP_TEXT, g_dfShow ? "FIB2: SHOW" : "FIB2: HIDE");   }}

void DeleteAllButtons() {
   string buttonNames[] = {"CloseAllBtn", "AutoTradeBtn", "PauseManagementBtn", "FibBtn", "DispFibBtn"};
   for(int i = 0; i < ArraySize(buttonNames); i++) {
      if(ObjectFind(0, buttonNames[i]) >= 0) {
         ObjectDelete(0, buttonNames[i]);  }}   ButtonLog("All buttons deleted");  }
//+------------------------------------------------------------------+
//| Save Button States                                               |
//+------------------------------------------------------------------+
void SaveButtonStates() {
   string stateKey = "EA_State_" + _Symbol + "_" + string(_Period);
   GlobalVariableSet(stateKey + "_AutoTrade", autoTradingActive);
   GlobalVariableSet(stateKey + "_ManagementPaused", managementPaused);
   GlobalVariableSet(stateKey + "_Fib", g_lgShowFib);
   SystemLog("وضعیت دکمه‌ها ذخیره شد - خودکار: " + string(autoTradingActive) + "، مدیریت: " + string(managementPaused));  }
//+------------------------------------------------------------------+
//| Get Deinit Reason Text                                           |
//+------------------------------------------------------------------+
string GetDeinitReasonText(int reason) {
   switch(reason) {
      case REASON_REMOVE:        return "EA Removed";
      case REASON_RECOMPILE:     return "Recompiled";
      case REASON_CHARTCHANGE:   return "Chart Changed";
      case REASON_CHARTCLOSE:    return "Chart Closed";
      case REASON_PARAMETERS:    return "Parameters Changed";
      case REASON_ACCOUNT:       return "Account Changed";
      case REASON_TEMPLATE:      return "Template Changed";
      case REASON_INITFAILED:    return "Init Failed";
      case REASON_CLOSE:         return "Terminal Closed";
      default:                   return "Unknown (" + string(reason) + ")";   }}

//+------------------------------------------------------------------+
//| Close All Positions Instant                                      |
//+------------------------------------------------------------------+
void CloseAllPositionsInstant() {
   int total = PositionsTotal();
   if(total <= 0) {
      ButtonLog("No positions to close");
      return;  }
      
   ButtonLog("Instant close requested for " + string(total) + " پوزیشن شکست خورد");
   
   int closedCount = 0;
   int failedCount = 0;
   double totalProfit = 0.0;
   
   trade.SetDeviationInPoints(3);
   
   ulong tickets[];
   ArrayResize(tickets, total);
   
   for(int i = 0; i < total; i++) {
      tickets[i] = PositionGetTicket(i); }
      
   for(int i = 0; i < total; i++) {
      ulong ticket = tickets[i];
      if(ticket > 0 && PositionSelectByTicket(ticket)) {
         string symbol = PositionGetString(POSITION_SYMBOL);
         long type = PositionGetInteger(POSITION_TYPE);
         
         if(symbol == _Symbol) {
            double volume = PositionGetDouble(POSITION_VOLUME);
            double profit = PositionGetDouble(POSITION_PROFIT);
            
            if(trade.PositionClose(ticket)) {
               closedCount++;
               totalProfit += profit;
            } else {
               failedCount++;
               int error = GetLastError();
               ErrorLog("بستن فوری شکست خورد: پوزیشن " + string(ticket) + "، خطا: " + string(error));
               
               trade.SetDeviationInPoints(1);
             
               if(trade.PositionClose(ticket)) {
                  closedCount++;
                  totalProfit += profit;
               } else {
                  ErrorLog("تلاش دوم هم شکست خورد: پوزیشن " + string(ticket));   }}}}}

   if(closedCount > 0) {
      string message = StringFormat("✅ INSTANT CLOSE: %d/%d positions closed | Total P/L: %.2f", 
                                   closedCount, total, totalProfit);
      if(EnableNotification) {
         SendNotification(message);  }
            
      lastPositionCloseTime = TimeCurrent();
      pauseBarsCounter = 0;
      hasManualPosition = false;
      manualPositionsCount = 0;   }
 
   if(failedCount > 0) {
      ErrorLog("بستن " + string(failedCount) + " پوزیشن شکست خورد");   }}
//+------------------------------------------------------------------+
//| Combined Loss Management Functions                               |
//+------------------------------------------------------------------+
void UpdateLossManagement(double profit) {
   if(!EnableLossManagement) return;
   
   if(profit < 0) {
      consecutiveLossCount++;
      totalLossToday += MathAbs(profit);
      lastLossTime = TimeCurrent();
      
      SystemLog(StringFormat("LOSS: Consecutive losses: %d/%d, Today's loss: %.2f", 
                            consecutiveLossCount, MaxConsecutiveLosses, totalLossToday));
      
      if(consecutiveLossCount >= MaxConsecutiveLosses) {
         tradingPauseUntil = TimeCurrent() + (TradingPauseMinutes * 60);
         SystemLog(StringFormat("🚨 TRADING PAUSED for %d minutes due to %d consecutive losses", 
                               TradingPauseMinutes, consecutiveLossCount));
         
         if(EnableNotification) {
            SendNotification(StringFormat("TRADING PAUSED: %d consecutive losses on %s", 
              consecutiveLossCount, _Symbol));   }}
  
   } else if(profit > 0 && ResetOnProfit) {
      if(consecutiveLossCount > 0) {
         consecutiveLossCount = 0;  }}}

bool IsTradingAllowedByLossManagement() {
   if(!EnableLossManagement) return true;

   static int s_lastResetDay = -1;
   MqlDateTime nowDt;
   TimeToStruct(TimeCurrent(), nowDt);
   if(nowDt.day != s_lastResetDay) {
      totalLossToday = 0.0;
      s_lastResetDay = nowDt.day;
   }
   
   if(tradingPauseUntil > TimeCurrent()) {
      int remainingSeconds = (int)(tradingPauseUntil - TimeCurrent());
      int remainingMinutes = (int)MathCeil(remainingSeconds / 60.0);
      
      return false;
   } else if(tradingPauseUntil > 0 && tradingPauseUntil <= TimeCurrent()) {
      if(DebugLogEnable) {
         SystemLog("✅ معامله بعد از دورهٔ توقف از سر گرفته شد");
      }
      tradingPauseUntil = 0;
      consecutiveLossCount = 0;   
   }   
   return true; }
//+------------------------------------------------------------------+
//| Stochastic Functions (Enhanced)                                  |
//+------------------------------------------------------------------+

void InitStochastic1() {
    if(stoch1Handle != INVALID_HANDLE) IndicatorRelease(stoch1Handle);

    ENUM_TIMEFRAMES tf = (Stochastic1Timeframe == PERIOD_CURRENT) ? _Period : Stochastic1Timeframe;
       stoch1Handle = iStochastic(_Symbol, tf, 
                              Stochastic1_K_Period,    
                              Stochastic1_D_Period,    
                              Stochastic1_Slowing,     
                              MODE_SMA,      
                              STO_LOWHIGH);  
                             
}

void InitStochastic2() {
    if(stoch2Handle != INVALID_HANDLE) IndicatorRelease(stoch2Handle);

    ENUM_TIMEFRAMES tf = (Stochastic2Timeframe == PERIOD_CURRENT) ? _Period : Stochastic2Timeframe;
    stoch2Handle = iStochastic(_Symbol, tf,
                              Stochastic2_K_Period,    
                              Stochastic2_D_Period,    
                              Stochastic2_Slowing,     
                              MODE_SMA,      
                              STO_LOWHIGH); 
}

bool IsStochastic1DataValid(int idx) {
   if(stoch1Handle == INVALID_HANDLE) {
      return false;
   }
   
   if(idx >= ArraySize(Stochastic1MainBuffer) || idx >= ArraySize(Stochastic1SignalBuffer)) {
      return false;
   }
   
   if(Stochastic1MainBuffer[idx] == EMPTY_VALUE || Stochastic1SignalBuffer[idx] == EMPTY_VALUE) {
      return false;
   }
   
   if(Stochastic1MainBuffer[idx] < 0 || Stochastic1MainBuffer[idx] > 100) {
      return false;
   }
   
   if(Stochastic1SignalBuffer[idx] < 0 || Stochastic1SignalBuffer[idx] > 100) {
      return false;
   }
   
   return true;
}

bool IsStochastic2DataValid(int idx) {
   if(stoch2Handle == INVALID_HANDLE) {
      return false;
   }
   
   if(idx >= ArraySize(Stochastic2MainBuffer) || idx >= ArraySize(Stochastic2SignalBuffer)) {
      return false;
   }
   
   if(Stochastic2MainBuffer[idx] == EMPTY_VALUE || Stochastic2SignalBuffer[idx] == EMPTY_VALUE) {
      return false;
   }
   
   if(Stochastic2MainBuffer[idx] < 0 || Stochastic2MainBuffer[idx] > 100) {
      return false;
   }
   
   if(Stochastic2SignalBuffer[idx] < 0 || Stochastic2SignalBuffer[idx] > 100) {
      return false;
   }
   
   return true;
}

int FindLastStoch1Cross(int &crossBar) {
   if(!UseStochastic1Confirmation) return 0;
   int size = MathMin(ArraySize(Stochastic1MainBuffer), ArraySize(Stochastic1SignalBuffer));
   if(size < 3) {
      return 0;
   }
        
   int barsToCheck = MathMin(StochasticCrossLookbackBars, size-1);
    
   for(int i = 1; i <= barsToCheck; i++) {
      if(!IsStochastic1DataValid(i) || !IsStochastic1DataValid(i-1)) continue;
        
      double k_previous = Stochastic1MainBuffer[i];
      double d_previous = Stochastic1SignalBuffer[i];
      double k_current = Stochastic1MainBuffer[i-1];
      double d_current = Stochastic1SignalBuffer[i-1];
        
      if(k_previous <= d_previous && k_current > d_current) { 
         crossBar = i-1;
         return 1;
      }
        
      if(k_previous >= d_previous && k_current < d_current) { 
         crossBar = i-1;
         return -1;
      }
   }
   return 0;
}

int FindLastStoch2Cross(int &crossBar) {
   if(!UseStochastic2Confirmation) return 0;
   int size = MathMin(ArraySize(Stochastic2MainBuffer), ArraySize(Stochastic2SignalBuffer));
   if(size < 3) {
      return 0;
   }
            
   int barsToCheck = MathMin(StochasticCrossLookbackBars, size-1);
    
   for(int i = 1; i <= barsToCheck; i++) {
      if(!IsStochastic2DataValid(i) || !IsStochastic2DataValid(i-1)) continue;
        
      double k_previous = Stochastic2MainBuffer[i];
      double d_previous = Stochastic2SignalBuffer[i];
      double k_current = Stochastic2MainBuffer[i-1];
      double d_current = Stochastic2SignalBuffer[i-1];
        
      if(k_previous <= d_previous && k_current > d_current) { 
         crossBar = i-1;
         return 1;
      }
        
      if(k_previous >= d_previous && k_current < d_current) { 
         crossBar = i-1;
         return -1;
      }
   }
   return 0;
}

bool IsStochastic1OutsideObOs(int signalType, int idx) {
    if(!IsStochastic1DataValid(idx)) return false;
    
    double k = Stochastic1MainBuffer[idx];
    double d = Stochastic1SignalBuffer[idx];
    
    if(signalType == 1) {
        return !(k >= Stochastic1_Overbought || d >= Stochastic1_Overbought);
    } else if(signalType == -1) {
        return !(k <= Stochastic1_Oversold || d <= Stochastic1_Oversold);
    }
    return false;
}

bool IsStochastic2OutsideObOs(int signalType, int idx) {
    if(!IsStochastic2DataValid(idx)) return false;
    
    double k = Stochastic2MainBuffer[idx];
    double d = Stochastic2SignalBuffer[idx];
    
    if(signalType == 1) {
        return !(k >= Stochastic2_Overbought || d >= Stochastic2_Overbought);
    } else if(signalType == -1) {
        return !(k <= Stochastic2_Oversold || d <= Stochastic2_Oversold);
    }
    return false;
}

void CalculateStochastic1(int barsToCopy) {
   if(!UseStochastic1Confirmation || stoch1Handle == INVALID_HANDLE) return;
   
   ENUM_TIMEFRAMES tf = (Stochastic1Timeframe == PERIOD_CURRENT) ? _Period : Stochastic1Timeframe;
   int availableBars = Bars(_Symbol, tf);
   barsToCopy = MathMin(barsToCopy, availableBars);
   if(barsToCopy <= 0) return;
   
   int currentSize = ArraySize(Stochastic1MainBuffer);
   if(barsToCopy > currentSize) {
      ArrayResize(Stochastic1MainBuffer, barsToCopy);
      ArrayResize(Stochastic1SignalBuffer, barsToCopy);
      ArraySetAsSeries(Stochastic1MainBuffer, true);
      ArraySetAsSeries(Stochastic1SignalBuffer, true);
   }
   
   if(CopyBuffer(stoch1Handle, 0, 0, barsToCopy, Stochastic1MainBuffer) <= 0) {
      return;
   }
   
   CopyBuffer(stoch1Handle, 1, 0, barsToCopy, Stochastic1SignalBuffer);
}

void CalculateStochastic2(int barsToCopy) {
   if(!UseStochastic2Confirmation || stoch2Handle == INVALID_HANDLE) return;
   
   ENUM_TIMEFRAMES tf = (Stochastic2Timeframe == PERIOD_CURRENT) ? _Period : Stochastic2Timeframe;
   int availableBars = Bars(_Symbol, tf);
   barsToCopy = MathMin(barsToCopy, availableBars);
   if(barsToCopy <= 0) return;
   
   int currentSize = ArraySize(Stochastic2MainBuffer);
   if(barsToCopy > currentSize) {
      ArrayResize(Stochastic2MainBuffer, barsToCopy);
      ArrayResize(Stochastic2SignalBuffer, barsToCopy);
      ArraySetAsSeries(Stochastic2MainBuffer, true);
      ArraySetAsSeries(Stochastic2SignalBuffer, true);
   }
   
   if(CopyBuffer(stoch2Handle, 0, 0, barsToCopy, Stochastic2MainBuffer) <= 0) {
      return;
   }
   
   CopyBuffer(stoch2Handle, 1, 0, barsToCopy, Stochastic2SignalBuffer);
}
     
void InitStochasticBuffers() {
   int barsNeeded = StochasticCrossLookbackBars + 50;
   
   if(UseStochastic1Confirmation) {
      ArrayResize(Stochastic1MainBuffer, barsNeeded);
      ArrayResize(Stochastic1SignalBuffer, barsNeeded);
      ArraySetAsSeries(Stochastic1MainBuffer, true);
      ArraySetAsSeries(Stochastic1SignalBuffer, true);
   }
   
   if(UseStochastic2Confirmation) {
      ArrayResize(Stochastic2MainBuffer, barsNeeded);
      ArrayResize(Stochastic2SignalBuffer, barsNeeded);
      ArraySetAsSeries(Stochastic2MainBuffer, true);
      ArraySetAsSeries(Stochastic2SignalBuffer, true);
   }
   
}
void CheckTimeframeChange() {
    if(currentTimeframe != _Period) {
        currentTimeframe = _Period;
        SystemLog("تایم‌فریم تغییر کرد به: " + EnumToString(_Period));
        
        if(UseStochastic1Confirmation) {
            if(stoch1Handle != INVALID_HANDLE) IndicatorRelease(stoch1Handle);
            InitStochastic1();
            CalculateStochastic1(StochasticCrossLookbackBars + 20);
            ResetStochMemory(stoch1Memory);
        }
        
        if(UseStochastic2Confirmation) {
            if(stoch2Handle != INVALID_HANDLE) IndicatorRelease(stoch2Handle);
            InitStochastic2();
            CalculateStochastic2(StochasticCrossLookbackBars + 20);
            ResetStochMemory(stoch2Memory);
        }

        Div_Init();   // DIVFILTER: بازسازی MACD و واگرایی برای تایم‌فریم جدید
    }
}
//+------------------------------------------------------------------+
//| Stochastic Memory Functions                                      |
//+------------------------------------------------------------------+
void UpdateStoch1Memory() {
   if(!UseStochastic1Confirmation) return;
   
   datetime now = TimeCurrent();

   int crossBar = -1;
   int crossType = FindLastStoch1Cross(crossBar);
   
   if(crossType != 0) {
      ENUM_TIMEFRAMES tf1 = (Stochastic1Timeframe == PERIOD_CURRENT) ? _Period : Stochastic1Timeframe;
      datetime barTime = iTime(_Symbol, tf1, crossBar);

      if(barTime != 0 && barTime != stoch1Memory.crossBarTime) {
         stoch1Memory.crossType = crossType;
         stoch1Memory.crossTime = now;
         stoch1Memory.crossBarTime = barTime;
         stoch1Memory.lastUpdate = now;
         stoch1Memory.barsPassed = 0;
         stoch1Memory.timeframe = tf1;

         if(ArraySize(Stochastic1MainBuffer) > 0 && IsStochastic1DataValid(0)) {
            stoch1Memory.currentK = Stochastic1MainBuffer[0];
            stoch1Memory.currentD = Stochastic1SignalBuffer[0];
         }

         double kAtCross = (crossBar >= 0 && crossBar < ArraySize(Stochastic1MainBuffer)) ? Stochastic1MainBuffer[crossBar] : stoch1Memory.currentK;
         double dAtCross = (crossBar >= 0 && crossBar < ArraySize(Stochastic1SignalBuffer)) ? Stochastic1SignalBuffer[crossBar] : stoch1Memory.currentD;

         if(crossType == 1) {
            bool insideOS = (kAtCross <= Stochastic1_Oversold || dAtCross <= Stochastic1_Oversold);
            stoch1Memory.signalState = insideOS ? 1 : 2;   
         } else {
            bool insideOB = (kAtCross >= Stochastic1_Overbought || dAtCross >= Stochastic1_Overbought);
            stoch1Memory.signalState = insideOB ? 3 : 4;   
         }

         if(DebugLogEnable) {
              }}}
   
   if(ArraySize(Stochastic1MainBuffer) > 0 && ArraySize(Stochastic1SignalBuffer) > 0 && IsStochastic1DataValid(0)) {
      double kNow = Stochastic1MainBuffer[0];
      double dNow = Stochastic1SignalBuffer[0];
      stoch1Memory.currentK = kNow;
      stoch1Memory.currentD = dNow;

      int prevState = stoch1Memory.signalState;
      if(prevState == 1) {
         if(kNow > Stochastic1_Oversold || dNow > Stochastic1_Oversold) stoch1Memory.signalState = 2;
      } else if(prevState == 3) {
         if(kNow < Stochastic1_Overbought || dNow < Stochastic1_Overbought) stoch1Memory.signalState = 4;
      } else if(prevState == 2) {
         if(kNow >= Stochastic1_Overbought || dNow >= Stochastic1_Overbought) stoch1Memory.signalState = 0;
      } else if(prevState == 4) {
         if(kNow <= Stochastic1_Oversold || dNow <= Stochastic1_Oversold) stoch1Memory.signalState = 0;
      }

   }
}

void UpdateStoch2Memory() {
   if(!UseStochastic2Confirmation) return;
   
   datetime now = TimeCurrent();

   int crossBar = -1;
   int crossType = FindLastStoch2Cross(crossBar);
   
   if(crossType != 0) {
      ENUM_TIMEFRAMES tf2 = (Stochastic2Timeframe == PERIOD_CURRENT) ? _Period : Stochastic2Timeframe;
      datetime barTime = iTime(_Symbol, tf2, crossBar);

         if(barTime != 0 && barTime != stoch2Memory.crossBarTime) {
         stoch2Memory.crossType = crossType;
         stoch2Memory.crossTime = now;
         stoch2Memory.crossBarTime = barTime;
         stoch2Memory.lastUpdate = now;
         stoch2Memory.barsPassed = 0;
         stoch2Memory.timeframe = tf2;

         if(ArraySize(Stochastic2MainBuffer) > 0 && IsStochastic2DataValid(0)) {
            stoch2Memory.currentK = Stochastic2MainBuffer[0];
            stoch2Memory.currentD = Stochastic2SignalBuffer[0];
         }

         double kAtCross = (crossBar >= 0 && crossBar < ArraySize(Stochastic2MainBuffer)) ? Stochastic2MainBuffer[crossBar] : stoch2Memory.currentK;
         double dAtCross = (crossBar >= 0 && crossBar < ArraySize(Stochastic2SignalBuffer)) ? Stochastic2SignalBuffer[crossBar] : stoch2Memory.currentD;

         if(crossType == 1) {
            bool insideOS = (kAtCross <= Stochastic2_Oversold || dAtCross <= Stochastic2_Oversold);
            stoch2Memory.signalState = insideOS ? 1 : 2;
         } else {
            bool insideOB = (kAtCross >= Stochastic2_Overbought || dAtCross >= Stochastic2_Overbought);
            stoch2Memory.signalState = insideOB ? 3 : 4;
         }

         if(DebugLogEnable) {
               }}}
 
   if(ArraySize(Stochastic2MainBuffer) > 0 && ArraySize(Stochastic2SignalBuffer) > 0 && IsStochastic2DataValid(0)) {
      double kNow = Stochastic2MainBuffer[0];
      double dNow = Stochastic2SignalBuffer[0];
      stoch2Memory.currentK = kNow;
      stoch2Memory.currentD = dNow;

      int prevState = stoch2Memory.signalState;
      if(prevState == 1) {
         if(kNow > Stochastic2_Oversold || dNow > Stochastic2_Oversold) stoch2Memory.signalState = 2;
      } else if(prevState == 3) {
         if(kNow < Stochastic2_Overbought || dNow < Stochastic2_Overbought) stoch2Memory.signalState = 4;
      } else if(prevState == 2) {
         if(kNow >= Stochastic2_Overbought || dNow >= Stochastic2_Overbought) stoch2Memory.signalState = 0;
      } else if(prevState == 4) {
         if(kNow <= Stochastic2_Oversold || dNow <= Stochastic2_Oversold) stoch2Memory.signalState = 0;
      }
   }}

void ResetStochMemory(StochMemory &memory) {
   memory.crossType = 0;
   memory.crossTime = 0;
   memory.crossBarTime = 0;
   memory.lastUpdate = 0;
   memory.barsPassed = 0;
   memory.currentK = 50.0;
   memory.currentD = 50.0;
   memory.signalState = 0;  
 }
bool IsStochMemoryValid(StochMemory &memory) {
   if(memory.crossType == 0) return false;
   if(TimeCurrent() - memory.crossTime > STOCH_MEMORY_SECONDS) return false;
   return true;
}

string News_ExtractField(const string &block, const string &key)
{
   string pattern = "\"" + key + "\":\"";
   int p = StringFind(block, pattern);
   if(p < 0) return "";
   p += StringLen(pattern);
   int e = StringFind(block, "\"", p);
   if(e < 0) return "";
   return StringSubstr(block, p, e - p);
}

datetime News_ParseIsoToGMT(const string &iso)
{
   if(StringLen(iso) < 19) return 0;

   string datePart = StringSubstr(iso, 0, 10);   // YYYY-MM-DD
   string timePart = StringSubstr(iso, 11, 8);   // HH:MM:SS
   datetime local = StringToTime(datePart + " " + timePart);
   if(local == 0) return 0;

   int offsetSeconds = 0;
   int signPos = -1;
   int len = StringLen(iso);
   for(int i = 19; i < len; i++) {
      ushort ch = StringGetCharacter(iso, i);
      if(ch == '+' || ch == '-') { signPos = i; break; }
   }
   if(signPos >= 0 && len >= signPos + 6) {
      int sign = (StringGetCharacter(iso, signPos) == '-') ? -1 : 1;
      int offH = (int)StringToInteger(StringSubstr(iso, signPos + 1, 2));
      int offM = (int)StringToInteger(StringSubstr(iso, signPos + 4, 2));
      offsetSeconds = sign * (offH * 3600 + offM * 60);
   }
   return local - offsetSeconds;
}

datetime News_GmtToServerTime(datetime gmt)
{
   return gmt + GetBrokerGMTOffsetSeconds();
}

bool News_IsGermanyEvent(const NewsEvent &ev)
{
   string c = ev.country; StringToUpper(c);
   if(c == "GER" || c == "DE" || c == "DEU") return true;
   string t = ev.title; StringToLower(t);
   if(c == "EUR" && StringFind(t, "german") >= 0) return true;
   return false;
}

void News_ParseJson(const string &json)
{
   ArrayResize(g_newsEvents, 0);
   int pos = 0;
   int total = StringLen(json);

   while(true) {
      int startBrace = StringFind(json, "{", pos);
      if(startBrace < 0) break;
      int endBrace = StringFind(json, "}", startBrace);
      if(endBrace < 0) break;

      string block = StringSubstr(json, startBrace, endBrace - startBrace + 1);
      pos = endBrace + 1;
      if(pos >= total) break;

      string title   = News_ExtractField(block, "title");
      string country = News_ExtractField(block, "country");
      string impact  = News_ExtractField(block, "impact");
      string dateStr = News_ExtractField(block, "date");

      if(title == "" || country == "" || dateStr == "") continue;

      datetime evGMT = News_ParseIsoToGMT(dateStr);
      if(evGMT == 0) continue;

      int n = ArraySize(g_newsEvents);
      ArrayResize(g_newsEvents, n + 1);
      g_newsEvents[n].title   = title;
      g_newsEvents[n].country = country;
      g_newsEvents[n].impact  = impact;
      g_newsEvents[n].timeGMT = evGMT;
   }

}

bool News_Fetch()
{
   if(!EnableNewsFilter) return false;

   char post[]; char result[]; string headers;
   ResetLastError();
   int res = WebRequest("GET", NewsCalendarURL, "", 5000, post, result, headers);

   if(res == -1) {
      int err = GetLastError();
      g_newsWebRequestOK = false;
      if(DebugLogEnable)
         FilterLog(StringFormat("⚠️ News WebRequest failed (Error=%d). آدرس زیر را در Tools->Options->Expert Advisors->Allow WebRequest اضافه کنید: %s", err, NewsCalendarURL));
      return false;
   }

   string json = CharArrayToString(result);
   if(StringLen(json) < 10) {
      g_newsWebRequestOK = false;
      return false;
   }

   News_ParseJson(json);
   g_lastNewsFetch    = TimeCurrent();
   g_newsWebRequestOK = true;
   return true;
}

void News_MaybeRefresh()
{
   if(!EnableNewsFilter) return;
   if(g_lastNewsFetch == 0 || (TimeCurrent() - g_lastNewsFetch) >= NewsRefreshMinutes * 60) {
      News_Fetch();
   }
}
string News_RepresentativePair(const string &countryRaw, bool isGermanyGroup)
{
   string c = countryRaw; StringToUpper(c);
   if(isGermanyGroup) return "EURCHF";
   if(c == "USD") return "USDCHF";
   if(c == "GBP") return "GBPCHF";
   if(c == "JPY") return "JPYCHF";
   if(c == "AUD") return "AUDCHF";
   return "";
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+

string NewsPro_RelevantCurrencies[] = {"USD","EUR","GBP","JPY","CHF","AUD","CAD","NZD"};

string NewsPro_ProtectedSymbols[] = {
   "EURUSD","GBPUSD","USDJPY","USDCHF","AUDUSD","USDCAD","NZDUSD","EURGBP","EURJPY","GBPJPY",
   "XAUUSD","XAGUSD","WTI","BRENT","USOIL","UKOIL"
};

string NewsPro_USD_MustBlockTitles[] = {
   "nonfarm payrolls", "non-farm payrolls", "nfp",
   "fomc rate decision", "fomc statement", "interest rate decision", "federal funds rate",
   "fomc meeting minutes", "fomc minutes",
   "cpi", "consumer price index",
   "core pce", "pce price index",
   "gdp", "gross domestic product",
   "initial jobless claims", "jobless claims",
   "powell", "fed chair",
   "retail sales",
   "ism manufacturing", "ism manufacturing pmi"
};

bool NewsPro_IsCurrentSymbolProtected()
{
   string sym = _Symbol; StringToUpper(sym);
   for(int i = 0; i < ArraySize(NewsPro_ProtectedSymbols); i++) {
      if(StringFind(sym, NewsPro_ProtectedSymbols[i]) >= 0) return true;
   }
   return false;
}

bool NewsPro_IsSymbolRelevantToCurrency(const string &currencyCode)
{
   string sym = _Symbol; StringToUpper(sym);
   string cur = currencyCode; StringToUpper(cur);

   if(cur == "USD") {
      if(StringFind(sym, "XAU")   >= 0) return true;
      if(StringFind(sym, "XAG")   >= 0) return true;
      if(StringFind(sym, "WTI")   >= 0) return true;
      if(StringFind(sym, "BRENT") >= 0) return true;
      if(StringFind(sym, "OIL")   >= 0) return true;   // USOIL / UKOIL
   }
   if(StringFind(sym, cur) >= 0) return true;

   return false;
}

bool NewsPro_IsMustBlockTitle(const string &title)
{
   string t = title; StringToLower(t);
   for(int i = 0; i < ArraySize(NewsPro_USD_MustBlockTitles); i++) {
      if(StringFind(t, NewsPro_USD_MustBlockTitles[i]) >= 0) return true;
   }
   return false;
}


bool IsNewsTimeBlocked()
{
   if(!EnableNewsFilter) return false;


   if(!NewsPro_IsCurrentSymbolProtected()) return false;

   datetime nowSrv = TimeCurrent();
   int n = ArraySize(g_newsEvents);

   for(int i = 0; i < n; i++) {
      string c = g_newsEvents[i].country; StringToUpper(c);

      bool isRelevantCurrency = false;
      for(int k = 0; k < ArraySize(NewsPro_RelevantCurrencies); k++) {
         if(c == NewsPro_RelevantCurrencies[k]) { isRelevantCurrency = true; break; }
      }
      if(!isRelevantCurrency) continue;

      if(!NewsPro_IsSymbolRelevantToCurrency(c)) continue;

      string imp = g_newsEvents[i].impact; StringToUpper(imp);
      bool isMustBlockTitle = (c == "USD" && NewsPro_IsMustBlockTitle(g_newsEvents[i].title));

      if(imp != "HIGH" && !isMustBlockTitle) continue;

      datetime evSrv      = News_GmtToServerTime(g_newsEvents[i].timeGMT);
      datetime blockStart  = evSrv - NewsBlockMinutesBefore * 60;
      datetime blockEnd    = evSrv + NewsBlockMinutesAfter  * 60;

      if(nowSrv >= blockStart && nowSrv <= blockEnd) {
         return true;
      }
   }
   return false;
}
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
void News_CreatePanelObjects()
{
   for(int i = 0; i <= 5; i++) {
      string labelName = "NewsPanel_" + IntegerToString(i);
      if(ObjectFind(0, labelName) < 0) {
         ObjectCreate(0, labelName, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, NewsPanel_X);
         ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, NewsPanel_Y + i * 16);
         ObjectSetInteger(0, labelName, OBJPROP_CORNER, CORNER_LEFT_LOWER);
         ObjectSetInteger(0, labelName, OBJPROP_COLOR, clrSilver);
         ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 9);
         ObjectSetString(0, labelName, OBJPROP_FONT, "Consolas");
         ObjectSetInteger(0, labelName, OBJPROP_BACK, false);
         ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
      }
   }
}

void News_DeletePanelObjects()
{
   for(int i = 0; i <= 5; i++)
      ObjectDelete(0, "NewsPanel_" + IntegerToString(i));
}

void News_SetPanelLine(int line, const string &text, color clr)
{
   string labelName = "NewsPanel_" + IntegerToString(line);
   if(ObjectFind(0, labelName) >= 0) {
      ObjectSetString(0, labelName, OBJPROP_TEXT, text);
      ObjectSetInteger(0, labelName, OBJPROP_COLOR, clr);
   }
}

bool News_FindNextForGroup(const string &countryCode, bool isGermanyGroup, NewsEvent &outEv)
{
   datetime nowSrv = TimeCurrent();
   datetime bestSrv = 0;
   bool found = false;
   int n = ArraySize(g_newsEvents);

   for(int i = 0; i < n; i++) {
      string imp = g_newsEvents[i].impact; StringToUpper(imp);
      if(imp != "HIGH") continue;

      bool matches = false;
      if(isGermanyGroup) {
         matches = News_IsGermanyEvent(g_newsEvents[i]);
      } else {
         string c = g_newsEvents[i].country; StringToUpper(c);
         matches = (c == countryCode);
      }
      if(!matches) continue;

      datetime evSrv = News_GmtToServerTime(g_newsEvents[i].timeGMT);
      if(evSrv < nowSrv) continue;

      if(!found || evSrv < bestSrv) {
         bestSrv = evSrv;
         outEv = g_newsEvents[i];
         found = true;
      }
   }
   return found;
}
string News_BuildLineForGroup(const string &countryCode, bool isGermanyGroup)
{
   NewsEvent ev;
   string pair = News_RepresentativePair(countryCode, isGermanyGroup);

   if(!News_FindNextForGroup(countryCode, isGermanyGroup, ev)) {
      return StringFormat("%-8s | بدون خبر مهم نزدیک", pair);
   }

   datetime evSrv = News_GmtToServerTime(ev.timeGMT);
   long secsLeft = (long)(evSrv - TimeCurrent());
   if(secsLeft < 0) secsLeft = 0;
   int hh = (int)(secsLeft / 3600);
   int mm = (int)((secsLeft % 3600) / 60);

   string title = ev.title;
   if(StringLen(title) > 28) title = StringSubstr(title, 0, 28) + "..";

   return StringFormat("%-8s | %02d:%02d | %s", pair, hh, mm, title);
}

void News_UpdatePanel()
{
   if(!ShowNewsPanel || !EnableNewsFilter) {
      News_DeletePanelObjects();
      return;
   }

   News_CreatePanelObjects();

   bool blockedNow = IsNewsTimeBlocked();
   string header = blockedNow ? "📰 News Filter | 🚫 ترید متوقف (خبر مهم)" : "📰 News Filter | ✅ آزاد";
   if(!g_newsWebRequestOK && g_lastNewsFetch == 0)
      header = "📰 News Filter | ⚠️ اتصال به تقویم برقرار نشد (WebRequest را چک کنید)";

   News_SetPanelLine(5, header, blockedNow ? clrRed : clrLime);
   string lineUSD = News_BuildLineForGroup("USD", false);
   string lineGBP = News_BuildLineForGroup("GBP", false);
   string lineEUR = News_BuildLineForGroup("EUR", true);
   string lineJPY = News_BuildLineForGroup("JPY", false);
   string lineAUD = News_BuildLineForGroup("AUD", false);
   News_SetPanelLine(4, lineUSD, clrWhite);
   News_SetPanelLine(3, lineGBP, clrWhite);
   News_SetPanelLine(2, lineEUR, clrSilver);
   News_SetPanelLine(1, lineJPY, clrSilver);
   News_SetPanelLine(0, lineAUD, clrSilver);
}

//+------------------------------------------------------------------+
//| Trading Core Functions (Optimized with Cache)                   |
//+------------------------------------------------------------------+
bool CheckSpread() {
 
   double spreadPoints = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double pip = GetPip();
   double spreadPips = (pip > 0) ? (spreadPoints * _Point / pip) : 0.0;
   bool ok = (spreadPips <= currentParams.maxSpread);
   return ok;
}

double CalculateLotSize() {
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   double lot = minLot;

   double riskMoney = AccountBalanceForRisk * (RiskPercentPerTrade / 100.0);
   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pip        = GetPip();

   if(tickSize > 0 && StopLoss > 0 && riskMoney > 0) {
      double moneyPerPipPerLot = (tickValue / tickSize) * pip;
      double slMoneyPerLot = StopLoss * moneyPerPipPerLot;
      if(slMoneyPerLot > 0)
         lot = riskMoney / slMoneyPerLot;
   }

   if(lot <= 0 || !MathIsValidNumber(lot)) {
      lot = minLot;
      if(DebugLogEnable) FilterLog("⚠️ محاسبهٔ حجم بر پایهٔ ریسک نامعتبر بود -> بازگشت به حداقل حجم");
   }

   lot = MathMax(lot, minLot);
   lot = MathMin(lot, maxLot);
   lot = MathRound(lot / lotStep) * lotStep;
   
   return NormalizeDouble(lot, 2);   }

//+------------------------------------------------------------------+
//| Check Open Position with Cache (Optimized)                      |
//+------------------------------------------------------------------+
bool HasOpenPosition() {   // ONETRADE v177.0: همیشه تازه (بدون حافظهٔ موقت)؛ هر پوزیشن روی این نماد، چه اکسپرت چه دستی
   g_cachedHasPosition = false;
   g_cachedPositionCount = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++) {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == _Symbol) {
         g_cachedHasPosition = true;
         g_cachedPositionCount++;
      }
   }
   g_lastPositionCheck = TimeCurrent();
   return g_cachedHasPosition;
}
bool IsSessionTimeAllowed() {
   if(!EnableSession1 && !EnableSession2) return true;   
      
   datetime brokerTime = TimeCurrent();
   
   int IranOffset = 3 * 3600 + 30 * 60;
   
   int BrokerOffset = GetBrokerGMTOffsetSeconds();
   
   datetime iranTime = brokerTime - BrokerOffset + IranOffset;
   
   MqlDateTime mqlTime;
   TimeToStruct(iranTime, mqlTime);
   string currentTimeStr = StringFormat("%02d:%02d", mqlTime.hour, mqlTime.min);
   
   // ============================================================
     if(EnableSession1) {
      if(currentTimeStr >= StartTime1 && currentTimeStr <= EndTime1) {
         return true;
      }
   }
   if(EnableSession2) {
      if(currentTimeStr >= StartTime2 && currentTimeStr <= EndTime2) {
         return true;
      }
   }
   return false;
}
bool ATRAllowedToTrade() {
   if(!EnableATRFilter) return true;
  
   double atrPips = last_atr_value / GetPip();
   return (atrPips >= MinimalATR && atrPips <= MaximalATR);
}
//+------------------------------------------------------------------+
//| Manual Position Management                                       |
//+------------------------------------------------------------------+
bool HasManualPositions() {
   if(!EnableManualManagement) {
      hasManualPosition = false;
      manualPositionsCount = 0;
      return false;    }
  
   int previousCount = manualPositionsCount;
   manualPositionsCount = 0;
   totalManualProfit = 0.0;
   bool foundManual = false;
   
   int total = PositionsTotal();
   
   for(int i = 0; i < total; i++) {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket)) {
         string symbol = PositionGetString(POSITION_SYMBOL);
         if(symbol == _Symbol) {
            bool isManual = IsManualPosition(ticket);
            
            if(isManual) {
               manualPositionsCount++;
               totalManualProfit += PositionGetDouble(POSITION_PROFIT);
               foundManual = true;
             
               if(Manual_AutoSLTP) {
                  ApplySLTPToPosition(ticket);
               }
            }
         }
      }
   }
 
   hasManualPosition = foundManual;
   
   if(previousCount != manualPositionsCount && EnableManualManagement) {
    if(manualPositionsCount > 0) {
        SendManualPositionAlert();   
    }
}   
return hasManualPosition;   }

bool IsManualPosition(ulong ticket) {
   if(ticket == 0) return false;
   if(!PositionSelectByTicket(ticket)) return false;
   
   string symbol = PositionGetString(POSITION_SYMBOL);
   long magic = PositionGetInteger(POSITION_MAGIC);
   string comment = PositionGetString(POSITION_COMMENT);
   
   if(symbol != _Symbol) return false;
   
   if(magic == 0 && comment == "") return true;
   
   if(Manual_CommentFilter != "" && StringFind(comment, Manual_CommentFilter) >= 0) return true;
   
   if(comment != "EA_ADAPTIVE_FILTER" && 
      StringFind(comment, "AUTO") == -1 &&
      StringFind(comment, "EXPERT") == -1 &&
      StringFind(comment, "EA") == -1) {
      return true;   }   return false;   }

void ApplySLTPToPosition(ulong ticket) {
   if(ticket == 0 || !PositionSelectByTicket(ticket)) return;
   
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   long type = PositionGetInteger(POSITION_TYPE);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double pip = GetPip();
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double slDist = StopLoss;
   double tpDist = TakeProfit;
   
   double newSL = currentSL, newTP = currentTP;
   bool needModify = false;
   
   if(type == POSITION_TYPE_BUY) {
      if(currentSL == 0) {
         newSL = openPrice - slDist * pip;
         newSL = NormalizeDouble(newSL, digits);
         needModify = true;
      }
      if(currentTP == 0) {
         newTP = openPrice + tpDist * pip;
         newTP = NormalizeDouble(newTP, digits);
         needModify = true;
      }
   } else if(type == POSITION_TYPE_SELL) {
      if(currentSL == 0) {
         newSL = openPrice + slDist * pip;
         newSL = NormalizeDouble(newSL, digits);
         needModify = true;
      }
      if(currentTP == 0) {
         newTP = openPrice - tpDist * pip;
         newTP = NormalizeDouble(newTP, digits);
         needModify = true;    }   }   
 
   if(needModify) {
      if(!trade.PositionModify(ticket, newSL, newTP)) {
         ErrorLog("اعمال حد ضرر/حد سود روی پوزیشن " + string(ticket) + " خطا: " + string(GetLastError()));    }   }   }

void SendManualPositionAlert() {
   if(!Manual_SendAlerts || !hasManualPosition) return;
   
   string alertMsg = StringFormat("MANUAL POSITIONS: %d positions on %s | Total P/L: %.2f", 
                                 manualPositionsCount, _Symbol, totalManualProfit);
   
   if(EnableNotification) {
      SendNotification(alertMsg);
   }

   if(DebugLogEnable) {
      SystemLog(alertMsg);}}
//+------------------------------------------------------------------+
//| Signal Processing Functions                                      |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| v172: استراتژی باکس ایچیموکو - دو سیستم کاملاً مستقل              |
//| باکس‌ها از سقف/کف (های/لو) کندل‌های بسته‌شده ساخته می‌شوند       |
//+------------------------------------------------------------------+
//BOX_CORE_BEGIN
struct BoxData {
   double   hi;
   double   lo;
   double   mid;
   datetime tLeft;
   datetime tRight;
};

double Box_MaxHigh(const double &a[], int from, int to) {
   double m = a[from];
   for(int i = from + 1; i <= to; i++) if(a[i] > m) m = a[i];
   return m;
}

double Box_MinLow(const double &a[], int from, int to) {
   double m = a[from];
   for(int i = from + 1; i <= to; i++) if(a[i] < m) m = a[i];
   return m;
}

class CBoxSystem {
public:
   int             id;
   string          tag;          // برچسب پوزیشن‌ها: B1 / B2
   string          pfx;          // پیشوند اشیای چارت
   ENUM_TIMEFRAMES tf;
   int             nT, nK, nS;   // تعداد کندل باکس‌ها
   int             chk;          // شیفت چیکو اسپن = دورهٔ کیجن‌سن شرط 2
   bool            show;
   double          tolPts;

   int      dir;                 // +1 تحلیل خرید، -1 تحلیل فروش، 0 بدون تحلیل
   double   extreme;             // لو/های مشترک ثبت‌شده
   datetime extremeTime;         // زمان کندلی که لو/های مشترک را ساخته (مرز چپ/راست)
   bool     frozen;              // تراز کندلی پیدا و باکس ثابت شده
   bool     used;                // از این تحلیل معامله باز شده
   bool     brokeUp, brokeDown;  // کلوز بیرون از باکس ثابت (بالا / پایین)
   double   level;               // تراز کندلی
   datetime levelTime;
   double   tp;                  // سقف/کف باکس بزرگِ ثابت‌شده
   int      signal;
   datetime signalBar;
   double   signalTP;
   datetime lastBar;
   BoxData  bT, bK, bS;          // باکس‌های زنده
   BoxData  fT, fK, fS;          // باکس‌های ثابت‌شده

   CBoxSystem() {
      id = 0; tag = ""; pfx = ""; tf = PERIOD_CURRENT;
      nT = 8; nK = 25; nS = 51; chk = 26; show = true; tolPts = 0.0;
      signal = 0; signalBar = 0; signalTP = 0.0; lastBar = 0;
      ResetState();
   }

   void Init(int id_, ENUM_TIMEFRAMES tf_, int t_, int k_, int s_, int chikou_, bool show_, double tol_) {
      id = id_;
      tag = "B" + IntegerToString(id_);
      pfx = "BoxStr" + IntegerToString(id_) + "_";
      tf = tf_;
      nT = t_; nK = k_; nS = s_; chk = chikou_;
      show = show_;
      tolPts = tol_;
   }

   void ResetState() {
      dir = 0; extreme = 0.0; extremeTime = 0; frozen = false; used = false;
      brokeUp = false; brokeDown = false;
      level = 0.0; levelTime = 0; tp = 0.0;
   }

   // ---------------- رسم ----------------
   void DrawRect(const string name, const BoxData &b, color clr) {
      if(ObjectFind(0, name) < 0) {
         ObjectCreate(0, name, OBJ_RECTANGLE, 0, b.tLeft, b.hi, b.tRight, b.lo);
         ObjectSetInteger(0, name, OBJPROP_FILL, false);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      }
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, b.tLeft);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, b.hi);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, b.tRight);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, b.lo);
   }

   // دات دقیقاً روی قیمت و زمان داده‌شده (متن با لنگر مرکز؛ فلش متاتریدر چند پیکسل جابه‌جا می‌نشست)
   void DrawDot(const string name, datetime t, double price, color clr) {
      if(ObjectFind(0, name) < 0) {
         ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
         ObjectSetString(0, name, OBJPROP_TEXT, ShortToString(0x25CF));
         ObjectSetString(0, name, OBJPROP_FONT, "Arial");
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      }
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, t);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   }

   void DrawBoxes(const BoxData &s, const BoxData &k, const BoxData &t) {
      if(!show) return;
      DrawRect(pfx + "S", s, clrLime);
      DrawRect(pfx + "K", k, clrDodgerBlue);
      DrawRect(pfx + "T", t, clrRed);
      // دات روی دو دیوارهٔ هر باکس برای کنترل تعداد کندل‌ها
      DrawDot(pfx + "S_L", s.tLeft,  s.mid, clrLime);
      DrawDot(pfx + "S_R", s.tRight, s.mid, clrLime);
      DrawDot(pfx + "K_L", k.tLeft,  k.mid, clrDodgerBlue);
      DrawDot(pfx + "K_R", k.tRight, k.mid, clrDodgerBlue);
      DrawDot(pfx + "T_L", t.tLeft,  t.mid, clrRed);
      DrawDot(pfx + "T_R", t.tRight, t.mid, clrRed);
   }

   void DrawLevel() {
      if(!show) return;
      color clr = (dir > 0) ? clrDodgerBlue : clrOrangeRed;
      string name = pfx + "Level";
      datetime t2 = levelTime + (datetime)(PeriodSeconds(tf) * 5);
      if(ObjectFind(0, name) < 0) {
         ObjectCreate(0, name, OBJ_TREND, 0, levelTime, level, t2, level);
         ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      }
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, levelTime);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, level);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, level);
      DrawDot(name + "_dot", levelTime, level, clr);
   }

   void DeleteObjects() {
      ObjectsDeleteAll(0, pfx);
   }

   // ---------------- منطق ----------------
   // باکس n کندلی: شیفت (1+off) تا (n+off)؛ شیفت 1 = آخرین کندل بسته‌شده
   void Calc(BoxData &b, int n, int off, const double &H[], const double &L[], const datetime &Tm[]) {
      int a = 1 + off, z = n + off;
      double h = H[a], l = L[a];
      for(int i = a + 1; i <= z; i++) {
         if(H[i] > h) h = H[i];
         if(L[i] < l) l = L[i];
      }
      b.hi = h;
      b.lo = l;
      b.mid = (h + l) / 2.0;
      b.tLeft = Tm[z];
      b.tRight = Tm[a];
   }

   // نگه‌دارندهٔ سقف: کندلی با بیشترین های در شیفت‌های from..to؛ در تساوی، قدیمی‌ترین (شیفت بزرگ‌تر)
   int HighHolder(const double &H[], int from, int to) {
      int idx = from;
      double m = H[from];
      for(int i = from + 1; i <= to; i++) if(H[i] >= m) { m = H[i]; idx = i; }
      return idx;
   }

   // نگه‌دارندهٔ کف: کندلی با کمترین لو؛ در تساوی، قدیمی‌ترین
   int LowHolder(const double &L[], int from, int to) {
      int idx = from;
      double m = L[from];
      for(int i = from + 1; i <= to; i++) if(L[i] <= m) { m = L[i]; idx = i; }
      return idx;
   }

   // جدیدترین کندلِ باکس کیجن که لو (های) مشترک را ساخته؛ مرز بین «کندل‌های چپ» و «کندل‌های راست»
   datetime ExtremeCandleTime(const double &H[], const double &L[], const datetime &Tm[], double tol) {
      for(int i = 1; i <= nK; i++) {
         if(dir > 0 && MathAbs(L[i] - extreme) <= tol) return Tm[i];
         if(dir < 0 && MathAbs(H[i] - extreme) <= tol) return Tm[i];
      }
      return Tm[1];
   }

   // شرط 2: چیکو اسپن (کلوز آخرین کندل بسته‌شده) نسبت به کیجن‌سن مقابل خودش (P کندل قبل‌تر)
   // کیجن‌سنِ آن نقطه از پنجرهٔ شیفت P+1 تا 2P ساخته می‌شود. خروجی: +1 بالا، -1 پایین، 0 روی خط
   int ChikouVsKijun(const double &H[], const double &L[], const double &C[]) {
      int P = chk;
      double kj = (Box_MaxHigh(H, P + 1, 2 * P) + Box_MinLow(L, P + 1, 2 * P)) / 2.0;
      if(C[1] > kj) return 1;
      if(C[1] < kj) return -1;
      return 0;
   }

   int NeedBars() {
      return MathMax(nS + 2, MathMax(2 * chk, nK + 1)) + 1;
   }

   void Start(int d, double ext) {
      DeleteObjects();
      ResetState();
      dir = d;
      extreme = ext;
   }

   void Reset() {
      DeleteObjects();
      ResetState();
   }

   void Freeze(double lvl, datetime lvlTime, const double &H[], const double &L[], const datetime &Tm[]) {
      // باکس‌ها یک کندل قبل از کندل تثبیت ثابت می‌شوند (کندل چپ هنوز سقف/کف کیجن را نگه داشته)
      Calc(fT, nT, 1, H, L, Tm);
      Calc(fK, nK, 1, H, L, Tm);
      Calc(fS, nS, 1, H, L, Tm);
      level = lvl;
      levelTime = lvlTime;
      tp = (dir > 0) ? fS.hi : fS.lo;
      frozen = true;
      brokeUp = false;
      brokeDown = false;
      DrawBoxes(fS, fK, fT);
      DrawLevel();
   }

   // یک بار در هر کندل بسته‌شدهٔ همین تایم‌فریم؛ آرایه‌ها سری هستند (اندیس 1 = آخرین کندل بسته‌شده)
   void OnBar(const double &H[], const double &L[], const double &C[], const datetime &Tm[], int cnt, double point) {
      signal = 0;
      signalTP = 0.0;
      int K = nK, P = chk;
      if(nT < 2 || K < 3 || nS < K || P < 2) return;
      if(cnt < NeedBars()) return;

      Calc(bT, nT, 0, H, L, Tm);
      Calc(bK, nK, 0, H, L, Tm);
      Calc(bS, nS, 0, H, L, Tm);

      double tol = MathMax(point * 0.5, tolPts * point);
      bool sharedLow  = (MathAbs(bT.lo - bK.lo) <= tol && MathAbs(bK.lo - bS.lo) <= tol);
      bool sharedHigh = (MathAbs(bT.hi - bK.hi) <= tol && MathAbs(bK.hi - bS.hi) <= tol);

      // شرط 1: لو/های مشترک سه باکس تحلیل را شروع می‌کند؛ لو/های مشترک جدید در محل جدید، تحلیل تازه می‌سازد
      // BOXLOCK (v176.2): تحلیل جهت مخالف، باکس ثابت‌شدهٔ بدون معامله را پاک نمی‌کند؛ فقط لو/های تازهٔ هم‌جهت آن را پاک می‌کند.
      // پس از معامله (used) یا انقضا (Reset) قفل باز است.
      if(sharedLow && !(frozen && !used && dir == -1)) {   // BOXLOCK
         if(!(dir == 1 && MathAbs(bK.lo - extreme) <= tol)) {
            Start(1, bK.lo);
            extremeTime = ExtremeCandleTime(H, L, Tm, tol);
            DrawBoxes(bS, bK, bT);
         }
      } else if(sharedHigh && !(frozen && !used && dir == 1)) {   // BOXLOCK
         if(!(dir == -1 && MathAbs(bK.hi - extreme) <= tol)) {
            Start(-1, bK.hi);
            extremeTime = ExtremeCandleTime(H, L, Tm, tol);
            DrawBoxes(bS, bK, bT);
         }
      }

      // تا پیدا شدن تراز: ادامهٔ تحلیل فقط تا وقتی لو/های مشترک بین باکس کیجن و اسپن بی برقرار است
      if(dir != 0 && !frozen) {
         bool cont = (dir > 0) ? (MathAbs(bK.lo - bS.lo) <= tol) : (MathAbs(bK.hi - bS.hi) <= tol);
         if(!cont) {
            Reset();
         } else {
            // «چپ» = کندل‌های تا خودِ کندل لو/های مشترک، «راست» = کندل‌های بعد از آن.
            // تراز وقتی ثبت می‌شود که نگه‌دارندهٔ سقف (کف) کیجن، برای اولین بار از چپ به راست برسد؛
            // تراز = های (لوی) آخرین نگه‌دارندهٔ چپ، یعنی سقف (کف) باکس قبلی
            if(dir > 0) {
               int pIdx = HighHolder(H, 2, K + 1);   // نگه‌دارندهٔ باکس یک کندل قبل
               int cIdx = HighHolder(H, 1, K);       // نگه‌دارندهٔ باکس فعلی
               if(Tm[pIdx] <= extremeTime && Tm[cIdx] > extremeTime) Freeze(H[pIdx], Tm[pIdx], H, L, Tm);
            } else {
               int pIdx = LowHolder(L, 2, K + 1);
               int cIdx = LowHolder(L, 1, K);
               if(Tm[pIdx] <= extremeTime && Tm[cIdx] > extremeTime) Freeze(L[pIdx], Tm[pIdx], H, L, Tm);
            }
         }
         if(dir != 0 && !frozen) DrawBoxes(bS, bK, bT);   // باکس‌ها همراه کندل‌ها جلو می‌روند
      }

      if(dir == 0 || !frozen) { signalBar = Tm[0]; return; }

      // انقضا: قیمت از هر دو طرف باکس ثابت بیرون رفته و معامله‌ای باز نشده
      if(!used) {
         if(C[1] > fK.hi) brokeUp = true;
         if(C[1] < fK.lo) brokeDown = true;
         if(brokeUp && brokeDown) {
            Reset();
            signalBar = Tm[0];
            return;
         }
      }

      // شرط 2: چیکو اسپن نسبت به کیجن‌سن مقابل خودش
      int chikouRel = ChikouVsKijun(H, L, C);
      bool chikouAbove = (chikouRel > 0);
      bool chikouBelow = (chikouRel < 0);

      // ماشه: کلوز کندل بسته‌شده بالای (پایین) تراز + شرط 2
      if(!used) {
         if(dir > 0 && C[1] > level && chikouAbove) { signal = 1;  signalTP = tp; }
         if(dir < 0 && C[1] < level && chikouBelow) { signal = -1; signalTP = tp; }
      }
      signalBar = Tm[0];
   }

   void Refresh() {
      datetime cur = iTime(_Symbol, tf, 0);
      if(cur == 0 || cur == lastBar) return;
      int need = NeedBars();
      double H[], L[], C[];
      datetime Tm[];
      ArraySetAsSeries(H, true);
      ArraySetAsSeries(L, true);
      ArraySetAsSeries(C, true);
      ArraySetAsSeries(Tm, true);
      if(CopyHigh(_Symbol, tf, 0, need, H) < need) return;
      if(CopyLow(_Symbol, tf, 0, need, L) < need) return;
      if(CopyClose(_Symbol, tf, 0, need, C) < need) return;
      if(CopyTime(_Symbol, tf, 0, need, Tm) < need) return;
      lastBar = cur;
      OnBar(H, L, C, Tm, need, SymbolInfoDouble(_Symbol, SYMBOL_POINT));
   }

   int GetSignal() {
      Refresh();
      datetime cur = iTime(_Symbol, tf, 0);
      if(signal != 0 && signalBar == cur) return signal;
      return 0;
   }

   // بعد از اجرای موفق معامله: تحلیل مصرف شد ولی باکس و تراز روی چارت می‌مانند
   void OnTradeDone() {
      used = true;
      signal = 0;
   }
};
//BOX_CORE_END

//BOXBREAK_BEGIN
//+------------------------------------------------------------------+
//| v176.1: شکست باکس — کلاس مستقل                                   |
//| فقط وضعیت عمومیِ CBoxSystem را می‌خواند و چیزی در آن تغییر نمی‌دهد. |
//| حذف این قابلیت: پاک کردن همین بخش (تا BOXBREAK_END) و خط‌های        |
//| برچسب‌خورده با BOXBREAK در بقیهٔ فایل                              |
//+------------------------------------------------------------------+
class CBoxBreak {
public:
   int             id;
   string          tag;              // K1 / K2
   ENUM_TIMEFRAMES tf;
   int             lockBars;         // طول قفل به کندل بسته (یک دورهٔ کیجن)
   bool            lockActive;       // نسخهٔ قفل‌شدهٔ باکس تا پایان قفل نگه داشته می‌شود
   int             lockCount;        // کندل‌های بسته‌شده از کندل اولین شکست
   double          lkHi, lkLo, lkTpUp, lkTpDown;   // نسخهٔ قفل‌شدهٔ باکس (مستقل از CBoxSystem)
   bool            tracking;         // یک باکس ثابت‌شده را دنبال می‌کنیم
   datetime        keyLevelTime, keyExtremeTime;
   double          keyLevel;
   int             keyDir;
   bool            lockStarted;      // برای همین باکس قفل شروع شده
   bool            doneUp, doneDown; // هر سمت در عمر هر باکس فقط یک‌بار سیگنال می‌دهد
   int             signal;
   datetime        signalBar;
   double          signalTP;
   datetime        lastBar;

   CBoxBreak() {
      id = 0; tag = ""; tf = PERIOD_CURRENT; lockBars = 26;
      signal = 0; signalBar = 0; signalTP = 0.0; lastBar = 0;
      ResetAll();
   }

   void Init(int id_, ENUM_TIMEFRAMES tf_, int lockBars_) {
      id = id_;
      tag = "K" + IntegerToString(id_);
      tf = tf_;
      lockBars = lockBars_;
   }

   void ResetAll() {
      lockActive = false; lockCount = 0;
      lkHi = 0.0; lkLo = 0.0; lkTpUp = 0.0; lkTpDown = 0.0;
      tracking = false; keyLevelTime = 0; keyExtremeTime = 0; keyLevel = 0.0; keyDir = 0;
      lockStarted = false; doneUp = false; doneDown = false;
   }

   // یک بار در هر کندل بسته‌شده، بعد از آن‌که src همان کندل را پردازش کرد
   void OnBar(CBoxSystem *src, double closePrev, datetime curBarTime) {
      signal = 0;
      signalTP = 0.0;
      signalBar = curBarTime;
      bool lockedAtStart = lockActive;
      if(lockedAtStart) lockCount++;

      double hi = 0.0, lo = 0.0, tpUp = 0.0, tpDn = 0.0;
      bool haveBox = false;
      if(lockedAtStart) {
         hi = lkHi; lo = lkLo; tpUp = lkTpUp; tpDn = lkTpDown;
         haveBox = true;
      } else if(src != NULL && src.frozen && src.dir != 0) {
         bool same = tracking && keyLevelTime == src.levelTime && keyExtremeTime == src.extremeTime &&
                     keyDir == src.dir && keyLevel == src.level;
         if(!same) {   // باکس ثابت‌شدهٔ تازه
            tracking = true;
            keyLevelTime = src.levelTime; keyExtremeTime = src.extremeTime;
            keyDir = src.dir; keyLevel = src.level;
            lockStarted = false; doneUp = false; doneDown = false;
         }
         hi = src.fK.hi; lo = src.fK.lo; tpUp = src.fS.hi; tpDn = src.fS.lo;
         haveBox = true;
      } else {
         tracking = false;   // باکس برداشته شد؛ دفعهٔ بعد نمونهٔ تازه حساب می‌شود
      }

      if(haveBox) {
         if(closePrev > hi && !doneUp) {
            signal = 1;  signalTP = tpUp;  doneUp = true;
         } else if(closePrev < lo && !doneDown) {
            signal = -1; signalTP = tpDn;  doneDown = true;
         }
         if(signal != 0 && !lockStarted && !lockedAtStart) {
            lockStarted = true; lockActive = true; lockCount = 0;
            lkHi = hi; lkLo = lo; lkTpUp = tpUp; lkTpDown = tpDn;
         }
      }
      if(lockedAtStart && lockCount >= lockBars) lockActive = false;
   }

   void Refresh(CBoxSystem *src) {
      if(src == NULL) return;
      datetime cur = iTime(_Symbol, tf, 0);
      if(cur == 0 || cur == lastBar) return;
      if(src.lastBar != cur) return;       // منبع هنوز این کندل را پردازش نکرده
      double c1 = iClose(_Symbol, tf, 1);
      if(c1 <= 0.0) return;
      lastBar = cur;
      OnBar(src, c1, cur);
   }

   int GetSignal(CBoxSystem *src) {
      Refresh(src);
      datetime cur = iTime(_Symbol, tf, 0);
      if(signal != 0 && signalBar == cur) return signal;
      return 0;
   }

   void OnDone() {
      signal = 0;
   }
};
//BOXBREAK_END

EnumSignalSource Src_Primary() {
   if(UseBoxSignal || UseBoxBreakSignal || UseBoxBreak2Signal) return SIGNAL_ICHIMOKU_BOX;   // BOXBREAK
   if(UseCompositeSignal)  return SIGNAL_COMPOSITE_SCORE;
   return SIGNAL_EXTERNAL_INDICATOR;
}

CBoxSystem *g_box1 = NULL;
CBoxSystem *g_box2 = NULL;
CBoxBreak  *g_brk1 = NULL;   // BOXBREAK
CBoxBreak  *g_brk2 = NULL;   // BOXBREAK

void Box_InitSystems() {
   ObjectsDeleteAll(0, "BoxStr1_");   // v177.0: باکس‌های باقی‌مانده از اجراهای قبلی یا ذخیره‌شده با چارت
   ObjectsDeleteAll(0, "BoxStr2_");
   if(g_box1 != NULL) { delete g_box1; g_box1 = NULL; }
   if(g_box2 != NULL) { delete g_box2; g_box2 = NULL; }
   if(g_brk1 != NULL) { delete g_brk1; g_brk1 = NULL; }   // BOXBREAK
   if(g_brk2 != NULL) { delete g_brk2; g_brk2 = NULL; }   // BOXBREAK
   bool need1 = (UseBoxSignal || UseBoxBreakSignal);                          // BOXBREAK
   bool need2 = (Box2_Enable && (UseBoxSignal || UseBoxBreak2Signal));       // BOXBREAK
   if(need1) {
      g_box1 = new CBoxSystem();
      g_box1.Init(1, (ENUM_TIMEFRAMES)_Period, Box_TenkanBars, Box_KijunBars, Box_SpanBBars,
                  Box_ChikouShift, ShowBoxObjects, Box_SharedTolPoints);
      if(UseBoxBreakSignal) {                                                   // BOXBREAK
         g_brk1 = new CBoxBreak();
         g_brk1.Init(1, (ENUM_TIMEFRAMES)_Period, Box_KijunBars);
      }
   }
   if(need2) {
      ENUM_TIMEFRAMES tf2 = (Box2_Timeframe == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : Box2_Timeframe;
      g_box2 = new CBoxSystem();
      g_box2.Init(2, tf2, Box2_TenkanBars, Box2_KijunBars, Box2_SpanBBars,
                  Box2_ChikouShift, ShowBox2Objects, Box_SharedTolPoints);
      if(UseBoxBreak2Signal) {                                                  // BOXBREAK
         g_brk2 = new CBoxBreak();
         g_brk2.Init(2, tf2, Box2_KijunBars);
      }
   }
}

void Box_DeinitSystems() {
   if(g_box1 != NULL) { g_box1.DeleteObjects(); delete g_box1; g_box1 = NULL; }
   if(g_box2 != NULL) { g_box2.DeleteObjects(); delete g_box2; g_box2 = NULL; }
   if(g_brk1 != NULL) { delete g_brk1; g_brk1 = NULL; }   // BOXBREAK
   if(g_brk2 != NULL) { delete g_brk2; g_brk2 = NULL; }   // BOXBREAK
   ObjectsDeleteAll(0, "BoxStr1_");   // v177.0: حتی وقتی سیستم باکس ساخته نشده بود
   ObjectsDeleteAll(0, "BoxStr2_");
}

// حد سود = سقف (کف) باکس بزرگِ ثابت‌شده؛ اگر معتبر نبود، حد سود ثابت ورودی
double Box_ResolveTP(int signal, double price, double fallbackTP) {
   double target = g_boxCtxTP;
   double minDist = ((double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) +
                     (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(signal > 0 && target > price + minDist) return target;
   if(signal < 0 && target > 0.0 && target < price - minDist) return target;
   return fallbackTP;
}

int GetTradingSignal() {
    if(SignalSource == SIGNAL_COMPOSITE_SCORE) {   // v153
        int sig = GetCompositeSignal();
        lastSignalUsed = sig;
        return sig;
    }
    return GetSignalFromGlobalVariable();
}

int GetSignalFromGlobalVariable() {
   string currentVarName = StringFormat("DualIchimokuSignal_%s_%d", _Symbol, _Period);
   if(GlobalVariableCheck(currentVarName)) {
      double value = GlobalVariableGet(currentVarName);
      
      static int lastSignal = 0;
      static datetime lastSignalTime = 0;
      datetime currentTime = TimeCurrent();
      
      if(value == lastSignal && (currentTime - lastSignalTime) < 3) { 
         lastSignalUsed = 0;
         return 0;  
      }
   
      GlobalVariableDel(currentVarName);
      
      lastSignal = (int)value;
      lastSignalTime = currentTime;
      
      if(value == 66) {
         lastSignalUsed = 1;
         return 1;
      }
      if(value == 83) {
         lastSignalUsed = -1;
         return -1;
      }
   }
   lastSignalUsed = 0;
   return 0;
}
int ApplySignalDelay(int currentSignal, bool newBar) {
   if(SignalExecutionDelay <= 0 || currentSignal == 0) return currentSignal;
   
   if(newBar) {
      signalDelayCounter++;
      if(signalDelayCounter >= SignalExecutionDelay) {
         signalDelayCounter = 0;
         return currentSignal;
      }
   }
   return 0;
}

//+------------------------------------------------------------------+
//| v174: حالت پیشنهاد — چند روش، دو جهت، نقطهٔ ورود                  |
//| پیشنهاد فقط با یک نقطهٔ بزرگ روی همین چارت نشان داده می‌شود و      |
//| برای اکسپرت دیده‌بان با متغیر سراسری فرستاده می‌شود                |
//+------------------------------------------------------------------+
int      g_sugMask[2];      // [0]=خرید [1]=فروش ؛ بیت هر روش = 1<<کد روش
datetime g_sugStart[2];     // اولین لحظهٔ پیشنهاد (شروع اعتبار و محل نقطه)
double   g_sugEntryP[2];    // قیمت نقطهٔ ورود
double   g_sugTP[2];        // هدف پیشنهادی (باکس یا ثابت)

//+------------------------------------------------------------------+
//| LEG (v178.0): ورود هوشمند بر پایهٔ کیفیت لگ                         |
//| هر سیگنالی که از همهٔ فیلترها گذشته، به‌جای اجرای مستقیم این‌جا      |
//| تصمیم می‌گیرد «فوری» وارد شود یا «روی فیبوناچی منتظر پولبک» بماند.   |
//|                                                                  |
//| مرحلهٔ ۱) اندازهٔ لگ = فاصلهٔ قیمت تا «مبدأ لگ».                    |
//|   مبدأ در کندل‌های تازهٔ سیگنال = قیمت شروع سیگنال اندیکاتور؛        |
//|   بعد از آن = کف/سقفِ آخرین کندلی که سمت اشتباهِ تنکن ۹ بسته شد.    |
//|   اندازهٔ لگ تا قله/دره‌ی واقعی (نه فقط قیمت فعلی) سنجیده می‌شود.   |
//| مرحلهٔ ۲) لگ بزرگ: لگ ≥ (Leg_BigRangeMult × میانهٔ دامنهٔ ۲۰ کندل)   |
//|   ← فقط پولبک. (بدون وابستگی به حد ضرر)                            |
//| مرحلهٔ ۳) لگ کوچک: تیک قوی + سیگنال تازه ← فوری؛ فقط یکی ← فیبوی ۱؛   |
//|   هیچ‌کدام ← فیبوی ۲.                                               |
//| مرحلهٔ ۴) بعد از لمس سطح فیبو، با بسته شدن کندل سه شرطِ «مشکوک»      |
//|   بررسی می‌شود: بدنهٔ پولبک، تیکِ خلاف‌جهت، عمق بیش از حد.          |
//|   صفر شرط ← ورود | یک شرط ← تاخیر یک کندل و بررسی دوباره |            |
//|   دو شرط یا بیشتر ← لغو.                                           |
//| برای حذف ماژول: این بلوک و خطوطِ دارای برچسب «LEG v178.0».          |
//+------------------------------------------------------------------+
#define LG_FIB_PREFIX  "LGF_"
#define LG_NOTE_PREFIX "LGN_"
#define LG_DOT_PREFIX  "LGO_"
#define LG_MAX_ORIGIN_BARS 30      // v178.1: حداکثر کندل جست‌وجوی مبدأ پویا
#define LG_WAIT_BARS       15      // v178.1: حداکثر کندل انتظار برای رسیدن به فیبو
#define LG_INVALID_PCT     61.8    // v178.1: عمق مشکوک (درصد لگ)
#define LG_BODY_RATIO      1.0     // v178.1: ضریب بدنهٔ پولبک نسبت به بدنهٔ لگ
#define LG_OPP_MULT        1.5     // v178.1: حدهای تیک خلاف‌جهت = این ضریب × حدهای تیک قوی
#define LG_RANGE_BARS      20      // v178.1: تعداد کندل برای میانهٔ دامنه

int      g_lgState       = 0;       // 0 بیکار، 1 منتظر لمس سطح، 2 سطح لمس شد (ارزیابی با کندل بعد)، 3 تاخیر یک کندل
int      g_lgDir         = 0;       // +1 خرید، -1 فروش
datetime g_lgArmBar      = 0;       // کندلی که سیگنال در آن مسلح شد
double   g_lgOrigin      = 0.0;     // مبدأ لگ (ثابت)
datetime g_lgOriginTime  = 0;
double   g_lgExtreme     = 0.0;     // سقف (خرید) یا کف (فروش) لگ تا این لحظه؛ فقط گسترش می‌یابد
datetime g_lgExtremeTime = 0;
double   g_lgPct         = 38.2;    // درصد فیبوی ورود
datetime g_lgEvalFrom    = 0;       // کندلی که لمس/تاخیر در آن رخ داد؛ ارزیابی با باز شدن کندل بعدی
bool     g_lgBoxActive   = false;   // زمینهٔ سیگنال در لحظهٔ مسلح شدن
string   g_lgBoxTag      = "";
double   g_lgBoxTP       = 0.0;
int      g_lgMask        = 0;
bool     g_lgFilling     = false;   // در حال اجرای ورود پولبک
int      g_lgMaskOverride = 0;      // فقط هنگام اجرا: روش‌های ذخیره‌شده
int      g_lgDoneDir     = 0;       // جهت آخرین ورود/لغو (برای جلوگیری از مسلح شدن تکراریِ همان سیگنال)
datetime g_lgDoneBar     = 0;

// متغیرهای نمایشی (با پایان انتظار پاک نمی‌شوند تا دکمهٔ FIB بتواند دوباره بکشد)
int      g_ldDir         = 0;
double   g_ldOrigin      = 0.0;
datetime g_ldOriginTime  = 0;
double   g_ldExtreme     = 0.0;
datetime g_ldExtremeTime = 0;
double   g_ldPct         = 0.0;     // 0 = سطح ورودی وجود ندارد (ورود فوری)

string   g_lgNote[6];
color    g_lgNoteClr[6];

// نتیجهٔ آخرین تصمیم
int      g_lgDecMode     = 0;       // 0 فوری، 1 پولبک، 2 رد
double   g_lgDecPct      = 38.2;
double   g_lgDecExt      = 0.0;     // قله/دره‌ی واقعی لگ از مبدأ تا همین لحظه
datetime g_lgDecExtTime  = 0;

double LG_Pip() { const double p = GetPip(); return (p > 0.0) ? p : _Point; }

void LG_ClearFib()   { ObjectsDeleteAll(0, LG_FIB_PREFIX); }
void LG_ClearNotes() { ObjectsDeleteAll(0, LG_NOTE_PREFIX); }
void LG_Cleanup()    { LG_ClearFib(); LG_ClearNotes(); ObjectsDeleteAll(0, LG_DOT_PREFIX); ObjectsDeleteAll(0, "PPINFO_"); }

void LG_Reset()
{
   g_lgState = 0;
   g_lgDir = 0;
   g_lgArmBar = 0;
   g_lgOrigin = 0.0;
   g_lgOriginTime = 0;
   g_lgExtreme = 0.0;
   g_lgExtremeTime = 0;
   g_lgEvalFrom = 0;
   g_lgBoxActive = false;
   g_lgBoxTag = "";
   g_lgBoxTP = 0.0;
   g_lgMask = 0;
}

void LG_SetNote(const int k, const string text, const color clr)
{
   if(k < 0 || k >= 6) return;
   g_lgNote[k] = text;
   g_lgNoteClr[k] = clr;
}

void LG_ClearNoteTexts()
{
   for(int k = 0; k < 6; k++) { g_lgNote[k] = ""; g_lgNoteClr[k] = clrSilver; }
}

void LG_SetDisplay(const int dir, const double org, const datetime ot, const double ext, const datetime et, const double pct)
{
   g_ldDir = dir;
   g_ldOrigin = org;
   g_ldOriginTime = ot;
   g_ldExtreme = ext;
   g_ldExtremeTime = et;
   g_ldPct = pct;
}

void LG_MakeLine(const string name, const datetime t1, const double p1, const datetime t2, const double p2,
                 const color clr, const ENUM_LINE_STYLE style, const int width)
{
   if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2)) return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void LG_MakeText(const string name, const datetime t, const double p, const string text, const color clr)
{
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, p)) return;
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

// فیبوناچی: خط لگ (مبدأ تا قله) + سطح‌های ۰ ، ۳۸٫۲ ، ۵۰ ، ۶۱٫۸ ، ۱۰۰ ؛ سطحِ ورود طلایی
void LG_DrawFib()
{
   LG_ClearFib();
   if(!g_lgShowFib || g_ldDir == 0) return;
   const double legsz = (g_ldExtreme - g_ldOrigin) * g_ldDir;
   if(legsz <= 0.0 || g_ldOriginTime == 0 || g_ldExtremeTime == 0) return;
   const datetime t0 = iTime(_Symbol, _Period, 0);
   if(t0 == 0) return;
   const datetime tE = t0 + (datetime)(PeriodSeconds() * (LG_WAIT_BARS + 2));

   LG_MakeLine(LG_FIB_PREFIX + "LEG", g_ldOriginTime, g_ldOrigin, g_ldExtremeTime, g_ldExtreme,
               (g_ldDir > 0 ? clrLime : clrRed), STYLE_SOLID, 2);

   double pcts[5] = {0.0, 38.2, 50.0, 61.8, 100.0};
   bool selDrawn = false;
   for(int k = 0; k < 5; k++)
   {
      const double lv = g_ldExtreme - g_ldDir * (pcts[k] / 100.0) * legsz;
      const bool sel = (g_ldPct > 0.0 && MathAbs(pcts[k] - g_ldPct) < 0.05);
      color c = clrSilver;
      if(k == 1) c = clrDodgerBlue;
      if(k == 2) c = clrOrange;
      if(k == 3) c = clrTomato;
      if(sel) { c = clrGold; selDrawn = true; }
      LG_MakeLine(LG_FIB_PREFIX + "L" + IntegerToString(k), g_ldOriginTime, lv, tE, lv, c, (sel ? STYLE_SOLID : STYLE_DOT), (sel ? 2 : 1));
      string lbl = StringFormat("%.1f%%  %s%s", pcts[k], DoubleToString(lv, _Digits), (sel ? "   <- ورود" : ""));
      LG_MakeText(LG_FIB_PREFIX + "T" + IntegerToString(k), tE, lv, lbl, c);
   }
   if(g_ldPct > 0.0 && !selDrawn)
   {
      const double lv = g_ldExtreme - g_ldDir * (g_ldPct / 100.0) * legsz;
      LG_MakeLine(LG_FIB_PREFIX + "LS", g_ldOriginTime, lv, tE, lv, clrGold, STYLE_SOLID, 2);
      LG_MakeText(LG_FIB_PREFIX + "TS", tE, lv, StringFormat("%.1f%%  %s   <- ورود", g_ldPct, DoubleToString(lv, _Digits)), clrGold);
   }
}

// توضیح مراحل کار الگوریتم کنار کندل
void LG_DrawNotes()
{
   LG_ClearNotes();
   if(!ShowEntryDecisionDetails || g_ldDir == 0) return;
   const datetime t0 = iTime(_Symbol, _Period, 0);
   if(t0 == 0) return;
   const int ih = iHighest(_Symbol, _Period, MODE_HIGH, 20, 1);
   const int il = iLowest(_Symbol, _Period, MODE_LOW, 20, 1);
   double range = 0.0;
   if(ih >= 0 && il >= 0) range = iHigh(_Symbol, _Period, ih) - iLow(_Symbol, _Period, il);
   if(range <= 0.0) range = 10.0 * LG_Pip();
   const double step = range * 0.07;
   const double base = (g_ldDir > 0) ? iLow(_Symbol, _Period, 0) - step : iHigh(_Symbol, _Period, 0) + step;
   int n = 0;
   for(int k = 0; k < 6; k++)
   {
      if(g_lgNote[k] == "") continue;
      const double p = base - g_ldDir * step * n;
      n++;
      LG_MakeText(LG_NOTE_PREFIX + IntegerToString(k), t0, p, g_lgNote[k], g_lgNoteClr[k]);
   }
}

// نقطهٔ دقیق مبدأ لگ (مستقل از دکمهٔ FIB)
void LG_DrawOriginDot()
{
   ObjectsDeleteAll(0, LG_DOT_PREFIX);
   if(g_ldDir == 0 || g_ldOrigin <= 0.0 || g_ldOriginTime == 0) return;
   const string name = LG_DOT_PREFIX + "ORG";
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, g_ldOriginTime, g_ldOrigin)) return;
   ObjectSetString(0, name, OBJPROP_TEXT, "●");
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 12);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrMagenta);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, "مبدأ لگ");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void LG_Refresh(const bool notes, const bool force)
{
   static uint s_lastMs = 0;
   const uint nowMs = GetTickCount();
   if(!force && (nowMs - s_lastMs) < 400) return;
   s_lastMs = nowMs;
   LG_DrawFib();
   LG_DrawOriginDot();
   if(notes) LG_DrawNotes();
   ChartRedraw(0);
}

// تنکن ۹ در شیفت داده‌شده (وسط بالاترین سقف و پایین‌ترین کف ۹ کندل)
double LG_Tenkan(const int shift)
{
   const int ih = iHighest(_Symbol, _Period, MODE_HIGH, 9, shift);
   const int il = iLowest(_Symbol, _Period, MODE_LOW, 9, shift);
   if(ih < 0 || il < 0) return 0.0;
   return (iHigh(_Symbol, _Period, ih) + iLow(_Symbol, _Period, il)) / 2.0;
}

// زمان و قیمت شروع سیگنال اندیکاتور (فقط اگر تازه باشد؛ حافظهٔ سیگنال اندیکاتور ۶ کندل است)
bool LG_SignalStart(datetime &st, double &sp)
{
   if(!Sug_IndicatorEntry(st, sp)) return false;
   const datetime now = TimeCurrent();
   if(st > now) return false;
   if((long)(now - st) > (long)PeriodSeconds() * 8) return false;
   return true;
}

// مبدأ لگ: کندل‌های تازه ← قیمت شروع سیگنال؛ بعد ← مبدأ پویا با تنکن ۹
bool LG_FindOrigin(const int dir, double &origin, datetime &otime, int &freshBars, string &src, bool &isDynamic)
{
   datetime st = 0;
   double sp = 0.0;
   freshBars = 0;                      // بدون زمان اندیکاتور (باکس، ماشهٔ ترکیبی) سیگنال تازه فرض می‌شود
   isDynamic = false;
   if(LG_SignalStart(st, sp))
   {
      const int sh = iBarShift(_Symbol, _Period, st, false);
      freshBars = (sh >= 0) ? sh : 0;
      if(freshBars <= Leg_FreshBars)
      {
         // کف (خرید) یا سقف (فروش) واقعی از شروع سیگنال تا الان؛ نه فقط قیمتِ لحظهٔ شروع
         double best = sp;
         datetime btime = st;
         const double nowP = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if((dir > 0 && nowP < best) || (dir < 0 && nowP > best)) { best = nowP; btime = iTime(_Symbol, _Period, 0); }
         for(int s = 0; s < freshBars; s++)          // کندل‌های بعد از کندل شروع سیگنال
         {
            const double v = (dir > 0) ? iLow(_Symbol, _Period, s) : iHigh(_Symbol, _Period, s);
            if((dir > 0 && v < best) || (dir < 0 && v > best)) { best = v; btime = iTime(_Symbol, _Period, s); }
         }
         origin = best;
         otime = btime;
         src = "کف/سقف واقعی از شروع سیگنال اندیکاتور تا الان";
         return true;
      }
   }
   const int bars = Bars(_Symbol, _Period);
   const int maxBars = MathMin(LG_MAX_ORIGIN_BARS, bars - 12);
   if(maxBars < 3) return false;
   int wrong = -1;
   for(int k = 1; k <= maxBars; k++)
   {
      const double tk = LG_Tenkan(k);
      if(tk <= 0.0) break;
      const double c = iClose(_Symbol, _Period, k);
      if((dir > 0 && c < tk) || (dir < 0 && c > tk)) { wrong = k; break; }
   }
   const int cnt = (wrong > 0) ? wrong : maxBars;
   const int idx = (dir > 0) ? iLowest(_Symbol, _Period, MODE_LOW, cnt, 1) : iHighest(_Symbol, _Period, MODE_HIGH, cnt, 1);
   if(idx < 0) return false;
   origin = (dir > 0) ? iLow(_Symbol, _Period, idx) : iHigh(_Symbol, _Period, idx);
   otime = iTime(_Symbol, _Period, idx);
   isDynamic = true;
   src = (wrong > 0) ? "مبدأ پویا: کف/سقف قبل از عبور قیمت به سمت درست تنکن 9" : "مبدأ پویا: کف/سقف بازهٔ جست‌وجو (قیمت هیچ‌وقت سمت اشتباه تنکن 9 نبسته)";
   return true;
}

// میانهٔ دامنهٔ (سقف منهای کف) ۲۰ کندل بستهٔ اخیر؛ مقیاس نوسان بازار
double LG_MedianRange()
{
   double r[];
   ArrayResize(r, LG_RANGE_BARS);
   for(int s = 1; s <= LG_RANGE_BARS; s++)
   {
      const double h = iHigh(_Symbol, _Period, s);
      const double l = iLow(_Symbol, _Period, s);
      if(h <= 0.0 || l <= 0.0) return 0.0;
      r[s - 1] = h - l;
   }
   ArraySort(r);
   return (r[LG_RANGE_BARS / 2 - 1] + r[LG_RANGE_BARS / 2]) / 2.0;
}

// قله (خرید) یا دره (فروش) واقعی لگ: از مبدأ تا کندل جاری
bool LG_SwingExtreme(const int dir, const datetime otime, double &ext, datetime &etime)
{
   const int sOri = iBarShift(_Symbol, _Period, otime, false);
   if(sOri < 0) return false;
   const int idx = (dir > 0) ? iHighest(_Symbol, _Period, MODE_HIGH, sOri + 1, 0) : iLowest(_Symbol, _Period, MODE_LOW, sOri + 1, 0);
   if(idx < 0) return false;
   ext = (dir > 0) ? iHigh(_Symbol, _Period, idx) : iLow(_Symbol, _Period, idx);
   etime = iTime(_Symbol, _Period, idx);
   return true;
}

// تصمیم: 0 فوری ، 1 پولبک ، 2 رد
int LG_Decide(const int dir, double &origin, datetime &otime, double &px)
{
   px = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   LG_ClearNoteTexts();
   int fresh = 0;
   string src = "";
   g_lgDecPct = Leg_PullbackPct;
   bool dyn = false;
   if(!LG_FindOrigin(dir, origin, otime, fresh, src, dyn))
   {
      LG_SetNote(0, "ورود لگ: مبدأ لگ پیدا نشد (کندل کافی نیست) ← ورود فوری", clrSilver);
      g_lgDecMode = 0;
      return 0;
   }
   const double pip = LG_Pip();
   const bool behind = (dyn && (px - origin) * dir <= 0.0);   // «پشت مبدأ» فقط برای مبدأ پویا (کفِ واقعی)
   double ext = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   datetime etime = iTime(_Symbol, _Period, 0);
   if(!LG_SwingExtreme(dir, otime, ext, etime)) { ext = SymbolInfoDouble(_Symbol, SYMBOL_BID); etime = iTime(_Symbol, _Period, 0); }
   g_lgDecExt = ext;
   g_lgDecExtTime = etime;
   double legPips = (ext - origin) * dir / pip;
   if(legPips < 0.0) legPips = 0.0;
   const double refRange = LG_MedianRange();
   const double refPips = refRange / pip;
   const double legMult = (refRange > 0.0) ? (legPips / refPips) : 0.0;
   const bool big = (refRange > 0.0 && legMult >= Leg_BigRangeMult);
   double eff = 1.0, imb = 0.0;
   if(g_tick_analyzer_opt != NULL)
   {
      MarketStats ms = g_tick_analyzer_opt.GetMarketStats();
      eff = ms.efficiencyRatio;
      imb = ms.tickImbalance;
   }
   const bool strong = (eff >= Leg_MinEfficiency && dir * imb >= Leg_MinImbalance);
   const bool isFresh = (fresh <= Leg_FreshBars);

   int mode = 1;
   double pct = Leg_PullbackPct;
   string why = "";
   if(behind)                    { mode = 2; why = "قیمت پشت مبدأ لگ است؛ سیگنال رد شد"; }
   else if(big)                  { mode = 1; why = "لگ نسبت به نوسان بازار بزرگ است ← فقط پولبک"; }
   else if(strong && isFresh)    { mode = 0; why = "لگ کوچک + تیک قوی + سیگنال تازه ← ورود فوری"; }
   else if(strong || isFresh)    { mode = 1; why = "لگ کوچک ولی فقط یکی از (تیک قوی، تازگی) برقرار است ← پولبک"; }
   else                          { mode = 1; pct = Leg_Fib2Pct; why = "لگ کوچک، تیک ضعیف و سیگنال کهنه ← پولبک عمیق‌تر"; }
   g_lgDecMode = mode;
   g_lgDecPct = pct;

   const color cMain = (mode == 0) ? clrOrange : (mode == 1 ? clrDeepSkyBlue : clrTomato);
   LG_SetNote(0, StringFormat("1) لگ %s %.1f پیپ (از مبدأ تا %s) | مبدأ: %s", (dir > 0 ? "صعودی" : "نزولی"), legPips, (dir > 0 ? "سقف" : "کف"), src), clrSilver);
   LG_SetNote(1, StringFormat("2) لگ = %.1f برابر میانهٔ دامنهٔ %d کندل (%.1f پیپ) %s حد %.1f ← لگ %s", legMult, LG_RANGE_BARS, refPips,
                              (big ? ">=" : "<"), Leg_BigRangeMult, (big ? "بزرگ" : "کوچک")), clrSilver);
   LG_SetNote(2, StringFormat("3) کارایی تیک %.2f (حد %.2f) | عدم‌توازن %+.2f (حد %.2f) ← تیک %s | تازگی %d کندل (حد %d) ← %s",
                              eff, Leg_MinEfficiency, dir * imb, Leg_MinImbalance, (strong ? "قوی" : "ضعیف"),
                              fresh, Leg_FreshBars, (isFresh ? "تازه" : "کهنه")), clrSilver);
   LG_SetNote(3, "تصمیم: " + why + ((mode == 1) ? StringFormat(" (فیبو %.1f)", pct) : ""), cMain);
   return mode;
}

// سه شرطِ «مشکوک به تغییر روند» روی کندل‌های بسته
void LG_EvalChecks(bool &c1, bool &c2, bool &c3)
{
   c1 = false; c2 = false; c3 = false;
   const int sExt = iBarShift(_Symbol, _Period, g_lgExtremeTime, false);
   const int sOri = iBarShift(_Symbol, _Period, g_lgOriginTime, false);
   // ۱) قدرت بدنهٔ پولبک نسبت به بدنهٔ لگ
   if(sExt >= 0)
   {
      const int fromS = MathMax(sExt, 1);
      int toS = sExt + 7;
      if(sOri >= fromS && sOri < toS) toS = sOri;
      double legSum = 0.0, pbSum = 0.0;
      int legN = 0, pbN = 0;
      for(int s = fromS; s <= toS; s++) { legSum += MathAbs(iClose(_Symbol, _Period, s) - iOpen(_Symbol, _Period, s)); legN++; }
      for(int s = 1; s < sExt; s++)     { pbSum  += MathAbs(iClose(_Symbol, _Period, s) - iOpen(_Symbol, _Period, s)); pbN++; }
      if(legN > 0 && pbN > 0 && legSum > 0.0)
         c1 = ((pbSum / pbN) > LG_BODY_RATIO * (legSum / legN));
   }
   // ۲) تیکِ خلاف‌جهت قوی
   if(g_tick_analyzer_opt != NULL)
   {
      MarketStats ms = g_tick_analyzer_opt.GetMarketStats();
      c2 = (ms.efficiencyRatio >= MathMin(1.0, Leg_MinEfficiency * LG_OPP_MULT) && g_lgDir * ms.tickImbalance <= -MathMin(1.0, Leg_MinImbalance * LG_OPP_MULT));
   }
   // ۳) عمق: بستهٔ آخرین کندل بیش از LG_INVALID_PCT درصد لگ برگشته
   const double legsz = (g_lgExtreme - g_lgOrigin) * g_lgDir;
   if(legsz > 0.0)
   {
      const double depth = ((g_lgExtreme - iClose(_Symbol, _Period, 1)) * g_lgDir) / legsz;
      c3 = (depth > LG_INVALID_PCT / 100.0);
   }
}

void LG_Finish(const string reason, const bool entered)
{
   SystemLog("ورود لگ: " + (g_lgDir > 0 ? "خرید" : "فروش") + " — " + reason);
   LG_SetNote(5, (entered ? "نتیجه: ورود انجام شد — " : "نتیجه: ") + reason, (entered ? clrLime : clrTomato));
   g_lgDoneDir = g_lgDir;
   g_lgDoneBar = iTime(_Symbol, _Period, 0);
   LG_SetDisplay(g_lgDir, g_lgOrigin, g_lgOriginTime, g_lgExtreme, g_lgExtremeTime, g_lgPct);
   LG_Refresh(true, true);
   LG_Reset();
}

// از ExecuteTrade صدا زده می‌شود. true = سیگنال به‌جای اجرای فوری، مسلح (یا رد) شد
bool LG_Intercept(const int signal)
{
   if(!EnableLegEntry || g_lgFilling || signal == 0) return false;
   const int dir = (signal > 0) ? 1 : -1;
   const datetime bar0 = iTime(_Symbol, _Period, 0);

   if(g_lgState != 0 && g_lgDir == dir) { g_lastExecOK = true; return true; }      // همان جهت در انتظار است
   if(g_lgState == 0 && dir == g_lgDoneDir && g_lgDoneBar > 0)                      // همان سیگنالِ اجرا/لغو‌شده دوباره
   {
      const int since = iBarShift(_Symbol, _Period, g_lgDoneBar, false);
      if(since >= 0 && since <= LG_WAIT_BARS) { g_lastExecOK = true; return true; }
   }
   if(g_lgState != 0)
   {
      SystemLog("ورود لگ: سیگنال مخالف آمد؛ انتظار " + (g_lgDir > 0 ? "خرید" : "فروش") + " لغو و جایگزین شد");
      LG_Reset();
   }

   double origin = 0.0, px = 0.0;
   datetime otime = 0;
   const int mode = LG_Decide(dir, origin, otime, px);

   if(mode == 0)       // فوری: اجرا از مسیر معمولی
   {
      if(origin > 0.0)
      {
         LG_SetDisplay(dir, origin, otime, g_lgDecExt, g_lgDecExtTime, 0.0);
         LG_Refresh(true, false);
      }
      return false;
   }
   if(mode == 2)       // رد
   {
      g_lgDoneDir = dir;
      g_lgDoneBar = bar0;
      g_lastExecOK = true;
      LG_SetNote(5, "نتیجه: سیگنال بدون ورود رد شد", clrTomato);
      if(origin > 0.0) LG_SetDisplay(dir, origin, otime, g_lgDecExt, g_lgDecExtTime, 0.0);
      LG_Refresh(true, true);
      SystemLog("ورود لگ: " + (dir > 0 ? "خرید" : "فروش") + " رد شد — " + g_lgNote[3]);
      return true;
   }

   // پولبک: مسلح شدن
   g_lgState = 1;
   g_lgDir = dir;
   g_lgArmBar = bar0;
   g_lgOrigin = origin;
   g_lgOriginTime = otime;
   g_lgExtreme = g_lgDecExt;
   g_lgExtremeTime = g_lgDecExtTime;
   g_lgPct = g_lgDecPct;
   g_lgEvalFrom = 0;
   g_lgBoxActive = g_boxCtxActive;
   g_lgBoxTag = g_boxCtxTag;
   g_lgBoxTP = g_boxCtxTP;
   g_lgMask = Sug_CurrentMask();
   g_lastExecOK = true;                // سیگنال مصرف شد (مثلاً تحلیل باکس تکرار نشود)
   LG_SetDisplay(dir, origin, otime, g_lgExtreme, g_lgExtremeTime, g_lgPct);
   LG_Refresh(true, true);
   SystemLog(StringFormat("ورود لگ: %s مسلح شد؛ منتظر فیبو %.1f | مبدأ %s | %s", (dir > 0 ? "خرید" : "فروش"), g_lgPct,
             DoubleToString(origin, _Digits), g_lgNote[3]));
   return true;
}

// هر تیک (فقط وقتی معامله‌ی خودکار فعال است)
void LG_OnTick()
{
   if(!EnableLegEntry || g_lgState == 0) return;
   const datetime bar0 = iTime(_Symbol, _Period, 0);
   const int age = iBarShift(_Symbol, _Period, g_lgArmBar, false);
   if(age < 0 || age > LG_WAIT_BARS)
   {
      LG_SetNote(4, StringFormat("بعد از %d کندل پولبک کامل نشد", LG_WAIT_BARS), clrTomato);
      LG_Finish(StringFormat("بعد از %d کندل پر نشد و لغو شد", LG_WAIT_BARS), false);
      return;
   }
   if(HasOpenPosition())
   {
      LG_Finish("لغو شد؛ روی این نماد پوزیشن باز است", false);
      return;
   }
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0.0) return;

   // لگ باطل: بستهٔ کندل از مبدأ گذشت
   if(age >= 1)
   {
      const double c1 = iClose(_Symbol, _Period, 1);
      if((c1 - g_lgOrigin) * g_lgDir <= 0.0)
      {
         LG_Finish("کندل بسته از مبدأ لگ گذشت؛ لگ باطل شد", false);
         return;
      }
   }

   // قله/دره‌ی لگ فقط گسترش می‌یابد
   bool extended = false;
   if(g_lgDir > 0) { if(bid > g_lgExtreme) { g_lgExtreme = bid; extended = true; } }
   else            { if(bid < g_lgExtreme) { g_lgExtreme = bid; extended = true; } }
   if(extended)
   {
      g_lgExtremeTime = bar0;
      LG_SetDisplay(g_lgDir, g_lgOrigin, g_lgOriginTime, g_lgExtreme, g_lgExtremeTime, g_lgPct);
      LG_Refresh(false, false);
   }

   const double legsz = (g_lgExtreme - g_lgOrigin) * g_lgDir;
   if(legsz <= 0.0) return;
   const double lvl = g_lgExtreme - g_lgDir * (g_lgPct / 100.0) * legsz;

   if(g_lgState == 1)
   {
      if(!((g_lgDir > 0 && bid <= lvl) || (g_lgDir < 0 && bid >= lvl))) return;
      g_lgState = 2;
      g_lgEvalFrom = bar0;
      LG_SetNote(4, StringFormat("قیمت به فیبو %.1f رسید (%s)؛ تایید پولبک با بسته شدن این کندل", g_lgPct, DoubleToString(lvl, _Digits)), clrGold);
      LG_SetDisplay(g_lgDir, g_lgOrigin, g_lgOriginTime, g_lgExtreme, g_lgExtremeTime, g_lgPct);
      LG_Refresh(true, true);
      return;
   }

   // حالت ۲ یا ۳: ارزیابی با باز شدن کندل بعد از لمس/تاخیر
   if(bar0 <= g_lgEvalFrom) return;
   bool k1 = false, k2 = false, k3 = false;
   LG_EvalChecks(k1, k2, k3);
   const int n = (k1 ? 1 : 0) + (k2 ? 1 : 0) + (k3 ? 1 : 0);
   const double depthPct = (g_lgExtreme - iClose(_Symbol, _Period, 1)) * g_lgDir / legsz * 100.0;
   LG_SetNote(4, StringFormat("تایید پولبک: بدنه %s | تیک خلاف %s | عمق %.0f%% %s ← %d شرط مشکوک",
                              (k1 ? "مشکوک" : "سالم"), (k2 ? "مشکوک" : "سالم"), depthPct, (k3 ? "مشکوک" : "سالم"), n),
              (n == 0 ? clrLime : clrOrange));

   if(n >= 2 || (n >= 1 && g_lgState == 3))
   {
      LG_Finish(n >= 2 ? "پولبک رد شد: دو شرط یا بیشتر مشکوک به تغییر روند" : "پولبک رد شد: بعد از تاخیر یک کندل هنوز مشکوک است", false);
      return;
   }
   if(n == 1)
   {
      g_lgState = 3;
      g_lgEvalFrom = bar0;
      LG_SetNote(5, "یک شرط مشکوک: تاخیر یک کندل و بررسی دوباره", clrOrange);
      LG_Refresh(true, true);
      return;
   }

   // صفر شرط مشکوک ← ورود
   const bool   sA  = g_boxCtxActive;
   const string sT  = g_boxCtxTag;
   const double sP  = g_boxCtxTP;
   const int    dir = g_lgDir;
   const double lv0 = lvl;
   const int    age0 = age;
   g_boxCtxActive   = g_lgBoxActive;
   g_boxCtxTag      = g_lgBoxTag;
   g_boxCtxTP       = g_lgBoxTP;
   g_lgMaskOverride = g_lgMask;
   g_lgFilling      = true;
   ExecuteTrade(dir);
   g_lgFilling      = false;
   g_lgMaskOverride = 0;
   g_boxCtxActive   = sA;
   g_boxCtxTag      = sT;
   g_boxCtxTP       = sP;
   LG_Finish(StringFormat("پولبک تایید شد؛ ورود روی فیبو %.1f (%s) بعد از %d کندل", g_lgPct, DoubleToString(lv0, _Digits), age0), true);
}

// متن وضعیت برای پنل
string LG_StatusText(color &clr)
{
   if(g_lgState == 0) { clr = clrSilver; return "ورود لگ: منتظر سیگنالی نیست"; }
   const int age = iBarShift(_Symbol, _Period, g_lgArmBar, false);
   clr = clrGold;
   string st = "منتظر رسیدن به فیبو";
   if(g_lgState == 2) st = "فیبو لمس شد؛ منتظر بسته شدن کندل تایید";
   if(g_lgState == 3) st = "تاخیر یک کندل؛ بررسی دوباره";
   return StringFormat("ورود لگ: %s | %s %.1f (%d/%d کندل)", (g_lgDir > 0 ? "خرید" : "فروش"), st, g_lgPct, MathMax(0, age), LG_WAIT_BARS);
}

// خط‌های توضیح تصمیم برای پنل؛ k = 0..5 ؛ رشتهٔ خالی = چیزی نمایش داده نشود
string LG_DetailText(const int k, color &clr)
{
   clr = clrSilver;
   if(!ShowEntryDecisionDetails || k < 0 || k >= 6) return "";
   clr = g_lgNoteClr[k];
   return g_lgNote[k];
}

//+------------------------------------------------------------------+
//| DISPLAY FIB (v178.3): «فیبو نمایش» — فقط نمایش؛ در هیچ محاسبه یا    |
//| تصمیمی شرکت ندارد. ۱۰۰ = شروع موج ، ۰ = انتهای موج.                |
//| موج = لگ فعلی (مبدأ پویا با تنکن ۹ تا قله/دره). با ساخته شدن لگ جدید |
//| (عبور بستهٔ کندل از تنکن ۹ به سمت مخالف) روی لگ جدید می‌نشیند.       |
//| دستی: دو خط ۰ و ۱۰۰ (افقی، قابل کشیدن) را کاربر روی چارت جابه‌جا     |
//| می‌کند؛ بقیهٔ سطح‌ها خودکار دنبالشان می‌آیند و تا زدن دکمهٔ         |
//| SHOW/HIDE حالت دستی می‌ماند (با زدن دکمه به حالت خودکار برمی‌گردد).  |
//| وضعیت دکمه و شیءها با تعویض تایم‌فریم تغییر نمی‌کنند.               |
//| برای حذف: این بلوک و خطوطِ دارای برچسب «DISPLAY FIB».               |
//+------------------------------------------------------------------+
#define DF_PREFIX "LGD_"

int      g_dfDir          = 0;       // جهت لگ نمایش: +1 صعودی، -1 نزولی، 0 = هنوز رسم نشده
double   g_dfOrigin       = 0.0;     // شروع موج (۱۰۰)
datetime g_dfOriginTime   = 0;
double   g_dfExtreme      = 0.0;     // انتهای موج (۰)
datetime g_dfExtremeTime  = 0;
datetime g_dfLastBar      = 0;
bool     g_dfFrozen       = false;   // شیءهای تایم‌فریم قبلی: تا ساخته شدن لگ جدید دست نمی‌خورند
int      g_dfBaseDir      = 0;       // جهت لگِ لحظهٔ تعویض تایم‌فریم
bool     g_dfManual       = false;   // کاربر ۰ یا ۱۰۰ را دستی جابه‌جا کرده

string DF_StateKey()  { return "EA_DispFib_" + _Symbol; }          // عمداً بدون تایم‌فریم
string DF_ManualKey() { return "EA_DispFibManual_" + _Symbol; }

void DF_Clear() { ObjectsDeleteAll(0, DF_PREFIX); }

// لگ فعلی: جهت = سمت بستهٔ آخرین کندل نسبت به تنکن ۹ ؛ مبدأ = کف/سقف تا اولین کندلِ سمت اشتباه
bool DF_ComputeLeg(int &dir, double &origin, datetime &otime, double &ext, datetime &etime)
{
   const int bars = Bars(_Symbol, _Period);
   const int maxBars = MathMin(LG_MAX_ORIGIN_BARS, bars - 12);
   if(maxBars < 3) return false;
   const double t1 = LG_Tenkan(1);
   const double c1 = iClose(_Symbol, _Period, 1);
   if(t1 <= 0.0 || c1 == t1) return false;
   dir = (c1 > t1) ? 1 : -1;
   int wrong = -1;
   for(int k = 1; k <= maxBars; k++)
   {
      const double tk = LG_Tenkan(k);
      if(tk <= 0.0) break;
      const double c = iClose(_Symbol, _Period, k);
      if((dir > 0 && c < tk) || (dir < 0 && c > tk)) { wrong = k; break; }
   }
   const int cnt = (wrong > 0) ? wrong : maxBars;
   const int idx = (dir > 0) ? iLowest(_Symbol, _Period, MODE_LOW, cnt, 1) : iHighest(_Symbol, _Period, MODE_HIGH, cnt, 1);
   if(idx < 0) return false;
   origin = (dir > 0) ? iLow(_Symbol, _Period, idx) : iHigh(_Symbol, _Period, idx);
   otime = iTime(_Symbol, _Period, idx);
   return LG_SwingExtreme(dir, otime, ext, etime);
}

// ساخت یا به‌روزرسانی در جا (تا شیءِ در حال کشیدن/انتخاب‌شده از بین نرود)
void DF_PutHLine(const string name, const double price, const color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_HLINE, 0, 0, price)) return;
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, "فیبو نمایش: برای تنظیم دستی دوبار کلیک و بکشید");
   }
   else ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
}

void DF_PutTrend(const string name, const datetime t1, const double p1, const datetime t2, const double p2,
                 const color clr, const ENUM_LINE_STYLE style)
{
   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2)) return;
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, _Symbol);   // برای تشخیص نماد هنگام راه‌اندازی دوباره
   }
   else
   {
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
   }
}

void DF_PutText(const string name, const datetime t, const double p, const string text, const color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, p)) return;
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   else ObjectMove(0, name, 0, t, p);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

// skip = نام خطی که کاربر همین الان کشیده (دست نمی‌خورد)
void DF_Draw(const string skip = "")
{
   if(!g_dfShow || g_dfDir == 0) { DF_Clear(); return; }
   const double legsz = (g_dfExtreme - g_dfOrigin) * g_dfDir;
   if(legsz <= 0.0 || g_dfOriginTime == 0 || g_dfExtremeTime == 0) { DF_Clear(); return; }
   const datetime t0 = iTime(_Symbol, _Period, 0);
   if(t0 == 0) return;
   const datetime tE = t0 + (datetime)(PeriodSeconds() * 8);

   DF_PutTrend(DF_PREFIX + "LEG", g_dfOriginTime, g_dfOrigin, g_dfExtremeTime, g_dfExtreme, clrAqua, STYLE_SOLID);

   double pcts[7] = {0.0, 23.6, 38.2, 50.0, 61.8, 78.6, 100.0};
   for(int k = 0; k < 7; k++)
   {
      const double lv = g_dfExtreme - g_dfDir * (pcts[k] / 100.0) * legsz;   // ۰ روی انتهای موج، ۱۰۰ روی شروع موج
      const bool edge = (k == 0 || k == 6);
      const color c = edge ? clrAqua : clrMediumPurple;
      const string ln = DF_PREFIX + "L" + IntegerToString(k);
      if(edge) { if(ln != skip) DF_PutHLine(ln, lv, c); }
      else DF_PutTrend(ln, g_dfOriginTime, lv, tE, lv, c, STYLE_DOT);
      string lbl = StringFormat("%.1f  %s", pcts[k], DoubleToString(lv, _Digits));
      if(k == 0) lbl += "  (انتهای موج)";
      if(k == 6) lbl += "  (شروع موج)";
      DF_PutText(DF_PREFIX + "T" + IntegerToString(k), tE, lv, lbl, c);
   }
}

void DF_Refresh(const bool force)
{
   static uint s_lastMs = 0;
   const uint nowMs = GetTickCount();
   if(!force && (nowMs - s_lastMs) < 400) return;
   s_lastMs = nowMs;
   DF_Draw();
   ChartRedraw(0);
}

// قیمت دو خط ۰ و ۱۰۰ و زمان‌ها را از خود شیءهای روی چارت می‌خواند (بعد از تعویض تایم یا ری‌استارت)
bool DF_LoadFromObjects()
{
   const string n0 = DF_PREFIX + "L0";
   const string n6 = DF_PREFIX + "L6";
   if(ObjectFind(0, n0) < 0 || ObjectFind(0, n6) < 0 || ObjectFind(0, DF_PREFIX + "LEG") < 0) return false;
   const double p0 = ObjectGetDouble(0, n0, OBJPROP_PRICE, 0);
   const double p6 = ObjectGetDouble(0, n6, OBJPROP_PRICE, 0);
   if(p0 == p6) return false;
   g_dfExtreme = p0;
   g_dfOrigin = p6;
   g_dfDir = (p0 > p6) ? 1 : -1;
   g_dfOriginTime = (datetime)ObjectGetInteger(0, DF_PREFIX + "LEG", OBJPROP_TIME, 0);
   g_dfExtremeTime = (datetime)ObjectGetInteger(0, DF_PREFIX + "LEG", OBJPROP_TIME, 1);
   return (g_dfOriginTime > 0 && g_dfExtremeTime > 0);
}

// کاربر یکی از دو خط ۰ یا ۱۰۰ را کشید ← حالت دستی؛ بقیهٔ سطح‌ها دنبالش می‌آیند
void DF_OnDrag(const string name)
{
   if(!g_dfShow) return;
   if(!DF_LoadFromObjects()) return;
   g_dfManual = true;
   GlobalVariableSet(DF_ManualKey(), 1.0);
   DF_Draw(name);
   ChartRedraw(0);
}

// هر تیک
void DF_OnTick()
{
   if(!g_dfShow || g_dfManual) return;
   const datetime bar0 = iTime(_Symbol, _Period, 0);
   if(bar0 == 0) return;
   if(bar0 != g_dfLastBar)
   {
      int dir = 0;
      double org = 0.0, ext = 0.0;
      datetime ot = 0, et = 0;
      if(!DF_ComputeLeg(dir, org, ot, ext, et)) return;
      g_dfLastBar = bar0;
      if(g_dfFrozen)
      {
         if(g_dfBaseDir == 0) { g_dfBaseDir = dir; return; }   // جهت لگِ لحظهٔ تعویض تایم‌فریم
         if(dir == g_dfBaseDir) return;                         // هنوز همان لگ؛ شیءهای قبلی دست نمی‌خورند
         g_dfFrozen = false;                                    // لگ جدید ساخته شد
      }
      if(dir != g_dfDir)                                        // لگ جدید ← فیبو روی لگ جدید
      {
         g_dfDir = dir;
         g_dfOrigin = org;
         g_dfOriginTime = ot;
         g_dfExtreme = ext;
         g_dfExtremeTime = et;
         DF_Refresh(true);
         return;
      }
   }
   if(g_dfFrozen || g_dfDir == 0) return;
   // گسترش انتهای موج
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0.0) return;
   if((g_dfDir > 0 && bid > g_dfExtreme) || (g_dfDir < 0 && bid < g_dfExtreme))
   {
      g_dfExtreme = bid;
      g_dfExtremeTime = bar0;
      DF_Refresh(false);
   }
}

// راه‌اندازی: وضعیت دکمه و حالت دستی از آخرین انتخاب کاربر (مستقل از تایم‌فریم)؛ شیءهای موجود همان نماد دست‌نخورده می‌مانند
void DF_Init()
{
   g_dfShow = ShowDisplayFib;
   if(GlobalVariableCheck(DF_StateKey())) g_dfShow = (GlobalVariableGet(DF_StateKey()) > 0.5);
   GlobalVariableSet(DF_StateKey(), g_dfShow ? 1.0 : 0.0);
   g_dfManual = (g_dfShow && GlobalVariableCheck(DF_ManualKey()) && GlobalVariableGet(DF_ManualKey()) > 0.5);
   g_dfDir = 0;
   g_dfLastBar = 0;
   g_dfFrozen = false;
   g_dfBaseDir = 0;
   if(ObjectFind(0, DF_PREFIX + "LEG") >= 0)
   {
      if(g_dfShow && ObjectGetString(0, DF_PREFIX + "LEG", OBJPROP_TOOLTIP) == _Symbol) g_dfFrozen = true;
      else { DF_Clear(); g_dfManual = false; }
   }
   else g_dfManual = false;
}

void DF_Deinit(const int reason)
{
   if(reason == REASON_REMOVE)
   {
      DF_Clear();
      GlobalVariableDel(DF_StateKey());
      GlobalVariableDel(DF_ManualKey());
   }
}

string Sug_Dir(int d) { return (d == 0) ? "B" : "S"; }
string Sug_GV(string field) { return "WD_S_" + _Symbol + "_" + field; }
string Sug_GVD(int d, string field) { return "WD_S_" + _Symbol + "_" + Sug_Dir(d) + "_" + field; }
int    Sug_Bit(int code) { return (code >= 0 && code < 30) ? (1 << code) : 0; }
string Sug_MethodName(int code) {
   switch(code) {
      case 1:  return "کراس معمولی";
      case 2:  return "کراس پویا";
      case 3:  return "رودکراس موازی قوی";
      case 4:  return "رودکراس ادامه‌دار";
      case 5:  return "میانگین متحرک اندیکاتور";
      case 6:  return "موازی قوی";
      case 11: return "باکس سیستم اول";
      case 12: return "باکس سیستم دوم";
      case 13: return "شکست باکس سیستم اول";
      case 14: return "شکست باکس سیستم دوم";
      case 21: return "Ma Angle";
      case 22: return "امتیاز ترکیبی";
   }
   return "نامشخص";
}
string Sug_MaskNames(int mask) {
   string s = "";
   int codes[13] = {1, 2, 3, 4, 5, 6, 11, 12, 13, 14, 21, 22, 9};
   for(int k = 0; k < 13; k++) {
      if((mask & (1 << codes[k])) != 0) {
         if(s != "") s += " / ";
         s += Sug_MethodName(codes[k]);
      }
   }
   return (s == "") ? "نامشخص" : s;
}

// کد روش‌ها: ۱ کراس معمولی، ۲ کراس پویا، ۳ رودکراس موازی قوی، ۴ رودکراس ادامه‌دار، ۵ میانگین اندیکاتور،
// ۶ موازی قوی، ۱۱ و ۱۲ باکس سیستم اول و دوم، ۱۳ و ۱۴ شکست باکس سیستم اول و دوم، ۲۲ ماشهٔ ترکیبی، ۹ نامشخص
int Sug_CurrentMask() {
   if(g_lgMaskOverride != 0) return g_lgMaskOverride;   // LEG v178.0
   if(g_boxCtxActive) {
      if(g_boxCtxTag == "K2") return Sug_Bit(14);   // BOXBREAK: شکست باکس سیستم دوم
      if(g_boxCtxTag == "K1") return Sug_Bit(13);   // BOXBREAK: شکست باکس سیستم اول
      return Sug_Bit((g_boxCtxTag == "B2") ? 12 : 11);
   }
   if(SignalSource == SIGNAL_COMPOSITE_SCORE)   return Sug_Bit(22);
   string nm = StringFormat("DualIchimokuMask_%s_%d", _Symbol, _Period);
   if(GlobalVariableCheck(nm)) {
      int m = (int)GlobalVariableGet(nm);
      if(m != 0) return m;
   }
   string nc = StringFormat("DualIchimokuMethod_%s_%d", _Symbol, _Period);
   return Sug_Bit(GlobalVariableCheck(nc) ? (int)GlobalVariableGet(nc) : 9);
}

// اولین لحظه‌ای که اندیکاتور سیگنال را صادر کرد (زمان و قیمت)
bool Sug_IndicatorEntry(datetime &t, double &p) {
   string nt = StringFormat("DualIchimokuSigTime_%s_%d",  _Symbol, _Period);
   string np = StringFormat("DualIchimokuSigPrice_%s_%d", _Symbol, _Period);
   if(!GlobalVariableCheck(nt) || !GlobalVariableCheck(np)) return false;
   t = (datetime)(long)GlobalVariableGet(nt);
   p = GlobalVariableGet(np);
   return (t > 0 && p > 0.0);
}

// فلش پیشنهاد: خرید = فلش سبز رو به بالا زیر کندلِ پیشنهاد (نوک روی کف کندل)،
// فروش = فلش قرمز رو به پایین بالای کندلِ پیشنهاد (نوک روی سقف کندل)
void Sug_DrawArrow(int d) {
   string name = (d == 0) ? "SUG_ARW_B" : "SUG_ARW_S";
   if(!ShowSuggestionObjects || g_sugMask[d] == 0) {
      ObjectDelete(0, name);
      return;
   }
   int shift = iBarShift(_Symbol, _Period, g_sugStart[d], false);
   if(shift < 0) {
      ObjectDelete(0, name);
      return;
   }
   datetime bt = iTime(_Symbol, _Period, shift);
   if(bt == 0) {
      ObjectDelete(0, name);
      return;
   }
   double gap = GetPip();   // فاصلهٔ کوچک تا نوک فلش به سایهٔ کندل نچسبد
   double price = (d == 0) ? iLow(_Symbol, _Period, shift) - gap : iHigh(_Symbol, _Period, shift) + gap;
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, (d == 0) ? OBJ_ARROW_UP : OBJ_ARROW_DOWN, 0, bt, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, (long)bt);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, (d == 0) ? clrLime : clrRed);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 4);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, (d == 0) ? ANCHOR_TOP : ANCHOR_BOTTOM);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ChartRedraw(0);
}

void Sug_Write(int d) {
   GlobalVariableSet(Sug_GVD(d, "START"), (double)g_sugStart[d]);
   GlobalVariableSet(Sug_GVD(d, "ENTRY"), g_sugEntryP[d]);
   GlobalVariableSet(Sug_GVD(d, "TP"),    g_sugTP[d]);
   GlobalVariableSet(Sug_GVD(d, "MASK"),  (double)g_sugMask[d]);   // آخر نوشته می‌شود تا خواننده داده کامل ببیند
   Sug_DrawArrow(d);
}

void Sug_Clear(int d) {
   g_sugMask[d] = 0;
   g_sugStart[d] = 0;
   GlobalVariableSet(Sug_GVD(d, "MASK"), 0.0);
   Sug_DrawArrow(d);
}

// سیگنالی که از همهٔ فیلترهای روشن گذشته به این‌جا می‌رسد
void Sug_Publish(int signal) {
   int d = (signal > 0) ? 0 : 1;
   int o = 1 - d;
   int bits = Sug_CurrentMask();
   if(bits == 0) return;
   datetime now = TimeCurrent();
   long validSec = (long)SUGGESTION_VALID_MIN * 60;

   // هر روشی که اکنون در جهت مخالف سیگنال داد از جهت قبلی‌اش کنار می‌رود
   if(g_sugMask[o] != 0) {
      g_sugMask[o] &= ~bits;
      if(g_sugMask[o] == 0) Sug_Clear(o); else Sug_Write(o);
   }
   // پیشنهاد منقضی‌شدهٔ همین جهت پاک شود تا این سیگنال، پیشنهاد تازه بسازد
   if(g_sugMask[d] != 0 && (now - g_sugStart[d]) >= validSec) Sug_Clear(d);

   double price = (signal > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(g_sugMask[d] == 0) {   // پیشنهاد تازه: نقطه در اولین لحظهٔ سیگنال
      datetime et = now;
      double ep = price;
      if(!g_boxCtxActive && SignalSource == SIGNAL_EXTERNAL_INDICATOR && !g_lgFilling) {   // LEG v178.0: در پولبک، قیمت ورودِ واقعی
         datetime it = 0;
         double ip = 0.0;
         if(Sug_IndicatorEntry(it, ip) && it <= now && (now - it) < validSec) { et = it; ep = ip; }
      }
      g_sugStart[d] = et;
      g_sugEntryP[d] = ep;
   }
   const int sugMaskBefore = g_sugMask[d];
   g_sugMask[d] |= bits;

   double pip = GetPip();
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double tp = (signal > 0) ? price + TakeProfit * pip : price - TakeProfit * pip;
   // v177.0: حد سود باکس = حد سود منوی اکسپرت (هدف باکس استفاده نمی‌شود)
   g_sugTP[d] = NormalizeDouble(tp, digits);
   Sug_Write(d);
   if(sugMaskBefore != g_sugMask[d]) {   // پیشنهاد تازه یا روشِ تازه به پیشنهاد اضافه شد
      g_lastSugTime = TimeCurrent();
      g_lastSugDir  = signal;
      g_lastSugMask = g_sugMask[d];
      SystemLog("پیشنهاد ارسال شد: " + (signal > 0 ? "خرید" : "فروش") + " | روش‌ها: " + Sug_MaskNames(g_sugMask[d]) + " | از همهٔ فیلترها گذشت");
   }
}

void Sug_Housekeeping() {
   static datetime lastRun = 0;
   datetime now = TimeCurrent();
   if(now == lastRun) return;
   lastRun = now;
   long validSec = (long)SUGGESTION_VALID_MIN * 60;
   for(int d = 0; d < 2; d++) {
      if(g_sugMask[d] != 0 && (now - g_sugStart[d]) >= validSec) Sug_Clear(d);
      else if(g_sugMask[d] != 0) Sug_DrawArrow(d);   // فلش با سقف/کف کندلِ در حال تشکیل هم‌گام می‌ماند
   }
   if(SuggestionOnlyMode) GlobalVariableSet(Sug_GV("MGMT"), managementPaused ? 0.0 : 1.0);
}

void Sug_Startup() {
   if(!SuggestionOnlyMode) return;
   // نقطه‌های نسخه‌های قبلی (اگر روی چارت مانده‌اند) پاک شوند
   ObjectDelete(0, "SUG_DOT_B");
   ObjectDelete(0, "SUG_DOT_S");
   // متغیرهای نسخهٔ قبلی پاک شوند
   string old[6] = {"DIR", "ENTRY", "SL", "TP", "MTH", "TIME"};
   for(int i = 0; i < 6; i++) GlobalVariableDel(Sug_GV(old[i]));
   long validSec = (long)SUGGESTION_VALID_MIN * 60;
   datetime now = TimeCurrent();
   for(int d = 0; d < 2; d++) {
      g_sugMask[d] = 0; g_sugStart[d] = 0; g_sugEntryP[d] = 0.0; g_sugTP[d] = 0.0;
      string nm = Sug_GVD(d, "MASK");
      if(GlobalVariableCheck(nm)) {
         int m = (int)GlobalVariableGet(nm);
         datetime st = (datetime)(long)GlobalVariableGet(Sug_GVD(d, "START"));
         if(m != 0 && st > 0 && st <= now && (now - st) < validSec) {   // هنوز معتبر است؛ برمی‌گردد
            g_sugMask[d] = m;
            g_sugStart[d] = st;
            g_sugEntryP[d] = GlobalVariableGet(Sug_GVD(d, "ENTRY"));
            g_sugTP[d] = GlobalVariableGet(Sug_GVD(d, "TP"));
            Sug_DrawArrow(d);
            continue;
         }
      }
      GlobalVariableSet(nm, 0.0);
      Sug_DrawArrow(d);
   }
   GlobalVariableSet(Sug_GV("MAGIC"), (double)EA_MAGIC_NUMBER);
   GlobalVariableSet(Sug_GV("TF"),    (double)_Period);
   GlobalVariableSet(Sug_GV("TPP"),   TakeProfit);
   GlobalVariableSet(Sug_GV("MGMT"),  managementPaused ? 0.0 : 1.0);
}

void Sug_Shutdown() {
   ObjectDelete(0, "SUG_ARW_B");
   ObjectDelete(0, "SUG_ARW_S");
   if(SuggestionOnlyMode) {
      GlobalVariableSet(Sug_GVD(0, "MASK"), 0.0);
      GlobalVariableSet(Sug_GVD(1, "MASK"), 0.0);
   }
}

// تغییر تایم‌فریم یا نماد: پیشنهاد باید بماند؛ فقط با حذف یا بستن اکسپرت پاک می‌شود
void Sug_OnDeinit(int reason) {
   if(reason == REASON_CHARTCHANGE) return;
   Sug_Shutdown();
}

//+------------------------------------------------------------------+
//| Execute Trade Function                                           |
//+------------------------------------------------------------------+
void ExecuteTrade(int signal) {
   if(HasOpenPosition()) {   // ONETRADE v177.0: روی این نماد پوزیشن باز است (اکسپرت یا دستی) → معامله/پیشنهاد دوم نه
      g_lastExecOK = false;
      lastTradeFailureReason = "One trade per symbol: a position is already open";
      return;
   }
   if(LG_Intercept(signal)) return;   // LEG v178.0: فوری یا مسلح شدن برای پولبک روی فیبوناچی
   if(SuggestionOnlyMode) {   // v173: فقط پیشنهاد؛ معامله باز نمی‌شود
      Sug_Publish(signal);
      g_lastExecOK = true;    // تحلیل باکس مصرف شود تا تکرار نشود
      return;
   }
   double lot = CalculateLotSize();
   double price = (signal > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double pip = GetPip();
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   double slDist = StopLoss;
   double tpDist = TakeProfit;
   
   double sl = (signal > 0) ? price - slDist * pip : price + slDist * pip;
   double tp = (signal > 0) ? price + tpDist * pip : price - tpDist * pip;
   
   sl = NormalizeDouble(sl, digits);
   // v177.0: حد سود باکس = حد سود منوی اکسپرت (هدف باکس استفاده نمی‌شود)
   tp = NormalizeDouble(tp, digits);
   
   bool success = false;
   string cmt = g_boxCtxActive ? ("EA_ADAPTIVE_FILTER_ENHANCED|" + g_boxCtxTag) : "EA_ADAPTIVE_FILTER_ENHANCED";
   if(signal > 0) {
      success = trade.Buy(lot, _Symbol, price, sl, tp, cmt);
   } else {
      success = trade.Sell(lot, _Symbol, price, sl, tp, cmt);
   }

   g_lastExecOK = success;
   if(success) {
      string msg = StringFormat("✅ %s ORDER EXECUTED: Lot=%.2f, Price=%.5f, SL=%.5f, TP=%.5f", 
                               (signal > 0 ? "BUY" : "SELL"), lot, price, sl, tp);
           
      lastTradeFailureReason = "";
      pauseBarsCounter = 0;
      
   } else {
      lastTradeFailureReason = StringFormat("Trade execution failed: Error=%d", GetLastError());
    if(DebugLogEnable) {  ErrorLog(lastTradeFailureReason);  }} }

struct PostEntryTicketState {
    ulong    ticket;
    double   adverseSeconds;
    int      tightenCount;
    datetime lastUpdate;
    datetime lastActionTime;
    string   lastReason;   // v146: for panel readability - why adverseSeconds is climbing right now
    bool     lastActionSucceeded;  // v149 fix #2: did the LAST attempted modify/close actually go through?
    datetime lastSuccessTime;      // v149 fix #2: when that last real success happened
};

PostEntryTicketState g_postEntryStates[];

double g_postEntry_thresholdSeconds = 0.0;
double g_postEntry_est_tps = 0.0;

int FindPostEntryState(ulong ticket) {
    for(int i = 0; i < ArraySize(g_postEntryStates); i++)
        if(g_postEntryStates[i].ticket == ticket) return i;
    return -1;
}

void CleanupClosedPostEntryStates() {
    for(int i = ArraySize(g_postEntryStates) - 1; i >= 0; i--) {
        if(!PositionSelectByTicket(g_postEntryStates[i].ticket)) {
            ArrayRemove(g_postEntryStates, i, 1);
        }
    }
}

void MonitorPostEntryRegime() {
    if(!EnablePostEntryRegimeMonitor) return;
    if(g_tick_analyzer_opt == NULL) return;

    string regime_v30  = g_tick_analyzer_opt.GetMarketRegimeText();
    MarketStats st = g_tick_analyzer_opt.GetMarketStats();

    datetime now = TimeCurrent();

       const double BASE_DECAY_PER_SECOND = 0.8;   // how fast adverseSeconds decays when favorable

    const int    MAX_TIGHTEN_STEPS      = 4;    // safety cap
    const double MIN_TPS               = 0.05; // minimum ticks-per-second to avoid divide-by-zero

    double est_tps = 1.0;
    {
        int newestIdx = (bufferIndex - 1 + MAX_HISTORY) % MAX_HISTORY;
        int oldestIdx = -1, sampleCount = 0;
        for(int k = 0; k < 30; k++) {
            int idx = (bufferIndex - k - 1 + MAX_HISTORY) % MAX_HISTORY;
            if(tickPriceBuffer[idx] <= 0) break;
            oldestIdx = idx;
            sampleCount++;
        }
        if(sampleCount >= 2 && tickPriceBuffer[newestIdx] > 0 && oldestIdx >= 0) {
            double dtSpan = (double)(tickTimeBuffer[newestIdx] - tickTimeBuffer[oldestIdx]);
            if(dtSpan > 0.5) est_tps = (sampleCount - 1) / dtSpan;
        }
    }
    est_tps = MathMax(est_tps, MIN_TPS);

     double thresholdSeconds = (double)GetPostEntryEffectiveTicks() / est_tps;
    thresholdSeconds = MathMax(0.5, MathMin(60.0, thresholdSeconds)); // sane bounds
    g_postEntry_thresholdSeconds = thresholdSeconds;  // v146: expose real value to the panel
    g_postEntry_est_tps = est_tps;

    int total = PositionsTotal();
    for(int i = 0; i < total; i++) {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0 || !PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

        long type = PositionGetInteger(POSITION_TYPE);
        double dirScore = st.directionScore;
        
        bool directionReversed = st.directionPersistOK &&
                                 ((type == POSITION_TYPE_BUY  && dirScore < -RegimeNoisyOverrideScore) ||
                                  (type == POSITION_TYPE_SELL && dirScore >  RegimeNoisyOverrideScore));

        bool regimeAdverse = (regime_v30 == "NOISY_MARKET" || regime_v30 == "TOO_FAST");
        bool adverseNow = regimeAdverse || directionReversed;

        int idx = FindPostEntryState(ticket);
        if(idx < 0) {
            int n = ArraySize(g_postEntryStates);
            ArrayResize(g_postEntryStates, n + 1);
            g_postEntryStates[n].ticket = ticket;
            g_postEntryStates[n].adverseSeconds = 0.0;
            g_postEntryStates[n].tightenCount = 0;
            g_postEntryStates[n].lastUpdate = now;
            g_postEntryStates[n].lastActionTime = 0;
            g_postEntryStates[n].lastReason = "";
            g_postEntryStates[n].lastActionSucceeded = false;
            g_postEntryStates[n].lastSuccessTime = 0;
            idx = n;
        }

        double dt = (double)(now - g_postEntryStates[idx].lastUpdate);
        if(dt < 0) dt = 0;
        g_postEntryStates[idx].lastUpdate = now;

        if(adverseNow) {
            g_postEntryStates[idx].adverseSeconds += dt;
            // v146: record WHY it's climbing, so the panel can say something meaningful
            if(regimeAdverse && directionReversed) g_postEntryStates[idx].lastReason = "رژیم نامناسب + برگشت جهت";
            else if(regimeAdverse)                 g_postEntryStates[idx].lastReason = "رژیم پرنویز/سریع";
            else                                   g_postEntryStates[idx].lastReason = "برگشت جهت (پایدار)";
        } else {
            g_postEntryStates[idx].adverseSeconds = MathMax(0.0, g_postEntryStates[idx].adverseSeconds - BASE_DECAY_PER_SECOND * dt);
            if(g_postEntryStates[idx].adverseSeconds <= 0.0001) g_postEntryStates[idx].lastReason = "";
        }

        bool cooldownOk = (g_postEntryStates[idx].lastActionTime == 0) || ((now - g_postEntryStates[idx].lastActionTime) >= POSTENTRY_COOLDOWN_SECONDS);

        if(g_postEntryStates[idx].adverseSeconds >= thresholdSeconds && cooldownOk) {
            g_postEntryStates[idx].adverseSeconds = 0.0;
            g_postEntryStates[idx].lastActionTime = now;
            g_postEntryStates[idx].lastActionSucceeded = false;   // v149 fix #2: default to "nothing really happened" this attempt

            if(GetPostEntryEffectiveClose()) {
                if(trade.PositionClose(ticket)) {
                    g_postEntryStates[idx].lastActionSucceeded = true;
                    g_postEntryStates[idx].lastSuccessTime = now;
                    if(DebugLogEnable) Print("PostEntry: closed ticket ", ticket, " due to adverse regime/time-based detection");
                } else {
                    if(DebugLogEnable) ErrorLog("PostEntry: failed to close ticket " + string(ticket) + " err=" + string(GetLastError()));
                }
            } else {
              
                int prospectiveStep = MathMin(g_postEntryStates[idx].tightenCount + 1, MAX_TIGHTEN_STEPS);

                double pip = GetPip();
                int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
                double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                double currentSL = PositionGetDouble(POSITION_SL);
                double currentTP = PositionGetDouble(POSITION_TP);

                double atrFloorPips = GetTrailATR_Pips() * 0.3;
                double bufferPips = MathMax(PostEntry_TightenBufferPip, atrFloorPips);
                double buffer = bufferPips * pip * prospectiveStep;
                double tightSL = (type == POSITION_TYPE_BUY) ? NormalizeDouble(openPrice + buffer, digits)
                                                              : NormalizeDouble(openPrice - buffer, digits);
                bool better = (type == POSITION_TYPE_BUY) ? (tightSL > currentSL || currentSL == 0)
                                                          : (tightSL < currentSL || currentSL == 0);
                if(better) {
                    if(trade.PositionModify(ticket, tightSL, currentTP)) {
                        g_postEntryStates[idx].tightenCount = prospectiveStep;
                        g_postEntryStates[idx].lastActionSucceeded = true;
                        g_postEntryStates[idx].lastSuccessTime = now;
                    } else {
                        if(DebugLogEnable) ErrorLog("PostEntry: failed to tighten SL for ticket " + string(ticket) + " err=" + string(GetLastError()));
                    }
                }
            }
        }
    }

    CleanupClosedPostEntryStates();
}



//--------------------------------------
void UpdateTrailingStop() {
   if(TrailingMode == TRAIL_DISABLED) return;
   
   int total = PositionsTotal();
   if(total <= 0) return;
   
   for(int i = 0; i < total; i++) {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket)) {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol) {
            ProcessTrailingForPosition(ticket);   }}}}
  
void ProcessTrailingForPosition(ulong ticket) {
   if(!PositionSelectByTicket(ticket)) return;
   
   long type = PositionGetInteger(POSITION_TYPE);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   double currentPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double pip = GetPip();
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double profitPips = 0;
   if(type == POSITION_TYPE_BUY) {
      profitPips = (currentPrice - openPrice) / pip;
   } else {
      profitPips = (openPrice - currentPrice) / pip;    }
 
   double newSL = currentSL;
   bool modifyNeeded = false;
  
   bool riskFreeActive = (TrailingMode == TRAIL_RISKFREE_STEP || TrailingMode == TRAIL_MA_RISKFREE);
   if(riskFreeActive && profitPips >= RiskFreeStart) {
      double buffer = RiskFreeBufferPip * pip;
      double rfSL = (type == POSITION_TYPE_BUY) ? NormalizeDouble(openPrice + buffer, digits)
                                                  : NormalizeDouble(openPrice - buffer, digits);
      bool rfBetter = (type == POSITION_TYPE_BUY) ? (rfSL > newSL || newSL == 0)
                                                    : (rfSL < newSL || newSL == 0);
      if(rfBetter) { newSL = rfSL; modifyNeeded = true; }
   }
 
   if(TrailingMode != TRAIL_DISABLED && TrailingMode != TRAIL_ADVANCED_ATR && TrailingMode != TRAIL_ATR_STEP
      && TrailingMode != TRAIL_HYBRID_ALL && TrailingMode != TRAIL_MA && TrailingMode != TRAIL_MA_RISKFREE
      && profitPips >= TrailingStart) {
      switch(TrailingMode) {
         case TRAIL_STEP:
         case TRAIL_RISKFREE_STEP: {
            double stepSL = (type == POSITION_TYPE_BUY) ? NormalizeDouble(currentPrice - TrailingStep * pip, digits)
                                                          : NormalizeDouble(currentPrice + TrailingStep * pip, digits);
            bool stepBetter = (type == POSITION_TYPE_BUY) ? (stepSL > newSL || newSL == 0)
                                                            : (stepSL < newSL || newSL == 0);
            if(stepBetter) { newSL = stepSL; modifyNeeded = true; }
            break;  }
             
         case TRAIL_RISKFREE: {
            double buffer = RiskFreeBufferPip * pip;
            double minProfitRequired = RiskFreeBufferPip * 2.0 * pip;
            double currentProfitPips = (type == POSITION_TYPE_BUY) ? (currentPrice - openPrice) / pip : (openPrice - currentPrice) / pip;
            if(currentProfitPips * pip >= minProfitRequired) {
               double legacySL = (type == POSITION_TYPE_BUY) ? NormalizeDouble(openPrice + buffer, digits)
                                                               : NormalizeDouble(openPrice - buffer, digits);
               bool legacyBetter = (type == POSITION_TYPE_BUY) ? (legacySL > newSL || newSL == 0)
                                                                 : (legacySL < newSL || newSL == 0);
               if(legacyBetter) { newSL = legacySL; modifyNeeded = true; }
            }
            break;  }
      }
   }

   if((TrailingMode == TRAIL_ADVANCED_ATR || TrailingMode == TRAIL_ATR_STEP || TrailingMode == TRAIL_HYBRID_ALL)
      && profitPips >= AdvATR_TrailingStart) {
      double atrPips = GetTrailATR_Pips();
      double trailDist = MathMax(AdvATR_MinTrailPips, atrPips * AdvATR_TrailMultiplier);
      double advSL = (type == POSITION_TYPE_BUY) ? NormalizeDouble(currentPrice - trailDist * pip, digits)
                                                    : NormalizeDouble(currentPrice + trailDist * pip, digits);
      bool advBetter = (type == POSITION_TYPE_BUY) ? (advSL > currentSL || currentSL == 0)
                                                      : (advSL < currentSL || currentSL == 0);

      if(TrailingMode == TRAIL_ADVANCED_ATR) {
         if(advBetter) { newSL = advSL; modifyNeeded = true; }
      } else if(TrailingMode == TRAIL_ATR_STEP) {
         
         double movePips = advBetter ? MathAbs(advSL - currentSL) / pip : 0.0;
         if(advBetter && (currentSL == 0 || movePips >= TrailingStep)) {
            newSL = advSL; modifyNeeded = true;
         }
      } else if(TrailingMode == TRAIL_HYBRID_ALL) {
         
         double stepSL = (type == POSITION_TYPE_BUY) ? NormalizeDouble(currentPrice - TrailingStep * pip, digits)
                                                       : NormalizeDouble(currentPrice + TrailingStep * pip, digits);
         double candidateSL = (type == POSITION_TYPE_BUY) ? MathMax(advSL, stepSL) : MathMin(advSL, stepSL);
         bool candidateBetter = (type == POSITION_TYPE_BUY) ? (candidateSL > currentSL || currentSL == 0)
                                                              : (candidateSL < currentSL || currentSL == 0);
         if(candidateBetter) { newSL = candidateSL; modifyNeeded = true; }
      }
   }

   // ------------------------------------------------------------------
   // Trill MA  /  Trill MA & Risk Free   (v165 - موینگ‌اوریج پریود 3، بدون هیچ دخالت ATR)
   if((TrailingMode == TRAIL_MA || TrailingMode == TRAIL_MA_RISKFREE) && profitPips >= TrailingStartMA) {
      bool maOk = false;
      double maValue = GetTrailMA_Value(maOk);
      if(maOk) {
         double maSL = (type == POSITION_TYPE_BUY) ? NormalizeDouble(maValue - MA_TrailDistancePip * pip, digits)
                                                     : NormalizeDouble(maValue + MA_TrailDistancePip * pip, digits);
         bool maBetter = (type == POSITION_TYPE_BUY) ? (maSL > newSL || newSL == 0)
                                                       : (maSL < newSL || newSL == 0);
         if(maBetter) { newSL = maSL; modifyNeeded = true; }
      }
   }
   
if(modifyNeeded && newSL != currentSL) {
    if(!trade.PositionModify(ticket, newSL, currentTP)) {
        if(DebugLogEnable) {
            ErrorLog(StringFormat("تریل ناموفق (تیکت %I64u): Retcode=%d, %s", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription()));
        }
    }
}}
//+------------------------------------------------------------------+
//| ADX Power Exit Functions                                         |
//+------------------------------------------------------------------+
double plusDIPowerExit_PrevValue = 0.0;
double minusDIPowerExit_PrevValue = 0.0;
bool   g_adxNewCrossThisBar = false;
int    g_adxCrossDirection  = 0;

void UpdateADXPowerExit() {
   if((!EnableADXPowerExit && !EnableDMICrossExit && !EnableADXStrengthExit) || adxPowerExit_Handle == INVALID_HANDLE) return;
   
   double adx[];
   ArraySetAsSeries(adx, true);
   if(CopyBuffer(adxPowerExit_Handle, 0, 0, 3, adx) > 0) {
      adxPowerExit_LastValue = adx[0];
   }
   
   g_adxNewCrossThisBar = false;
   
   static datetime s_lastADXBarTime = 0;
   datetime barTime = iTime(_Symbol, ADXPowerExit_Timeframe, 0);
   if(barTime == s_lastADXBarTime) return;
   s_lastADXBarTime = barTime;
   
   double pdi[], mdi[];
   ArraySetAsSeries(pdi, true);
   ArraySetAsSeries(mdi, true);
   if(CopyBuffer(adxPowerExit_Handle, 1, 0, 4, pdi) <= 0) return;
   if(CopyBuffer(adxPowerExit_Handle, 2, 0, 4, mdi) <= 0) return;

   plusDIPowerExit_PrevValue  = pdi[2];
   minusDIPowerExit_PrevValue = mdi[2];
   plusDIPowerExit_LastValue  = pdi[1];
   minusDIPowerExit_LastValue = mdi[1];
   
   bool nowBullish  = (plusDIPowerExit_LastValue  < minusDIPowerExit_LastValue);
   bool prevBullish = (plusDIPowerExit_PrevValue  < minusDIPowerExit_PrevValue);
   bool nowBearish  = (minusDIPowerExit_LastValue < plusDIPowerExit_LastValue);
   bool prevBearish = (minusDIPowerExit_PrevValue < plusDIPowerExit_PrevValue);
   
   if(nowBullish && !prevBullish) {
      g_adxNewCrossThisBar = true;
      g_adxCrossDirection = 1;
   } else if(nowBearish && !prevBearish) {
      g_adxNewCrossThisBar = true;
      g_adxCrossDirection = -1;
   }
}
  
void CheckADXPowerExit() {
    if(!EnableADXPowerExit && !EnableDMICrossExit && !EnableADXStrengthExit) return;
   UpdateADXPowerExit();
   
   if(EnableADXStrengthExit && adxPowerExit_LastValue < ADXPowerExit_Min) {
      CloseAllPositionsADX("ADX weak trend: " + DoubleToString(adxPowerExit_LastValue, 1));
      return;   }
   
    if(EnableDMICrossExit && g_adxNewCrossThisBar) {
    
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0 && PositionSelectByTicket(ticket)) {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol) {
               ProcessADXExitForPosition(ticket);  }}}}}
               
void ProcessADXExitForPosition(ulong ticket) {
   if(!g_adxNewCrossThisBar) return;
   long type = PositionGetInteger(POSITION_TYPE);
   bool closePos = false;
   string reason = "";
   
   if(type == POSITION_TYPE_BUY && g_adxCrossDirection == 1) {
      closePos = true;
      reason = "Buy exit: +DI crossed below -DI (bar close)";
   } else if(type == POSITION_TYPE_SELL && g_adxCrossDirection == -1) {
      closePos = true;
      reason = "Sell exit: -DI crossed below +DI (bar close)";   }  
     
   if(closePos) {
      if(trade.PositionClose(ticket)) {
         lastPositionCloseTime = TimeCurrent();
         pauseBarsCounter = 0;
    if(DebugLogEnable) {     SystemLog("پوزیشن با ADX بسته شد: " + reason);  } }} }
    
   void CloseAllPositionsADX(string reason) {
   int total = PositionsTotal();
   int closedCount = 0;
   
   for(int i = 0; i < total; i++) {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket)) {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol) {
            if(trade.PositionClose(ticket)) {
               lastPositionCloseTime = TimeCurrent();
               pauseBarsCounter = 0;
               closedCount++;
               
  if(DebugLogEnable)     {        
               SystemLog("پوزیشن با ADX بسته شد: " + reason);   }  }}}    }
  
   if(closedCount > 0 && DebugLogEnable) {
    SystemLog("بستن " + string(closedCount) + " پوزیشن با خروج قدرت ADX"); }}      
//+------------------------------------------------------------------+
//| ATR Functions                                                    |
//+------------------------------------------------------------------+
void UpdateATRStats() {     if(!EnableATRFilter || atrHandle == INVALID_HANDLE) return;
 
   static datetime s_lastATRStatsUpdate = 0;
   if(s_lastATRStatsUpdate != 0 && (TimeCurrent() - s_lastATRStatsUpdate) < 30) return;
   s_lastATRStatsUpdate = TimeCurrent();
   double atrVals[];
   ArraySetAsSeries(atrVals, true);
   int copied = CopyBuffer(atrHandle, 0, 0, ATR_BestRangeBars, atrVals);
      if(copied > 0) {
      last_atr_value = atrVals[0];
      atr_best_min = atrVals[ArrayMinimum(atrVals)];
      atr_best_max = atrVals[ArrayMaximum(atrVals)];      
      double sum = 0;
      for(int i = 0; i < copied; i++) sum += atrVals[i];
      atr_best_avg = sum / copied;    }   }
// ===== ATR: globals + robust Init/Update (professional patch) =====

bool   g_atrFrozenWarning = false;
string g_atrHandleSymbol = "";
ENUM_TIMEFRAMES g_atrHandleTimeframe = PERIOD_CURRENT;
ENUM_TIMEFRAMES g_atrTrailHandleTimeframe = PERIOD_M1;
int    g_atrTrailHandlePeriod = 0;   // v147 fix #2: period actually baked into the live trail-ATR handle
int    g_atrDonchianFailCount = 0;
int    g_atrTrailFailCount = 0;
datetime g_lastPeriodChangeRecreate = 0;   // v152 item #5: debounce for period-triggered handle recreation
#define ATR_FREEZE_THRESHOLD 8
#define ATR_PERIOD_RECREATE_COOLDOWN 30   // v152 item #5: seconds - see bug explanation below

double g_lastValidATR_Donchian_Pips = 0.0;
double g_lastValidATR_Trail_Pips    = 0.0;

#define ATR_JUMP_RATIO 3.0
double g_pendingATR_Donchian_Pips = 0.0;
double g_pendingATR_Trail_Pips    = 0.0;

double SanitizeATRReading(double newVal, double &lastValid, double &pending) {
    if(newVal <= 0.0) return lastValid;
    if(lastValid <= 0.0) { lastValid = newVal; pending = 0.0; return lastValid; }
    if(newVal <= lastValid * ATR_JUMP_RATIO) {
        lastValid = newVal; pending = 0.0; return lastValid;
    }
    // Suspiciously large jump - require confirmation from a second, similar reading
    // before trusting it (within 20%), otherwise keep the old value and wait.
    if(pending > 0.0 && MathAbs(newVal - pending) <= pending * 0.2) {
        lastValid = newVal; pending = 0.0; return lastValid;
    }
    pending = newVal;
    return lastValid;
}

// ------------------------------------------------------------------
// Robust InitIndependentATR() - ensures handles created for correct TFs
void InitIndependentATR() {
    // Determine the actual timeframes we want for each ATR handle
    ENUM_TIMEFRAMES donchianTf = Period(); // Donchian ATR intentionally uses current chart TF
    ENUM_TIMEFRAMES trailTf = (AdvATR_Timeframe == PERIOD_CURRENT) ? Period() : AdvATR_Timeframe;
    
    // Create Donchian ATR handle if missing
    if(g_atrDonchianHandle == INVALID_HANDLE) {
        g_atrDonchianHandle = iATR(_Symbol, donchianTf, DonchianATR_Period);
        if(g_atrDonchianHandle != INVALID_HANDLE) {
            g_atrHandleSymbol = _Symbol;
            g_atrHandleTimeframe = donchianTf;
            g_atrDonchianFailCount = 0;
        } else {
            if(DebugLogEnable) ErrorLog("InitIndependentATR: Failed to create Donchian ATR handle (tf=" + EnumToString(donchianTf) + ")");
        }
    }
    
    // Create Trail ATR handle if missing
    if(g_atrTrailHandle == INVALID_HANDLE) {
        int trailPeriod = g_EffectiveAdvATR_Period;   // v147 fix #2
        g_atrTrailHandle = iATR(_Symbol, trailTf, trailPeriod);
        if(g_atrTrailHandle != INVALID_HANDLE) {
            g_atrTrailHandleTimeframe = trailTf;
            g_atrTrailHandlePeriod = trailPeriod;
            g_atrTrailFailCount = 0;
        } else {
            if(DebugLogEnable) ErrorLog("InitIndependentATR: Failed to create Trail ATR handle (tf=" + EnumToString(trailTf) + ")");
        }
    }
}

// ------------------------------------------------------------------
// Trill MA - هندل مستقل موینگ‌اوریج تریل (کاملاً جدا از ATR، هیچ محاسبهٔ ATR در آن دخیل نیست)
void InitTrailMA() {
    if(g_trailMAHandle == INVALID_HANDLE) {
        g_trailMAHandle = iMA(_Symbol, PERIOD_CURRENT, TRAILMA_PERIOD, 0, TRAILMA_METHOD, PRICE_CLOSE);
        if(g_trailMAHandle != INVALID_HANDLE) {
            g_trailMAHandleTimeframe = Period();
        } else {
            if(DebugLogEnable) ErrorLog("InitTrailMA: Failed to create MA handle, err=" + string(GetLastError()));
        }
    }
}

// v165 fix: مثل UpdateIndependentATR - هر تیک چک می‌کند تایم‌فریم عوض شده یا نه و هندل را در صورت نیاز از نو می‌سازد
// (هندلی که فقط یک‌بار در OnInit ساخته شود، با تغییر تایم‌فریم یا گذشت زمان توسط ترمینال نامعتبر می‌شود - خطای 4807)
void UpdateTrailMA() {
    ENUM_TIMEFRAMES desiredTf = Period();   // PERIOD_CURRENT همیشه یعنی تایم‌فریم زندهٔ چارت
    if(g_trailMAHandle == INVALID_HANDLE || g_trailMAHandleTimeframe != desiredTf) {
        if(g_trailMAHandle != INVALID_HANDLE) {
            IndicatorRelease(g_trailMAHandle);
            g_trailMAHandle = INVALID_HANDLE;
        }
        InitTrailMA();
    }
}

// مقدار جاری موینگ‌اوریج تریل را برمی‌گرداند؛ در صورت شکست خواندن، ok=false می‌شود (تریل آن تیک نادیده گرفته می‌شود)
int g_trailMALastError = 0;   // v165 fix: کد خطای واقعی برای عیب‌یابی (به‌جای فقط "نامعتبر")
double GetTrailMA_Value(bool &ok) {
    ok = false;
    g_trailMALastError = 0;
    UpdateTrailMA();   // v165 fix: قبل از هر خواندن، مطمئن شو هندل با تایم‌فریم فعلی هماهنگ و معتبر است
    if(g_trailMAHandle == INVALID_HANDLE) { g_trailMALastError = (int)GetLastError(); return 0.0; }

    int calculated = BarsCalculated(g_trailMAHandle);
    if(calculated < 1) {
        g_trailMALastError = (int)GetLastError();   // معمولاً یعنی اندیکاتور هنوز محاسبه نشده (تازه ساخته شده)
        return 0.0;
    }

    double buf[];
    ArraySetAsSeries(buf, true);
    if(CopyBuffer(g_trailMAHandle, 0, 0, 1, buf) != 1) {
        g_trailMALastError = (int)GetLastError();
        return 0.0;
    }
    ok = true;
    return buf[0];
}

void UpdateIndependentATR() {
     ENUM_TIMEFRAMES desiredDonchianTf = Period();
    ENUM_TIMEFRAMES desiredTrailTf = (AdvATR_Timeframe == PERIOD_CURRENT) ? Period() : AdvATR_Timeframe;
   
    bool symbolOrTfChanged = (g_atrHandleSymbol != _Symbol ||
                               g_atrHandleTimeframe != desiredDonchianTf ||
                               g_atrTrailHandleTimeframe != desiredTrailTf);

  
    bool periodMismatch = (g_atrTrailHandlePeriod != g_EffectiveAdvATR_Period);
    bool periodChangeDebounced = periodMismatch &&
                                  (g_lastPeriodChangeRecreate == 0 || (TimeCurrent() - g_lastPeriodChangeRecreate) >= ATR_PERIOD_RECREATE_COOLDOWN);

    if(symbolOrTfChanged || periodChangeDebounced) {
        if(periodChangeDebounced) g_lastPeriodChangeRecreate = TimeCurrent();
        if(g_atrDonchianHandle != INVALID_HANDLE) { IndicatorRelease(g_atrDonchianHandle); g_atrDonchianHandle = INVALID_HANDLE; }
        if(g_atrTrailHandle != INVALID_HANDLE)    { IndicatorRelease(g_atrTrailHandle);    g_atrTrailHandle = INVALID_HANDLE; }
        g_atrHandleSymbol = _Symbol;
        g_atrHandleTimeframe = desiredDonchianTf;
        g_atrTrailHandleTimeframe = desiredTrailTf;
        g_atrDonchianFailCount = 0;
        g_atrTrailFailCount = 0;
        g_pendingATR_Donchian_Pips = 0.0;
        g_pendingATR_Trail_Pips = 0.0;
    }
    
    // Ensure handles exist (try to init immediately if missing)
    if(g_atrDonchianHandle == INVALID_HANDLE || g_atrTrailHandle == INVALID_HANDLE) {
        InitIndependentATR();
    }
    
    // Throttle regular CopyBuffer calls: at most once per 30s, UNLESS recent volatility spiked
    static datetime s_lastATRUpdate = 0;
    bool forceEarlyUpdate = false;
    if(s_lastATRUpdate != 0 && g_lastValidATR_Donchian_Pips > 0) {
        double recentHigh = -1, recentLow = 1e12;
        datetime cutoff = TimeCurrent() - 2;
        for(int k = 0; k < 30; k++) {
            int idx = (bufferIndex - k - 1 + MAX_HISTORY) % MAX_HISTORY;
            if(tickPriceBuffer[idx] <= 0 || tickTimeBuffer[idx] < cutoff) break;
            if(tickPriceBuffer[idx] > recentHigh) recentHigh = tickPriceBuffer[idx];
            if(tickPriceBuffer[idx] < recentLow)  recentLow  = tickPriceBuffer[idx];
        }
        if(recentHigh > 0 && recentLow < 1e12) {
            double pipChk = GetPip();
            if(pipChk > 0) {
                double recentRangePips = (recentHigh - recentLow) / pipChk;
                if(recentRangePips > g_lastValidATR_Donchian_Pips * 2.0) forceEarlyUpdate = true;
            }
        }
    }
    if(s_lastATRUpdate != 0 && (TimeCurrent() - s_lastATRUpdate) < 30 && !forceEarlyUpdate) {
        // Update panel flag from fail counters, but skip heavy CopyBuffer
        g_atrFrozenWarning = (g_atrDonchianFailCount > 3 || g_atrTrailFailCount > 3);
        return;
    }
    s_lastATRUpdate = TimeCurrent();
    
    // If handles are still missing after attempted init, skip updates (keep last valid values)
    if(g_atrDonchianHandle == INVALID_HANDLE && g_atrTrailHandle == INVALID_HANDLE) {
        return;
    }
    
    double buf1[], buf2[];
    ArraySetAsSeries(buf1, true);
    ArraySetAsSeries(buf2, true);
    
    // --- Donchian ATR (safe update with fallback) ---
    if(g_atrDonchianHandle != INVALID_HANDLE) {
        int copied = CopyBuffer(g_atrDonchianHandle, 0, 0, 1, buf1);
        if(copied > 0 && buf1[0] > 0.0) {
            double pip = GetPip();
            if(pip > 0.0) SanitizeATRReading(buf1[0] / pip, g_lastValidATR_Donchian_Pips, g_pendingATR_Donchian_Pips);
            g_atrDonchianFailCount = 0;
        } else {
            g_atrDonchianFailCount++;
            if(g_atrDonchianFailCount > ATR_FREEZE_THRESHOLD) {
                // release and allow InitIndependentATR to recreate later
                if(g_atrDonchianHandle != INVALID_HANDLE) { IndicatorRelease(g_atrDonchianHandle); g_atrDonchianHandle = INVALID_HANDLE; }
                g_atrDonchianFailCount = 0;
            }
            // preserve previous g_lastValidATR_Donchian_Pips as fallback
        }
    }
    
    // --- Trail ATR (safe update with fallback) ---
    if(g_atrTrailHandle != INVALID_HANDLE) {
        int copied2 = CopyBuffer(g_atrTrailHandle, 0, 0, 1, buf2);
        if(copied2 > 0 && buf2[0] > 0.0) {
            double pip2 = GetPip();
            if(pip2 > 0.0) SanitizeATRReading(buf2[0] / pip2, g_lastValidATR_Trail_Pips, g_pendingATR_Trail_Pips);
            g_atrTrailFailCount = 0;
        } else {
            g_atrTrailFailCount++;
            if(g_atrTrailFailCount > ATR_FREEZE_THRESHOLD) {
                if(g_atrTrailHandle != INVALID_HANDLE) { IndicatorRelease(g_atrTrailHandle); g_atrTrailHandle = INVALID_HANDLE; }
                g_atrTrailFailCount = 0;
            }  }}         
    g_atrFrozenWarning = (g_atrDonchianFailCount > 3 || g_atrTrailFailCount > 3);
}

double GetDonchianATR_Pips() {
    return g_lastValidATR_Donchian_Pips;
}
double GetTrailATR_Pips() {
    return g_lastValidATR_Trail_Pips;
}

//+------------------------------------------------------------------+
#define DONCHIAN_FAST_PERIOD 3
#define DONCHIAN_FAST_THRESHOLD_SCALE 0.2
int g_donchianStatus = 0;

bool IsCandleRange(double &channelWidthPip) {
    channelWidthPip = 0.0;
    g_donchianStatus = 0;
    if(!EnableCandleRangeFilter) { g_donchianStatus = 1; return false; }
    double highs[], lows[];
    ArraySetAsSeries(highs, true);
    ArraySetAsSeries(lows, true);
    if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, DonchianPeriod, highs) < DonchianPeriod) { g_donchianStatus = 2; return false; }
    if(CopyLow(_Symbol, PERIOD_CURRENT, 0, DonchianPeriod, lows)  < DonchianPeriod) { g_donchianStatus = 2; return false; }

    double h1 = -DBL_MAX, l1 = DBL_MAX;
    for(int i = 0; i < DonchianPeriod; i++) {
        if(highs[i] > h1) h1 = highs[i];
        if(lows[i] < l1) l1 = lows[i];
    }
    double channelWidth = (h1 - l1) / GetPip();

    double fh1 = -DBL_MAX, fl1 = DBL_MAX;
    int fastN = MathMin(DONCHIAN_FAST_PERIOD, DonchianPeriod);
    for(int i = 0; i < fastN; i++) {
        if(highs[i] > fh1) fh1 = highs[i];
        if(lows[i] < fl1) fl1 = lows[i];
    }
    double fastWidth = (fh1 - fl1) / GetPip();

    channelWidthPip = channelWidth;

    double atrPips = GetDonchianATR_Pips();
    if(atrPips <= 0.0) { g_donchianStatus = 3; return false; }

    double threshold = atrPips * DonchianRangeWidthATRRatio;
    double fastThreshold = threshold * DONCHIAN_FAST_THRESHOLD_SCALE;
    if(channelWidth >= threshold && fastWidth < fastThreshold)
        return true;
    return channelWidth < threshold;
}
//+------------------------------------------------------------------+
//| Update Status Bar (Object-Based)                                 |
//+------------------------------------------------------------------+
void UpdateStatusBar() {
   if(!StatusBarEnable) return;
   
   string status = StringFormat("%s | TF: %s", _Symbol, EnumToString(_Period));
   status += StringFormat("  | Positions: %d", PositionsTotal());
   
   if(EnableLossManagement && consecutiveLossCount > 0) {
      status += StringFormat(" | Losses: %d/%d", consecutiveLossCount, MaxConsecutiveLosses);   }
    
   if(!autoTradingActive) status += " | AUTO: OFF";
   else if(managementPaused) status += " | MGMT: OFF";
   
   string statusBarName = "StatusBar";
   if(ObjectFind(0, statusBarName) < 0) {
      ObjectCreate(0, statusBarName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, statusBarName, OBJPROP_XDISTANCE, 450);
      ObjectSetInteger(0, statusBarName, OBJPROP_YDISTANCE, 10);
      ObjectSetInteger(0, statusBarName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, statusBarName, OBJPROP_COLOR, clrGold);
      ObjectSetInteger(0, statusBarName, OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, statusBarName, OBJPROP_BACK, false);   }
      
   ObjectSetString(0, statusBarName, OBJPROP_TEXT, status);   }

//+------------------------------------------------------------------+
//| Process Auto Trading (core)                                      |
//+------------------------------------------------------------------+
// v171: معاملهٔ استراتژی باکس: هر سیستم سیگنال، فیلتر و پوزیشن مستقل خودش را دارد
void ProcessBoxTrading() {
   if(!UseBoxSignal) return;   // BOXBREAK: سیستمی که فقط برای شکست باکس ساخته شده، ورود تراز اجرا نکند
   for(int n = 1; n <= 2; n++) {
      CBoxSystem *sys = (n == 1) ? g_box1 : g_box2;
      if(sys == NULL) continue;
      int sig = sys.GetSignal();
      if(sig == 0) continue;
      lastSignalUsed = sig;
      g_boxCtxActive = true;
      g_boxCtxTag = sys.tag;
      g_boxCtxTP = sys.signalTP;
      g_lastExecOK = false;
      if(CheckOtherFiltersEnhanced(sig)) {
         ExecuteTrade(sig);
         if(g_lastExecOK) sys.OnTradeDone();
      } else if(DebugLogEnable) {
         RejectLog("Box" + IntegerToString(n) + " signal", lastTradeFailureReason);
      }
      g_boxCtxActive = false;
      g_boxCtxTag = "";
      g_boxCtxTP = 0.0;
   }
}

// BOXBREAK: پردازش سیگنال «شکست باکس» (جدا از ProcessBoxTrading)
void ProcessBoxBreakTrading() {
   for(int n = 1; n <= 2; n++) {
      CBoxSystem *sys = (n == 1) ? g_box1 : g_box2;
      CBoxBreak  *bk  = (n == 1) ? g_brk1 : g_brk2;
      if(sys == NULL || bk == NULL) continue;
      sys.Refresh();
      int bs = bk.GetSignal(sys);
      if(bs == 0) continue;
      lastSignalUsed = bs;
      g_boxCtxActive = true;
      g_boxCtxTag = bk.tag;
      g_boxCtxTP = bk.signalTP;
      g_lastExecOK = false;
      if(CheckOtherFiltersEnhanced(bs)) {
         ExecuteTrade(bs);
         if(g_lastExecOK) bk.OnDone();
      } else if(DebugLogEnable) {
         RejectLog("BoxBreak" + IntegerToString(n) + " signal", lastTradeFailureReason);
      }
      g_boxCtxActive = false;
      g_boxCtxTag = "";
      g_boxCtxTP = 0.0;
   }
}

// v174: اجرای هم‌زمان چند منبع سیگنال؛ هر منبع حالت جدای خودش را دارد
int g_srcLastSignalUsed[3];
int g_srcDelayCounter[3];

// اندیکاتور خارجی / زاویهٔ میانگین داخلی / ماشهٔ ترکیبی (SignalSource پیش‌تر تنظیم شده)
void ProcessSimpleSource(bool newBar) {
   int signal = GetTradingSignal();
   int processedSignal = ApplySignalDelay(signal, newBar);
   int effectiveSignal = processedSignal;

   bool processSignal = false;
   if(OnlyTradeOnNewBar && newBar) processSignal = true;
   if(ImmediateTradeOnSignal && effectiveSignal != 0) processSignal = true;
   if(effectiveSignal != lastSignalUsed) processSignal = true;

   if(processSignal && effectiveSignal != 0) {
      if(CheckOtherFiltersEnhanced(effectiveSignal)) {
         ExecuteTrade(effectiveSignal);
      } else {
         if(DebugLogEnable) {
            RejectLog("Signal", lastTradeFailureReason);
         }
      }
      lastSignalUsed = effectiveSignal;
   }
}

void ProcessAllSources(bool newBar) {
   EnumSignalSource order[3] = {SIGNAL_ICHIMOKU_BOX, SIGNAL_EXTERNAL_INDICATOR, SIGNAL_COMPOSITE_SCORE};
   bool enabled[3];
   enabled[0] = (UseBoxSignal || UseBoxBreakSignal || UseBoxBreak2Signal);   // BOXBREAK
   enabled[1] = UseIndicatorSignal;
   enabled[2] = UseCompositeSignal;
   for(int k = 0; k < 3; k++) {
      if(!enabled[k]) continue;
      SignalSource = order[k];
      lastSignalUsed = g_srcLastSignalUsed[k];
      signalDelayCounter = g_srcDelayCounter[k];
      g_lastExecOK = false;
      if(order[k] == SIGNAL_ICHIMOKU_BOX) { ProcessBoxTrading(); ProcessBoxBreakTrading(); }   // BOXBREAK
      else                                ProcessSimpleSource(newBar);
      g_srcLastSignalUsed[k] = lastSignalUsed;
      g_srcDelayCounter[k] = signalDelayCounter;
      if(!SuggestionOnlyMode && g_lastExecOK) break;   // در حالت معاملهٔ واقعی، با اولین معامله بس است
   }
   SignalSource = Src_Primary();
}

void ProcessAutoTrading(bool newBar, datetime currentBarTime) {
   if(UseStochastic1Confirmation && stoch1Handle == INVALID_HANDLE) {
      InitStochastic1();  }
   
   if(UseStochastic2Confirmation && stoch2Handle == INVALID_HANDLE) {
      InitStochastic2();   }

if(currentTimeframe != _Period) {
    if(newBar && DebugLogEnable) {
        SystemLog("تایم‌فریم تغییر کرد - معامله متوقف شد"); }  return; }
 
if(Manual_BlockAutoTrading && hasManualPosition) {
    if(DebugLogEnable && newBar) {
        SystemLog("معاملهٔ خودکار به‌خاطر پوزیشن دستی مسدود شد");   }  return; }

   UpdateATRStats();
   if(UseStochastic1Confirmation) {
      CalculateStochastic1(StochasticCrossLookbackBars + 20);    }
   
   if(UseStochastic2Confirmation) {
      CalculateStochastic2(StochasticCrossLookbackBars + 20);   }   
   
   ProcessAllSources(newBar);   // v174
}
// v173.1: متاتریدر هنگام تغییر تایم‌فریم/نماد اکسپرت را دوباره راه‌اندازی می‌کند؛
// وضعیت دکمه‌های «مدیریت» و «معاملهٔ خودکار» باید در همین تغییر حفظ شود
string Keep_Key() { return "EA_Keep_" + IntegerToString((long)ChartID()); }

void Keep_Save(int reason) {
   if(reason != REASON_CHARTCHANGE) return;
   string k = Keep_Key();
   GlobalVariableSet(k + "_Mgmt", managementPaused ? 1.0 : 0.0);
   GlobalVariableSet(k + "_Auto", autoTradingActive ? 1.0 : 0.0);
}

void Keep_Restore() {
   string k = Keep_Key();
   if(GlobalVariableCheck(k + "_Mgmt")) {
      managementPaused = (GlobalVariableGet(k + "_Mgmt") > 0.5);
      GlobalVariableDel(k + "_Mgmt");
   }
   if(GlobalVariableCheck(k + "_Auto")) {
      autoTradingActive = (GlobalVariableGet(k + "_Auto") > 0.5);
      GlobalVariableDel(k + "_Auto");
   }
}

int OnInit() {
   Sug_Startup();   // v173
   // ╔══════════════════════════════════════════════════════════════╗
   // ╚══════════════════════════════════════════════════════════════╝
   if(LICENSED_ACCOUNT_NUMBER != 0) {
      long currentAccount = AccountInfoInteger(ACCOUNT_LOGIN);
      if(currentAccount != LICENSED_ACCOUNT_NUMBER) {
         Alert("⛔ این اکسپرت فقط برای شماره حساب مجاز قابل اجراست. حساب فعلی: ", currentAccount);
         Print("❌ قفل لایسنس: حساب ", currentAccount, " با حساب مجاز ", LICENSED_ACCOUNT_NUMBER, " یکی نیست - اکسپرت متوقف شد.");
         return(INIT_FAILED);
      }
   }
   if(LICENSE_EXPIRY_DATE != "") {
      datetime expiry = StringToTime(LICENSE_EXPIRY_DATE);
      if(expiry > 0 && TimeCurrent() > expiry) {
         Alert("⛔ تاریخ انقضای مجوز استفاده از این اکسپرت گذشته است (", LICENSE_EXPIRY_DATE, ").");
         Print("❌ قفل لایسنس: در تاریخ ", LICENSE_EXPIRY_DATE, " منقضی شد (زمان فعلی سرور: ", TimeToString(TimeCurrent()), ") - اکسپرت متوقف شد.");
         return(INIT_FAILED);
      }
   }
   // ╔══════════════════════════════════════════════════════════════╗
   // ╚══════════════════════════════════════════════════════════════╝
   
   trade.SetExpertMagicNumber(EA_MAGIC_NUMBER);
   trade.SetDeviationInPoints(5);
   Box_InitSystems();   // v171
   Div_Init();   // DIVFILTER
   LG_Reset();   // LEG v178.0
   ObjectsDeleteAll(0, "PPINFO_");   // v178.3: شیءهای باقی‌مانده از الگوریتم قدیمی
   
   InitIndependentATR();
   InitTrailMA();
   
   
   string stateKey = "EA_State_" + _Symbol + "_" + IntegerToString((int)_Period);
   
   if(GlobalVariableCheck(stateKey + "_AutoTrade")) {
      autoTradingActive = (bool)GlobalVariableGet(stateKey + "_AutoTrade");
      SystemLog("وضعیت معاملهٔ خودکار بازیابی شد: " + string(autoTradingActive));
   } else {
      autoTradingActive = AutoTradingEnabled;
      GlobalVariableSet(stateKey + "_AutoTrade", autoTradingActive);
         }
        

   managementPaused = false;
   GlobalVariableSet(stateKey + "_ManagementPaused", managementPaused);
   Keep_Restore();   // v173.1: در تغییر تایم‌فریم وضعیت قبلی دکمه‌ها برمی‌گردد
   g_lgShowFib = ShowFibOnChart;   // LEG v178.0: وضعیت دکمهٔ FIB
   if(GlobalVariableCheck(stateKey + "_Fib")) g_lgShowFib = (GlobalVariableGet(stateKey + "_Fib") > 0.5);
   GlobalVariableSet(stateKey + "_Fib", g_lgShowFib);
   GlobalVariableSet(stateKey + "_AutoTrade", autoTradingActive);
   GlobalVariableSet(stateKey + "_ManagementPaused", managementPaused);
   
   currentTimeframe = _Period;
   
   DeleteAllButtons();   
   CreateCloseAllButton();
   CreateAutoTradeButton();
   CreatePauseManagementButton();
   CreateFibButton();   // LEG v178.0
   DF_Init();           // DISPLAY FIB v178.2: وضعیت دکمه مستقل از تایم‌فریم
   CreateDispFibButton();
   
   
   SYMBOL_GROUPS detectedGroup;
   if(AutoDetectGroup) {
       detectedGroup = DetectSymbolGroup();
   } else {
       detectedGroup = ManualSymbolGroup;
   }

  
   currentParams = LoadGroupParams(detectedGroup);
   LoadRegimeParams(detectedGroup);
   sysState.currentGroup = (AutoDetectGroup && g_symbolUnknown) ? "Unknown symbol" : GetGroupName(detectedGroup);
   if(AutoDetectGroup && g_symbolUnknown)
      Print("⚠️ نماد ", _Symbol, " ناشناخته است (طلا/ماژور/کراس نیست). تشخیص خودکار گروه را خاموش کنید، گروه را دستی روی طلا بگذارید و تنظیمات این نماد را در بخش طلا وارد کنید.");

   if(g_tick_analyzer_opt != NULL) {
       g_tick_analyzer_opt.SetMinDirection(currentParams.minDirection);
   }


   if(currentParams.minRange == 0) {
       currentParams.minRange = 4.0;
       currentParams.minDirection = 45;
       currentParams.maxSpread = 25.0;
       currentParams.maxNoiseSpeed = 6.0;
       currentParams.minRealStrength = 40.0;
       currentParams.enabled = true;
       if(DebugLogEnable) SystemLog("⚠️ CurrentParams initialized with defaults");
   }

   if(EnableATRFilter) {
      atrHandle = iATR(_Symbol, ATRTimeframe, ATRPeriod);
      if(atrHandle == INVALID_HANDLE) {
         ErrorLog("Failed to create ATR handle!");
      } else {
            }   }

   if(UseStochastic1Confirmation) {
      InitStochastic1();    }
   
   if(UseStochastic2Confirmation) {
      InitStochastic2();   }
         InitStochasticBuffers(); 

   if(EnableADXPowerExit || EnableDMICrossExit || EnableADXStrengthExit) {
      adxPowerExit_Handle = iADX(_Symbol, ADXPowerExit_Timeframe, ADXPowerExit_Period);
      if(adxPowerExit_Handle == INVALID_HANDLE) {
         ErrorLog("Failed to create ADX handle!");    } else {
             }    }

g_tick_analyzer_opt = new CTickAnalyzerOptimized();

g_tick_hub = new CTickHub();
if(g_tick_hub == NULL) {
    Print("❌ ERROR: Failed to create Tick Hub!");
    return INIT_FAILED;
}   
 
if(g_tick_analyzer_opt == NULL) {
    Print("❌ خطا: ساخت اشیای تحلیل‌گر تیک شکست خورد!");
    
    if(g_tick_analyzer_opt != NULL) {
        delete g_tick_analyzer_opt;
        g_tick_analyzer_opt = NULL;
    }
    if(g_tick_hub != NULL) {
        delete g_tick_hub;
        g_tick_hub = NULL;
    }
    
    return INIT_FAILED;
}

if(g_tick_analyzer_opt != NULL) {
    g_tick_analyzer_opt.SetMinDirection(currentParams.minDirection);
   
}

GlobalVariableSet("DualIchimokuSignal_" + _Symbol + "_" + string(_Period), 0.0);


g_direction_avg = 0.5;

CreateStatusPanel();

ApplySessionMultiplier();

if(EnableNewsFilter) {
   if(!News_Fetch()) {
      SystemLog("⚠️ News Filter: دانلود اولیه تقویم خبری ناموفق بود - آدرس را در Allow WebRequest اضافه کنید");
   }
   if(ShowNewsPanel) News_CreatePanelObjects();
}

return INIT_SUCCEEDED; 
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest &request,
                         const MqlTradeResult &result) {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   if(!HistoryDealSelect(trans.deal)) return;

   long dealMagic  = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(dealMagic != EA_MAGIC_NUMBER) return;

   string dealSymbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   if(dealSymbol != _Symbol) return;

   long dealEntry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_OUT_BY) return;

   double dealProfit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                      + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                      + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   UpdateLossManagement(dealProfit);

   if(DebugLogEnable) {
      SystemLog(StringFormat("💰 معامله بسته شد - سود/زیان خالص: %.2f (deal=%I64u)", dealProfit, trans.deal));
   }
}

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   Keep_Save(reason);     // v173.1
   Sug_OnDeinit(reason);  // v175        // v173
   Box_DeinitSystems();   // v171
   Div_Deinit();   // DIVFILTER
   LG_Cleanup();   // LEG v178.0
   DF_Deinit(reason);   // DISPLAY FIB v178.2: شیءها با تعویض تایم‌فریم می‌مانند
   ClearStatusDisplay();  
   if(ObjectFind(0, "StatusBar") >= 0) {
      ObjectDelete(0, "StatusBar");   }
   News_DeletePanelObjects();
          
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(g_atrDonchianHandle != INVALID_HANDLE) IndicatorRelease(g_atrDonchianHandle);   // ✅ v115
   if(g_atrTrailHandle != INVALID_HANDLE) IndicatorRelease(g_atrTrailHandle);         // ✅ v115
   if(g_trailMAHandle != INVALID_HANDLE) IndicatorRelease(g_trailMAHandle);           // v165: Trill MA
   if(stoch1Handle != INVALID_HANDLE) IndicatorRelease(stoch1Handle);
   if(stoch2Handle != INVALID_HANDLE) IndicatorRelease(stoch2Handle);
   if(adxPowerExit_Handle != INVALID_HANDLE) IndicatorRelease(adxPowerExit_Handle);
   
   if(g_tick_analyzer_opt != NULL) {
      delete g_tick_analyzer_opt;
      g_tick_analyzer_opt = NULL;
   }
   
   if(g_tick_hub != NULL) {
      delete g_tick_hub;
      g_tick_hub = NULL;
   }
      
   string tickLabels[] = {
       "TickCounter_Group", "TickCounter_Status", "TickCounter_Market"     };   
    
   for(int i = 0; i < ArraySize(tickLabels); i++) {
       if(ObjectFind(0, tickLabels[i]) >= 0) {
           ObjectDelete(0, tickLabels[i]);    }}
  
   if(reason == REASON_REMOVE) {
      DeleteAllButtons();
      string stateKey = "EA_State_" + _Symbol + "_" + string(_Period);
      GlobalVariableDel(stateKey + "_AutoTrade");
      GlobalVariableDel(stateKey + "_ManagementPaused");
      GlobalVariableDel(stateKey + "_Fib");
      if(DebugLogEnable) {
          SystemLog("EA Removed - All buttons and states deleted");
      }
   } else {
      if(reason == REASON_INITFAILED) {
          Print("[ERROR] EA Failed to Initialize - Buttons preserved");
      }
      else if(DebugLogEnable) {
          SystemLog("Expert deinitialized - Buttons preserved (Reason: " + GetDeinitReasonText(reason) + ")");  
      }    }      }
//+------------------------------------------------------------------+
//| === FREQUENCY CONTROLLER v4.0 ===                               |
//+------------------------------------------------------------------+
struct TaskScheduler {
    ulong lastExecution[10];
    int executionCount[10];
    
    TaskScheduler() {
        ArrayInitialize(lastExecution, 0);
        ArrayInitialize(executionCount, 0);
    }
    
    bool ShouldExecute(int taskId, ulong intervalMicros) {
        ulong current = GetMicrosecondCount();
        
        if(current < lastExecution[taskId]) {
            lastExecution[taskId] = current;
            return true;
        }
        
        if(current - lastExecution[taskId] >= intervalMicros) {
            lastExecution[taskId] = current;
            executionCount[taskId]++;
            return true;
        }
        return false;
    }
    
    int GetExecutionCount(int taskId) {
        return executionCount[taskId];
    }
    
    void ResetTask(int taskId) {
        lastExecution[taskId] = 0;
        executionCount[taskId] = 0;
    }
};

enum TASK_IDS {
    TASK_CACHE_UPDATE = 0,     
    TASK_FAST_ANALYSIS = 1,    
    TASK_MEDIUM_ANALYSIS = 2, 
    TASK_DEEP_ANALYSIS = 3,     
    TASK_DISPLAY_UPDATE = 4,    
    TASK_STATUS_UPDATE = 5,   
    TASK_OBJECT_CLEANUP = 6,    
    TASK_PERF_MONITOR = 7      
};

TaskScheduler g_scheduler;

void ProcessMediumTasks() {
    if(g_tick_analyzer_opt != NULL) {
        g_tick_analyzer_opt.ProcessTick();
    }
    
    UpdateStoch1Memory();
    UpdateStoch2Memory();
    
}

void ProcessHeavyTasks() {
    datetime timesArr[];
    ArraySetAsSeries(timesArr, true);
    datetime currentBarTime = 0;
    if(CopyTime(_Symbol, _Period, 0, 1, timesArr) > 0) {
        currentBarTime = timesArr[0];
    }
    
    static datetime lastBarTimeLocal = 0;
    bool newBarLocal = (lastBarTimeLocal != currentBarTime);
    
    if(newBarLocal) {
        lastBarTimeLocal = currentBarTime;
        pauseBarsCounter++;
        
        bufferIndex = 0;
        bufferReady = false;
        ArrayInitialize(tickPriceBuffer, 0);
        ArrayInitialize(tickTimeBuffer, 0);
        ArrayInitialize(tickSpeedBuffer, 0);
        ArrayInitialize(tickDirectionBuffer, 0);
        
        if(g_tick_analyzer_opt != NULL) {
            g_tick_analyzer_opt.ResetStats();
        }
        
          ApplySessionMultiplier();
    }
    
    if(autoTradingActive && !managementPaused) {
        ProcessAutoTrading(newBarLocal, currentBarTime);
    }
    
    if(StatusBarEnable) {
        UpdateStatusBar();
    }
}


//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick() {
      static datetime lastFullCheck = 0;
      Sug_Housekeeping();   // v173
      DF_OnTick();   // DISPLAY FIB v178.2

    UpdateIndependentATR();
    UpdateTrailMA();

    if(EnableNewsFilter) {
        News_MaybeRefresh();
        if(TimeCurrent() - g_lastNewsPanelDraw >= 1) {
            News_UpdatePanel();
            g_lastNewsPanelDraw = TimeCurrent();
        }
    } else if(ShowNewsPanel == false) {
     }
    
      if(!autoTradingActive) {
        if(TimeCurrent() - lastFullCheck < 2) return;
        lastFullCheck = TimeCurrent();
    }
    
    static datetime lastRefresh = 0;
    
    if(TimeCurrent() - lastRefresh >= 2) {
        RefreshDirectionSettings();
        lastRefresh = TimeCurrent();
    }

    static MqlTick last_tick;
    MqlTick current_tick;
    
    if(!SymbolInfoTick(_Symbol, current_tick)) return;
    
    if(current_tick.time_msc == last_tick.time_msc && 
       current_tick.bid == last_tick.bid && 
       current_tick.ask == last_tick.ask) {
        return;
    }
    
    last_tick = current_tick;
    
    if(g_tick_hub != NULL) {
        g_tick_hub.AddTick(current_tick);
    }
    
    g_cache.bid = current_tick.bid;
    g_cache.ask = current_tick.ask;
    g_cache.spread = (long)((current_tick.ask - current_tick.bid) / _Point);
    g_cache.lastUpdate = current_tick.time;
    
    if(g_tick_analyzer_opt != NULL) {
        g_tick_analyzer_opt.SetMinDirection(currentParams.minDirection);
    }
    
    static ulong lastTickProcess = 0;
    ulong currentMicros = GetMicrosecondCount();   
 
    if(g_tick_hub != NULL) {
        if(currentMicros - lastTickProcess > 10000) {
            if(g_tick_analyzer_opt != NULL) {
                g_tick_analyzer_opt.ProcessTick();
            }
            lastTickProcess = currentMicros;
        }
    } 

    static ulong lastIndicatorCheck = 0;
    if(currentMicros - lastIndicatorCheck > 100000) {
        if(EnableATRFilter && atrHandle == INVALID_HANDLE) {
            atrHandle = iATR(_Symbol, ATRTimeframe, ATRPeriod);
        }
        
        if((EnableADXPowerExit || EnableDMICrossExit || EnableADXStrengthExit) && adxPowerExit_Handle == INVALID_HANDLE) {
            adxPowerExit_Handle = iADX(_Symbol, ADXPowerExit_Timeframe, ADXPowerExit_Period);
        }
        
        UpdateStoch1Memory();
        UpdateStoch2Memory();
        
        lastIndicatorCheck = currentMicros;
    }
    
    CheckTimeframeChange();
    
    datetime timesArr[];
    ArraySetAsSeries(timesArr, true);
    datetime currentBarTime = 0;
    if(CopyTime(_Symbol, _Period, 0, 1, timesArr) > 0) {
        currentBarTime = timesArr[0];
    }
    
    bool newBar = (lastBarTime != currentBarTime);
   
    if(newBar) {
        lastBarTime = currentBarTime;
        pauseBarsCounter++;
        
        ApplySessionMultiplier(); 

    }
    Div_OnTick();   // DIVFILTER v176.7: هر تیک؛ کندل‌های تازه‌بستهٔ تایم جاری، M5 و M15 را پردازش می‌کند
    
    static ulong lastManualCheckMicros = 0;
    if(currentMicros - lastManualCheckMicros > 1000000) {
        HasManualPositions();
        lastManualCheckMicros = currentMicros;
    }
    
    if(!managementPaused) {
        MonitorPostEntryRegime(); 
        if(TrailingMode != TRAIL_DISABLED) {
            UpdateTrailingStop();
        }
               
        if(EnableADXPowerExit || EnableDMICrossExit || EnableADXStrengthExit) {
            CheckADXPowerExit();
        }
    }
    
    if(!IsTradingAllowedByLossManagement()) {
        string pauseReason = StringFormat("Trading Paused: Loss Management (%d/%d consecutive losses)", consecutiveLossCount, MaxConsecutiveLosses);
        lastTradeFailureReason = pauseReason;
        AddBlockReason(pauseReason);
        return;
    }
   
    if(autoTradingActive) {
        LG_OnTick();   // LEG v178.0: اول بررسی رسیدن به فیبوی پولبک و تایید آن
        ProcessAutoTrading(newBar, currentBarTime);
    }
 
    static bool s_wasShowingPanelReal = true;
    if(ShowTickAnalysisOnChart) {
        if(!s_wasShowingPanelReal) {
            CreateStatusPanel();
            s_wasShowingPanelReal = true;
        }
        UpdateLine6Only();
        
        static ulong lastFullDisplay = 0;
        if(currentMicros - lastFullDisplay > 300000) {
            DisplayEnhancedTickAnalysis();
            lastFullDisplay = currentMicros;
        }
    } else if(s_wasShowingPanelReal) {
        ClearStatusDisplay();
        s_wasShowingPanelReal = false;
    }
    
    static ulong lastDebugLogMicros = 0;
    if(DebugLogEnable && (currentMicros - lastDebugLogMicros > 120000000)) {
        lastDebugLogMicros = currentMicros;
    }
}
//+------------------------------------------------------------------+
//| UPDATE LINE 6 ONLY                                               |
//+------------------------------------------------------------------+
void UpdateLine6Only() {
    if(g_tick_analyzer_opt == NULL) return;
    
    MarketStats stats = g_tick_analyzer_opt.GetMarketStats();
        
    int direction = (int)(g_direction_avg * 100);
    if(direction == 0 && stats.directionScore != 0) {
        direction = stats.directionScore;
    }
    
    int required = currentParams.minDirection;
    
    double momentum = 0;
    int available = 0;
    for(int i = 0; i < MAX_HISTORY; i++) {
        if(tickPriceBuffer[i] > 0) available++;
    }
    
    if(available >= 10) {
        int start_idx = (bufferIndex - 10 + MAX_HISTORY) % MAX_HISTORY;
        int end_idx = (bufferIndex - 1 + MAX_HISTORY) % MAX_HISTORY;
        if(tickPriceBuffer[start_idx] > 0 && tickPriceBuffer[end_idx] > 0) {
            momentum = (tickPriceBuffer[end_idx] - tickPriceBuffer[start_idx]) / GetPip();
        }
    }
    
    color textColor = clrYellow;
    if(momentum > 0.5 && MathAbs(direction) >= required) textColor = clrLime;
    else if(momentum < -0.5 && MathAbs(direction) >= required) textColor = clrRed;
    else if(MathAbs(momentum) > 0.2 && MathAbs(direction) >= required * 0.7) textColor = clrOrange;
    
    string mode = "Auto";
    string text = StringFormat("%s | Mom:%+.1f | Dir:%+3d [%s] Req:%d",
        sysState.currentGroup, momentum, direction, mode, required);
}
//+------------------------------------------------------------------+
//| Chart Event Function                                             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   if(id == CHARTEVENT_OBJECT_DRAG) {   // DISPLAY FIB v178.3: تنظیم دستی ۰ و ۱۰۰
      if(sparam == DF_PREFIX + "L0" || sparam == DF_PREFIX + "L6") DF_OnDrag(sparam);
      return;
   }
   if(id == CHARTEVENT_OBJECT_CLICK) {
        if(sparam == "CloseAllBtn") {
         CloseAllPositionsInstant();      return; }
        
        if(sparam == "AutoTradeBtn") {
         autoTradingActive = !autoTradingActive;
         UpdateAutoTradeButton();
         SaveButtonStates();
         return;
        }
        
        if(sparam == "DispFibBtn") {   // DISPLAY FIB v178.2
         g_dfShow = !g_dfShow;
         GlobalVariableSet(DF_StateKey(), g_dfShow ? 1.0 : 0.0);
         g_dfManual = false;                     // دکمه ← برگشت به حالت اصلی (خودکار)
         GlobalVariableSet(DF_ManualKey(), 0.0);
         UpdateDispFibButton();
         if(g_dfShow) { g_dfFrozen = false; g_dfDir = 0; g_dfLastBar = 0; DF_OnTick(); }
         else { DF_Clear(); ChartRedraw(0); }
         return;
        }

        if(sparam == "FibBtn") {
         g_lgShowFib = !g_lgShowFib;
         UpdateFibButton();
         SaveButtonStates();
         LG_DrawFib();
         ChartRedraw(0);
         return;
        }

        if(sparam == "PauseManagementBtn") {
         managementPaused = !managementPaused;
         UpdatePauseManagementButton();
         SaveButtonStates();
         return;  }}
  }

double g_lastRawMomentumPips = 0.0;

double RobustPriceAt(int idx, int neighborIdx) {
    double p1 = tickPriceBuffer[idx];
    double p2 = tickPriceBuffer[neighborIdx];
    if(p1 <= 0) return p2;
    if(p2 <= 0) return p1;
    return (p1 + p2) / 2.0;
}

double GetMomentum(int window = MOMENTUM_LOOKBACK_TICKS) {
   int available = 0;
   for(int i = 0; i < MAX_HISTORY; i++) {
       if(tickPriceBuffer[i] > 0) available++;
   }
   
   if(available >= window) {
       int start_idx = (bufferIndex - window + MAX_HISTORY) % MAX_HISTORY;
       int end_idx = (bufferIndex - 1 + MAX_HISTORY) % MAX_HISTORY;
       int start_idx2 = (start_idx + 1) % MAX_HISTORY;   // one tick newer than start
       int end_idx2   = (end_idx - 1 + MAX_HISTORY) % MAX_HISTORY; // one tick older than end
       
       if(tickPriceBuffer[start_idx] > 0 && tickPriceBuffer[end_idx] > 0) {
           double startPrice = RobustPriceAt(start_idx, start_idx2);
           double endPrice   = RobustPriceAt(end_idx, end_idx2);
           double momentum = (endPrice - startPrice) / GetPip();
           
          static double smoothBuf[3] = {0, 0, 0};
           static int s_lastEndIdx = -1;
           static datetime s_lastEndTime = 0;
           
           datetime endTime = tickTimeBuffer[end_idx];
           if(end_idx != s_lastEndIdx || endTime != s_lastEndTime) {
               smoothBuf[2] = smoothBuf[1];
               smoothBuf[1] = smoothBuf[0];
               smoothBuf[0] = momentum;
               s_lastEndIdx = end_idx;
               s_lastEndTime = endTime;
           }
           
           double smoothed = momentum;
           if(smoothBuf[0] != 0 || smoothBuf[1] != 0 || smoothBuf[2] != 0) {
               smoothed = (smoothBuf[0] + smoothBuf[1] + smoothBuf[2]) / 3;
           }
         
           g_lastRawMomentumPips = smoothed;
           return smoothed;
       }
       
       
   }
   g_lastRawMomentumPips = 0.0;
   return 0.0;
}
//6730
//+------------------------------------------------------------------+
//| End of file marker     //******64.00 165(7)                                           |
//+------------------------------------------------------------------+



