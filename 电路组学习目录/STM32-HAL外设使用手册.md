# STM32 HAL 库外设使用手册
## ——CubeMX 配置完之后，代码里到底该调用哪些函数

> **适用对象**：用 STM32CubeMX 生成、基于 STM32Cube HAL 驱动（`Drivers/STMicroelectronics/STM32xx_HAL_Driver`）的工程。
> **本文示例基准**：你工作区打开的 **STM32G474RBT6** 工程（STM32G4 系列，HAL 驱动来自 STM32CubeG4）。
> 文中所有函数名均与本地 `Drivers/STM32G4xx_HAL_Driver/Inc/stm32g4xx_hal_*.h` 中的声明一一核对过。
> 其它系列（F1/F4/G0/H7…）函数名基本一致，差异只在个别 `xxxEx_` 扩展函数和新增外设。

---

## 目录

0. [关于本文档](#0-关于本文档)
1. [通用套路（先看这一章）](#1-通用套路先看这一章)
2. [GPIO 与 EXTI 外部中断](#2-gpio-与-exti-外部中断)
3. [NVIC / SysTick / 系统内核（CORTEX）](#3-nvic--systick--系统内核cortex)
4. [RCC 时钟系统](#4-rcc-时钟系统)
5. [DMA + DMAMUX](#5-dma--dmamux)
6. [TIM 通用/高级定时器](#6-tim-通用高级定时器)
7. [HRTIM 高分辨率定时器（重点）](#7-hrtim-高分辨率定时器重点)
8. [LPTIM 低功耗定时器](#8-lptim-低功耗定时器)
9. [UART / USART / LPUART（含 RS485、LIN、IRDA、SmartCard）](#9-uart--usart--lpuart)
10. [SPI / I2S / SAI](#10-spi--i2s--sai)
11. [I2C / SMBUS](#11-i2c--smbus)
12. [ADC（含注入组与多重模式）](#12-adc)
13. [DAC（含噪声/三角波/LFSR）](#13-dac)
14. [COMP 比较器 / OPAMP 运算放大器](#14-comp-比较器--opamp-运算放大器)
15. [CORDIC / FMAC（G4 数学加速器）](#15-cordic--fmac)
16. [CRC / RNG](#16-crc--rng)
17. [RTC 实时时钟（闹钟、唤醒、时间戳、防拆）](#17-rtc-实时时钟)
18. [IWDG / WWDG 看门狗](#18-iwdg--wwdg-看门狗)
19. [FDCAN（CAN-FD）](#19-fdcan)
20. [USB Device（PCD）](#20-usb-devicepcd)
21. [QSPI（外部 Flash）](#21-qspi)
22. [FMC：SRAM / NOR / NAND](#22-fmcsram--nor--nand)
23. [FLASH 内部 Flash 读写与选项字节](#23-flash-内部-flash-读写与选项字节)
24. [PWR 电源与低功耗模式](#24-pwr-电源与低功耗模式)
25. [UCPD（USB Type-C PD，仅 LL 驱动）](#25-ucpd)
- [附录 A：最常用宏速查](#附录-a最常用宏速查)
- [附录 B：常见坑与排查清单](#附录-b常见坑与排查清单)

---

## 0. 关于本文档

CubeMX 只负责**生成初始化代码**，真正的使用（启动、收发、改占空比、读数据）都要你自己在
`/* USER CODE BEGIN */` 区域里写。本文按外设逐个说明：

1. CubeMX 里关键配置项 → 它生成了什么代码；
2. 运行期该调用哪些 HAL 函数（阻塞 / `_IT` 中断 / `_DMA` 三种版本）；
3. 中断服务函数与用户回调（Callback）怎么串起来；
4. 常用的 `__HAL_xxx` 寄存器级宏（改值最快的方式）。

**命名约定**
- `hxxx`：CubeMX 生成的句柄，如 `huart1`、`hadc1`、`htim1`、`hhrtim1`、`hspi1`、`hi2c1`；
- 函数后缀含义：无后缀 = 阻塞查询式；`_IT` = 中断方式；`_DMA` = DMA 方式；
- 回调函数在 HAL 里都是 `__weak` 空实现，你只要在任意 .c 文件里写同名函数就自动覆盖。

---

## 1. 通用套路（先看这一章）

### 概览

**常用 API（按实际调用顺序）**

| API | 一句话作用 |
|---|---|
| `HAL_Init()` | 初始化 Flash 预取 / HAL / SysTick 1ms 时基，上电第一条 |
| `SystemClock_Config()` | CubeMX 生成的时钟树配置（HSE/PLL/分频/Flash 延迟） |
| `MX_xxx_Init()` | 每个外设的初始化函数，main() 里逐个调用 |
| `HAL_xxx_MspInit()` | 底层初始化：开时钟、配 GPIO、使能 NVIC、关联 DMA（由 HAL 自动回调） |
| `HAL_xxx_Init(&hxxx)` | 把 `hxxx.Init.*` 的配置真正写进寄存器 |
| `HAL_xxx_Start[_IT/_DMA]()` / `HAL_xxx_Transmit[_IT/_DMA]()` | 运行期的启动 / 收发函数 |
| `HAL_xxx_IRQHandler(&hxxx)` | 中断服务函数里唯一要写的一行 |
| `HAL_xxx_XxxCpltCallback()` | 用户回调（HAL 里是 `__weak`，重写即可） |
| `HAL_Delay(ms)` / `HAL_GetTick()` | 阻塞延时 / 取毫秒计数 |
| `__HAL_RCC_xxx_CLK_ENABLE()` | 打开外设时钟（写在 MspInit 里） |

**不常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_xxx_DeInit()` / `HAL_xxx_MspDeInit()` | 反初始化，释放引脚与时钟（低功耗前常用） |
| `HAL_xxx_GetState()` / `HAL_xxx_GetError()` | 查状态机 / 错误码，用来定位卡死 |
| `HAL_xxx_RegisterCallback()` | 回调注册式写法（多实例时更安全） |
| `HAL_xxx_Abort[_IT]()` | 强行终止正在进行的传输 |
| `HAL_NVIC_*()` | 手动改中断优先级 / 开关 |
| `__HAL_LINKDMA()` | 把 DMA 句柄挂到外设句柄上（用 `_DMA` 版本的前提） |
| `Error_Handler()` | CubeMX 生成的统一错误落点 |

**关键选项速解**

- **句柄 `hxxx`**：一个外设一个全局句柄，里面装着"实例指针 + 配置 + 状态机 + 回调指针"。
- **`hxxx.Instance = USART1`**：选哪一个物理外设。
- **`hxxx.Init.*`**：CubeMX 按界面填好的参数，交给 `HAL_xxx_Init()` 写寄存器。
- **`/* USER CODE BEGIN */ … /* USER CODE END */`**：唯一允许手写代码的区段，重新生成代码时不会被覆盖。
- **函数后缀**：无后缀 = 阻塞轮询；`_IT` = 中断方式；`_DMA` = DMA 方式。


### 1.1 CubeMX 生成的工程结构

```
工程根/
├─ Core/Inc/             xxx.h        —— 句柄 extern 声明、引脚宏
├─ Core/Src/
│   ├─ main.c            HAL_Init()→SystemClock_Config()→MX_xxx_Init()→while(1)
│   ├─ gpio.c / adc.c / spi.c / usart.c ...   每个外设一个文件
│   ├─ stm32g4xx_hal_msp.c   HAL_xxx_MspInit()：时钟、GPIO、NVIC、DMA 关联
│   ├─ stm32g4xx_it.c        中断入口：USART1_IRQHandler() 等
│   └─ system_stm32g4xx.c    时钟树底层
└─ Drivers/STM32G4xx_HAL_Driver/{Inc,Src}/    HAL 驱动本体（只读，别改）
```

### 1.2 一个外设的完整生命周期（以 UART1 为例）

```c
/* ① usart.c 里：句柄 + 初始化函数 */
UART_HandleTypeDef huart1;                      // 全局句柄，usart.h 中 extern
void MX_USART1_UART_Init(void)                  // 由 main() 调用
{
  huart1.Instance          = USART1;            // 选择外设实例
  huart1.Init.BaudRate     = 115200;            // 波特率
  huart1.Init.WordLength   = UART_WORDLENGTH_8B;
  huart1.Init.StopBits     = UART_STOPBITS_1;
  huart1.Init.Parity       = UART_PARITY_NONE;
  huart1.Init.Mode         = UART_MODE_TX_RX;
  huart1.Init.HwFlowCtl    = UART_HWCONTROL_NONE;
  huart1.Init.OverSampling = UART_OVERSAMPLING_16;
  if (HAL_UART_Init(&huart1) != HAL_OK)         // ← 真正的初始化
  {
    Error_Handler();
  }
}

/* ② HAL_UART_Init() 内部会自动回调 HAL_UART_MspInit()（在 stm32g4xx_hal_msp.c 或 usart.c）*/
void HAL_UART_MspInit(UART_HandleTypeDef* uartHandle)
{
  if (uartHandle->Instance == USART1)
  {
    __HAL_RCC_USART1_CLK_ENABLE();              // 开外设时钟（必须）
    /* GPIO 复用配置、NVIC 使能、DMA 关联 __HAL_LINKDMA() 都在这里 */
  }
}

/* ③ main.c 里按顺序调用 */
HAL_Init();                                     // HAL 库 + SysTick 1ms
SystemClock_Config();                           // 时钟树
MX_GPIO_Init(); MX_DMA_Init(); MX_USART1_UART_Init();

/* ④ 使用：阻塞发 / 中断发 / DMA 发 */
HAL_UART_Transmit(&huart1, (uint8_t*)"hi\r\n", 4, 100);   // 阻塞，超时 100ms
```

### 1.3 中断是怎么走通的

```
硬件事件 → NVIC → Core/Src/stm32g4xx_it.c
   void USART1_IRQHandler(void) { HAL_UART_IRQHandler(&huart1); }
        → HAL 驱动内部处理 → 调用用户回调（weak 函数）
             void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart) { /* 你的代码 */ }
```
**要检查三件事，缺一不可**：① `stm32g4xx_it.c` 里有对应 `xxx_IRQHandler`；
② `HAL_NVIC_EnableIRQ(USART1_IRQn)`（MspInit 里）；③ 外设中断源使能（`_IT` 函数会做）。

### 1.4 回调的两种写法

```c
/* 写法 A（默认，最简单）：直接重写 weak 回调 */
void HAL_ADC_ConvCpltCallback(ADC_HandleTypeDef *hadc) { ... }

/* 写法 B：打开 stm32g4xx_hal_conf.h 中的
   #define USE_HAL_ADC_REGISTER_CALLBACKS 1U
   然后运行时注册（同一外设多实例时更方便）*/
HAL_ADC_RegisterCallback(&hadc1, HAL_ADC_CONVERSION_COMPLETE_CB_ID, MyAdcCb);
```

### 1.5 必须确认的开关

| 检查项 | 位置 |
|---|---|
| `#define HAL_XXX_MODULE_ENABLED` | `Core/Inc/stm32g4xx_hal_conf.h`（CubeMX 勾选外设后自动打开） |
| `#define USE_HAL_XXX_REGISTER_CALLBACKS` | 同上（用写法 B 时才需要） |
| 中断函数 + `HAL_NVIC_EnableIRQ()` | `stm32g4xx_it.c` / `MspInit` |
| `__HAL_LINKDMA(&h, DMA_Handle, hdma)` | MspInit（用 `_DMA` 版本时必须有） |
| DMA 请求号（DMAMUX） | CubeMX 里自动生成，如 `hdma_adc1.Init.Request = DMA_REQUEST_ADC1` |

### 1.6 出错统一处理

所有 HAL 函数都返回 `HAL_StatusTypeDef`：`HAL_OK / HAL_ERROR / HAL_BUSY / HAL_TIMEOUT`。
超时时间单位是 `HAL_GetTick()` 的毫秒；失败时用 `HAL_xxx_GetError(&h)` 看错误码。

### 完整工程骨架（CubeMX 生成 + 你手写）

以"点灯 + 串口打印"为例，先看一个 CubeMX 工程的全貌——**搞清楚哪些文件是生成的、哪些代码要自己写**：

| 文件 | 内容 | 谁写 |
|---|---|---|
| `Core/Src/main.c` | 主流程、外设初始化调用、主循环、所有回调 | CubeMX 生成**骨架**，你在 USER CODE 段填逻辑 |
| `Core/Src/gpio.c` / `usart.c` / `tim.c` … | 每个外设一个 `MX_xxx_Init()` | CubeMX 生成（也可在 USER CODE 段补充） |
| `Core/Src/stm32g4xx_hal_msp.c` | `HAL_xxx_MspInit/MspDeInit`：时钟、GPIO、NVIC、DMA | CubeMX 生成 |
| `Core/Src/stm32g4xx_it.c` | 中断服务函数 → 调 `HAL_xxx_IRQHandler` | CubeMX 生成 |
| `Core/Inc/xxx.h` | 句柄 `extern` 声明、引脚宏 | CubeMX 生成 |

```c
/* ============ Core/Src/main.c ============ */

/* ---- CubeMX 生成，不要改 ---- */
int main(void)
{
  HAL_Init();                 /* 生成：HAL + SysTick 1ms */
  SystemClock_Config();       /* 生成：时钟树 */
  MX_GPIO_Init();             /* 生成：引脚 */
  MX_USART1_UART_Init();      /* 生成：外设 */

  /* USER CODE BEGIN 2 */     /* ↓↓↓ 你手写：初始化后的启动动作 ↓↓↓ */
  HAL_GPIO_WritePin(LD2_GPIO_Port, LD2_Pin, GPIO_PIN_RESET);
  HAL_UART_Transmit(&huart1, (uint8_t *)"boot\r\n", 6, 100);
  /* USER CODE END 2 */

  while (1)
  {
    /* USER CODE BEGIN 3 */   /* ↓↓↓ 你手写：主循环业务逻辑 ↓↓↓ */
    HAL_GPIO_TogglePin(LD2_GPIO_Port, LD2_Pin);
    HAL_Delay(500);
    /* USER CODE END 3 */
  }
}

/* USER CODE BEGIN 4 */       /* ↓↓↓ 你手写：所有回调 / 自定义函数 ↓↓↓ */
void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
{
  /* 收到数据后干什么 */
}
/* USER CODE END 4 */
```

```c
/* ============ Core/Src/stm32g4xx_it.c（全部由 CubeMX 生成）============ */
void NMI_Handler(void)      { while (1) {} }
void HardFault_Handler(void){ while (1) {} }
void SysTick_Handler(void)  { HAL_IncTick(); }                     /* 必须保留 */
void USART1_IRQHandler(void){ HAL_UART_IRQHandler(&huart1); }      /* 只需调 HAL */
void EXTI15_10_IRQHandler(void){ HAL_GPIO_EXTI_IRQHandler(GPIO_PIN_13); }
```

**结论：你真正要手写的只有三类位置** ——
① `USER CODE BEGIN 2`（启动/配置运行参数）；② `USER CODE BEGIN 3`（主循环）；
③ `USER CODE BEGIN 4`（回调函数、自己的工具函数）。其余全部交给 CubeMX。

---

## 2. GPIO 与 EXTI 外部中断

### 概览

**常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_GPIO_Init(GPIOx, &GPIO_InitStruct)` | 配置引脚（CubeMX 生成在 `MX_GPIO_Init()` 里自动调用） |
| `HAL_GPIO_WritePin(GPIOx, pin, GPIO_PIN_SET/RESET)` | 输出高电平 / 低电平 |
| `HAL_GPIO_ReadPin(GPIOx, pin)` | 读引脚电平，返回 `GPIO_PinState` |
| `HAL_GPIO_TogglePin(GPIOx, pin)` | 电平翻转（点灯最常用） |
| `HAL_GPIO_EXTI_IRQHandler(pin)` | EXTI 中断服务函数里调用（清标志由它完成） |
| `HAL_GPIO_EXTI_Callback(pin)` | 用户回调：判断是哪个引脚触发 |
| `HAL_GPIO_DeInit(GPIOx, pin)` | 把引脚恢复为复位默认状态（配低功耗前用） |

**不常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_GPIO_LockPin(GPIOx, pin)` | 锁定引脚配置，只有复位才能解锁（防误改） |
| `HAL_EXTI_GetHandle(&hexti, EXTI_LINE_x)` | 取得 EXTI 线的句柄（低层 API 的入口） |
| `HAL_EXTI_SetConfigLine()/GetConfigLine()/ClearConfigLine()` | 运行期改/读/清 EXTI 线的触发边沿与模式 |
| `HAL_EXTI_GetPending()/ClearPending()` | 查询 / 清除 EXTI 挂起标志 |
| `HAL_EXTI_GenerateSWI()` | 软件触发一次 EXTI（调试、模拟按键） |
| `HAL_EXTI_RegisterCallback()/IRQHandler()` | 注册回调 / 通用中断入口 |
| `__HAL_GPIO_EXTI_GET_IT()` / `__HAL_GPIO_EXTI_CLEAR_IT()` | 手动查 / 清某引脚的 EXTI 标志 |

**关键选项速解**

- **`Mode`**：`GPIO_MODE_OUTPUT_PP` 推挽输出（能拉高拉低）／`OUTPUT_OD` 开漏（需外部上拉）；
  `GPIO_MODE_INPUT` 输入；`GPIO_MODE_AF_PP/OD` 复用给外设；`GPIO_MODE_ANALOG` 模拟（ADC/DAC/OPAMP/COMP 必须用它）；
  `GPIO_MODE_IT_RISING/FALLING/RISING_FALLING` 中断触发；`GPIO_MODE_EVT_*` 只产生事件、不进中断。
- **`Pull`**：`GPIO_NOPULL`／`GPIO_PULLUP`／`GPIO_PULLDOWN`，按键一般用上拉+按下接地。
- **`Speed`**：输出翻转速度档位（LOW→VERY_HIGH），高速 SPI/并口信号要选高，普通 LED 用 LOW 即可（省 EMI）。
- **`Alternate`**：复用功能号，如 `GPIO_AF7_USART1`、`GPIO_AF5_SPI1`、`GPIO_AF13_HRTIM1`。
- **EXTI 线号 = 引脚号**：PA13/PB13/PC13 争用同一条 EXTI13，同一时刻只能有一个端口映射到该线。


### 2.1 CubeMX 配置要点
每个引脚选：`GPIO_Output / GPIO_Input / GPIO_AF（复用，勾外设后自动）/ GPIO_Analog /
External Interrupt Mode（上升/下降/双边沿）/ GPIO_Event Mode`，再设 Pull-up/down、Speed、User Label
（如 `LD2` → 生成 `LD2_Pin`、`LD2_GPIO_Port` 宏）。

### 2.2 生成的代码
```c
void MX_GPIO_Init(void)
{
  GPIO_InitTypeDef GPIO_InitStruct = {0};
  __HAL_RCC_GPIOC_CLK_ENABLE();                       // ① 必须先开端口时钟
  HAL_GPIO_WritePin(GPIOC, GPIO_PIN_0, GPIO_PIN_RESET);// ② 先定初始电平，再配输出
  GPIO_InitStruct.Pin   = GPIO_PIN_0;
  GPIO_InitStruct.Mode  = GPIO_MODE_OUTPUT_PP;         // 推挽输出
  GPIO_InitStruct.Pull  = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(GPIOC, &GPIO_InitStruct);              // ③ 应用配置
  GPIO_InitStruct.Mode  = GPIO_MODE_IT_FALLING;        // 下降沿中断（EXTI）
  HAL_GPIO_Init(GPIOB, &GPIO_InitStruct);
  HAL_NVIC_SetPriority(EXTI15_10_IRQn, 0, 0);          // ④ 使能 EXTI 中断
  HAL_NVIC_EnableIRQ(EXTI15_10_IRQn);
}
```

### 2.3 运行期该用的函数（`stm32g4xx_hal_gpio.h`）

| 函数 | 用途 |
|---|---|
| `HAL_GPIO_Init(GPIO_TypeDef*, GPIO_InitTypeDef*)` | 初始化/重配置引脚 |
| `HAL_GPIO_DeInit(GPIOx, pin)` | 恢复引脚为复位默认值 |
| `HAL_GPIO_WritePin(GPIOx, pin, GPIO_PIN_SET/GPIO_PIN_RESET)` | 输出电平（最常用） |
| `HAL_GPIO_ReadPin(GPIOx, pin)` | 读输入，返回 `GPIO_PinState`（`GPIO_PIN_SET/RESET`） |
| `HAL_GPIO_TogglePin(GPIOx, pin)` | 翻转（点灯） |
| `HAL_GPIO_LockPin(GPIOx, pin)` | 锁定引脚配置，只能复位解锁 |
| `HAL_GPIO_EXTI_IRQHandler(uint16_t GPIO_Pin)` | EXTI 中断入口调用 |
| `HAL_GPIO_EXTI_Callback(uint16_t GPIO_Pin)` | **用户回调**，清标志由 HAL 完成 |

```c
/* 简单用法 */
HAL_GPIO_WritePin(GPIOC, GPIO_PIN_0, GPIO_PIN_SET);
HAL_Delay(500);
HAL_GPIO_TogglePin(GPIOC, GPIO_PIN_0);
if (HAL_GPIO_ReadPin(GPIOA, GPIO_PIN_0) == GPIO_PIN_RESET) { /* 按键按下 */ }

/* 中断用法：在 stm32g4xx_it.c 中（CubeMX 已生成）*/
void EXTI15_10_IRQHandler(void)
{
  HAL_GPIO_EXTI_IRQHandler(GPIO_PIN_13);   // 参数必须是触发中断的引脚
}
/* 你的回调 */
void HAL_GPIO_EXTI_Callback(uint16_t GPIO_Pin)
{
  if (GPIO_Pin == GPIO_PIN_13) { flag = 1; }
}
```

### 2.4 EXTI 的低层专用 API（`stm32g4xx_hal_exti.h`）
动态改边沿触发、软件触发、查挂起位时用：
`HAL_EXTI_GetHandle()`、`HAL_EXTI_SetConfigLine()`、`HAL_EXTI_GetConfigLine()`、
`HAL_EXTI_ClearConfigLine()`、`HAL_EXTI_GetPending()`、`HAL_EXTI_ClearPending()`、
`HAL_EXTI_GenerateSWI()`、`HAL_EXTI_RegisterCallback()`、`HAL_EXTI_IRQHandler()`。

```c
EXTI_ConfigTypeDef cfg = {0};
HAL_EXTI_GetHandle(&hexti13, EXTI_LINE_13);
cfg.Line = EXTI_LINE_13;
cfg.Mode = EXTI_MODE_INTERRUPT;
cfg.Trigger = EXTI_TRIGGER_RISING | EXTI_TRIGGER_FALLING;  // 运行中改触发方式
HAL_EXTI_SetConfigLine(&hexti13, &cfg);
```

> 注意：EXTI 线号 = 引脚号（PA13/PB13/PC13 共用 EXTI13），同一时刻只能有一个端口映射到该线；
> 中断里不要做耗时操作，更不要调用 `HAL_Delay()`（会死等）。

### 完整工程骨架（CubeMX 生成 + 你手写）

**一个引脚输出 + 一个按键中断**的完整工程：

```c
/* ============ Core/Src/gpio.c —— CubeMX 生成 ============ */
void MX_GPIO_Init(void)
{
  GPIO_InitTypeDef GPIO_InitStruct = {0};
  __HAL_RCC_GPIOC_CLK_ENABLE();
  __HAL_RCC_GPIOB_CLK_ENABLE();

  /* LED：推挽输出，初始低电平 */
  HAL_GPIO_WritePin(LD2_GPIO_Port, LD2_Pin, GPIO_PIN_RESET);
  GPIO_InitStruct.Pin   = LD2_Pin;
  GPIO_InitStruct.Mode  = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull  = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(LD2_GPIO_Port, &GPIO_InitStruct);

  /* 按键：上拉输入 + 下降沿中断 */
  GPIO_InitStruct.Pin  = KEY_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_IT_FALLING;
  GPIO_InitStruct.Pull = GPIO_PULLUP;
  HAL_GPIO_Init(KEY_GPIO_Port, &GPIO_InitStruct);

  /* NVIC：CubeMX 自动生成 */
  HAL_NVIC_SetPriority(EXTI15_10_IRQn, 0, 0);
  HAL_NVIC_EnableIRQ(EXTI15_10_IRQn);
}

/* ============ Core/Src/stm32g4xx_it.c —— CubeMX 生成（不用改）============ */
void EXTI15_10_IRQHandler(void)
{
  HAL_GPIO_EXTI_IRQHandler(KEY_Pin);      /* 清标志 + 调回调 */
}
```

```c
/* ============ 以下全部是你手写进 main.c 的 ============ */

/* ---- USER CODE BEGIN PV：回调与主循环之间传数据的全局变量 ---- */
volatile uint8_t g_key_event = 0;

/* ---- USER CODE BEGIN 2：上电初始化后的动作 ---- */
HAL_GPIO_WritePin(LD2_GPIO_Port, LD2_Pin, GPIO_PIN_SET);   /* 开机亮灯 */
if (HAL_GPIO_ReadPin(KEY_GPIO_Port, KEY_Pin) == GPIO_PIN_RESET) { /* 判断开机时按键状态 */ }

/* ---- USER CODE BEGIN 3：主循环（中断里只置标志，业务放这里）---- */
while (1)
{
  if (g_key_event)
  {
    g_key_event = 0;
    HAL_GPIO_TogglePin(LD2_GPIO_Port, LD2_Pin);            /* 每次按键翻灯 */
  }
}

/* ---- USER CODE BEGIN 4：中断回调 ---- */
void HAL_GPIO_EXTI_Callback(uint16_t GPIO_Pin)
{
  if (GPIO_Pin == KEY_Pin) { g_key_event = 1; }
}
```

**手写到别处的常见补充**（都属于"运行期动态操作"）：

```c
/* 运行期把某引脚改成别的功能（比如复用号/模式变了） */
GPIO_InitTypeDef g = {0};
g.Pin = GPIO_PIN_5; g.Mode = GPIO_MODE_OUTPUT_OD; g.Pull = GPIO_NOPULL;
g.Speed = GPIO_SPEED_FREQ_HIGH;
HAL_GPIO_Init(GPIOA, &g);

/* 运行期改 EXTI 的触发边沿（低层 API） */
EXTI_ConfigTypeDef cfg = {0};
HAL_EXTI_GetHandle(&hexti13, EXTI_LINE_13);
cfg.Line = EXTI_LINE_13; cfg.Mode = EXTI_MODE_INTERRUPT;
cfg.Trigger = EXTI_TRIGGER_RISING | EXTI_TRIGGER_FALLING;
HAL_EXTI_SetConfigLine(&hexti13, &cfg);

/* 软件触发一次中断（自测） */
HAL_EXTI_GenerateSWI(&hexti13);
```

---

## 3. NVIC / SysTick / 系统内核（CORTEX）

### 概览

**常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_NVIC_SetPriority(IRQn, pre, sub)` | 设中断优先级（数值越小优先级越高） |
| `HAL_NVIC_EnableIRQ(IRQn)` | 使能某个中断（MspInit 里必须写，否则回调不来） |
| `HAL_NVIC_DisableIRQ(IRQn)` | 关闭某个中断 |
| `HAL_Delay(ms)` | 基于 SysTick 的阻塞延时 |
| `HAL_GetTick()` | 取系统毫秒滴答（做超时/计时） |
| `HAL_SYSTICK_Config(SystemCoreClock/1000)` | 重配 SysTick 周期（默认 1ms 一次） |
| `HAL_InitTick(prio)` | `__weak`，可改用某个 TIM 做时基（RTOS 常用） |
| `HAL_SYSTICK_IRQHandler()` | SysTick 中断入口（`stm32g4xx_it.c` 里已生成） |

**不常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_NVIC_SetPriorityGrouping(g)` | 分配"抢占位 / 子优先级位"的位数 |
| `HAL_NVIC_GetPriority()` / `GetPriorityGrouping()` | 回读优先级设置 |
| `HAL_NVIC_SetPendingIRQ()` / `ClearPendingIRQ()` / `GetPendingIRQ()` | 手动挂起 / 清挂起 / 查询 |
| `HAL_NVIC_GetActive()` | 查当前正在执行的中断 |
| `HAL_NVIC_SystemReset()` | 软件复位芯片 |
| `HAL_SYSTICK_CLKSourceConfig(src)` | SysTick 时钟源（HCLK 或 HCLK/8） |
| `HAL_SYSTICK_Callback()` | SysTick 用户回调（也可直接重写 IRQHandler） |
| `HAL_MPU_Enable/Disable/ConfigRegion/EnableRegion` | MPU 内存保护（划分只读/不可执行区域） |
| `HAL_IncTick()` | 手动累加滴答（换时基时通常不用） |

**关键选项速解**

- **优先级分组**：把 4 位优先级切成"抢占位 + 子优先级位"；裸机常用 `NVIC_PRIORITYGROUP_4`（4 位全抢占，简单好算）。
- **抢占 vs 子优先级**：高抢占可打断低抢占；子优先级只在同时挂起时决定谁先执行，不能互相打断。
- **时基**：HAL 的所有超时判断都基于 1ms 滴答；`HAL_Delay()` 在中断里、关中断时、RTOS 下会出问题。
- **SysTick vs TIM 时基**：用 RTOS 时把 `HAL_InitTick()` 重写为 OS 的 1ms 时基，SysTick 交给 OS。


CubeMX 里在 **System Core → NVIC** 配置优先级分组和每个中断的抢占/子优先级；`SYS` 里选时基源
（SysTick 或某个 TIMx）。生成到 `stm32g4xx_it.c` 与 `stm32g4xx_hal_msp.c`。

```c
/* 中断优先级（数值越小优先级越高） */
HAL_NVIC_SetPriorityGrouping(NVIC_PRIORITYGROUP_4);        // 4 位抢占、0 位子优先级
HAL_NVIC_SetPriority(TIM1_UP_TIM16_IRQn, 1, 0);
HAL_NVIC_EnableIRQ(TIM1_UP_TIM16_IRQn);
HAL_NVIC_DisableIRQ(TIM1_UP_TIM16_IRQn);
/* 查询/触发软件中断 */
HAL_NVIC_GetPriority(...); HAL_NVIC_SetPendingIRQ(...); HAL_NVIC_ClearPendingIRQ(...);
HAL_NVIC_SystemReset();                                   // 软复位
```

| SysTick / 系统函数 | 说明 |
|---|---|
| `HAL_Init()` | 初始化 Flash 预取、HAL、SysTick 1ms（内部调用 `HAL_InitTick`） |
| `HAL_InitTick(TickPriority)` | `__weak`，可重写为用其它定时器做时基（RTOS 下常改） |
| `HAL_SYSTICK_Config(SystemCoreClock/1000)` | 重新配置 1ms 滴答 |
| `HAL_SYSTICK_CLKSourceConfig(SYSTICK_CLKSOURCE_HCLK)` | SysTick 时钟源 |
| `HAL_Delay(ms)` / `HAL_GetTick()` / `HAL_IncTick()` | 阻塞延时 / 取滴答 / 滴答自增 |
| `HAL_SYSTICK_IRQHandler()` + `HAL_SYSTICK_Callback()` | SysTick 中断与用户回调 |

MPU（G4 有）：`HAL_MPU_Enable/Disable()`、`HAL_MPU_ConfigRegion()`、`HAL_MPU_EnableRegion()`。

> 常见坑：`HAL_Delay()` 依赖 SysTick 中断，在**中断里或关中断状态下调用会卡死**；RTOS 下要把
> `HAL_InitTick()` 改到 1ms 的 OS 时基上。

### 完整工程骨架（CubeMX 生成 + 你手写）

NVIC/SysTick **没有自己的 `.c` 文件**，代码分布在 `main.c`、`stm32g4xx_it.c` 和 `stm32g4xx_hal_msp.c` 里：

```c
/* ============ Core/Src/stm32g4xx_it.c —— CubeMX 生成 ============ */
void SysTick_Handler(void)  { HAL_IncTick(); }     /* 1ms 滴答，HAL_Delay 靠它 */
void NMI_Handler(void)      { while (1) {} }
void HardFault_Handler(void){ while (1) {} }
void SVC_Handler(void)      { }
void PendSV_Handler(void)   { }

/* CubeMX 会为每个使能的中断生成对应 ISR，例如： */
void EXTI15_10_IRQHandler(void) { HAL_GPIO_EXTI_IRQHandler(GPIO_PIN_13); }
void TIM2_IRQHandler(void)      { HAL_TIM_IRQHandler(&htim2); }
void USART1_IRQHandler(void)    { HAL_UART_IRQHandler(&huart1); }
```

```c
/* ============ Core/Src/stm32g4xx_hal_msp.c —— CubeMX 生成 ============ */
void HAL_MspInit(void)                     /* HAL_Init() 会调用它 */
{
  __HAL_RCC_SYSCFG_CLK_ENABLE();
  __HAL_RCC_PWR_CLK_ENABLE();
  HAL_NVIC_SetPriorityGrouping(NVIC_PRIORITYGROUP_4);   /* 优先级分组 */
}
/* 各外设 MspInit 里的中断使能也是 CubeMX 生成的： */
void HAL_TIM_Base_MspInit(TIM_HandleTypeDef *htim)
{
  __HAL_RCC_TIM2_CLK_ENABLE();
  HAL_NVIC_SetPriority(TIM2_IRQn, 1, 0);
  HAL_NVIC_EnableIRQ(TIM2_IRQn);
}
```

```c
/* ============ 你手写的部分 ============ */

/* ① main.c：USER CODE BEGIN SysInit / Init —— 想改优先级就在外设初始化之后再设一次 */
HAL_NVIC_SetPriority(USART1_IRQn, 2, 0);      /* 数字越小优先级越高 */
HAL_NVIC_EnableIRQ(USART1_IRQn);

/* ② 想在别处重新安排中断（比如临时屏蔽某个中断） */
HAL_NVIC_DisableIRQ(ADC1_2_IRQn);
HAL_NVIC_EnableIRQ(ADC1_2_IRQn);

/* ③ 用其它定时器替代 SysTick 做 HAL 时基（RTOS 或需要更高精度时）*/
/* 把下列函数放到 main.c 的 USER CODE BEGIN 4 —— 它会覆盖 HAL 的弱定义 */
// HAL_StatusTypeDef HAL_InitTick(uint32_t TickPriority)
// {
//   /* 让 TIM6 每 1ms 中断一次，中断里调用 HAL_IncTick() */
//   return HAL_OK;
// }

/* ④ SysTick 回调（需要在每个滴答做事时） */
void HAL_SYSTICK_Callback(void) { /* 1ms 一次，越短越好 */ }
```

**CubeMX 里对应的配置位置**（都不产生新文件，只影响生成内容）：
- `System Core → SYS → Timebase Source`：选 SysTick 还是某个 TIMx 作为 HAL 时基；
- `System Core → NVIC`：每个中断的**抢占/子优先级**、是否使能；
- `System Core → NVIC → Code generation`：`Generate IRQ handler`（生成 ISR）/ `Call HAL handler`（ISR 里调 HAL）。

---

## 4. RCC 时钟系统

### 概览

**常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_RCC_OscConfig(&RCC_OscInitStruct)` | 开关振荡器（HSE/HSI/HSI48/LSE/LSI）并配置 PLL |
| `HAL_RCC_ClockConfig(&RCC_ClkInitStruct, FLASH_LATENCY_x)` | 设 SYSCLK 来源、AHB/APB 分频、Flash 等待周期 |
| `HAL_RCCEx_PeriphCLKConfig(&PeriphClkInit)` | 给外设选独立时钟源（UART/ADC/RTC/HRTIM/USB/FDCAN…） |
| `HAL_RCC_GetSysClockFreq()` / `GetHCLKFreq()` / `GetPCLK1Freq()` / `GetPCLK2Freq()` | 读各总线频率（算波特率、定时器分频的基础） |
| `HAL_RCCEx_GetPeriphCLKFreq(RCC_PERIPHCLK_xxx)` | 读某个外设的实际时钟频率 |
| `__HAL_RCC_<外设>_CLK_ENABLE()/_DISABLE()` | 外设时钟门控（MspInit 必写） |
| `HAL_PWREx_ControlVoltageScaling(PWR_REGULATOR_VOLTAGE_SCALE1)` | 设调压器档位（决定能跑多高主频） |

**不常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_RCC_MCOConfig(src, div)` | 把内部时钟输出到 MCO 引脚（示波器验证频率） |
| `HAL_RCC_EnableCSS()` + `HAL_RCC_CSSCallback()` | 时钟安全系统：HSE 停振自动切 HSI 并进回调 |
| `HAL_RCC_EnableLSECSS()` / `HAL_RCCEx_EnableLSECSS_IT()` | LSE 失效检测（RTC 场景） |
| `HAL_RCCEx_CRSConfig()` / `CRSWaitSynchronization()` / `CRSGetSynchronizationInfo()` | CRS：用 USB SOF 校准 HSI48 |
| `HAL_RCCEx_EnableLSCO()` / `DisableLSCO()` | 把 LSE/LSI 输出到引脚（给外部芯片当时钟） |
| `HAL_RCC_GetOscConfig()` / `HAL_RCC_GetClockConfig()` | 回读当前振荡器/时钟配置 |
| `HAL_RCC_DeInit()` | 复位 RCC 回到 HSI 8MHz（低功耗唤醒后常用） |

**关键选项速解**

- **`OscillatorType`**：本次要配置哪几个振荡器（HSE / HSI / HSI48 / LSE / LSI 可组合）。
- **PLL 参数**：`PLLSource`（HSE 或 HSI）+ `PLLM`(输入分频) → `PLLN`(倍频) → `PLLP/Q/R`(输出分频)；
  其中 P 管 ADC 时钟、Q 管 USB/FDCAN 类 48MHz 外设、R 管 SYSCLK。
- **`SYSCLKSource`**：HSI / HSE / PLLCLK（跑高频必须用 PLL）。
- **AHB/APB1/APB2 分频**：APB 分频 ≠1 时，挂在 APB 上的定时器时钟是 PCLK×2，算分频时别搞错。
- **`FLASH_LATENCY_x`**：必须与主频匹配（主频越高需要越大），配错会跑飞或死机。
- **`PeriphClockSelection`**：一次调用可配多个外设的时钟源（如同时给 UART1 选 PCLK2、给 ADC 选 SYSCLK）。


CubeMX 里在 **Clock Configuration** 选项卡直接画时钟树，生成 `SystemClock_Config()`。

### 4.1 运行期常用的初始化函数
```c
void SystemClock_Config(void)   /* CubeMX 生成，一般不用改 */
{
  RCC_OscInitTypeDef RCC_OscInitStruct = {0};
  RCC_ClkInitTypeDef RCC_ClkInitStruct = {0};

  HAL_PWREx_ControlVoltageScaling(PWR_REGULATOR_VOLTAGE_SCALE1);  // 先设调压器档位
  /* ① HSE/HSI/HSI48/LSE/PLL 配置 */
  RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_HSE | RCC_OSCILLATORTYPE_HSI48;
  RCC_OscInitStruct.HSEState      = RCC_HSE_ON;
  RCC_OscInitStruct.PLL.PLLState  = RCC_PLL_ON;
  RCC_OscInitStruct.PLL.PLLSource = RCC_PLLSOURCE_HSE;
  RCC_OscInitStruct.PLL.PLLM = RCC_PLLM_DIV4;  /* PLLN/PLLP/PLLQ/PLLR 见生成的代码 */
  if (HAL_RCC_OscConfig(&RCC_OscInitStruct) != HAL_OK) { Error_Handler(); }

  /* ② SYSCLK / HCLK / PCLK1 / PCLK2 分频 + Flash 延迟 */
  RCC_ClkInitStruct.ClockType      = RCC_CLOCKTYPE_HCLK | RCC_CLOCKTYPE_SYSCLK
                                   | RCC_CLOCKTYPE_PCLK1 | RCC_CLOCKTYPE_PCLK2;
  RCC_ClkInitStruct.SYSCLKSource   = RCC_SYSCLKSOURCE_PLLCLK;
  RCC_ClkInitStruct.AHBCLKDivider  = RCC_SYSCLK_DIV1;
  RCC_ClkInitStruct.APB1CLKDivider = RCC_HCLK_DIV1;
  RCC_ClkInitStruct.APB2CLKDivider = RCC_HCLK_DIV1;
  if (HAL_RCC_ClockConfig(&RCC_ClkInitStruct, FLASH_LATENCY_4) != HAL_OK) { Error_Handler(); }
}
```

### 4.2 外设独立时钟源（UART/ADC/RTC/HRTIM/USB…）
```c
RCC_PeriphCLKInitTypeDef PeriphClkInit = {0};
PeriphClkInit.PeriphClockSelection  = RCC_PERIPHCLK_USART1;
PeriphClkInit.Usart1ClockSelection  = RCC_USART1CLKSOURCE_PCLK2;   // 也可选 SYSCLK/HSI/LSE
if (HAL_RCCEx_PeriphCLKConfig(&PeriphClkInit) != HAL_OK) { Error_Handler(); }
```
> HRTIM 时钟源必须在 HRTIM 的 MspInit 里选：`PeriphClkInit.Hrtim1ClockSelection =
> RCC_HRTIM1CLK_PLLCLK;`（要 144/170MHz 满速高分辨率就选 PLL）。

### 4.3 读取与输出时钟
```c
uint32_t f_sysclk = HAL_RCC_GetSysClockFreq();
uint32_t f_hclk   = HAL_RCC_GetHCLKFreq();
uint32_t f_pclk1  = HAL_RCC_GetPCLK1Freq();   // 定时器实际时钟 = 2×PCLK1（当 APB 分频≠1）
uint32_t f_pclk2  = HAL_RCC_GetPCLK2Freq();
uint32_t f_adc    = HAL_RCCEx_GetPeriphCLKFreq(RCC_PERIPHCLK_ADC12);
HAL_RCC_MCOConfig(RCC_MCO1, RCC_MCO1SOURCE_SYSCLK, RCC_MCODIV_1);  // 引脚输出时钟，示波器量频
```

### 4.4 安全/校准类
| 函数 | 用途 |
|---|---|
| `HAL_RCC_EnableCSS()` / `HAL_RCC_CSSCallback()` | HSE 时钟失效检测（自动切 HSI） |
| `HAL_RCC_EnableLSECSS()` / `HAL_RCCEx_EnableLSECSS_IT()` | LSE 失效检测 |
| `HAL_RCCEx_CRSConfig()` + `HAL_RCCEx_CRSWaitSynchronization()` | CRS：用 USB SOF 校准 HSI48 |
| `HAL_RCCEx_GetPeriphCLKConfig()` / `HAL_RCC_GetOscConfig()` / `HAL_RCC_GetClockConfig()` | 回读配置 |
| `HAL_RCC_DeInit()` | 复位 RCC |

### 4.5 最常用的时钟宏
```c
__HAL_RCC_GPIOA_CLK_ENABLE();   __HAL_RCC_DMA1_CLK_ENABLE();
__HAL_RCC_ADC12_CLK_ENABLE();   __HAL_RCC_USART1_CLK_ENABLE();
__HAL_RCC_TIM1_CLK_ENABLE();    __HAL_RCC_HRTIM1_CLK_ENABLE();  __HAL_RCC_HRTIM1_CONFIG(...);
__HAL_RCC_GET_SYSCLK_SOURCE();  __HAL_RCC_GET_FLAG(RCC_FLAG_HSERDY);
```

### 完整工程骨架（CubeMX 生成 + 你手写）

RCC 的生成物是 `main.c` 里的 `SystemClock_Config()` + 各外设 MspInit 里的时钟源选择：

```c
/* ============ main.c —— CubeMX 生成（一般不用改）============ */
void SystemClock_Config(void)
{
  RCC_OscInitTypeDef RCC_OscInitStruct = {0};
  RCC_ClkInitTypeDef RCC_ClkInitStruct = {0};

  HAL_PWREx_ControlVoltageScaling(PWR_REGULATOR_VOLTAGE_SCALE1);   /* 调压器档位 */

  RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_HSE | RCC_OSCILLATORTYPE_HSI48;
  RCC_OscInitStruct.HSEState       = RCC_HSE_ON;
  RCC_OscInitStruct.HSI48State     = RCC_HSI48_ON;                 /* USB 用 */
  RCC_OscInitStruct.PLL.PLLState   = RCC_PLL_ON;
  RCC_OscInitStruct.PLL.PLLSource  = RCC_PLLSOURCE_HSE;
  RCC_OscInitStruct.PLL.PLLM       = RCC_PLLM_DIV4;
  RCC_OscInitStruct.PLL.PLLN       = 25;                           /* 170MHz 方案 */
  RCC_OscInitStruct.PLL.PLLP       = RCC_PLLP_DIV2;
  RCC_OscInitStruct.PLL.PLLQ       = RCC_PLLQ_DIV2;
  RCC_OscInitStruct.PLL.PLLR       = RCC_PLLR_DIV2;
  if (HAL_RCC_OscConfig(&RCC_OscInitStruct) != HAL_OK) { Error_Handler(); }

  RCC_ClkInitStruct.ClockType      = RCC_CLOCKTYPE_HCLK | RCC_CLOCKTYPE_SYSCLK
                                   | RCC_CLOCKTYPE_PCLK1 | RCC_CLOCKTYPE_PCLK2;
  RCC_ClkInitStruct.SYSCLKSource   = RCC_SYSCLKSOURCE_PLLCLK;
  RCC_ClkInitStruct.AHBCLKDivider  = RCC_SYSCLK_DIV1;
  RCC_ClkInitStruct.APB1CLKDivider = RCC_HCLK_DIV1;
  RCC_ClkInitStruct.APB2CLKDivider = RCC_HCLK_DIV1;
  if (HAL_RCC_ClockConfig(&RCC_ClkInitStruct, FLASH_LATENCY_4) != HAL_OK) { Error_Handler(); }
}

/* ============ usart.c / adc.c 等的 MspInit —— CubeMX 生成 ============ */
void HAL_UART_MspInit(UART_HandleTypeDef* uartHandle)
{
  RCC_PeriphCLKInitTypeDef PeriphClkInit = {0};
  if (uartHandle->Instance == USART1)
  {
    PeriphClkInit.PeriphClockSelection = RCC_PERIPHCLK_USART1;      /* 外设时钟源 */
    PeriphClkInit.Usart1ClockSelection = RCC_USART1CLKSOURCE_PCLK2;
    HAL_RCCEx_PeriphCLKConfig(&PeriphClkInit);
    __HAL_RCC_USART1_CLK_ENABLE();                                  /* 门控 */
    /* GPIO / NVIC / DMA ... */
  }
}
```

```c
/* ============ 你手写的部分 ============ */

/* ① 上电打印实际频率（排查时钟问题的第一招）*/
printf("SYSCLK=%lu HCLK=%lu PCLK1=%lu PCLK2=%lu\r\n",
       HAL_RCC_GetSysClockFreq(), HAL_RCC_GetHCLKFreq(),
       HAL_RCC_GetPCLK1Freq(), HAL_RCC_GetPCLK2Freq());

/* ② 把某个时钟输出到 MCO 引脚，用示波器量（排查晶振/PLL 是否真跑起来）*/
HAL_RCC_MCOConfig(RCC_MCO1, RCC_MCO1SOURCE_SYSCLK, RCC_MCODIV_4);

/* ③ 时钟安全系统：HSE 掉电自动切 HSI，并在回调里记录/闪灯报警
      （先在 USER CODE 里使能，再实现弱回调）*/
HAL_RCC_EnableCSS();
void HAL_RCC_CSSCallback(void) { /* HSE 失效了 */ }

/* ④ 运行期换外设时钟源（例如 ADC 想从 PCLK 切到 PLLP）*/
RCC_PeriphCLKInitTypeDef pclk = {0};
pclk.PeriphClockSelection = RCC_PERIPHCLK_ADC12;
pclk.Adc12ClockSelection  = RCC_ADC12CLKSOURCE_PLL;
HAL_RCCEx_PeriphCLKConfig(&pclk);

/* ⑤ 低功耗唤醒后（Stop）时钟会被切回 HSI，必须重新配置 */
// SystemClock_Config();
```

**CubeMX 配置入口**：`Clock Configuration` 页（图形化时钟树）→ 自动生成上面两个函数；
外设独立时钟源在**每个外设的 Parameter 页**里勾选（或在时钟树里点对应外设的分频器）。

---

## 5. DMA + DMAMUX

### 概览

**常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_DMA_Init(&hdma)` | 配通道：请求号、方向、地址递增、数据宽度、模式、优先级 |
| `__HAL_LINKDMA(&hxxx, DMA_Handle, hdma)` | 把 DMA 句柄挂到外设句柄（用 `_DMA` 版本的前提） |
| 外设的 `HAL_xxx_Start_DMA()` / `Transmit_DMA()` / `Receive_DMA()` | 真正启动传输的入口（推荐用这些，而不是直接玩 DMA） |
| `HAL_DMA_Abort(&hdma)` / `HAL_DMA_Abort_IT()` | 终止传输 |
| `HAL_DMA_IRQHandler(&hdma)` | DMA 中断入口（在 `DMAx_Channely_IRQHandler` 里调用） |
| `__HAL_DMA_GET_COUNTER(&hdma)` | 读剩余传输数量（环形缓冲算写入位置） |

**不常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_DMA_Start()` / `HAL_DMA_Start_IT(&hdma, src, dst, len)` | 不经过外设，手动搬一次数据 |
| `HAL_DMA_PollForTransfer(&hdma, level, timeout)` | 阻塞等传输完成 |
| `HAL_DMA_DeInit()` / `GetState()` / `GetError()` | 反初始化 / 查状态 / 查错误 |
| `HAL_DMA_RegisterCallback()` | 注册 `XferCplt` / `XferHalfCplt` / `XferError` / `XferAbort` 回调 |
| `HAL_DMAEx_ConfigMuxRequestGenerator()` + `EnableMuxRequestGenerator()` | 让 DMAMUX 用事件（EXTI/TIM）自动产生 DMA 请求 |
| `HAL_DMAEx_ConfigMuxSync()` | 请求同步 / 门控（按事件"放行"请求） |
| `HAL_DMAEx_MUX_IRQHandler()` | DMAMUX 中断入口 |
| `__HAL_DMA_ENABLE_IT(&hdma, DMA_IT_HT)` | 开半传输中断（流式处理的节拍） |

**关键选项速解**

- **`Request`**：DMAMUX 请求号，决定"谁触发 DMA"，如 `DMA_REQUEST_ADC1`、`DMA_REQUEST_USART1_TX`。
- **`Direction`**：外设→内存 / 内存→外设 / 内存↔内存。
- **`PeriphInc` / `MemInc`**：地址是否自增——外设寄存器地址固定（DISABLE），缓冲区要自增（ENABLE）。
- **对齐 `PeriphDataAlignment`/`MemDataAlignment`**：BYTE/HALFWORD/WORD，两边要匹配，否则数据错位。
- **`Mode`**：`DMA_NORMAL` 只搬一次；`DMA_CIRCULAR` 循环不停（ADC 连续采集、音频播放必须）。
- **`Priority`**：通道之间抢总线时的优先级。
- **中断**：`DMA_IT_TC` 传输完成、`DMA_IT_HT` 半传输、`DMA_IT_TE` 出错。


CubeMX 里在 **DMA Settings** 页给外设加通道，选方向、优先级、普通/循环模式、数据宽度；
G4 的请求是 **DMAMUX**（每个通道可选任意请求号），生成 `MX_DMA_Init()` + 外设 MspInit 里的
`__HAL_LINKDMA()`。

### 5.1 生成的代码（在 adc.c 的 `HAL_ADC_MspInit` 里）
```c
hdma_adc1.Instance                 = DMA1_Channel1;
hdma_adc1.Init.Request             = DMA_REQUEST_ADC1;      // DMAMUX 请求号
hdma_adc1.Init.Direction           = DMA_PERIPH_TO_MEMORY;
hdma_adc1.Init.PeriphInc           = DMA_PINC_DISABLE;
hdma_adc1.Init.MemInc              = DMA_MINC_ENABLE;       // 内存地址递增
hdma_adc1.Init.PeriphDataAlignment = DMA_PDATAALIGN_HALFWORD;
hdma_adc1.Init.MemDataAlignment    = DMA_MDATAALIGN_HALFWORD;
hdma_adc1.Init.Mode                = DMA_CIRCULAR;          // 循环模式
hdma_adc1.Init.Priority            = DMA_PRIORITY_HIGH;
if (HAL_DMA_Init(&hdma_adc1) != HAL_OK) { Error_Handler(); }
__HAL_LINKDMA(adcHandle, DMA_Handle, hdma_adc1);            // 关键：把 DMA 挂到外设句柄
HAL_NVIC_SetPriority(DMA1_Channel1_IRQn, 0, 0); HAL_NVIC_EnableIRQ(DMA1_Channel1_IRQn);
```

### 5.2 运行期该用的函数（`stm32g4xx_hal_dma.h`）

| 函数 | 用途 |
|---|---|
| `HAL_DMA_Init(&hdma)` / `HAL_DMA_DeInit()` | 初始化/反初始化通道 |
| `HAL_DMA_Start(&hdma, SrcAddress, DstAddress, DataLength)` | 手动启动（不推荐，通常用外设的 `_DMA` 函数） |
| `HAL_DMA_Start_IT(&hdma, Src, Dst, Length)` | 手动启动 + 传输完成中断 |
| `HAL_DMA_Abort(&hdma)` / `HAL_DMA_Abort_IT(&hdma)` | 停止传输 |
| `HAL_DMA_PollForTransfer(&hdma, HAL_DMA_FULL_TRANSFER, Timeout)` | 阻塞等待完成 |
| `HAL_DMA_IRQHandler(&hdma)` | 中断入口（在 `DMA1_Channel1_IRQHandler` 里调用） |
| `HAL_DMA_GetState()` / `HAL_DMA_GetError()` | 状态/错误码 |
| `HAL_DMA_RegisterCallback()` | 注册 `XferCpltCallback / XferHalfCpltCallback / XferErrorCallback / XferAbortCallback` |

```c
/* 手动启动一次内存→外设传输（例如自己组帧） */
HAL_DMA_Start_IT(&hdma_usart1_tx, (uint32_t)buf, (uint32_t)&USART1->TDR, len);
```

### 5.3 DMAMUX 高级用法（`stm32g4xx_hal_dma_ex.h`）
请求发生器（用定时器/EXTI 事件自动触发 DMA）：
`HAL_DMAEx_ConfigMuxRequestGenerator()`、`HAL_DMAEx_EnableMuxRequestGenerator()`、
`HAL_DMAEx_DisableMuxRequestGenerator()`、`HAL_DMAEx_ConfigMuxSync()`（同步/门控）、
`HAL_DMAEx_MUX_IRQHandler()`。

```c
HAL_DMA_MuxRequestGeneratorConfigTypeDef rg = {0};
rg.SignalID      = HAL_DMAMUX1_REQ_GEN_EXTI0;   // 触发源（EXTI/TIM/…）
rg.Polarity      = HAL_DMAMUX_REQ_GEN_RISING;   // 边沿
rg.RequestNumber = 1;                            // 一次事件产生几个请求（1~32）
HAL_DMAEx_ConfigMuxRequestGenerator(&hdma, &rg);
HAL_DMAEx_EnableMuxRequestGenerator(&hdma);
```

### 5.4 常用的 DMA 宏
```c
__HAL_DMA_GET_COUNTER(&hdma_adc1);              // 剩余传输次数（环形缓冲里很有用）
__HAL_DMA_DISABLE_IT(&hdma, DMA_IT_TC);
__HAL_DMA_ENABLE_IT(&hdma, DMA_IT_HT);          // 半传输中断
__HAL_LINKDMA(&hadc1, DMA_Handle, hdma_adc1);   // 关联
__HAL_DMA_ENABLE(&hdma); __HAL_DMA_DISABLE(&hdma);
```

> 注意：① DMA 中断优先级要低于（数值大于）用到它的外设中断里的关键操作；
> ② 用 `_DMA` 发送时缓冲区生命周期必须覆盖传输过程（别用局部数组）；
> ③ 把 DMA 中断优先级设得比 SPI/I2C 中断低，避免 HAL 状态机冲突。

### 完整工程骨架（CubeMX 生成 + 你手写）

以"ADC1 用 DMA 循环采集"为例（其它外设的 DMA 骨架完全同构）：

```c
/* ============ Core/Src/dma.c —— CubeMX 生成 ============ */
void MX_DMA_Init(void)
{
  __HAL_RCC_DMAMUX1_CLK_ENABLE();
  __HAL_RCC_DMA1_CLK_ENABLE();
  /* DMA 中断（要不要中断取决于你在 CubeMX 里有没有勾） */
  HAL_NVIC_SetPriority(DMA1_Channel1_IRQn, 0, 0);
  HAL_NVIC_EnableIRQ(DMA1_Channel1_IRQn);
}

/* ============ Core/Src/adc.c 里的 MspInit —— CubeMX 生成 ============ */
DMA_HandleTypeDef hdma_adc1;

void HAL_ADC_MspInit(ADC_HandleTypeDef* adcHandle)
{
  if (adcHandle->Instance == ADC1)
  {
    __HAL_RCC_ADC12_CLK_ENABLE();
    /* 通道参数：CubeMX 按你在 DMA Settings 页填的生成 */
    hdma_adc1.Instance                 = DMA1_Channel1;
    hdma_adc1.Init.Request             = DMA_REQUEST_ADC1;        /* DMAMUX 请求号 */
    hdma_adc1.Init.Direction           = DMA_PERIPH_TO_MEMORY;
    hdma_adc1.Init.PeriphInc           = DMA_PINC_DISABLE;
    hdma_adc1.Init.MemInc              = DMA_MINC_ENABLE;
    hdma_adc1.Init.PeriphDataAlignment = DMA_PDATAALIGN_HALFWORD;
    hdma_adc1.Init.MemDataAlignment    = DMA_MDATAALIGN_HALFWORD;
    hdma_adc1.Init.Mode                = DMA_CIRCULAR;
    hdma_adc1.Init.Priority            = DMA_PRIORITY_HIGH;
    if (HAL_DMA_Init(&hdma_adc1) != HAL_OK) { Error_Handler(); }

    __HAL_LINKDMA(adcHandle, DMA_Handle, hdma_adc1);              /* 关联，必须 */
  }
}

/* ============ Core/Src/stm32g4xx_it.c —— CubeMX 生成 ============ */
void DMA1_Channel1_IRQHandler(void) { HAL_DMA_IRQHandler(&hdma_adc1); }
```

```c
/* ============ 你手写的部分 ============ */

/* ① main.c USER CODE BEGIN PV：DMA 目标缓冲区（必须是全局/静态，不能是局部变量）*/
#define ADC_BUF_LEN 256
uint16_t adc_dma_buf[ADC_BUF_LEN];
volatile uint8_t adc_half_ready = 0, adc_full_ready = 0;

/* ② main.c USER CODE BEGIN 2：启动传输（用外设的 _DMA 入口，而不是裸 DMA）*/
HAL_ADC_Start_DMA(&hadc1, (uint32_t *)adc_dma_buf, ADC_BUF_LEN);
__HAL_DMA_DISABLE_IT(&hdma_adc1, DMA_IT_HT);      /* 不要半传输中断就关掉 */

/* ③ 若想让 DMA 支持半传输中断（双缓冲流式处理），自己注册回调 */
void MyDmaHalfCplt(DMA_HandleTypeDef *hdma) { adc_half_ready = 1; }
void MyDmaCplt    (DMA_HandleTypeDef *hdma) { adc_full_ready = 1; }
// 在 USER CODE BEGIN 2 里：
// hdma_adc1.XferHalfCpltCallback = MyDmaHalfCplt;
// hdma_adc1.XferCpltCallback     = MyDmaCplt;
/* 或者用 HAL 的注册接口（需开启 USE_HAL_DMA_REGISTER_CALLBACKS）：
   HAL_DMA_RegisterCallback(&hdma_adc1, HAL_DMA_XFER_CPLT_CB_ID, MyDmaCplt); */

/* ④ 运行期查进度：剩余传输次数 → 算出当前写到哪 */
uint32_t pos = ADC_BUF_LEN - __HAL_DMA_GET_COUNTER(&hdma_adc1);

/* ⑤ 手动搬一次数据（不经过外设，比如内存→内存拷贝）*/
HAL_DMA_Start_IT(&hdma_mem2mem, (uint32_t)src, (uint32_t)dst, len);

/* ⑥ 停止/重启传输 */
HAL_ADC_Stop_DMA(&hadc1);
HAL_DMA_Abort(&hdma_adc1);          /* 或 HAL_DMA_Abort_IT() */

/* ⑦ DMAMUX 请求发生器：让 EXTI/TIM 事件自动触发 DMA（不占外设请求）*/
HAL_DMA_MuxRequestGeneratorConfigTypeDef rg = {0};
rg.SignalID      = HAL_DMAMUX1_REQ_GEN_EXTI0;
rg.Polarity      = HAL_DMAMUX_REQ_GEN_RISING;
rg.RequestNumber = 1;
HAL_DMAEx_ConfigMuxRequestGenerator(&hdma, &rg);
HAL_DMAEx_EnableMuxRequestGenerator(&hdma);
```

**CubeMX 里对应的配置位置**：外设页 → `DMA Settings → Add` → 选通道/方向/模式/优先级（生成上面那段）；
`System Core → DMA` 里能统一看所有通道；DMAMUX 的请求号就是在这里自动填的。

---

## 6. TIM 通用/高级定时器

### 概览

**常用 API（80% 的场景只用这些）**

| API | 一句话作用 |
|---|---|
| `HAL_TIM_Base_Init(&htim)` | 配时基：Prescaler / Period / 计数模式 / 预装载 |
| `HAL_TIM_Base_Start[_IT]()` / `HAL_TIM_Base_Stop[_IT]()` | 启动/停止计数（`_IT` 顺带开更新中断） |
| `HAL_TIM_PWM_ConfigChannel(&htim, &sConfigOC, TIM_CHANNEL_x)` | 配某个通道为 PWM（模式/脉宽/极性） |
| `HAL_TIM_PWM_Start[_IT/_DMA]()` / `HAL_TIM_PWM_Stop*()` | 启动/停止 PWM 输出 |
| `__HAL_TIM_SET_COMPARE(&htim, ch, v)` | **运行期改占空比**（最快的方式） |
| `__HAL_TIM_SET_AUTORELOAD()` / `__HAL_TIM_SET_PRESCALER()` | 改频率 |
| `__HAL_TIM_GET_COUNTER()` / `__HAL_TIM_SET_COUNTER()` | 读/写当前计数（编码器位置、同步清零） |
| `HAL_TIM_IRQHandler(&htim)` | 中断入口（`TIMx_IRQHandler` 里调用） |
| `HAL_TIM_PeriodElapsedCallback()` | 更新中断回调（周期任务） |
| `HAL_TIM_IC_CaptureCallback()` + `HAL_TIM_ReadCapturedValue()` | 捕获中断回调 + 读捕获值 |

**较常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_TIM_IC_ConfigChannel()` / `HAL_TIM_IC_Start[_IT/_DMA]()` | 输入捕获（测频率/脉宽） |
| `HAL_TIM_OC_*` / `HAL_TIMEx_OCN_*` | 输出比较（到点翻转/置位） |
| `HAL_TIM_Encoder_Init()` / `HAL_TIM_Encoder_Start()` | 正交编码器接口 |
| `HAL_TIMEx_ConfigBreakDeadTime()` | 刹车 + 死区（互补 PWM 必配） |
| `HAL_TIMEx_PWMN_Start[_IT/_DMA]()` | 互补通道输出 |
| `HAL_TIMEx_MasterConfigSynchronization()` | 主模式：把本定时器的 TRGO 送给别的外设（ADC/DAC/其它 TIM） |
| `HAL_TIM_SlaveConfigSynchro()` | 从模式：被复位/门控/触发 |
| `HAL_TIM_ConfigClockSource()` | 内部时钟 / 外部 ETR / 其它定时器 ITR 作时钟 |
| `HAL_TIM_GenerateEvent(&htim, TIM_EVENTSOURCE_UPDATE)` | 软件产生更新事件（立即重装寄存器） |

**不常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_TIM_OnePulse_Init/Start` / `HAL_TIMEx_OnePulseN_Start` | 单脉冲输出（精确一个脉冲宽度） |
| `HAL_TIMEx_HallSensor_Init/Start` | 直流无刷电机霍尔接口 |
| `HAL_TIM_DMABurst_WriteStart` / `MultiWriteStart` / `ReadStart` | DMA 突发批量改寄存器（多通道波形） |
| `HAL_TIMEx_ConfigCommutEvent[_IT/_DMA]` | 换相事件（BLDC 六步换相） |
| `HAL_TIMEx_ConfigBreakInput()` / `ConfigDeadTime()` / `ConfigAsymmetricalDeadTime()` | 运行期改刹车源 / 只改死区 / 不对称死区 |
| `HAL_TIMEx_ReArmBreakInput()` / `DisarmBreakInput()` | 刹车后重新武装 / 临时屏蔽刹车 |
| `HAL_TIMEx_DitheringEnable()` | 抖动功能：等效提高 PWM 分辨率 |
| `HAL_TIMEx_TISelection()` / `RemapConfig()` / `GroupChannel5()` | 输入映射 / 引脚重映射 / 通道 5 组合 |
| `HAL_TIMEx_ConfigEncoderIndex()` / `EnableEncoderIndex()` | 编码器 Z 相索引信号 |
| `HAL_TIM_GetActiveChannel()` / `GetChannelState()` / `HAL_TIM_ErrorCallback()` | 诊断用 |

**关键选项速解**

- **时基**：`Prescaler`、`CounterMode`（UP/DOWN/CENTERALIGNED1~3）、`Period`(ARR)、`ClockDivision`、`AutoReloadPreload`；
  频率 = `f_tim / ((PSC+1) × (ARR+1))`。
- **PWM 侧**：`OCMode`（PWM1 正常/ PWM2 反相 / Toggle 翻转）、`Pulse`（比较值，占空比 = Pulse/(ARR+1)）、
  `OCPolarity`（有效电平极性）、`OCFastMode`（高速下不延迟响应）。
- **输入捕获侧**：`ICPolarity`（上升/下降/双边沿）、`ICSelection`（DIRECTTI 直连 / INDIRECTTI 间接）、
  `ICPrescaler`（几个事件捕获一次）、`ICFilter`（数字滤波抗抖动）。
- **编码器**：`EncoderMode`（TI1 / TI2 / TI12 四倍频），配合 `__HAL_TIM_GET_COUNTER` 读位置。
- **死区/刹车**：`DeadTime` 死区步数（按 DTG 分档，几十~几百 ns）、`BreakState`/`BreakPolarity`/`BreakFilter`、
  `AutomaticOutput`（刹车恢复后是否自动恢复输出）。
- **从模式**：`SlaveMode`（RESET 复位计数 / GATED 门控 / TRIGGER 触发启动 / EXTERNAL1）、
  `InputTrigger`（ITR0~ITR3 来自别的定时器、ETR 外部引脚、TI1/TI2）。
- **高级定时器才有**：TIM1/TIM8/TIM20 支持互补输出、死区、刹车、重复计数器。


CubeMX 里 **Timers → TIMx** 每个通道 4 选 1：`Output Compare / PWM Generation / Input Capture /
Forced Output`，加上 Clock Source（Internal/External/Encoder）、Prescaler、Counter Period、
PWM Generation 的 `Mode(PWM1/PWM2)`、`Pulse`、`Fast Mode`、`CH Polarity`；
**Break/Dead Time** 页配刹车和死区（高级定时器 TIM1/TIM8/TIM20）；
**Master/Slave Mode** 配触发与级联；NVIC 里勾选更新/捕获/比较中断。

### 6.1 时基计算与初始化
```c
/* 频率 = f_tim / ((PSC+1) × (ARR+1))，f_tim = 定时器时钟（见 HAL_RCC_GetPCLKxFreq×2） */
htim2.Instance               = TIM2;
htim2.Init.Prescaler         = 169;      // 170MHz/170 = 1MHz 计数
htim2.Init.CounterMode       = TIM_COUNTERMODE_UP;
htim2.Init.Period            = 999;      // 1MHz/1000 = 1kHz 更新
htim2.Init.ClockDivision     = TIM_CLOCKDIVISION_DIV1;
htim2.Init.AutoReloadPreload = TIM_AUTORELOAD_PRELOAD_DISABLE;
if (HAL_TIM_Base_Init(&htim2) != HAL_OK) { Error_Handler(); }
/* PWM 通道 */
TIM_OC_InitTypeDef sConfigOC = {0};
sConfigOC.OCMode     = TIM_OCMODE_PWM1;
sConfigOC.Pulse      = 500;                     // 占空比 50%
sConfigOC.OCPolarity = TIM_OCPOLARITY_HIGH;
sConfigOC.OCFastMode = TIM_OCFAST_DISABLE;
HAL_TIM_PWM_ConfigChannel(&htim2, &sConfigOC, TIM_CHANNEL_1);
HAL_TIM_MspPostInit(&htim2);                     // 配置 PWM 引脚（CubeMX 生成）
```

### 6.2 各种模式的启动/停止函数

| 模式 | 启动 / 停止 |
|---|---|
| 基础计数（更新中断/定时） | `HAL_TIM_Base_Start()` / `_Start_IT()` / `_Start_DMA()` / `HAL_TIM_Base_Stop[_IT/_DMA]()` |
| PWM 输出 | `HAL_TIM_PWM_Start(&htim2, TIM_CHANNEL_1)` / `_Start_IT()` / `_Start_DMA()`，停止 `HAL_TIM_PWM_Stop*()` |
| PWM 互补输出（高级定时器） | `HAL_TIMEx_PWMN_Start[_IT/_DMA]()` / `HAL_TIMEx_PWMN_Stop*()` |
| 输出比较 | `HAL_TIM_OC_Start*()` / `HAL_TIMEx_OCN_Start*()` |
| 输入捕获（测脉宽/频率） | `HAL_TIM_IC_Start[_IT/_DMA]()` / `HAL_TIM_IC_Stop*()` |
| 编码器接口 | `HAL_TIM_Encoder_Start[_IT/_DMA]()` / `HAL_TIM_Encoder_Stop*()` |
| 单脉冲 | `HAL_TIM_OnePulse_Start[_IT]()` / `HAL_TIMEx_OnePulseN_Start[_IT]()` |
| 霍尔传感器 | `HAL_TIMEx_HallSensor_Start[_IT/_DMA]()` |
| DMA 突发改占空比 | `HAL_TIM_DMABurst_WriteStart/Stop()`、`HAL_TIM_DMABurst_ReadStart/Stop()` |


### 6.3 运行期最常用的操作（宏，比调函数快）

```c
__HAL_TIM_SET_COMPARE(&htim2, TIM_CHANNEL_1, 750);   // 改占空比（关键！）
__HAL_TIM_GET_COMPARE(&htim2, TIM_CHANNEL_1);
__HAL_TIM_SET_AUTORELOAD(&htim2, 1999);              // 改周期（频率）
__HAL_TIM_SET_PRESCALER(&htim2, 84);
__HAL_TIM_SET_COUNTER(&htim2, 0);   __HAL_TIM_GET_COUNTER(&htim2);
__HAL_TIM_ENABLE(&htim2);  __HAL_TIM_DISABLE(&htim2);
__HAL_TIM_ENABLE_IT(&htim2, TIM_IT_UPDATE);          // 动态开关中断源
__HAL_TIM_GET_FLAG(&htim2, TIM_FLAG_UPDATE);  __HAL_TIM_CLEAR_FLAG(&htim2, TIM_FLAG_UPDATE);
```

### 6.4 中断与回调

```c
/* stm32g4xx_it.c（CubeMX 生成） */
void TIM2_IRQHandler(void) { HAL_TIM_IRQHandler(&htim2); }

/* 你实现其中一个或多个： */
void HAL_TIM_PeriodElapsedCallback(TIM_HandleTypeDef *htim)   { /* 更新/溢出：定时任务 */ }
void HAL_TIM_IC_CaptureCallback(TIM_HandleTypeDef *htim)      { /* 输入捕获完成 */ }
void HAL_TIM_OC_DelayElapsedCallback(TIM_HandleTypeDef *htim) { /* 输出比较 */ }
void HAL_TIM_PWM_PulseFinishedCallback(TIM_HandleTypeDef *htim) { /* PWM 一个周期结束 */ }
void HAL_TIM_TriggerCallback(TIM_HandleTypeDef *htim)         { /* 触发事件（从模式） */ }
void HAL_TIM_ErrorCallback(TIM_HandleTypeDef *htim)           { /* DMA/其它错误 */ }
void HAL_TIMEx_BreakCallback(TIM_HandleTypeDef *htim)         { /* 刹车输入触发 */ }
void HAL_TIMEx_CommutCallback(TIM_HandleTypeDef *htim)        { /* 换相事件 */ }
void HAL_TIMEx_DirectionChangeCallback(TIM_HandleTypeDef *htim){ /* 编码器换向 */ }
```

### 6.5 输入捕获（测频率/脉宽）

```c
TIM_IC_InitTypeDef sConfigIC = {0};
sConfigIC.ICPolarity  = TIM_INPUTCHANNELPOLARITY_RISING;
sConfigIC.ICSelection = TIM_ICSELECTION_DIRECTTI;
sConfigIC.ICPrescaler = TIM_ICPSC_DIV1;
sConfigIC.ICFilter    = 0;
HAL_TIM_IC_ConfigChannel(&htim3, &sConfigIC, TIM_CHANNEL_1);
HAL_TIM_IC_Start_IT(&htim3, TIM_CHANNEL_1);

void HAL_TIM_IC_CaptureCallback(TIM_HandleTypeDef *htim)
{
  static uint32_t t_last, t_now, period;
  if (htim->Channel == HAL_TIM_ACTIVE_CHANNEL_1)
  {
    t_now  = HAL_TIM_ReadCapturedValue(htim, TIM_CHANNEL_1);  // 读 CCR1
    period = (t_now > t_last) ? (t_now - t_last) : (0xFFFF - t_last + t_now);
    t_last = t_now;
    /* f = 1 / (period / f_tim) */
  }
}
```

### 6.6 编码器接口（正交编码/旋钮）

```c
TIM_Encoder_InitTypeDef sConfig = {0};
sConfig.EncoderMode  = TIM_ENCODERMODE_TI12;          // 4 倍频计数
sConfig.IC1Polarity  = TIM_ICPOLARITY_RISING;
sConfig.IC1Selection = TIM_ICSELECTION_DIRECTTI;
sConfig.IC2Polarity  = TIM_ICPOLARITY_RISING;
sConfig.IC2Selection = TIM_ICSELECTION_DIRECTTI;
HAL_TIM_Encoder_Init(&htim3, &sConfig);
HAL_TIM_Encoder_Start(&htim3, TIM_CHANNEL_ALL);
int16_t count = (int16_t)__HAL_TIM_GET_COUNTER(&htim3);   // 读位置
__HAL_TIM_SET_COUNTER(&htim3, 0);                          // 清零
```

### 6.7 死区、刹车（TIM1/TIM8/TIM20）

```c
TIM_BreakDeadTimeConfigTypeDef sBreakDeadTimeConfig = {0};
sBreakDeadTimeConfig.OffStateRunMode  = TIM_OSSR_DISABLE;
sBreakDeadTimeConfig.OffStateIDLEMode = TIM_OSSI_DISABLE;
sBreakDeadTimeConfig.LockLevel        = TIM_LOCKLEVEL_OFF;
sBreakDeadTimeConfig.DeadTime         = 20;                 // 死区步长按 DTG 分档（ns 级）
sBreakDeadTimeConfig.BreakState       = TIM_BREAK_ENABLE;   // 刹车使能
sBreakDeadTimeConfig.BreakPolarity    = TIM_BREAKPOLARITY_HIGH;
sBreakDeadTimeConfig.BreakFilter      = 0;
sBreakDeadTimeConfig.AutomaticOutput  = TIM_AUTOMATICOUTPUT_DISABLE;
HAL_TIMEx_ConfigBreakDeadTime(&htim1, &sBreakDeadTimeConfig);
/* 其它扩展 */
HAL_TIMEx_ConfigBreakInput(&htim1, TIM_BREAKINPUT_BRK, &cfg);  // 运行中改刹车源
HAL_TIMEx_ConfigDeadTime(&htim1, &sBreakDeadTimeConfig);       // 只改死区
HAL_TIMEx_ConfigAsymmetricalDeadTime(&htim1, &cfg);            // 不对称死区（G4）
HAL_TIMEx_ReArmBreakInput(&htim1, TIM_BREAKINPUT_BRK);         // 刹车后重新武装
HAL_TIMEx_DisarmBreakInput(&htim1, TIM_BREAKINPUT_BRK);
HAL_TIMEx_ConfigCommutEvent[_IT/_DMA](&htim1, &sConfig);       // 换相
HAL_TIMEx_DitheringEnable(&htim1, TIM_DITHERING_1);            // 抖动：等效更高 PWM 分辨率
```

### 6.8 从模式与外部时钟（级联、门控、外部计数）

```c
TIM_SlaveConfigTypeDef sSlaveConfig = {0};
sSlaveConfig.SlaveMode       = TIM_SLAVEMODE_TRIGGER;   // RESET/GATED/TRIGGER/EXTERNAL1
sSlaveConfig.InputTrigger    = TIM_TS_ITR0;             // 来自其它定时器/ETR/TI1
sSlaveConfig.TriggerPolarity = TIM_TRIGGERPOLARITY_RISING;
HAL_TIM_SlaveConfigSynchro(&htim2, &sSlaveConfig);

TIM_ClockConfigTypeDef sClockSource = {0};
sClockSource.ClockSource = TIM_CLOCKSOURCE_ETR;         // 外部引脚计数
sClockSource.ClockFilter = 0; sClockSource.ClockPolarity = TIM_CLOCKPOLARITY_RISING;
sClockSource.ClockPrescaler = TIM_CLOCKPRESCALER_DIV1;
HAL_TIM_ConfigClockSource(&htim2, &sClockSource);

HAL_TIMEx_MasterConfigSynchronization(&htim1, &sMasterConfig);  // 主模式触发输出给别的定时器
HAL_TIM_GenerateEvent(&htim1, TIM_EVENTSOURCE_UPDATE);          // 软件产生更新事件（立即生效）
```

### 完整工程骨架（CubeMX 生成 + 你手写）

以 **TIM2 出 1kHz PWM + 更新中断**为例：

```c
/* ============ Core/Src/tim.c —— CubeMX 生成 ============ */
TIM_HandleTypeDef htim2;

void MX_TIM2_Init(void)
{
  TIM_ClockConfigTypeDef  sClockSourceConfig = {0};
  TIM_MasterConfigTypeDef sMasterConfig      = {0};
  TIM_OC_InitTypeDef      sConfigOC          = {0};

  htim2.Instance               = TIM2;
  htim2.Init.Prescaler         = 169;                        /* 170MHz/170 = 1MHz */
  htim2.Init.CounterMode       = TIM_COUNTERMODE_UP;
  htim2.Init.Period            = 999;                        /* 1MHz/1000 = 1kHz */
  htim2.Init.ClockDivision     = TIM_CLOCKDIVISION_DIV1;
  htim2.Init.AutoReloadPreload = TIM_AUTORELOAD_PRELOAD_DISABLE;
  if (HAL_TIM_Base_Init(&htim2) != HAL_OK) { Error_Handler(); }

  sClockSourceConfig.ClockSource = TIM_CLOCKSOURCE_INTERNAL;  /* 内部时钟 */
  HAL_TIM_ConfigClockSource(&htim2, &sClockSourceConfig);

  sMasterConfig.MasterOutputTrigger = TIM_TRGO_RESET;         /* 主模式输出（给 ADC/DAC 用）*/
  sMasterConfig.MasterSlaveMode     = TIM_MASTERSLAVEMODE_DISABLE;
  HAL_TIMEx_MasterConfigSynchronization(&htim2, &sMasterConfig);

  sConfigOC.OCMode     = TIM_OCMODE_PWM1;
  sConfigOC.Pulse      = 500;                                 /* 50% 占空比 */
  sConfigOC.OCPolarity = TIM_OCPOLARITY_HIGH;
  sConfigOC.OCFastMode = TIM_OCFAST_DISABLE;
  HAL_TIM_PWM_ConfigChannel(&htim2, &sConfigOC, TIM_CHANNEL_1);

  HAL_TIM_MspPostInit(&htim2);                                /* 配 PWM 引脚 */
}

/* ============ Core/Src/stm32g4xx_hal_msp.c —— CubeMX 生成 ============ */
void HAL_TIM_Base_MspInit(TIM_HandleTypeDef* htim_base)
{
  if (htim_base->Instance == TIM2)
  {
    __HAL_RCC_TIM2_CLK_ENABLE();
    HAL_NVIC_SetPriority(TIM2_IRQn, 1, 0);
    HAL_NVIC_EnableIRQ(TIM2_IRQn);
  }
}
void HAL_TIM_MspPostInit(TIM_HandleTypeDef* htim)   /* PWM 输出引脚在这里配 */
{
  GPIO_InitTypeDef GPIO_InitStruct = {0};
  if (htim->Instance == TIM2)
  {
    __HAL_RCC_GPIOA_CLK_ENABLE();
    GPIO_InitStruct.Pin       = GPIO_PIN_5;                 /* PA5 = TIM2_CH1 */
    GPIO_InitStruct.Mode      = GPIO_MODE_AF_PP;
    GPIO_InitStruct.Pull      = GPIO_NOPULL;
    GPIO_InitStruct.Speed     = GPIO_SPEED_FREQ_LOW;
    GPIO_InitStruct.Alternate = GPIO_AF1_TIM2;
    HAL_GPIO_Init(GPIOA, &GPIO_InitStruct);
  }
}

/* ============ Core/Src/stm32g4xx_it.c —— CubeMX 生成 ============ */
void TIM2_IRQHandler(void) { HAL_TIM_IRQHandler(&htim2); }
```

```c
/* ============ 你手写的部分 ============ */

/* ① main.c USER CODE BEGIN 2：启动（PWM 必须显式 Start，否则没波形）*/
HAL_TIM_PWM_Start(&htim2, TIM_CHANNEL_1);      /* 只要 PWM：这一句就够 */
HAL_TIM_Base_Start_IT(&htim2);                 /* 再要更新中断：加这句 */

/* ② 主循环/中断里调速（用宏，最快）*/
__HAL_TIM_SET_COMPARE(&htim2, TIM_CHANNEL_1, 250);      /* 25% */
__HAL_TIM_SET_AUTORELOAD(&htim2, 1999);                 /* 改成 500Hz */
__HAL_TIM_SET_PRESCALER(&htim2, 84);

/* ③ 更新中断回调：做周期性任务 / 软启动斜坡 */
void HAL_TIM_PeriodElapsedCallback(TIM_HandleTypeDef *htim)
{
  if (htim->Instance == TIM2)
  {
    static uint16_t duty = 0;
    duty = (duty + 5) % 1000;
    __HAL_TIM_SET_COMPARE(htim, TIM_CHANNEL_1, duty);   /* 占空比缓慢上升 */
  }
}

/* ④ 输入捕获：测外部信号周期（配好 IC 通道后）*/
// HAL_TIM_IC_Start_IT(&htim3, TIM_CHANNEL_1);
void HAL_TIM_IC_CaptureCallback(TIM_HandleTypeDef *htim)
{
  if (htim->Channel == HAL_TIM_ACTIVE_CHANNEL_1)
  {
    uint32_t cap = HAL_TIM_ReadCapturedValue(htim, TIM_CHANNEL_1);
    /* 周期 = cap / f_tim */
  }
}

/* ⑤ 编码器读数（配好 Encoder 模式后）*/
// HAL_TIM_Encoder_Start(&htim3, TIM_CHANNEL_ALL);
int16_t pos = (int16_t)__HAL_TIM_GET_COUNTER(&htim3);

/* ⑥ 需要立刻生效（预装载关着时）*/
HAL_TIM_GenerateEvent(&htim2, TIM_EVENTSOURCE_UPDATE);

/* ⑦ 刹车事件回调（高级定时器，硬件过流保护触发时）*/
void HAL_TIMEx_BreakCallback(TIM_HandleTypeDef *htim) { /* 关输出、记录故障 */ }
```

**CubeMX 配置入口**：`Timers → TIMx` 的 Channel 下拉选择 PWM Generation / Input Capture / Output Compare /
Encoder Mode 等，Prescaler/Period 在 Parameter 页；`Break and Dead Time` 页配刹车与死区。

---

## 7. HRTIM 高分辨率定时器（重点）

### 概览

**常用 API（跑通一路 PWM 只需要这几个）**

| API | 一句话作用 |
|---|---|
| `HAL_HRTIM_Init(&hhrtim1)` | 初始化 HRTIM（内部自动调用 `HAL_HRTIM_MspInit`：时钟源+GPIO+NVIC） |
| `HAL_HRTIM_DLLCalibrationStart(&hhrtim1, rate)` | 启动 DLL 校准（**不做就没有高分辨率**） |
| `HAL_HRTIM_PollForDLLCalibration(&hhrtim1, timeout)` | 阻塞等校准完成（中断版：`..._IT` + `DLLCalibrationReadyCallback`） |
| `HAL_HRTIM_TimeBaseConfig(&hhrtim1, TimerIdx, &cfg)` | 配周期/重复次数/预分频/连续或单次 |
| `HAL_HRTIM_WaveformTimerConfig(&hhrtim1, TimerIdx, &cfg)` | 配中断/DMA 源、复位源、预装载等运行参数 |
| `HAL_HRTIM_WaveformCompareConfig(&hhrtim1, TimerIdx, CmpUnit, &cfg)` | 配比较值（**决定占空比**） |
| `HAL_HRTIM_WaveformOutputConfig(&hhrtim1, TimerIdx, Output, &cfg)` | 配输出的置位/复位事件、极性、空闲电平、故障电平 |
| `HAL_HRTIM_WaveformOutputStart(&hhrtim1, Outputs)` | 使能输出（可多位相加，如 `TA1+TA2`） |
| `HAL_HRTIM_WaveformCounterStart(&hhrtim1, Timers)` | 启动计数（用 `HRTIM_TIMERID_*`） |
| `HAL_HRTIM_IRQHandler(&hhrtim1, TimerIdx)` | 中断入口（`HRTIM1_TIMx_IRQHandler` 里调用） |
| `HAL_HRTIM_RepetitionEventCallback(h, TimerIdx)` | 每个开关周期进一次（环路计算放这里） |
| `__HAL_HRTIM_SETCOMPARE/SETPERIOD/SETCOUNTER` | 运行期改占空比/周期/计数（比调函数快） |

**进阶 API（电源、移相、保护）**

| API | 一句话作用 |
|---|---|
| `HAL_HRTIM_DeadTimeConfig()` | 互补输出的死区（正向/反向值 + 预分频 + 符号） |
| `HAL_HRTIM_ADCTriggerConfig()` + `HAL_HRTIM_ADCPostScalerConfig()` | 让 ADC 在指定时刻（PER/CMPx）自动启动采样 |
| `HAL_HRTIM_WaveformCounterStop/Stop_IT/Stop_DMA`、`WaveformOutputStop` | 停计数 / 关输出（回空闲电平） |
| `HAL_HRTIM_SoftwareUpdate/SoftwareReset/SoftwareCapture` | 软件产生更新/复位/捕获事件 |
| `HAL_HRTIM_UpdateEnable/UpdateDisable`、`RollOverModeConfig` | 全局更新允许 / 上下计数翻转模式 |
| `HAL_HRTIM_SimplePWMChannelConfig` + `SimplePWMStart` | **Simple API**：一个函数配一路 PWM |
| `HAL_HRTIM_SimpleOC/SimpleCapture/SimpleOnePulse/SimpleBase...` | 简化版的比较/捕获/单脉冲/纯计数 |
| `HAL_HRTIM_GetCapturedValue/GetCapturedDir` | 读捕获值 / 捕获时计数方向 |
| `HAL_HRTIM_WaveformGetOutputLevel/GetOutputState`、`GetState` | 查输出电平/使能状态与句柄状态 |

**不常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_HRTIM_BurstModeConfig/Ctl/SoftwareTrigger`、`BurstDMAConfig/BurstDMATransfer` | 突发模式（间歇工作/软启动）与配套 DMA |
| `HAL_HRTIM_FaultConfig/FaultModeCtl/FaultBlankingConfigAndEnable/FaultCounterConfig/FaultCounterReset` | 故障保护通道（硬件级关断、消隐、计数去抖） |
| `HAL_HRTIM_EventConfig/EventPrescalerConfig`、`ExtEventCounterConfig/Enable/Disable/Reset` | 外部事件通道与事件计数器 |
| `HAL_HRTIM_ChopperModeConfig()` | 斩波（用高频载波调制输出，变压器隔离驱动场景） |
| `HAL_HRTIM_SwapTimerOutput`、`OutputSwapEnable/Disable`、`WaveformTimerControl` | 输出交换 / 运行期改计数方向等控制 |
| `HAL_HRTIM_TimerDualChannelDacConfig()`、`TimerEventFilteringConfig()` | 与 DAC 双通道联动 / 事件滤波 |
| `HAL_HRTIM_GetDelayedProtectionStatus/GetBurstStatus/GetCurrentPushPullStatus/GetIdlePushPullStatus` | 各种状态查询（调试用） |

**关键选项速解**

- **`PrescalerRatio`**：`MUL32`（分辨率最高 ~184ps，但最低频率受限）/ `MUL16/MUL8/MUL4/MUL2/DIV1/DIV2/DIV4`——**频率低就往下调**。
- **`Mode`**：`HRTIM_MODE_CONTINUOUS` 连续跑；`SINGLESHOT` 跑一次；`SINGLESHOT_RETRIGGERABLE` 可重触发。
- **`Period` / `RepetitionCounter`**：周期决定开关频率；重复次数决定"几个周期进一次中断"（降低 CPU 负载）。
- **`CompareValue`**：与 Period 的比值就是占空比；CMP1/2 常用于同一桥臂的两路输出。
- **`SetSource` / `ResetSource`**：输出的"置位事件 / 复位事件"，用 `HRTIM_OUTPUTSET_*` 与 `HRTIM_OUTPUTRESET_*`
  （TIMPER 周期点、TIMCMP1~4、EEV_x 外部事件、其它定时器交叉信号、MASTER 事件…）。
- **`IdleLevel` / `IdleMode`**：输出被关或进入空闲时停在有效还是无效电平——**停机安全电平**。
- **`Polarity`**：输出有效电平是高还是低（驱动变压器/光耦时要注意）。
- **`Prescaler/RisingValue/FallingValue/RisingSign/FallingSign`（死区）**：互补驱动必须设置，防止上下管直通。
- **`UpdateSource` / `Trigger`（ADC 触发）**：选谁当时基、在哪个事件触发 ADC——环路采样时机的关键。
- **`Source` / `Polarity` / `Filter`（Fault）**：过流/过压从哪个引脚进来、有效极性、是否滤波。
- **三组标识别混**：`HRTIM_TIMERINDEX_*`=配置哪个定时器；`HRTIM_TIMERID_*`=启停哪些定时器；`HRTIM_OUTPUT_Tx1/Tx2`=操作哪路输出。


### 7.1 它是什么
HRTIM = High Resolution TIMer，用 DLL + 32 倍频把等效时钟做到 **4.6 GHz**（fHRTIM=144MHz 时），
分辨率 **184~217 ps**。结构是 **1 个 Master + 6 个独立定时器 A~F**，其中 A~E 各有 2 路输出（TA1/TA2…），
F 通常只引出 TF1 一路（头文件里也定义了 TF2 常量，是否可用取决于具体型号/封装）。
每个定时器有 4 个比较单元、4 个捕获/外部事件、独立死区、斩波、故障保护。
典型用途：数字电源（Buck/Boost/PFC/LLC/移相全桥）、高频互补 PWM、需要 ns 级时序的场合。

> G4 的 HRTIM 时钟源必须是 PLL（`RCC_HRTIM1CLK_PLLCLK`）才能满速；
> 关注开关频率上限：用 MUL32 时最小周期约 `70.3kHz`（144MHz）→ 想更慢要调 Prescaler Ratio。

### 7.2 CubeMX 里配什么
**Mode 页**：勾 `HRTIM1`，选择要用哪些定时器的通道（Channel1/Channel2）→ 引脚 TA1/TA2/TB1… 自动分配；
**Parameter Settings** 页（左侧树：Common / Timer A~F / Master / ADC Triggers）：

| 位置 | 关键项 |
|---|---|
| Common | 同步输入/输出（Sync）、DLL 校准周期 |
| Master | Prescaler Ratio、Period、Repetition |
| Timer A~F | Prescaler Ratio（MUL32…DIV4）、Mode（Continuous/Single-shot）、Period、Repetition |
| Compare | CMP1~CMP4 值（可预装载）、AutoDelayed Mode |
| Output x | Set/Reset 源（PER、CMP1~4、外部事件、其它定时器交叉）、Polarity、Idle Level、Fault、Chopper、Burst Entry |
| Deadtime | Rising/Falling value + Prescaler、RST 信号、正反相信号 |
| ADC Trigger | Trigger1/2 事件源、更新源、Postscaler（可让 ADC 与 PWM 同步采样） |
| Fault / Event / Burst / Chopper | 保护、外部事件滤波、突发、斩波 |
| NVIC | `HRTIM1_Master_IRQn`、`HRTIM1_TIMA_IRQn`…`HRTIM1_TIMF_IRQn`、`HRTIM1_FLT_IRQn` |

### 7.3 生成的代码长什么样

`Core/Src/hrtim.c`（CubeMX 生成的主要骨架）：
```c
HRTIM_HandleTypeDef hhrtim1;

void MX_HRTIM1_Init(void)
{
  HRTIM_TimeBaseCfgTypeDef  pTimeBaseCfg  = {0};
  HRTIM_TimerCfgTypeDef     pTimerCfg     = {0};
  HRTIM_CompareCfgTypeDef   pCompareCfg   = {0};
  HRTIM_OutputCfgTypeDef    pOutputCfg    = {0};

  hhrtim1.Instance = HRTIM1;
  hhrtim1.Init.HRTIMInterruptRequests = HRTIM_MASTER_IT_MCMP1 | HRTIM_MASTER_IT_MREP;
  hhrtim1.Init.SyncOptions            = HRTIM_SYNCOPTION_NONE;
  if (HAL_HRTIM_Init(&hhrtim1) != HAL_OK) { Error_Handler(); }     // 内部调用 HAL_HRTIM_MspInit

  /* ① DLL 校准（必须！否则高分辨率不准） */
  if (HAL_HRTIM_DLLCalibrationStart(&hhrtim1, HRTIM_CALIBRATIONRATE_3) != HAL_OK) { Error_Handler(); }
  if (HAL_HRTIM_PollForDLLCalibration(&hhrtim1, 10) != HAL_OK) { Error_Handler(); }

  /* ② 时基：周期/重复次数/预分频/模式 */
  pTimeBaseCfg.Period            = 0xFFFF;      // 170MHz×32 / 0xFFFF ≈ 83 kHz
  pTimeBaseCfg.RepetitionCounter = 0x00;
  pTimeBaseCfg.PrescalerRatio    = HRTIM_PRESCALERRATIO_MUL32;  // 32 倍频，最高分辨率
  pTimeBaseCfg.Mode              = HRTIM_MODE_CONTINUOUS;       // 连续 / 单次
  if (HAL_HRTIM_TimeBaseConfig(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A, &pTimeBaseCfg) != HAL_OK)
  { Error_Handler(); }

  /* ③ 定时器工作参数（中断源、上溢/复位源、预装载等） */
  pTimerCfg.InterruptRequests   = HRTIM_TIM_IT_REP;
  pTimerCfg.DMARequests         = HRTIM_TIM_DMA_NONE;
  pTimerCfg.Preloadable         = HRTIM_PRELOAD_DISABLED;   /* 或 HRTIM_PRELOAD_ENABLED */
  pTimerCfg.UpdateTrigger       = HRTIM_TIMUPDATETRIGGER_NONE;
  pTimerCfg.ResetTrigger        = HRTIM_TIMRESETTRIGGER_NONE;
  pTimerCfg.ResetUpdate         = HRTIM_TIMUPDATEONRESET_DISABLED;
  pTimerCfg.ReSyncUpdate        = HRTIM_TIMERESYNC_UPDATE_UNCONDITIONAL;
  if (HAL_HRTIM_WaveformTimerConfig(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A, &pTimerCfg) != HAL_OK)
  { Error_Handler(); }

  /* ④ 比较值（决定占空比）：CompareValue = Period × Duty */
  pCompareCfg.CompareValue = 0x8000;
  if (HAL_HRTIM_WaveformCompareConfig(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A,
                                     HRTIM_COMPAREUNIT_1, &pCompareCfg) != HAL_OK)
  { Error_Handler(); }

  /* ⑤ 输出：谁置位、谁复位、极性、空闲电平 */
  pOutputCfg.Polarity            = HRTIM_OUTPUTPOLARITY_HIGH;
  pOutputCfg.SetSource           = HRTIM_OUTPUTSET_TIMPER;         // 周期起点置位
  pOutputCfg.ResetSource         = HRTIM_OUTPUTRESET_TIMCMP1;      // CMP1 复位 → 占空比
  pOutputCfg.IdleMode            = HRTIM_OUTPUTIDLEMODE_NONE;
  pOutputCfg.IdleLevel           = HRTIM_OUTPUTIDLELEVEL_INACTIVE;
  pOutputCfg.FaultLevel          = HRTIM_OUTPUTFAULTLEVEL_NONE;
  pOutputCfg.ChopperModeEnable   = HRTIM_OUTPUTCHOPPERMODE_DISABLED;
  pOutputCfg.BurstModeEntryDelayed = HRTIM_OUTPUTBURSTMODEENTRY_REGULAR;
  if (HAL_HRTIM_WaveformOutputConfig(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A,
                                    HRTIM_OUTPUT_TA1, &pOutputCfg) != HAL_OK)
  { Error_Handler(); }

  HAL_HRTIM_MspPostInit(&hhrtim1);      // 最后配输出引脚（GPIO 复用）
}
```

`Core/Src/stm32g4xx_hal_msp.c` 里的 `HAL_HRTIM_MspInit()`：
```c
void HAL_HRTIM_MspInit(HRTIM_HandleTypeDef* hhrtim)
{
  GPIO_InitTypeDef GPIO_InitStruct = {0};
  RCC_PeriphCLKInitTypeDef PeriphClkInit = {0};
  if (hhrtim->Instance == HRTIM1)
  {
    PeriphClkInit.PeriphClockSelection = RCC_PERIPHCLK_HRTIM1;
    PeriphClkInit.Hrtim1ClockSelection = RCC_HRTIM1CLK_PLLCLK;   // ← 必须选 PLL
    HAL_RCCEx_PeriphCLKConfig(&PeriphClkInit);
    __HAL_RCC_HRTIM1_CLK_ENABLE();                               // 开 HRTIM 时钟

    /* 输出引脚：GPIO_MODE_AF_PP + GPIO_AF13_HRTIM1（在 MspPostInit 里配） */
    HAL_NVIC_SetPriority(HRTIM1_TIMA_IRQn, 0, 0);
    HAL_NVIC_EnableIRQ(HRTIM1_TIMA_IRQn);
  }
}
```

> `#define HAL_HRTIM_MODULE_ENABLED` 默认是注释掉的，CubeMX 里一旦启用 HRTIM 就会自动打开
> （见 `Core/Inc/stm32g4xx_hal_conf.h`）。


### 7.4 HRTIM 的 HAL API 分类速查（共 127 个）

**① 初始化 / 校准**
`HAL_HRTIM_Init()`、`HAL_HRTIM_DeInit()`、`HAL_HRTIM_MspInit()`、`HAL_HRTIM_MspDeInit()`、
`HAL_HRTIM_DLLCalibrationStart()`、`HAL_HRTIM_DLLCalibrationStart_IT()`、
`HAL_HRTIM_PollForDLLCalibration()`、`HAL_HRTIM_GetState()`

**② 时基与波形配置**

| 函数 | 作用 |
|---|---|
| `HAL_HRTIM_TimeBaseConfig(hhrtim, TimerIdx, &pTimeBaseCfg)` | 周期、重复次数、预分频、连续/单次 |
| `HAL_HRTIM_WaveformTimerConfig(hhrtim, TimerIdx, &pTimerCfg)` | 中断/DMA 源、复位源、预装载、Push-Pull 等 |
| `HAL_HRTIM_WaveformCompareConfig(hhrtim, TimerIdx, CompareUnit, &pCfg)` | CMP1~4 比较值 |
| `HAL_HRTIM_WaveformOutputConfig(hhrtim, TimerIdx, Output, &pCfg)` | 输出置位/复位源、极性、空闲、故障电平 |
| `HAL_HRTIM_WaveformCaptureConfig(hhrtim, TimerIdx, CaptureUnit, &pCfg)` | 捕获单元触发源 |
| `HAL_HRTIM_WaveformTimerControl(hhrtim, TimerIdx, &pTimerCtl)` | 运行时改计数方向/预装载/重启等 |
| `HAL_HRTIM_TimerDualChannelDacConfig()` | 与 DAC 双通道联动（电源环路） |
| `HAL_HRTIM_TimerEventFilteringConfig()` | 事件滤波 |

**③ 启动 / 停止 / 触发**

| 函数 | 作用 |
|---|---|
| `HAL_HRTIM_WaveformOutputStart(hhrtim, Outputs)` | **使能输出**（如 `HRTIM_OUTPUT_TA1`，可用 `+` 组合） |
| `HAL_HRTIM_WaveformOutputStop(hhrtim, Outputs)` | 关闭输出（回空闲电平） |
| `HAL_HRTIM_WaveformCounterStart(hhrtim, Timers)` | **启动计数**（如 `HRTIM_TIMERID_TIMER_A`） |
| `HAL_HRTIM_WaveformCounterStop(hhrtim, Timers)` | 停止计数 |
| `HAL_HRTIM_WaveformCountStart/Stop[_IT/_DMA](hhrtim, Timers)` | 计数 + 自动开中断/DMA |
| `HAL_HRTIM_SoftwareUpdate / SoftwareReset / SoftwareCapture` | 软件产生更新/复位/捕获事件 |
| `HAL_HRTIM_UpdateEnable / UpdateDisable` | 全局更新允许 |
| `HAL_HRTIM_BurstModeCtl / BurstModeSoftwareTrigger` | 突发（Burst）模式控制 |
| `HAL_HRTIM_BurstDMAConfig / BurstDMATransfer` | 突发模式 + DMA 批量改寄存器 |
| `HAL_HRTIM_SwapTimerOutput / OutputSwapEnable / OutputSwapDisable` | 输出交换 |

**④ 死区、斩波、故障、事件、ADC 触发**
`HAL_HRTIM_DeadTimeConfig()`、`HAL_HRTIM_ChopperModeConfig()`、
`HAL_HRTIM_FaultConfig()`、`HAL_HRTIM_FaultPrescalerConfig()`、
`HAL_HRTIM_FaultBlankingConfigAndEnable()`、`HAL_HRTIM_FaultCounterConfig()`、
`HAL_HRTIM_FaultCounterReset()`、`HAL_HRTIM_FaultModeCtl()`、
`HAL_HRTIM_EventConfig()`、`HAL_HRTIM_EventPrescalerConfig()`、
`HAL_HRTIM_ExtEventCounterConfig/Enable/Disable/Reset()`、
`HAL_HRTIM_ADCTriggerConfig()`、`HAL_HRTIM_ADCPostScalerConfig()`、
`HAL_HRTIM_BurstModeConfig()`、`HAL_HRTIM_RollOverModeConfig()`。

**⑤ 读取状态/数值**
`HAL_HRTIM_GetCapturedValue(hhrtim, TimerIdx, CaptureUnit)`、`HAL_HRTIM_GetCaptured`、
`HAL_HRTIM_GetCapturedDir`、`HAL_HRTIM_WaveformGetOutputLevel`、
`HAL_HRTIM_WaveformGetOutputState`、`HAL_HRTIM_GetDelayedProtectionStatus`、
`HAL_HRTIM_GetBurstStatus`、`HAL_HRTIM_GetCurrentPushPullStatus`、`HAL_HRTIM_GetIdlePushPullStatus`。

**⑥ Simple API（最省事的起步方式）**

| 函数 | 用途 |
|---|---|
| `HAL_HRTIM_SimpleBaseStart/Stop[_IT/_DMA](hhrtim, TimerIdx)` | 纯时基/计数 |
| `HAL_HRTIM_SimpleOCChannelConfig` + `SimpleOCStart/Stop[_IT/_DMA](hhrtim, TimerIdx, OCChannel)` | 输出比较（可翻转） |
| `HAL_HRTIM_SimplePWMChannelConfig` + `SimplePWMStart/Stop[_IT/_DMA](hhrtim, TimerIdx, PWMChannel)` | **单路 PWM** |
| `HAL_HRTIM_SimpleCaptureChannelConfig` + `SimpleCaptureStart/Stop[_IT/_DMA]` | 捕获 |
| `HAL_HRTIM_SimpleOnePulseChannelConfig` + `SimpleOnePulseStart/Stop[_IT]` | 单脉冲 |


### 7.5 中断与回调

```c
/* stm32g4xx_it.c —— 每个定时器/公共中断线一个入口（CubeMX 生成） */
void HRTIM1_Master_IRQHandler(void) { HAL_HRTIM_IRQHandler(&hhrtim1, HRTIM_TIMERINDEX_MASTER); }
void HRTIM1_TIMA_IRQHandler(void)   { HAL_HRTIM_IRQHandler(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A); }
void HRTIM1_TIMB_IRQHandler(void)   { HAL_HRTIM_IRQHandler(&hhrtim1, HRTIM_TIMERINDEX_TIMER_B); }
void HRTIM1_TIMC_IRQHandler(void)   { HAL_HRTIM_IRQHandler(&hhrtim1, HRTIM_TIMERINDEX_TIMER_C); }
void HRTIM1_TIMD_IRQHandler(void)   { HAL_HRTIM_IRQHandler(&hhrtim1, HRTIM_TIMERINDEX_TIMER_D); }
void HRTIM1_TIME_IRQHandler(void)   { HAL_HRTIM_IRQHandler(&hhrtim1, HRTIM_TIMERINDEX_TIMER_E); }
void HRTIM1_TIMF_IRQHandler(void)   { HAL_HRTIM_IRQHandler(&hhrtim1, HRTIM_TIMERINDEX_TIMER_F); }
void HRTIM1_FLT_IRQHandler(void)    { HAL_HRTIM_IRQHandler(&hhrtim1, HRTIM_TIMERINDEX_COMMON); }

/* 下面是运行期真正要你写的回调（按 TimerIdx 区分是哪个定时器） */
void HAL_HRTIM_RepetitionEventCallback(HRTIM_HandleTypeDef *hhrtim, uint32_t TimerIdx)
{
  if (TimerIdx == HRTIM_TIMERINDEX_TIMER_A)
  {
    /* 每个开关周期执行一次：做环路计算、算新占空比 */
    __HAL_HRTIM_SETCOMPARE(hhrtim, TimerIdx, HRTIM_COMPAREUNIT_1, new_duty);
  }
}
void HAL_HRTIM_Compare1EventCallback (HRTIM_HandleTypeDef *h, uint32_t TimerIdx) { }
void HAL_HRTIM_Compare2EventCallback (HRTIM_HandleTypeDef *h, uint32_t TimerIdx) { }
void HAL_HRTIM_Compare3EventCallback (HRTIM_HandleTypeDef *h, uint32_t TimerIdx) { }
void HAL_HRTIM_Compare4EventCallback (HRTIM_HandleTypeDef *h, uint32_t TimerIdx) { }
void HAL_HRTIM_Capture1EventCallback (HRTIM_HandleTypeDef *h, uint32_t TimerIdx) { }
void HAL_HRTIM_Capture2EventCallback (HRTIM_HandleTypeDef *h, uint32_t TimerIdx) { }
void HAL_HRTIM_RegistersUpdateCallback(HRTIM_HandleTypeDef *h, uint32_t TimerIdx) { }
void HAL_HRTIM_CounterResetCallback  (HRTIM_HandleTypeDef *h, uint32_t TimerIdx) { }
void HAL_HRTIM_Output1SetCallback    (HRTIM_HandleTypeDef *h, uint32_t TimerIdx) { }
void HAL_HRTIM_Output1ResetCallback  (HRTIM_HandleTypeDef *h, uint32_t TimerIdx) { }
void HAL_HRTIM_Output2SetCallback    (HRTIM_HandleTypeDef *h, uint32_t TimerIdx) { }
void HAL_HRTIM_Output2ResetCallback  (HRTIM_HandleTypeDef *h, uint32_t TimerIdx) { }
void HAL_HRTIM_DelayedProtectionCallback(HRTIM_HandleTypeDef *h, uint32_t TimerIdx) { }
void HAL_HRTIM_BurstDMATransferCallback (HRTIM_HandleTypeDef *h, uint32_t TimerIdx) { }

/* 与具体定时器无关的回调 */
void HAL_HRTIM_Fault1Callback(HRTIM_HandleTypeDef *h) { }   /* 另外还有 Fault2~Fault6Callback */
void HAL_HRTIM_SystemFaultCallback(HRTIM_HandleTypeDef *h) { }
void HAL_HRTIM_DLLCalibrationReadyCallback(HRTIM_HandleTypeDef *h) { }
void HAL_HRTIM_BurstModePeriodCallback(HRTIM_HandleTypeDef *h) { }
void HAL_HRTIM_SynchronizationEventCallback(HRTIM_HandleTypeDef *h) { }
void HAL_HRTIM_ErrorCallback(HRTIM_HandleTypeDef *h) { }
```

**中断/DMA 源怎么开**（写在 `HRTIM_TimerCfgTypeDef.InterruptRequests` / 或用宏）：
```c
/* 在 CubeMX 的 Timer 页勾选；运行期动态开关用宏： */
__HAL_HRTIM_TIMER_ENABLE_IT(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A, HRTIM_TIM_IT_REP);
__HAL_HRTIM_TIMER_DISABLE_IT(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A, HRTIM_TIM_IT_REP);
__HAL_HRTIM_TIMER_GET_FLAG(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A, HRTIM_TIM_FLAG_REP);
__HAL_HRTIM_TIMER_CLEAR_FLAG(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A, HRTIM_TIM_FLAG_REP);
/* 中断源常量：HRTIM_TIM_IT_CMP1..4 / CPT1..2 / REP / RST / SET1 / SET2 / RST1 / RST2 / UPD / DLYPRT */
/* Master 的：HRTIM_MASTER_IT_MCMP1..4 / MREP / MUPD / SYNC */
```

**HRTIM 常用宏一览**（共 42 个，最常用这些）：
```c
__HAL_HRTIM_ENABLE(&hhrtim1, HRTIM_TIMERID_TIMER_A);          // 等价于启动该定时器计数
__HAL_HRTIM_DISABLE(&hhrtim1, HRTIM_TIMERID_TIMER_A);
__HAL_HRTIM_SETCOMPARE(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A, HRTIM_COMPAREUNIT_1, val);
__HAL_HRTIM_GETCOMPARE(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A, HRTIM_COMPAREUNIT_1);
__HAL_HRTIM_SETPERIOD(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A, val);
__HAL_HRTIM_GETPERIOD(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A);
__HAL_HRTIM_SETCOUNTER(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A, 0);
__HAL_HRTIM_GETCOUNTER(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A);
__HAL_HRTIM_SETCLOCKPRESCALER / GETCLOCKPRESCALER(...);        // 运行期改预分频
__HAL_HRTIM_COUNTER_MODE_UP / COUNTER_MODE_UPDOWN(...);        // 改计数方向（上下计数）
__HAL_HRTIM_TIMER_OUTPUT_SWAP / TIMER_OUTPUT_NOSWAP(...);      // TA1/TA2 交换
__HAL_HRTIM_ENABLE_IT / DISABLE_IT / GET_FLAG / CLEAR_FLAG；MASTER_xxx / TIMER_xxx 对应版本
```


### 7.6 典型用法示例

**(a) 最快上手：Simple API 出单路 PWM**
```c
HRTIM_SimplePWMChannelCfgTypeDef pPwmCfg = {0};
pPwmCfg.Pulse     = 0x8000;                     // 占空比 = Pulse / Period
pPwmCfg.Polarity  = HRTIM_OUTPUTPOLARITY_HIGH;
pPwmCfg.IdleLevel = HRTIM_OUTPUTIDLELEVEL_INACTIVE;
HAL_HRTIM_SimplePWMChannelConfig(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A, HRTIM_OUTPUT_TA1, &pPwmCfg);
HAL_HRTIM_SimplePWMStart(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A, HRTIM_OUTPUT_TA1);
/* 运行中改占空比（用宏最快） */
__HAL_HRTIM_SETCOMPARE(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A, HRTIM_COMPAREUNIT_1, 0x4000);
/* 停止 */
HAL_HRTIM_SimplePWMStop(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A, HRTIM_OUTPUT_TA1);
```

**(b) 互补 PWM + 死区（数字电源/半桥常用）**
```c
/* 配置顺序：TimeBaseConfig → WaveformTimerConfig → WaveformCompareConfig(CMP1/CMP2)
   → WaveformOutputConfig(TA1/TA2) → DeadTimeConfig → MspPostInit */
HRTIM_DeadTimeCfgTypeDef pDeadTimeCfg = {0};
pDeadTimeCfg.Prescaler    = HRTIM_TIMDEADTIME_PRESCALERRATIO_DIV1;
pDeadTimeCfg.RisingValue  = 40;                                   // 上升沿死区步数
pDeadTimeCfg.RisingSign   = HRTIM_TIMDEADTIME_RISINGSIGN_POSITIVE;
pDeadTimeCfg.FallingValue = 40;                                   // 下降沿死区步数
pDeadTimeCfg.FallingSign  = HRTIM_TIMDEADTIME_FALLINGSIGN_POSITIVE;
HAL_HRTIM_DeadTimeConfig(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A, &pDeadTimeCfg);

/* 运行顺序很重要：先使能输出，再启动计数 */
HAL_HRTIM_WaveformOutputStart(&hhrtim1, HRTIM_OUTPUT_TA1 + HRTIM_OUTPUT_TA2);
HAL_HRTIM_WaveformCounterStart(&hhrtim1, HRTIM_TIMERID_TIMER_A);
```

**(c) 让 ADC 与 PWM 同步采样（环路关键技巧）**
```c
HRTIM_ADCTriggerCfgTypeDef pADCTriggerCfg = {0};
pADCTriggerCfg.UpdateSource = HRTIM_ADCTRIGGERUPDATE_TIMER_D;      // 谁是"更新源"
pADCTriggerCfg.Trigger      = HRTIM_ADCTRIGGEREVENT24_TIMERD_CMP2; // CMP2 时刻触发 ADC
HAL_HRTIM_ADCTriggerConfig(&hhrtim1, HRTIM_ADCTRIGGER_2, &pADCTriggerCfg);
/* 例子里后面再把 ADC 的外部触发源选成 HRTIM_TRG2（见第 12 章） */
```
> 触发事件常量命名规则：`HRTIM_ADCTRIGGEREVENTxy_…`，其中 `xy` 是该事件可以驱动的 ADC 触发线号
> （13 / 24 / 579 / 6810），所以选哪个前缀取决于你用的是 ADC Trigger 1~10 中的哪一路。

**(d) 突发模式（Burst，用于间歇工作/软启动）**
```c
HRTIM_BurstModeCfgTypeDef pBurstModeCfg = {0};
pBurstModeCfg.Mode         = HRTIM_BURSTMODE_SINGLESHOT;           // 或 HRTIM_BURSTMODE_CONTINOUS
pBurstModeCfg.ClockSource  = HRTIM_BURSTMODECLOCKSOURCE_FHRTIM;    // 也可用 TIMER_x / MASTER / TIM7_TRGO
pBurstModeCfg.Prescaler    = HRTIM_BURSTMODEPRESCALER_DIV1;
pBurstModeCfg.Trigger      = HRTIM_BURSTMODETRIGGER_NONE;          // 或某个 CMP/EVENT 触发源
pBurstModeCfg.IdleDuration = 0x1000;                               // 空闲时长
pBurstModeCfg.Period       = 0x2000;                               // 突发周期
HAL_HRTIM_BurstModeConfig(&hhrtim1, &pBurstModeCfg);
HAL_HRTIM_BurstModeCtl(&hhrtim1, HRTIM_BURSTMODECTL_ENABLED);
HAL_HRTIM_BurstModeSoftwareTrigger(&hhrtim1);                      // 软件触发一次
```

**(e) 故障（Fault）保护：过流硬件关断**
```c
HRTIM_FaultCfgTypeDef pFaultCfg = {0};
pFaultCfg.Source   = HRTIM_FAULTSOURCE_DIGITALINPUT;  // 数字输入引脚（也可 EEVINPUT / INTERNAL）
pFaultCfg.Polarity = HRTIM_FAULTPOLARITY_HIGH;
pFaultCfg.Filter   = HRTIM_FAULTFILTER_1;             // 滤波：HRTIM_FAULTFILTER_1..15 / NONE
pFaultCfg.Lock     = HRTIM_FAULTLOCK_READWRITE;
HAL_HRTIM_FaultConfig(&hhrtim1, HRTIM_FAULT_1, &pFaultCfg);
HAL_HRTIM_FaultModeCtl(&hhrtim1, HRTIM_FAULT_1, HRTIM_FAULTMODECTL_ENABLED); // 运行期启用/屏蔽
void HAL_HRTIM_Fault1Callback(HRTIM_HandleTypeDef *h) { /* 记录故障状态 */ }
```

### 7.7 HRTIM 使用注意事项（踩坑排行）
1. **必须做 DLL 校准**，否则高分辨率失效（退化成普通定时器精度）：
   初始化后立即 `HAL_HRTIM_DLLCalibrationStart()` + `HAL_HRTIM_PollForDLLCalibration()`（或 `_IT` 版）。
2. **时钟源必须是 PLL**：`PeriphClkInit.Hrtim1ClockSelection = RCC_HRTIM1CLK_PLLCLK;`，
   且不能漏 `__HAL_RCC_HRTIM1_CLK_ENABLE()`。
3. **输出使能要在启动计数之前（或同时）**，否则会先输出错误电平。
4. 三组宏别混用：`HRTIM_TIMERINDEX_xxx`（配置哪个定时器）、`HRTIM_OUTPUT_Tx1/Tx2`（操作哪路输出）、
   `HRTIM_TIMERID_xxx`（启动/停止哪些定时器计数）。
5. 周期不能小于 3 个 fHRTIM 时钟周期；MUL32 模式下最小周期受限（144MHz 时上限约 70kHz，
   想更低频率就降 Prescaler Ratio 到 MUL16/MUL8/…）。
6. Period/CMP 都是 16 位；要更宽的调速范围就改预分频。
7. 输出引脚在 `HAL_HRTIM_MspPostInit()` 里配置；若手动 `HAL_GPIO_Init()` 要选 `GPIO_AF13_HRTIM1`。
8. 公共中断（FLT/系统优先级）用 `HRTIM_TIMERINDEX_COMMON`，其余用各自 TimerIdx。
9. 过流/过压保护不要用软件轮询，直接用 Fault 输入实现硬件级关断。
10. 环路中断里只做计算和写 CMP，不要 `printf`、不要 `HAL_Delay`。
11. `HAL_HRTIM_WaveformOutputStop()` 会让输出回到 `IdleLevel` 规定的电平，调电源前先确认它的极性。

### 完整工程骨架（CubeMX 生成 + 你手写）

以 **Timer A 输出互补 PWM（TA1/TA2）+ 死区 + 每周期中断做环路 + 同步触发 ADC** 为例：

```c
/* ============ Core/Src/hrtim.c —— CubeMX 生成 ============ */
HRTIM_HandleTypeDef hhrtim1;

void MX_HRTIM1_Init(void)
{
  HRTIM_TimeBaseCfgTypeDef pTimeBaseCfg = {0};
  HRTIM_TimerCfgTypeDef    pTimerCfg    = {0};
  HRTIM_CompareCfgTypeDef  pCompareCfg  = {0};
  HRTIM_OutputCfgTypeDef   pOutputCfg   = {0};
  HRTIM_DeadTimeCfgTypeDef pDeadTimeCfg = {0};
  HRTIM_ADCTriggerCfgTypeDef pADCTriggerCfg = {0};

  hhrtim1.Instance = HRTIM1;
  hhrtim1.Init.HRTIMInterruptRequests = HRTIM_MASTER_IT_MREP;
  hhrtim1.Init.SyncOptions            = HRTIM_SYNCOPTION_NONE;
  if (HAL_HRTIM_Init(&hhrtim1) != HAL_OK) { Error_Handler(); }

  /* ① DLL 校准（生成代码里就有，别删）*/
  if (HAL_HRTIM_DLLCalibrationStart(&hhrtim1, HRTIM_CALIBRATIONRATE_3) != HAL_OK) { Error_Handler(); }
  if (HAL_HRTIM_PollForDLLCalibration(&hhrtim1, 10) != HAL_OK) { Error_Handler(); }

  /* ② 时基：周期 / 预分频 / 连续模式 */
  pTimeBaseCfg.Period            = 0xEFFF;
  pTimeBaseCfg.RepetitionCounter = 0x00;
  pTimeBaseCfg.PrescalerRatio    = HRTIM_PRESCALERRATIO_MUL32;
  pTimeBaseCfg.Mode              = HRTIM_MODE_CONTINUOUS;
  if (HAL_HRTIM_TimeBaseConfig(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A, &pTimeBaseCfg) != HAL_OK) { Error_Handler(); }

  /* ③ 定时器工作参数（中断源放在这里）*/
  pTimerCfg.InterruptRequests = HRTIM_TIM_IT_REP;      /* 每个开关周期中断一次 */
  pTimerCfg.DMARequests       = HRTIM_TIM_DMA_NONE;
  pTimerCfg.Preloadable       = HRTIM_PRELOAD_ENABLED;
  pTimerCfg.UpdateTrigger     = HRTIM_TIMUPDATETRIGGER_NONE;
  pTimerCfg.ResetTrigger      = HRTIM_TIMRESETTRIGGER_NONE;
  pTimerCfg.ResetUpdate       = HRTIM_TIMUPDATEONRESET_DISABLED;
  pTimerCfg.ReSyncUpdate      = HRTIM_TIMERESYNC_UPDATE_UNCONDITIONAL;
  if (HAL_HRTIM_WaveformTimerConfig(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A, &pTimerCfg) != HAL_OK) { Error_Handler(); }

  /* ④ 比较值（CMP1 决定占空比）*/
  pCompareCfg.CompareValue = 0x3000;
  if (HAL_HRTIM_WaveformCompareConfig(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A, HRTIM_COMPAREUNIT_1, &pCompareCfg) != HAL_OK) { Error_Handler(); }

  /* ⑤ 输出 TA1：PER 置位、CMP1 复位 */
  pOutputCfg.Polarity  = HRTIM_OUTPUTPOLARITY_HIGH;
  pOutputCfg.SetSource = HRTIM_OUTPUTSET_TIMPER;
  pOutputCfg.ResetSource = HRTIM_OUTPUTRESET_TIMCMP1;
  pOutputCfg.IdleMode  = HRTIM_OUTPUTIDLEMODE_NONE;
  pOutputCfg.IdleLevel = HRTIM_OUTPUTIDLELEVEL_INACTIVE;
  pOutputCfg.FaultLevel = HRTIM_OUTPUTFAULTLEVEL_NONE;
  pOutputCfg.ChopperModeEnable = HRTIM_OUTPUTCHOPPERMODE_DISABLED;
  pOutputCfg.BurstModeEntryDelayed = HRTIM_OUTPUTBURSTMODEENTRY_REGULAR;
  if (HAL_HRTIM_WaveformOutputConfig(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A, HRTIM_OUTPUT_TA1, &pOutputCfg) != HAL_OK) { Error_Handler(); }

  /* ⑥ 输出 TA2（互补，由 CubeMX 生成另一段对称配置）*/
  /* ... HAL_HRTIM_WaveformOutputConfig(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A, HRTIM_OUTPUT_TA2, &pOutputCfg); */

  /* ⑦ 死区 */
  pDeadTimeCfg.Prescaler    = HRTIM_TIMDEADTIME_PRESCALERRATIO_DIV1;
  pDeadTimeCfg.RisingValue  = 40;   pDeadTimeCfg.RisingSign  = HRTIM_TIMDEADTIME_RISINGSIGN_POSITIVE;
  pDeadTimeCfg.FallingValue = 40;   pDeadTimeCfg.FallingSign = HRTIM_TIMDEADTIME_FALLINGSIGN_POSITIVE;
  if (HAL_HRTIM_DeadTimeConfig(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A, &pDeadTimeCfg) != HAL_OK) { Error_Handler(); }

  /* ⑧ ADC 触发（在 CMP2 时刻采样）*/
  pADCTriggerCfg.UpdateSource = HRTIM_ADCTRIGGERUPDATE_TIMER_A;
  pADCTriggerCfg.Trigger      = HRTIM_ADCTRIGGEREVENT13_TIMERA_CMP3;
  if (HAL_HRTIM_ADCTriggerConfig(&hhrtim1, HRTIM_ADCTRIGGER_1, &pADCTriggerCfg) != HAL_OK) { Error_Handler(); }

  HAL_HRTIM_MspPostInit(&hhrtim1);        /* 配 TA1/TA2 引脚（AF13）*/
}

/* ============ Core/Src/stm32g4xx_hal_msp.c —— CubeMX 生成 ============ */
void HAL_HRTIM_MspInit(HRTIM_HandleTypeDef* hhrtim)
{
  RCC_PeriphCLKInitTypeDef PeriphClkInit = {0};
  if (hhrtim->Instance == HRTIM1)
  {
    PeriphClkInit.PeriphClockSelection = RCC_PERIPHCLK_HRTIM1;
    PeriphClkInit.Hrtim1ClockSelection = RCC_HRTIM1CLK_PLLCLK;   /* 必须 PLL */
    HAL_RCCEx_PeriphCLKConfig(&PeriphClkInit);
    __HAL_RCC_HRTIM1_CLK_ENABLE();

    HAL_NVIC_SetPriority(HRTIM1_TIMA_IRQn, 1, 0);
    HAL_NVIC_EnableIRQ(HRTIM1_TIMA_IRQn);
  }
}

/* ============ Core/Src/stm32g4xx_it.c —— CubeMX 生成 ============ */
void HRTIM1_TIMA_IRQHandler(void) { HAL_HRTIM_IRQHandler(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A); }
void HRTIM1_FLT_IRQHandler(void)  { HAL_HRTIM_IRQHandler(&hhrtim1, HRTIM_TIMERINDEX_COMMON); }
```

```c
/* ============ 你手写的部分 ============ */

/* ① main.c USER CODE BEGIN 2：启动顺序 —— 先使能输出，再启动计数 */
HAL_HRTIM_WaveformOutputStart(&hhrtim1, HRTIM_OUTPUT_TA1 + HRTIM_OUTPUT_TA2);
HAL_HRTIM_WaveformCounterStart(&hhrtim1, HRTIM_TIMERID_TIMER_A);

/* ② 环路中断（每个开关周期一次）：算完写 CMP 即改占空比 */
void HAL_HRTIM_RepetitionEventCallback(HRTIM_HandleTypeDef *hhrtim, uint32_t TimerIdx)
{
  if (TimerIdx == HRTIM_TIMERINDEX_TIMER_A)
  {
    uint16_t period = (uint16_t)__HAL_HRTIM_GETPERIOD(hhrtim, TimerIdx);
    uint16_t duty   = (uint16_t)(period * g_duty_ratio);          /* 你的控制算法 */
    __HAL_HRTIM_SETCOMPARE(hhrtim, TimerIdx, HRTIM_COMPAREUNIT_1, duty);
  }
}

/* ③ 运行时改频率（调速/软启动）*/
__HAL_HRTIM_SETPERIOD(&hhrtim1, HRTIM_TIMERINDEX_TIMER_A, 0xD000);

/* ④ 故障保护回调（过流硬件关断后记录状态、清故障）*/
void HAL_HRTIM_Fault1Callback(HRTIM_HandleTypeDef *hhrtim)
{
  /* 已由硬件关断输出；这里做记录/上报/延时重启 */
}

/* ⑤ ADC 采样完成（与 PWM 同步的电流采样）*/
void HAL_ADCEx_InjectedConvCpltCallback(ADC_HandleTypeDef *hadc)
{
  g_i_sample = HAL_ADCEx_InjectedGetValue(hadc, ADC_INJECTED_RANK_1);
}

/* ⑥ 需要停机时：先关输出（回安全电平），再停计数 */
HAL_HRTIM_WaveformOutputStop(&hhrtim1, HRTIM_OUTPUT_TA1 + HRTIM_OUTPUT_TA2);
HAL_HRTIM_WaveformCounterStop(&hhrtim1, HRTIM_TIMERID_TIMER_A);

/* ⑦ 想临时屏蔽故障输入（调试用，量产别这么干）*/
HAL_HRTIM_FaultModeCtl(&hhrtim1, HRTIM_FAULT_1, HRTIM_FAULTMODECTL_DISABLED);
```

**CubeMX 配置入口**：`Timers → HRTIM1` 勾选定时器通道（生成引脚）→ Parameter 页逐个配
Master/Timer A~F 的时基、Compare、Output、Deadtime、ADC Trigger、Fault；NVIC 里勾
`HRTIM1_Master/TIMA…/FLT` 中断。**生成的东西已经能跑，你只需要在 USER CODE 里加启动、环路和保护逻辑。**

---

## 8. LPTIM 低功耗定时器

### 概览

**常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_LPTIM_Init(&hlptim)` | 初始化（时钟源/预分频/计数模式/触发/输出） |
| `HAL_LPTIM_PWM_Start[_IT](&hlptim, Period, Pulse)` / `PWM_Stop[_IT]()` | 输出 PWM（周期和脉宽直接当参数传） |
| `HAL_LPTIM_Counter_Start[_IT]()` / `Counter_Stop[_IT]()` | 纯计数（周期性唤醒/计时） |
| `HAL_LPTIM_TimeOut_Start[_IT](&hlptim, Period, Timeout)` | 超时/看门狗式定时（Stop 模式下也能唤醒） |
| `HAL_LPTIM_ReadCounter(&hlptim)` | 读当前计数（**没有** `__HAL_LPTIM_GET_COUNTER` 宏） |
| `HAL_LPTIM_IRQHandler(&hlptim)` | 中断入口（`LPTIM1_IRQHandler` 里调用） |
| `HAL_LPTIM_AutoReloadMatchCallback()` / `CompareMatchCallback()` | 到期回调 / 比较匹配回调 |
| `__HAL_LPTIM_ENABLE/DISABLE`、`__HAL_LPTIM_AUTORELOAD_SET`、`__HAL_LPTIM_COMPARE_SET` | 基本控制与改值宏 |

**不常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_LPTIM_SetOnce_Start[_IT]()` / `Stop` | 单次延时（触发一次、延时一段时间） |
| `HAL_LPTIM_OnePulse_Start[_IT]()` / `Stop` | 单脉冲输出 |
| `HAL_LPTIM_Encoder_Start[_IT]()` / `Stop` | 低功耗正交编码计数（LPTIM1/2） |
| `HAL_LPTIM_ReadAutoReload()` / `ReadCompare()` | 读 ARR / 比较寄存器当前值 |
| `HAL_LPTIM_TriggerCallback()` | 外部触发事件回调 |
| `HAL_LPTIM_RegisterCallback()` / `UnRegisterCallback()` | 注册式回调（多实例） |
| `HAL_LPTIM_DeInit()` / `GetState()` | 反初始化 / 查状态 |
| `__HAL_LPTIM_START_CONTINUOUS/START_SINGLE`、`__HAL_LPTIM_RESET_COUNTER`、`__HAL_LPTIM_WAKEUPTIMER_EXTI_*` | LL 风格控制宏 |

**关键选项速解**

- **`ClockSource`**：内部时钟（LSI / LSE / APB / HSI）或外部/ULPTIM 引脚。**低功耗场景必须选 LSI 或 LSE**，
  选 APB/HSI 的话 Stop 模式下没时钟就没法唤醒。
- **`Prescaler`**：时钟分频（1/2/4/…/128），决定计数节拍。
- **`CounterMode`**：`Single` 数到 ARR 就停（配合单次中断）；`Continuous` 循环计数。
- **`Trigger`**：外部触发源（引脚/其它外设），可实现"外部事件驱动的延时"。
- **`Period` / `Pulse`**：与其他定时器不同，这两个是**函数参数**而不是初始化结构体字段。
- **`Output`**：是否用输出脚（PWM/单脉冲），不用输出则只做内部计时。


CubeMX 里 **Timers → LPTIMx**：选时钟源（Internal Clock / 外部 / ULPTIM）、Prescaler、
Counter Mode（Single/Continuous）、Trigger、是否用 Output（PWM 或 One Pulse）、NVIC。

| 用途 | 函数 |
|---|---|
| 初始化 | `HAL_LPTIM_Init(&hlptim1)` / `HAL_LPTIM_DeInit()` |
| **PWM 输出** | `HAL_LPTIM_PWM_Start[_IT](&hlptim1, Period, Pulse)` / `HAL_LPTIM_PWM_Stop[_IT]()` |
| 单脉冲 | `HAL_LPTIM_OnePulse_Start[_IT]()` / `Stop[_IT]()` |
| 单次延时（SetOnce） | `HAL_LPTIM_SetOnce_Start[_IT]()` / `Stop[_IT]()` |
| 超时/看门狗式定时 | `HAL_LPTIM_TimeOut_Start[_IT](Period, Timeout)` / `Stop[_IT]()` |
| 纯计数 | `HAL_LPTIM_Counter_Start[_IT]()` / `Stop[_IT]()` |
| 编码器（LPTIM1/2 支持） | `HAL_LPTIM_Encoder_Start[_IT]()` / `Stop[_IT]()` |
| 读取 | `HAL_LPTIM_ReadCounter()`、`HAL_LPTIM_ReadAutoReload()`、`HAL_LPTIM_ReadCompare()` |
| 中断 | `HAL_LPTIM_IRQHandler(&hlptim1)` |

```c
/* 注意：Start 函数把周期/脉宽当参数传进去，这是 LPTIM 与 TIM 的最大区别 */
HAL_LPTIM_PWM_Start(&hlptim1, 0xFFFF, 0x7FFF);     // Period, Pulse（16 位）
HAL_LPTIM_TimeOut_Start_IT(&hlptim1, 0xFFFF, 0x8000);// 超时中断唤醒

void LPTIM1_IRQHandler(void) { HAL_LPTIM_IRQHandler(&hlptim1); }
void HAL_LPTIM_AutoReloadMatchCallback(LPTIM_HandleTypeDef *hlptim) { /* 周期性唤醒事件 */ }
void HAL_LPTIM_CompareMatchCallback  (LPTIM_HandleTypeDef *hlptim) { }
void HAL_LPTIM_TriggerCallback       (LPTIM_HandleTypeDef *hlptim) { }
```
常用宏：`__HAL_LPTIM_ENABLE/DISABLE(&hlptim1)`、`__HAL_LPTIM_AUTORELOAD_SET(&hlptim1, v)`、
`__HAL_LPTIM_COMPARE_SET(&hlptim1, v)`、`__HAL_LPTIM_RESET_COUNTER(&hlptim1)`、
`__HAL_LPTIM_START_CONTINUOUS/START_SINGLE(&hlptim1)`、`__HAL_LPTIM_ENABLE_IT/DISABLE_IT/GET_FLAG/CLEAR_FLAG`；
读计数器用 `HAL_LPTIM_ReadCounter(&hlptim1)`（没有 __HAL_LPTIM_GET_COUNTER 宏）。
**典型用法**：Stop 模式下用 LPTIM+LSI 定时唤醒（`HAL_PWR_EnterSTOPMode()` 见第 24 章），
此时 LPTIM 时钟必须选 LSI/LSE（不能选要关掉的 HSI/PCLK）。

### 完整工程骨架（CubeMX 生成 + 你手写）

以 **LPTIM1 在 Stop 模式下定时唤醒 + 输出一路 PWM** 为例：

```c
/* ============ Core/Src/lptim.c —— CubeMX 生成 ============ */
LPTIM_HandleTypeDef hlptim1;

void MX_LPTIM1_Init(void)
{
  hlptim1.Instance = LPTIM1;
  hlptim1.Init.Clock.Source    = LPTIM_CLOCKSOURCE_APBCLOCK_LPOSC;   /* 或 ULPTIM/外部 */
  hlptim1.Init.Clock.Prescaler = LPTIM_PRESCALER_DIV128;             /* 慢速节拍 */
  hlptim1.Init.Trigger.Source  = LPTIM_TRIGSOURCE_SOFTWARE;          /* 软件触发 */
  hlptim1.Init.OutputPolarity  = LPTIM_OUTPUTPOLARITY_HIGH;
  hlptim1.Init.UpdateMode      = LPTIM_UPDATE_IMMEDIATE;
  hlptim1.Init.CounterSource   = LPTIM_COUNTERSOURCE_INTERNAL;
  hlptim1.Init.Input1Source    = LPTIM_INPUT1SOURCE_GPIO;
  hlptim1.Init.Input2Source    = LPTIM_INPUT2SOURCE_GPIO;
  if (HAL_LPTIM_Init(&hlptim1) != HAL_OK) { Error_Handler(); }
}

/* ============ Core/Src/stm32g4xx_hal_msp.c —— CubeMX 生成 ============ */
void HAL_LPTIM_MspInit(LPTIM_HandleTypeDef* hlptim)
{
  RCC_PeriphCLKInitTypeDef PeriphClkInit = {0};
  if (hlptim->Instance == LPTIM1)
  {
    PeriphClkInit.PeriphClockSelection = RCC_PERIPHCLK_LPTIM1;
    PeriphClkInit.Lptim1ClockSelection = RCC_LPTIM1CLKSOURCE_PCLK1;  /* 低功耗要改成 LSI/LSE */
    HAL_RCCEx_PeriphCLKConfig(&PeriphClkInit);
    __HAL_RCC_LPTIM1_CLK_ENABLE();
    /* PWM 输出引脚（如果用了输出）*/
    HAL_NVIC_SetPriority(LPTIM1_IRQn, 0, 0);
    HAL_NVIC_EnableIRQ(LPTIM1_IRQn);
  }
}

/* ============ Core/Src/stm32g4xx_it.c —— CubeMX 生成 ============ */
void LPTIM1_IRQHandler(void) { HAL_LPTIM_IRQHandler(&hlptim1); }
```

```c
/* ============ 你手写的部分 ============ */

/* ① 方式 A：周期性唤醒（低功耗主循环）*/
HAL_LPTIM_TimeOut_Start_IT(&hlptim1, 0xFFFF, 0x8000);   /* Period, Timeout */
while (1)
{
  HAL_PWR_EnterSTOPMode(PWR_LOWPOWERREGULATOR_ON, PWR_STOPENTRY_WFI);
  SystemClock_Config();                                  /* 唤醒后必须重配时钟 */
  DoPeriodicJob();
}

/* ① 方式 B：输出 PWM（把 LPTIM 当低速 PWM 用）*/
// HAL_LPTIM_PWM_Start(&hlptim1, 0xFFFF, 0x7FFF);     /* Period, Pulse */
// HAL_LPTIM_PWM_Stop(&hlptim1);

/* ① 方式 C：单次延时 / 一次脉冲 */
// HAL_LPTIM_SetOnce_Start_IT(&hlptim1, 0xFFFF, 0x8000);
// HAL_LPTIM_OnePulse_Start_IT(&hlptim1, ...);

/* ② 到期回调（方式 A/C 的中断入口）*/
void HAL_LPTIM_AutoReloadMatchCallback(LPTIM_HandleTypeDef *hlptim)
{
  /* 注意：Stop 模式下中断里不要做耗时操作；唤醒后主循环再处理 */
}

/* ③ 比较匹配回调（做精确延时/两步动作）*/
void HAL_LPTIM_CompareMatchCallback(LPTIM_HandleTypeDef *hlptim) { }

/* ④ 运行期读计数 / 改周期 */
uint32_t cnt = HAL_LPTIM_ReadCounter(&hlptim1);
__HAL_LPTIM_AUTORELOAD_SET(&hlptim1, 0xC000);      /* 改自动重装 */
__HAL_LPTIM_COMPARE_SET(&hlptim1, 0x6000);
__HAL_LPTIM_RESET_COUNTER(&hlptim1);
```

**CubeMX 配置入口**：`Timers → LPTIM1` 的 Mode 页勾 Clock Source / Trigger / Output，
Parameter 页设 Prescaler、Counter Mode；**做低功耗时一定要把 LPTIM 时钟源改成 LSI 或 LSE**，
否则进 Stop 后没有时钟就不会唤醒。

---

## 9. UART / USART / LPUART

### 概览

**常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_UART_Init(&huart1)` | 初始化：波特率/字长/校验/停止位/模式/过采样 |
| `HAL_UART_Transmit(&huart1, buf, len, timeout)` | 阻塞发送（调试打印最简单） |
| `HAL_UART_Receive(&huart1, buf, len, timeout)` | 阻塞接收 |
| `HAL_UART_Receive_IT(&huart1, buf, len)` | 中断接收：收满 len 字节进回调 |
| `HAL_UART_Transmit_DMA / Receive_DMA` | DMA 收发（大数据量必用） |
| `HAL_UARTEx_ReceiveToIdle_DMA(&huart1, buf, len)` | **不定长接收**（总线空闲即结束，协议解析标配） |
| `HAL_UARTEx_RxEventCallback(huart, Size)` | 不定长接收回调，`Size` = 本帧字节数 |
| `HAL_UART_TxCpltCallback / RxCpltCallback` | 发送 / 接收完成回调 |
| `HAL_UART_ErrorCallback` | 错误回调（ORE 溢出、帧错误在这里救） |
| `HAL_UART_IRQHandler(&huart1)` | 中断入口（`USART1_IRQHandler` 里调用） |

**不常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_UART_Transmit_IT()` | 中断发送（小数据，不占 CPU） |
| `HAL_UART_Abort[_IT]()` / `AbortTransmit_IT()` / `AbortReceive_IT()` | 终止收发 / 只终止发 / 只终止收 |
| `HAL_UART_DMAPause()` / `DMAResume()` / `DMAStop()` | 暂停 / 恢复 / 停止 DMA |
| `HAL_UART_EnableReceiverTimeout()` / `ReceiverTimeout_Config()` | 接收超时检测（MODBUS 帧间隔判断） |
| `HAL_UARTEx_EnableFifoMode/DisableFifoMode`、`SetTxFifoThreshold/SetRxFifoThreshold` | 收发 FIFO（G4 支持，可大幅降低中断次数） |
| `HAL_UARTEx_EnableStopMode()` / `StopModeWakeUpSourceConfig()` | Stop 模式下由串口唤醒 |
| `HAL_UARTEx_GetRxEventType()` | 判断本次 RxEvent 是 IDLE 触发还是缓冲区满 |
| `HAL_MultiProcessor_Init/EnableMuteMode/DisableMuteMode/EnterMuteMode` | 多机通信（地址唤醒 + 静默） |
| `HAL_LIN_Init/SendBreak`、`HAL_HalfDuplex_Init/EnableTransmitter/EnableReceiver`、`HAL_RS485Ex_Init` | LIN / 半双工 / RS485（DE 引脚）模式 |
| `HAL_UART_GetState/GetError`、`RegisterCallback/RegisterRxEventCallback` | 诊断与注册式回调 |

**关键选项速解**

- **`BaudRate`**：波特率，必须与对方一致；前提是时钟源选对（`HAL_RCCEx_PeriphCLKConfig` 里给 USART 选 PCLK2/HSI/SYSCLK）。
- **`WordLength`**：8bit 或 9bit（9bit 常用于带校验或地址位）。
- **`Parity`**：NONE / EVEN / ODD；开校验时有效数据位少一位。
- **`StopBits`**：1 / 2 位停止位。
- **`Mode`**：只发 / 只收 / 收发（`UART_MODE_TX_RX`）。
- **`HwFlowCtl`**：硬件流控 RTS/CTS，长数据流防丢字节。
- **`OverSampling`**：16 倍（默认稳）或 8 倍（可跑更高波特率）；8 倍时要配 `OneBitSampling`。
- **`AdvancedInit`**：自动波特率、TX/RX 引脚互换、数据反相、MSB First 等高级特性。
- **选型思路**：调试打印用阻塞 → 中小数据用 `_IT` → 大数据/不定长用 `_DMA` + IDLE。


### 9.1 CubeMX 配置要点
**Mode**：`Asynchronous`（普通串口）/ `Synchronous`（同步，出 CK 时钟）/ `Single Wire (Half-Duplex)` /
`Multiprocessor` / `IrDA` / `LIN` / `SmartCard` / `RS485`；
**Hardware Flow Control**：RTS/CTS（需要时选，否则 `UART_HWCONTROL_NONE`）；
**参数**：Baud Rate、Word Length(8/9bit)、Parity、Stop Bits、Data Direction、Over Sampling(16/8)；
**Advanced Features**：自动波特率、TX/RX 引脚互换、数据反相、MSB First 等；
**FIFO Mode**：G4 支持收发 FIFO（可设阈值）；**DMA Settings**：加 `USARTx_TX` / `USARTx_RX`；
**NVIC**：勾 `USARTx global interrupt`。

### 9.2 生成的代码
```c
UART_HandleTypeDef huart1;

void MX_USART1_UART_Init(void)
{
  huart1.Instance          = USART1;
  huart1.Init.BaudRate     = 115200;
  huart1.Init.WordLength   = UART_WORDLENGTH_8B;
  huart1.Init.StopBits     = UART_STOPBITS_1;
  huart1.Init.Parity       = UART_PARITY_NONE;
  huart1.Init.Mode         = UART_MODE_TX_RX;
  huart1.Init.HwFlowCtl    = UART_HWCONTROL_NONE;
  huart1.Init.OverSampling = UART_OVERSAMPLING_16;
  if (HAL_UART_Init(&huart1) != HAL_OK) { Error_Handler(); }
  /* FIFO 相关（CubeMX 勾了才有） */
  HAL_UARTEx_SetTxFifoThreshold(&huart1, UART_TXFIFO_THRESHOLD_1_8);
  HAL_UARTEx_SetRxFifoThreshold(&huart1, UART_RXFIFO_THRESHOLD_1_8);
  HAL_UARTEx_DisableFifoMode(&huart1);     /* 或 HAL_UARTEx_EnableFifoMode() */
}
/* HAL_UART_MspInit()：__HAL_RCC_USART1_CLK_ENABLE() + GPIO(AF7) + DMA 关联 + NVIC */
```

### 9.3 三种收发方式（最核心的一张表）

| 方式 | 发送 | 接收 |
|---|---|---|
| **阻塞**（简单、占 CPU） | `HAL_UART_Transmit(&huart1, buf, len, timeout)` | `HAL_UART_Receive(&huart1, buf, len, timeout)` |
| **中断** | `HAL_UART_Transmit_IT(&huart1, buf, len)` | `HAL_UART_Receive_IT(&huart1, buf, len)` |
| **DMA** | `HAL_UART_Transmit_DMA(&huart1, buf, len)` | `HAL_UART_Receive_DMA(&huart1, buf, len)` |
| 同时收发 | 异步 UART 没有 TransmitReceive；同步 USART 用 `HAL_USART_TransmitReceive[_IT/_DMA](&husart1, txbuf, rxbuf, len)` | 同左 |
| **不定长接收（最常用）** | — | `HAL_UARTEx_ReceiveToIdle_DMA(&huart1, buf, len)` / `HAL_UARTEx_ReceiveToIdle_IT()` |

```c
/* 阻塞发送（调试打印） */
HAL_UART_Transmit(&huart1, (uint8_t *)"hello\r\n", 7, 100);

/* 中断接收 1 字节（配合回调循环续接收） */
uint8_t rx_byte;
HAL_UART_Receive_IT(&huart1, &rx_byte, 1);

/* DMA 发送 */
HAL_UART_Transmit_DMA(&huart1, tx_buf, sizeof(tx_buf));
```

**中断服务与回调**
```c
void USART1_IRQHandler(void) { HAL_UART_IRQHandler(&huart1); }

void HAL_UART_TxCpltCallback(UART_HandleTypeDef *huart)      { /* 发送完成 */ }
void HAL_UART_TxHalfCpltCallback(UART_HandleTypeDef *huart)  { /* 发了一半 */ }
void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)      { /* 收到指定长度 */ }
void HAL_UART_RxHalfCpltCallback(UART_HandleTypeDef *huart)  { /* 收了一半（环形缓冲常用） */ }
void HAL_UART_ErrorCallback(UART_HandleTypeDef *huart)       { /* 帧错误/噪声/溢出/校验错 */ }
void HAL_UART_AbortCpltCallback(UART_HandleTypeDef *huart)   { }
void HAL_UARTEx_TxFifoEmptyCallback(UART_HandleTypeDef *huart) { }
void HAL_UARTEx_RxFifoFullCallback (UART_HandleTypeDef *huart) { }
void HAL_UARTEx_WakeupCallback     (UART_HandleTypeDef *huart) { }
```
> `HAL_UART_ErrorCallback` 里一定要判断/清除错误（读 `huart->ErrorCode`），
> 常见 ORE（溢出）会导致接收永久卡死，恢复方法：`__HAL_UART_CLEAR_OREFLAG(&huart1)` 并重新 `HAL_UART_Receive_IT/DMA()`。

### 9.4 不定长接收（DMA + 空闲中断，串口协议解析标配）

```c
#define RX_BUF_SIZE 256
uint8_t rx_buf[RX_BUF_SIZE];

/* 启动：只需一次，之后整个缓冲区持续工作 */
HAL_UARTEx_ReceiveToIdle_DMA(&huart1, rx_buf, RX_BUF_SIZE);
__HAL_DMA_DISABLE_IT(&hdma_usart1_rx, DMA_IT_HT);   // 不需要半传输中断时可关掉

/* 一帧结束（收到 IDLE）或缓冲区满时回调 */
void HAL_UARTEx_RxEventCallback(UART_HandleTypeDef *huart, uint16_t Size)
{
  uint32_t evt = HAL_UARTEx_GetRxEventType(huart);   // 判断是 IDLE 还是 TC/HT 触发
  if (huart->Instance == USART1)
  {
    /* Size 就是本帧收到的字节数；rx_buf[0..Size-1] 有效 */
    HandleFrame(rx_buf, Size);
    HAL_UARTEx_ReceiveToIdle_DMA(huart, rx_buf, RX_BUF_SIZE);  // 重新武装
  }
}
```

### 9.5 运行期常用操作

```c
HAL_UART_Abort(&huart1);                 /* 立即终止收发（阻塞式） */
HAL_UART_Abort_IT(&huart1);              /* 终止 + 回调 */
HAL_UART_AbortTransmit_IT(&huart1);      /* 只终止发送 */
HAL_UART_AbortReceive_IT(&huart1);       /* 只终止接收 */
HAL_UART_DMAPause(&huart1);  HAL_UART_DMAResume(&huart1);  HAL_UART_DMAStop(&huart1);
HAL_UART_EnableReceiverTimeout(&huart1); HAL_UART_ReceiverTimeout_Config(&huart1, 0xFF);
HAL_UART_GetState(&huart1);  HAL_UART_GetError(&huart1);
/* 其它模式（CubeMX 选对应 Mode 后由 HAL_xxx_Init 完成） */
HAL_MultiProcessor_Init(&huart1, address, UART_WAKEUPMETHOD_IDLELINE);
HAL_MultiProcessor_EnableMuteMode(&huart1);
HAL_LIN_Init(&huart1, UART_LINBREAKDETECTLENGTH_10B);   HAL_LIN_SendBreak(&huart1);
HAL_HalfDuplex_Init(&huart1);  HAL_HalfDuplex_EnableTransmitter(&huart1);
HAL_RS485Ex_Init(&huart1, UART_DE_POLARITY_HIGH, 0, 0);
HAL_UARTEx_EnableStopMode(&huart1);  HAL_UARTEx_StopModeWakeUpSourceConfig(&huart1, UART_WAKEUP_ON_READDATA_NONEMPTY);
```

### 9.6 常用宏

```c
__HAL_UART_ENABLE_IT(&huart1, UART_IT_IDLE);        // 手动开空闲中断（老代码常用）
__HAL_UART_GET_FLAG(&huart1, UART_FLAG_IDLE);  __HAL_UART_CLEAR_IDLEFLAG(&huart1);
__HAL_UART_CLEAR_OREFLAG(&huart1);                  // 清溢出错误（救活接收）
__HAL_UART_SEND_REQ(&huart1, UART_REQR_LIN_SBK);    // 发送 break（G4 无 __HAL_UART_SEND_BREAK）
SET_BIT(huart1.Instance->CR3, USART_CR3_DMAT);      // 手动开 DMA 发送请求
__HAL_UART_DISABLE_IT(&huart1, UART_IT_RXNE);
printf 重定向：重写 int __io_putchar(int ch){ HAL_UART_Transmit(&huart1,(uint8_t*)&ch,1,10); return ch;}
```

### 完整工程骨架（CubeMX 生成 + 你手写）

以 **USART1：printf 打印 + DMA/IDLE 不定长接收 + 出错自恢复**为例：

```c
/* ============ Core/Src/usart.c —— CubeMX 生成 ============ */
UART_HandleTypeDef huart1;
DMA_HandleTypeDef  hdma_usart1_rx;

void MX_USART1_UART_Init(void)
{
  huart1.Instance          = USART1;
  huart1.Init.BaudRate     = 115200;
  huart1.Init.WordLength   = UART_WORDLENGTH_8B;
  huart1.Init.StopBits     = UART_STOPBITS_1;
  huart1.Init.Parity       = UART_PARITY_NONE;
  huart1.Init.Mode         = UART_MODE_TX_RX;
  huart1.Init.HwFlowCtl    = UART_HWCONTROL_NONE;
  huart1.Init.OverSampling = UART_OVERSAMPLING_16;
  if (HAL_UART_Init(&huart1) != HAL_OK) { Error_Handler(); }
}

void HAL_UART_MspInit(UART_HandleTypeDef* uartHandle)
{
  if (uartHandle->Instance == USART1)
  {
    RCC_PeriphCLKInitTypeDef PeriphClkInit = {0};
    PeriphClkInit.PeriphClockSelection = RCC_PERIPHCLK_USART1;   /* 时钟源选择 */
    PeriphClkInit.Usart1ClockSelection = RCC_USART1CLKSOURCE_PCLK2;
    HAL_RCCEx_PeriphCLKConfig(&PeriphClkInit);
    __HAL_RCC_USART1_CLK_ENABLE();
    /* GPIO：PC4=TX, PC5=RX, GPIO_AF7_USART1 */
    /* DMA：RX 通道（CubeMX 勾了才有）*/
    HAL_NVIC_SetPriority(USART1_IRQn, 0, 0);
    HAL_NVIC_EnableIRQ(USART1_IRQn);
  }
}

/* ============ Core/Src/stm32g4xx_it.c —— CubeMX 生成 ============ */
void USART1_IRQHandler(void) { HAL_UART_IRQHandler(&huart1); }
```

```c
/* ============ 你手写的部分 ============ */

/* ① printf 重定向（放到 usart.c 的 USER CODE 1 段）—— 调试第一件事 */
int __io_putchar(int ch)
{
  HAL_UART_Transmit(&huart1, (uint8_t *)&ch, 1, 10);
  return ch;
}
/* 之后就能直接 printf("v=%d\r\n", v); */

/* ② main.c USER CODE BEGIN PV + 2：DMA + IDLE 不定长接收（收一帧进一次回调）*/
#define RX_LEN 256
uint8_t rx_buf[RX_LEN];

HAL_UARTEx_ReceiveToIdle_DMA(&huart1, rx_buf, RX_LEN);      /* 启动，自动循环 */
__HAL_DMA_DISABLE_IT(&hdma_usart1_rx, DMA_IT_HT);           /* 不需要半满中断就关掉 */

void HAL_UARTEx_RxEventCallback(UART_HandleTypeDef *huart, uint16_t Size)
{
  if (huart->Instance == USART1)
  {
    ProcessFrame(rx_buf, Size);                             /* Size = 本帧长度 */
    HAL_UARTEx_ReceiveToIdle_DMA(huart, rx_buf, RX_LEN);    /* 重新武装，别忘 */
  }
}

/* ③ 简单发送 / 应答 */
HAL_UART_Transmit(&huart1, (uint8_t *)"OK\r\n", 4, 100);      /* 阻塞 */
HAL_UART_Transmit_DMA(&huart1, tx_buf, len);                  /* DMA（大块）*/
void HAL_UART_TxCpltCallback(UART_HandleTypeDef *huart) { /* 发送完成，可以发下一包 */ }

/* ④ 出错自恢复（ORE 溢出最常见的"收不到数据"元凶）*/
void HAL_UART_ErrorCallback(UART_HandleTypeDef *huart)
{
  if (huart->ErrorCode & HAL_UART_ERROR_ORE)
  {
    __HAL_UART_CLEAR_OREFLAG(huart);
    HAL_UARTEx_ReceiveToIdle_DMA(huart, rx_buf, RX_LEN);      /* 重启接收 */
  }
}

/* ⑤ 中断接收固定长度（不想用 DMA 时）*/
// HAL_UART_Receive_IT(&huart1, rx_buf, 1);
void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
{
  /* 处理 rx_buf[0] */
  HAL_UART_Receive_IT(huart, rx_buf, 1);                      /* 继续收下一个字节 */
}
```

**CubeMX 配置入口**：`Connectivity → USART1` Mode 选 Asynchronous，Parameter 页设波特率/校验/停止位/FIFO，
`DMA Settings` 加 `USART1_RX`/`USART1_TX`，NVIC 勾 `USART1 global interrupt`。

---

## 10. SPI / I2S / SAI

### 概览

**常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_SPI_Init(&hspi1)` | 初始化：模式 / 数据宽度 / CPOL / CPHA / 分频 / NSS |
| `HAL_SPI_Transmit(&hspi1, buf, len, timeout)` | 阻塞发送（先发指令/数据） |
| `HAL_SPI_Receive(&hspi1, buf, len, timeout)` | 阻塞接收 |
| `HAL_SPI_TransmitReceive(&hspi1, txbuf, rxbuf, len, timeout)` | 全双工收发 |
| `HAL_SPI_Transmit_DMA / Receive_DMA / TransmitReceive_DMA` | DMA 版本（刷屏、大块传输必用） |
| `HAL_SPI_IRQHandler(&hspi1)` | 中断入口 |
| `HAL_SPI_TxCpltCallback / RxCpltCallback / TxRxCpltCallback` | 完成回调 |
| `HAL_I2S_Init()` + `HAL_I2S_Transmit_DMA/Receive_DMA` | I2S 音频收发 |
| `HAL_SAI_Init()` + `HAL_SAI_InitProtocol()` + `HAL_SAI_Transmit_DMA/Receive_DMA` | SAI（多路音频、TDM、PDM） |

**不常用 API**

| API | 一句话作用 |
|---|---|
| `..._IT` 版本（`Transmit_IT` 等） | 中断方式收发 |
| `HAL_SPI_Abort()` / `HAL_SPI_Abort_IT()` | 终止正在进行的传输 |
| `HAL_SPI_DMAPause()` / `DMAResume()` / `DMAStop()` | DMA 暂停 / 恢复 / 停止 |
| `HAL_SPIEx_FlushRxFifo(&hspi1)` | 清空 RX FIFO（丢残留脏数据，通信出错后常用） |
| `HAL_SPI_TxHalfCpltCallback` / `RxHalfCpltCallback` / `TxRxHalfCpltCallback` | 半传输回调（双缓冲流式补数） |
| `HAL_SPI_ErrorCallback` / `GetState` / `GetError`、`RegisterCallback` | 错误与状态诊断 |
| `HAL_I2S_TxHalfCpltCallback/RxCpltCallback`、`HAL_I2S_DMAStop/Abort` | I2S 侧对应的控制与回调 |
| `HAL_SAI_EnableRxMuteMode/DisableRxMuteMode`、`HAL_SAI_DMAStop/Abort`、`HAL_SAIEx_ConfigPdmMicDelay` | SAI 冷门功能 |

**关键选项速解**

- **`Mode`**：`Full-Duplex Master/Slave`、`Half-Duplex Master/Slave`、`Receive Only`、`Transmit Only`。
- **`DataSize`**：4~16 bit（有些屏/Flash 用 8bit，有些编码器用 16bit）。
- **`CLKPolarity` (CPOL)**：空闲时钟电平（0 或 1）；**`CLKPhase` (CPHA)**：在哪个边沿采样——
  这两个**必须与从机手册一致**（常用 Mode0：CPOL=0/CPHA=0）。
- **`FirstBit`**：MSB 或 LSB 先出（多为 MSB）。
- **`NSS`**：软件管理（一般自己用 GPIO 控制 CS）／硬件输入／硬件输出；还有 NSS Pulse Mode。
- **`BaudRatePrescaler`**：SCK = fPCLK / 2^n，从机有时钟上限，别超。
- **`TI Mode`**：TI 特有的时序（SS 与时钟的关系不同）。
- **I2S**：`AudioFreq`、`DataFormat`（16/24/32bit）、`MCLKOutput`、`CPOL`；
  **SAI**：`SyncMode`（异步/主从）、Slot/Frame 配置、PDM（数字麦克风）。


### 10.1 CubeMX 配置要点
**SPI**：Mode = Full-Duplex Master / Full-Duplex Slave / Half-Duplex Master/Slave / Receive Only /
Transmit Only；`Hardware NSS Signal`（Disable / Input / Output）；Data Size(4~16bit)、
First Bit(MSB/LSB)、Clock Polarity(CPOL)、Clock Phase(CPHA)、Prescaler（决定 SCK 频率）、
CRC Calculation、NSS Pulse Mode、TI Mode。
**I2S**：Mode = Master/Slave TX/RX（I2S、Left Justified、Right Justified、PCM…）、Audio Freq、Data/Frame Format。
**SAI**：类似 I2S，多了子块 A/B、Slot 配置、PDM。
别忘了 **DMA Settings** 和 **NVIC**。

### 10.2 SPI 的 HAL 函数（`stm32g4xx_hal_spi.h`）

| 方式 | 发送 | 接收 | 全双工 |
|---|---|---|---|
| 阻塞 | `HAL_SPI_Transmit(hspi, buf, len, timeout)` | `HAL_SPI_Receive(...)` | `HAL_SPI_TransmitReceive(...)` |
| 中断 | `HAL_SPI_Transmit_IT(hspi, buf, len)` | `HAL_SPI_Receive_IT(...)` | `HAL_SPI_TransmitReceive_IT(...)` |
| DMA | `HAL_SPI_Transmit_DMA(...)` | `HAL_SPI_Receive_DMA(...)` | `HAL_SPI_TransmitReceive_DMA(...)` |

```c
/* 典型：读一个 SPI Flash 的 ID（CS 由软件 GPIO 控制） */
uint8_t cmd = 0x9F, id[3];
HAL_GPIO_WritePin(SPI1_CS_GPIO_Port, SPI1_CS_Pin, GPIO_PIN_RESET);
HAL_SPI_Transmit(&hspi1, &cmd, 1, 100);
HAL_SPI_Receive(&hspi1, id, 3, 100);
HAL_GPIO_WritePin(SPI1_CS_GPIO_Port, SPI1_CS_Pin, GPIO_PIN_SET);

/* 收发中断/DMA 用到的回调 */
void HAL_SPI_TxCpltCallback(SPI_HandleTypeDef *hspi)     { }
void HAL_SPI_RxCpltCallback(SPI_HandleTypeDef *hspi)     { }
void HAL_SPI_TxRxCpltCallback(SPI_HandleTypeDef *hspi)   { }
void HAL_SPI_TxHalfCpltCallback / RxHalfCpltCallback / TxRxHalfCpltCallback(...) { }
void HAL_SPI_ErrorCallback(SPI_HandleTypeDef *hspi)      { }
void HAL_SPI_AbortCpltCallback(SPI_HandleTypeDef *hspi)  { }
/* 中断入口 */
void SPI1_IRQHandler(void) { HAL_SPI_IRQHandler(&hspi1); }
/* 运行期控制 */
HAL_SPI_Abort(&hspi1); HAL_SPI_Abort_IT(&hspi1);
HAL_SPI_DMAPause(&hspi1); HAL_SPI_DMAResume(&hspi1); HAL_SPI_DMAStop(&hspi1);
HAL_SPIEx_FlushRxFifo(&hspi1);
```

### 10.3 I2S / SAI（音频、DMA 双缓冲）

概念完全一致，把 `SPI` 换成 `I2S`/`SAI` 即可：
`HAL_I2S_Init()`、`HAL_I2S_Transmit_DMA()`、`HAL_I2S_Receive_DMA()`、
`HAL_I2S_TxCpltCallback/RxCpltCallback/TxHalfCpltCallback/RxHalfCpltCallback`、`HAL_I2S_IRQHandler()`；
`HAL_SAI_Init()`、`HAL_SAI_InitProtocol()`、`HAL_SAI_Transmit_DMA/Receive_DMA()`、
`HAL_SAI_TxCpltCallback/RxCpltCallback`、`HAL_SAI_IRQHandler()`、`HAL_SAI_Abort()`。

> 音频播放的标准做法：**DMA 循环模式 + 半传输/传输完成回调** 里填充下一半数据：
> ```c
> HAL_I2S_Transmit_DMA(&hi2s1, (uint16_t*)audio_buf, BUF_LEN);   // DMA_CIRCULAR
> void HAL_I2S_TxHalfCpltCallback(I2S_HandleTypeDef *hi2s) { FillBuffer(0); }            // 填前半
> void HAL_I2S_TxCpltCallback    (I2S_HandleTypeDef *hi2s) { FillBuffer(BUF_LEN/2); }    // 填后半
> ```
> SPI 做高速流式传输（如 ST7796 刷屏）同理：`HAL_SPI_Transmit_DMA()` + 循环模式 + 回调补数。

### 完整工程骨架（CubeMX 生成 + 你手写）

以 **SPI1 主机 + 软件 CS + ST7796/Flash 类器件读写**为例：

```c
/* ============ Core/Src/spi.c —— CubeMX 生成 ============ */
SPI_HandleTypeDef hspi1;
DMA_HandleTypeDef hdma_spi1_tx;

void MX_SPI1_Init(void)
{
  hspi1.Instance               = SPI1;
  hspi1.Init.Mode              = SPI_MODE_MASTER;
  hspi1.Init.Direction         = SPI_DIRECTION_2LINES;
  hspi1.Init.DataSize          = SPI_DATASIZE_8BIT;
  hspi1.Init.CLKPolarity       = SPI_POLARITY_LOW;        /* CPOL=0 */
  hspi1.Init.CLKPhase          = SPI_PHASE_1EDGE;         /* CPHA=0 → Mode0 */
  hspi1.Init.NSS               = SPI_NSS_SOFT;            /* CS 自己用 GPIO 控制 */
  hspi1.Init.BaudRatePrescaler = SPI_BAUDRATEPRESCALER_8;
  hspi1.Init.FirstBit          = SPI_FIRSTBIT_MSB;
  hspi1.Init.TIMode            = SPI_TIMODE_DISABLE;
  hspi1.Init.CRCCalculation    = SPI_CRCCALCULATION_DISABLE;
  if (HAL_SPI_Init(&hspi1) != HAL_OK) { Error_Handler(); }
}

void HAL_SPI_MspInit(SPI_HandleTypeDef* hspi)
{
  if (hspi->Instance == SPI1)
  {
    __HAL_RCC_SPI1_CLK_ENABLE();
    /* GPIO：SCK/MISO/MOSI = GPIO_MODE_AF_PP + GPIO_AF5_SPI1 */
    /* CS 引脚通常在 gpio.c 里配成普通输出 */
    /* DMA 通道（勾了才有）*/
    HAL_NVIC_SetPriority(SPI1_IRQn, 0, 0);
    HAL_NVIC_EnableIRQ(SPI1_IRQn);
  }
}

/* ============ Core/Src/stm32g4xx_it.c —— CubeMX 生成 ============ */
void SPI1_IRQHandler(void) { HAL_SPI_IRQHandler(&hspi1); }
```

```c
/* ============ 你手写的部分 ============ */

/* ① 片选宏（CS 引脚在 CubeMX 里配成输出并起名 SPI1_CS）*/
#define CS_LOW()   HAL_GPIO_WritePin(SPI1_CS_GPIO_Port, SPI1_CS_Pin, GPIO_PIN_RESET)
#define CS_HIGH()  HAL_GPIO_WritePin(SPI1_CS_GPIO_Port, SPI1_CS_Pin, GPIO_PIN_SET)

/* ② 器件读写封装（最常用的两段）*/
void SPIFlash_ReadID(uint8_t *id)
{
  uint8_t cmd = 0x9F;
  CS_LOW();
  HAL_SPI_Transmit(&hspi1, &cmd, 1, 100);        /* 阻塞发送命令 */
  HAL_SPI_Receive(&hspi1, id, 3, 100);           /* 读回 3 字节 */
  CS_HIGH();
}

void LCD_WriteDataDMA(uint8_t *buf, uint32_t len)
{
  CS_LOW();
  HAL_SPI_Transmit_DMA(&hspi1, buf, len);        /* 大块数据用 DMA */
  /* CS 的拉高放在 TxCpltCallback 里，见 ③ */
}

/* ③ DMA 完成回调：收尾 + 继续下一块（流式刷屏/音频）*/
void HAL_SPI_TxCpltCallback(SPI_HandleTypeDef *hspi)
{
  if (hspi->Instance == SPI1)
  {
    CS_HIGH();
    /* 若用循环 DMA + 双缓冲：在这里填下一半数据 */
  }
}

/* ④ 全双工收发（如读编码器/Flash 数据字节）*/
uint8_t tx[2] = {0x03, 0x00}, rx[2];
HAL_SPI_TransmitReceive(&hspi1, tx, rx, 2, 100);

/* ⑤ 通信出错后的清理（时钟错位/残留数据时）*/
void HAL_SPI_ErrorCallback(SPI_HandleTypeDef *hspi)
{
  HAL_SPIEx_FlushRxFifo(hspi);                   /* 清 RX FIFO */
  CS_HIGH();
}

/* ⑥ 音频（I2S）或 SAI 的流式播放骨架 */
// HAL_I2S_Transmit_DMA(&hi2s1, (uint16_t *)audio_buf, BUF_LEN);   /* DMA_CIRCULAR */
void HAL_I2S_TxHalfCpltCallback(I2S_HandleTypeDef *hi2s) { FillAudio(0); }              /* 填前半 */
void HAL_I2S_TxCpltCallback    (I2S_HandleTypeDef *hi2s) { FillAudio(BUF_LEN / 2); }    /* 填后半 */
```

**CubeMX 配置入口**：`Connectivity → SPI1` 选 Mode（Full-Duplex Master）、Data Size、CPOL/CPHA、
Prescaler、NSS（用软件管理时硬件 NSS 选 Disable）；`I2S1/SAI1` 类似；DMA 在 `DMA Settings` 加。

---

## 11. I2C / SMBUS

### 概览

**常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_I2C_Init(&hi2c1)` | 初始化：时序 / 地址模式 / 从机地址 |
| `HAL_I2C_Mem_Read(&hi2c1, devAddr, memAddr, memSize, buf, len, timeout)` | **读寄存器/EEPROM**（最常用） |
| `HAL_I2C_Mem_Write(...)` | 写寄存器/EEPROM |
| `HAL_I2C_Master_Transmit(&hi2c1, devAddr, buf, len, timeout)` | 纯数据发送（无寄存器地址的器件） |
| `HAL_I2C_Master_Receive(...)` | 纯数据读取 |
| `HAL_I2C_IsDeviceReady(&hi2c1, devAddr, trials, timeout)` | 探测器件在线（上电自检） |
| `_IT` / `_DMA` 版本（`Mem_Read_IT`、`Master_Transmit_DMA`…） | 非阻塞传输 |
| `HAL_I2C_EV_IRQHandler()` / `HAL_I2C_ER_IRQHandler()` | 事件中断 / 错误中断入口 |
| `HAL_I2C_MemTxCpltCallback / MemRxCpltCallback / MasterTxCpltCallback / MasterRxCpltCallback` | 完成回调 |
| `HAL_I2C_ErrorCallback()` | 错误回调（NACK/仲裁丢失/总线错误定位） |

**不常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_I2C_Master_Seq_Transmit_IT/_DMA`、`Master_Seq_Receive_*` | 连续传输（不插入 STOP 的复合时序） |
| `HAL_I2C_Slave_Transmit[_IT/_DMA]`、`Slave_Receive[_IT/_DMA]`、`Slave_Seq_*` | 从机模式收发 |
| `HAL_I2C_EnableListen_IT()` / `DisableListen_IT()` + `AddrCallback` / `ListenCpltCallback` | 从机监听（被主机寻址时回调） |
| `HAL_I2C_Master_Abort_IT()`、`AbortCpltCallback()` | 终止传输 |
| `HAL_I2CEx_ConfigAnalogFilter()` / `ConfigDigitalFilter()` | 模拟 / 数字噪声滤波（长线/干扰环境） |
| `HAL_I2CEx_EnableFastModePlus()` / `DisableFastModePlus()` | Fast Mode+（1MHz，需硬件与上拉支持） |
| `HAL_I2CEx_EnableWakeUp()` / `DisableWakeUp()` | I2C 地址唤醒（低功耗） |
| `HAL_I2C_GetState()` / `GetMode()` / `GetError()`、`RegisterCallback/RegisterAddrCallback` | 诊断与注册式回调 |

**关键选项速解**

- **`Timing`**：时序寄存器值（CubeMX 按你填的 100k/400k/1M 自动算出来），**改速率就是改它**。
- **`OwnAddress1/2` + `AddressingMode`**：从机地址与 7/10 位寻址。
- **`DualAddressMode`**：一个从机用两个地址；**`GeneralCallMode`**：响应全呼地址 0x00。
- **`NoStretchMode`**：是否禁止时钟拉伸（从机拉低 SCL 拖时间）。
- **地址写法坑**：HAL 的地址参数要 **7 位地址左移 1 位**（0x68 → 传 0x68<<1）。
- **`memAddrSize`**：寄存器地址宽度 `I2C_MEMADD_SIZE_8BIT`（多数传感器）或 `_16BIT`（EEPROM）。
- **速率与上拉**：100k 一般 4.7kΩ，400k 用 2.2~4.7kΩ；线长越长速率要越低。


### 11.1 CubeMX 配置要点
`I2C` 页：**I2C Speed Mode**（Standard/Fast/Fast Plus）、**Clock Speed**（100k/400k/1000k Hz）、
**Fast Mode Plus**、Dual Address、General Call、No Clock Stretch、Analog/Digital Noise Filter；
下面的 **Timing Setting** 会自动算出 `hi2c1.Init.Timing` 值；从机模式还要填 Own Address。
**DMA Settings** + **NVIC**（`I2C1 event interrupt` 和 `I2C1 error interrupt` 两个）。

### 11.2 生成的代码
```c
I2C_HandleTypeDef hi2c1;
void MX_I2C1_Init(void)
{
  hi2c1.Instance             = I2C1;
  hi2c1.Init.Timing          = 0x10805D88;      /* CubeMX 算好的时序寄存器值 */
  hi2c1.Init.OwnAddress1     = 0;
  hi2c1.Init.AddressingMode  = I2C_ADDRESSINGMODE_7BIT;
  hi2c1.Init.DualAddressMode = I2C_DUALADDRESS_DISABLE;
  hi2c1.Init.GeneralCallMode = I2C_GENERALCALL_DISABLE;
  hi2c1.Init.NoStretchMode   = I2C_NOSTRETCH_DISABLE;
  if (HAL_I2C_Init(&hi2c1) != HAL_OK) { Error_Handler(); }
}
```

### 11.3 主机的核心函数（`stm32g4xx_hal_i2c.h`）

| 用途 | 阻塞 | 中断 | DMA |
|---|---|---|---|
| 主机发送（写从机） | `HAL_I2C_Master_Transmit(&hi2c1, devAddr, buf, len, timeout)` | `_IT` | `_DMA` |
| 主机接收（读从机） | `HAL_I2C_Master_Receive(&hi2c1, devAddr, buf, len, timeout)` | `_IT` | `_DMA` |
| **读写寄存器/存储器** | `HAL_I2C_Mem_Write(&hi2c1, devAddr, memAddr, memAddrSize, buf, len, timeout)` | `_IT` | `_DMA` |
| | `HAL_I2C_Mem_Read(...)` | `_IT` | `_DMA` |
| 探测从机是否应答 | `HAL_I2C_IsDeviceReady(&hi2c1, devAddr, trials, timeout)` | — | — |
| 连续传输（无 STOP 的 Seq） | — | `HAL_I2C_Master_Seq_Transmit_IT/_DMA`、`_Seq_Receive_IT/_DMA` | |
| 从机模式 | `HAL_I2C_Slave_Transmit/Receive[_IT/_DMA]`、`HAL_I2C_Slave_Seq_Transmit/Receive_IT/_DMA` | | |
| 从机监听 | `HAL_I2C_EnableListen_IT()` / `HAL_I2C_DisableListen_IT()` | | |
| 终止传输 | `HAL_I2C_Master_Abort_IT()` | | |

```c
/* 例：读 MPU6050 的 WHO_AM_I（寄存器 0x75），器件地址 0x68<<1 */
uint8_t id = 0;
if (HAL_I2C_Mem_Read(&hi2c1, 0xD0, 0x75, I2C_MEMADD_SIZE_8BIT, &id, 1, 100) == HAL_OK)
{
  /* id 应为 0x68 */
}
/* 例：写一个字节寄存器 */
uint8_t val = 0x00;
HAL_I2C_Mem_Write(&hi2c1, 0xD0, 0x6B, I2C_MEMADD_SIZE_8BIT, &val, 1, 100);
```
> 注意：HAL 的 I2C 函数地址参数要**左移一位后的 8 位地址**（7 位地址 0x68 → 传 `0x68<<1`）。
> 用 `I2C_MEMADD_SIZE_16BIT` 读 EEPROM 之类 16 位寄存器地址器件。

### 11.4 中断入口与回调
```c
void I2C1_EV_IRQHandler(void) { HAL_I2C_EV_IRQHandler(&hi2c1); }   /* 事件中断 */
void I2C1_ER_IRQHandler(void) { HAL_I2C_ER_IRQHandler(&hi2c1); }   /* 错误中断 */

void HAL_I2C_MasterTxCpltCallback(I2C_HandleTypeDef *hi2c) { }
void HAL_I2C_MasterRxCpltCallback(I2C_HandleTypeDef *hi2c) { }
void HAL_I2C_MemTxCpltCallback   (I2C_HandleTypeDef *hi2c) { }
void HAL_I2C_MemRxCpltCallback   (I2C_HandleTypeDef *hi2c) { }
void HAL_I2C_SlaveTxCpltCallback (I2C_HandleTypeDef *hi2c) { }
void HAL_I2C_SlaveRxCpltCallback (I2C_HandleTypeDef *hi2c) { }
void HAL_I2C_AddrCallback(I2C_HandleTypeDef *hi2c, uint8_t TransferDirection, uint16_t AddrMatchCode) { }
void HAL_I2C_ListenCpltCallback (I2C_HandleTypeDef *hi2c) { }
void HAL_I2C_AbortCpltCallback  (I2C_HandleTypeDef *hi2c) { }
void HAL_I2C_ErrorCallback      (I2C_HandleTypeDef *hi2c) { /* 读 hi2c->ErrorCode 定位 AF/BERR/ARLO */ }
/* 也能用注册式回调（更安全的多实例写法） */
HAL_I2C_RegisterCallback(&hi2c1, HAL_I2C_MASTER_TX_COMPLETE_CB_ID, MyI2CTxCb);
HAL_I2C_RegisterAddrCallback(&hi2c1, MyAddrCb);
```

### 11.5 I2C 卡死（BUSY）怎么救
```c
if (HAL_I2C_GetState(&hi2c1) == HAL_I2C_STATE_BUSY)   /* 从机拉死 SDA 时的软件恢复 */
{
  HAL_I2C_DeInit(&hi2c1);
  /* 手动发 9 个时钟脉冲，或直接把 SCL 当 GPIO 翻转若干次 */
  MX_I2C1_Init();
}
```
其它可用：`HAL_I2CEx_ConfigAnalogFilter()`、`HAL_I2CEx_ConfigDigitalFilter()`、
`HAL_I2CEx_EnableFastModePlus()`。SMBUS 与 I2C 函数一一对应（把前缀换成 `HAL_SMBUS_`，
且 SMBUS 只有 `_IT` 版本）。

### 完整工程骨架（CubeMX 生成 + 你手写）

以 **I2C1 主机读写 MPU6050（寄存器读写 + 出错恢复）**为例：

```c
/* ============ Core/Src/i2c.c —— CubeMX 生成 ============ */
I2C_HandleTypeDef hi2c1;

void MX_I2C1_Init(void)
{
  hi2c1.Instance             = I2C1;
  hi2c1.Init.Timing          = 0x10805D88;      /* CubeMX 按 100k/400k 算好 */
  hi2c1.Init.OwnAddress1     = 0;
  hi2c1.Init.AddressingMode  = I2C_ADDRESSINGMODE_7BIT;
  hi2c1.Init.DualAddressMode = I2C_DUALADDRESS_DISABLE;
  hi2c1.Init.OwnAddress2     = 0;
  hi2c1.Init.GeneralCallMode = I2C_GENERALCALL_DISABLE;
  hi2c1.Init.NoStretchMode   = I2C_NOSTRETCH_DISABLE;
  if (HAL_I2C_Init(&hi2c1) != HAL_OK) { Error_Handler(); }
}

void HAL_I2C_MspInit(I2C_HandleTypeDef* i2cHandle)
{
  if (i2cHandle->Instance == I2C1)
  {
    __HAL_RCC_I2C1_CLK_ENABLE();
    /* GPIO：SCL/SDA = GPIO_MODE_AF_OD + GPIO_AF4_I2C1（开漏必须）*/
    HAL_NVIC_SetPriority(I2C1_EV_IRQn, 0, 0);
    HAL_NVIC_EnableIRQ(I2C1_EV_IRQn);
    HAL_NVIC_SetPriority(I2C1_ER_IRQn, 0, 0);
    HAL_NVIC_EnableIRQ(I2C1_ER_IRQn);
  }
}

/* ============ Core/Src/stm32g4xx_it.c —— CubeMX 生成 ============ */
void I2C1_EV_IRQHandler(void) { HAL_I2C_EV_IRQHandler(&hi2c1); }
void I2C1_ER_IRQHandler(void) { HAL_I2C_ER_IRQHandler(&hi2c1); }
```

```c
/* ============ 你手写的部分 ============ */

#define MPU_ADDR   (0x68 << 1)          /* 7 位地址必须左移 1 位 */

/* ① 最常用的封装：读/写一个寄存器 */
uint8_t MPU_ReadReg(uint8_t reg, uint8_t *val)
{
  return HAL_I2C_Mem_Read(&hi2c1, MPU_ADDR, reg, I2C_MEMADD_SIZE_8BIT,
                          val, 1, 100) == HAL_OK;
}
uint8_t MPU_WriteReg(uint8_t reg, uint8_t val)
{
  return HAL_I2C_Mem_Write(&hi2c1, MPU_ADDR, reg, I2C_MEMADD_SIZE_8BIT,
                           &val, 1, 100) == HAL_OK;
}

/* ② 连读多个寄存器（加速度 6 字节）*/
uint8_t buf[6];
HAL_I2C_Mem_Read(&hi2c1, MPU_ADDR, 0x3B, I2C_MEMADD_SIZE_8BIT, buf, 6, 100);

/* ③ 上电自检：器件在线吗（比盲读安全）*/
if (HAL_I2C_IsDeviceReady(&hi2c1, MPU_ADDR, 3, 100) != HAL_OK)
{
  printf("I2C device not found\r\n");
}

/* ④ 非阻塞版本（不想阻塞主循环时）*/
HAL_I2C_Mem_Read_IT(&hi2c1, MPU_ADDR, 0x3B, I2C_MEMADD_SIZE_8BIT, buf, 6);
void HAL_I2C_MemRxCpltCallback(I2C_HandleTypeDef *hi2c) { /* 数据到了 */ }

/* ⑤ 出错回调 + 总线恢复（SDA 被从机拉死的经典故障）*/
void HAL_I2C_ErrorCallback(I2C_HandleTypeDef *hi2c)
{
  if (hi2c->ErrorCode & HAL_I2C_ERROR_AF || HAL_I2C_ERROR_BERR)
  {
    HAL_I2C_DeInit(hi2c);
    /* 简易恢复：把 SCL 当 GPIO 翻转 9 次再重初始化 */
    MX_I2C1_Init();
  }
}

/* ⑥ 从机模式（被别的 MCU 当外设读写时）*/
// HAL_I2C_EnableListen_IT(&hi2c1);
void HAL_I2C_AddrCallback(I2C_HandleTypeDef *hi2c, uint8_t TransferDirection, uint16_t AddrMatchCode)
{
  if (TransferDirection == I2C_DIRECTION_TRANSMIT)                          /* 主机要读 */
    HAL_I2C_Slave_Seq_Transmit_IT(hi2c, tx_buf, len, I2C_FIRST_AND_LAST_FRAME);
  else                                                                       /* 主机要写 */
    HAL_I2C_Slave_Seq_Receive_IT(hi2c, rx_buf, len, I2C_FIRST_AND_LAST_FRAME);
}
```

**CubeMX 配置入口**：`Connectivity → I2C1` 选 `I2C`，Parameter 页设 `I2C Speed Mode`（Standard/Fast/Fast+）
与 Clock Speed（会自动算出 `Init.Timing`）；NVIC 里勾 Event 和 Error 两个中断。

---

## 12. ADC

### 概览

**常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_ADC_Init(&hadc1)` | 初始化：分辨率 / 扫描 / 连续 / 触发源 / 过采样 |
| `HAL_ADCEx_Calibration_Start(&hadc1, ADC_SINGLE_ENDED)` | **上电必做**的校准，不做读数会偏 |
| `HAL_ADC_ConfigChannel(&hadc1, &sConfig)` | 配通道：Rank 顺序、采样时间、单端/差分、偏移 |
| `HAL_ADC_Start(&hadc1)` / `HAL_ADC_Stop()` | 启动 / 停止常规组转换 |
| `HAL_ADC_PollForConversion(&hadc1, timeout)` | 阻塞等转换结束（配 `HAL_ADC_GetValue` 用） |
| `HAL_ADC_GetValue(&hadc1)` | 读转换结果 |
| `HAL_ADC_Start_IT()` + `HAL_ADC_ConvCpltCallback()` | 中断方式单次转换 |
| `HAL_ADC_Start_DMA(&hadc1, (uint32_t*)buf, len)` / `Stop_DMA()` | **DMA 采集**（多通道/连续，推荐） |
| `HAL_ADC_IRQHandler(&hadc1)` | 中断入口（`ADC1_2_IRQHandler` 里调用） |

**较常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_ADCEx_InjectedConfigChannel()` + `InjectedStart[_IT]()` + `InjectedGetValue()` | 注入组：可打断常规组的"插队"转换（电流采样） |
| `HAL_ADCEx_InjectedConvCpltCallback()` | 注入组转换完成回调 |
| `HAL_ADCEx_MultiModeConfigChannel()` / `MultiModeStart_DMA()` / `MultiModeGetValue()` | 多 ADC 同步/交替采样（一次拿到两个 ADC 的值） |
| `HAL_ADC_AnalogWDGConfig()` + `HAL_ADC_LevelOutOfWindowCallback()` | 模拟看门狗：越限立刻进中断（保护） |
| `HAL_ADCEx_InjectedPollForConversion()` | 阻塞等注入组完成 |

**不常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_ADC_StartSampling()` / `HAL_ADC_StopSampling()` | 提前启动采样，缩短触发到结果的延迟 |
| `HAL_ADCEx_EnableInjectedQueue()` / `DisableInjectedQueue()` | 注入队列（连续触发排队，不覆盖） |
| `HAL_ADCEx_EnterADCDeepPowerDownMode()` | ADC 深度掉电（低功耗） |
| `HAL_ADCEx_DisableVoltageRegulator()` / `EnableVoltageRegulator()` | 内部稳压器控制 |
| `HAL_ADCEx_Calibration_GetValue()` / `SetValue()` | 读 / 写校准值（省一次校准时间） |
| `HAL_ADCEx_RegularStop[_IT/_DMA]()`、`HAL_ADCEx_InjectedStop[_IT]()` | 分别停止常规组 / 注入组 |
| `HAL_ADC_PollForEvent()`、`HAL_ADC_GetState/GetError()`、`RegisterCallback()` | 诊断与注册式回调 |

**关键选项速解**

- **`ClockPrescaler`**：同步模式按 PCLK 分频，异步模式用专门时钟源（高频采样时更灵活）。
- **`Resolution`**：12/10/8/6 bit，位数越低转换越快。
- **`DataAlign`**：左对齐 / 右对齐（右对齐读出来就是原始码值，最常用）。
- **`ScanConvMode`**：多通道扫描必须 ENABLE，否则只转 Rank1。
- **`ContinuousConvMode`**：一次触发后是否连续不停转换。
- **`ExternalTrigConv` / `...Edge`**：软件启动，还是由 TIM/HRTIM/EXTI 触发（电源/电机场景必用）。
- **`DMAContinuousRequests`**：DMA 循环请求，配合 DMA 循环模式才能"一直采"。
- **`Overrun`**：数据没被读走时是覆盖还是丢弃（`ADC_OVR_DATA_PRESERVED` 保数据不丢）。
- **`SamplingTime`**：采样电容充电时间，源阻抗高就要加长（如 247.5 周期）。
- **`Oversampling`**：硬件过采样（多次平均），提升有效位数、抗噪，代价是速度与 CPU 无关。
- **注入 vs 常规**：常规组按 Rank 顺序转（DMA 批量）；注入组"插队"且可独立触发，适合与 PWM 同步的电流环。


### 12.1 CubeMX 配置要点
`ADCx → Parameter Settings`：**Clock Prescaler**（同步 PCLK 分频或异步）、
**Resolution**（12/10/8/6 位）、**Data Alignment**、**Scan Conversion Mode**（多通道必须开）、
**EOC Selection**、**Continuous Conversion Mode**、**Discontinuous Conversion Mode**、
**DMA Continuous Requests**、**Overrun behaviour**（覆盖/保留）、Low Power Auto Wait、
Gain Compensation；**External Trigger**（Regular / Injected 各自的触发源：软件、TIMx TRGO、HRTIM_TRGx）；
**Rank**：每个通道的采样时间与顺序；**Injected Conversion Mode**；**Analog Watchdog**；
**Oversampling**（硬件过采样，等效提高分辨率）；**NVIC** 勾 `ADC1_2 / ADC3 / ADC5` 中断；
用 DMA 时在 **DMA Settings** 加 `ADCx`。

### 12.2 生成的代码
```c
ADC_HandleTypeDef hadc1;
ADC_ChannelConfTypeDef sConfig = {0};

void MX_ADC1_Init(void)
{
  hadc1.Instance                   = ADC1;
  hadc1.Init.ClockPrescaler        = ADC_CLOCK_SYNC_PCLK_DIV4;
  hadc1.Init.Resolution            = ADC_RESOLUTION_12B;
  hadc1.Init.DataAlign             = ADC_DATAALIGN_RIGHT;
  hadc1.Init.ScanConvMode          = ADC_SCAN_DISABLE;      /* 多通道要 ADC_SCAN_ENABLE */
  hadc1.Init.EOCSelection          = ADC_EOC_SINGLE_CONV;
  hadc1.Init.ContinuousConvMode    = DISABLE;
  hadc1.Init.NbrOfConversion       = 1;
  hadc1.Init.DiscontinuousConvMode = DISABLE;
  hadc1.Init.ExternalTrigConv      = ADC_SOFTWARE_START;    /* 或 ADC_EXTERNALTRIGCONV_T1_TRGO 等 */
  hadc1.Init.ExternalTrigConvEdge  = ADC_EXTERNALTRIGCONVEDGE_NONE;
  hadc1.Init.DMAContinuousRequests = DISABLE;               /* DMA 循环采集要 ENABLE */
  hadc1.Init.Overrun               = ADC_OVR_DATA_PRESERVED;
  hadc1.Init.OversamplingMode      = DISABLE;
  if (HAL_ADC_Init(&hadc1) != HAL_OK) { Error_Handler(); }

  sConfig.Channel      = ADC_CHANNEL_3;
  sConfig.Rank         = ADC_REGULAR_RANK_1;
  sConfig.SamplingTime = ADC_SAMPLETIME_2CYCLES_5;          /* 高阻源要加长，如 247CYCLES_5 */
  sConfig.SingleDiff   = ADC_SINGLE_ENDED;
  sConfig.OffsetNumber = ADC_OFFSET_NONE;
  sConfig.Offset       = 0;
  if (HAL_ADC_ConfigChannel(&hadc1, &sConfig) != HAL_OK) { Error_Handler(); }
}
```

### 12.3 校准（上电必须做一次）
```c
HAL_ADCEx_Calibration_Start(&hadc1, ADC_SINGLE_ENDED);   /* G4 要传单端/差分 */
/* 也可以读/存校准值 */
HAL_ADCEx_Calibration_GetValue(&hadc1, ADC_SINGLE_ENDED);
```

### 12.4 三种常用读取方式

```c
/* ① 阻塞单次（最简单） */
HAL_ADC_Start(&hadc1);
if (HAL_ADC_PollForConversion(&hadc1, 10) == HAL_OK)
{
  uint16_t raw = HAL_ADC_GetValue(&hadc1);          /* 12 位结果 */
  float volt = raw * 3.3f / 4095.0f;
}
HAL_ADC_Stop(&hadc1);

/* ② 中断单次 */
HAL_ADC_Start_IT(&hadc1);
void HAL_ADC_ConvCpltCallback(ADC_HandleTypeDef *hadc)
{
  if (hadc->Instance == ADC1) { uint16_t v = HAL_ADC_GetValue(hadc); }
}

/* ③ DMA（多通道/连续采集，推荐） */
uint16_t adc_buf[4];
HAL_ADC_Start_DMA(&hadc1, (uint32_t *)adc_buf, 4);   /* DMA 循环模式则一直采 */
void HAL_ADC_ConvCpltCallback(ADC_HandleTypeDef *hadc) { /* adc_buf 已刷新 */ }
HAL_ADC_Stop_DMA(&hadc1);
```
中断入口：`void ADC1_2_IRQHandler(void) { HAL_ADC_IRQHandler(&hadc1); }`
（CubeMX 会自动生成到 `stm32g4xx_it.c`）。

### 12.5 注入组（Injected，可打断常规组，适合电流采样）
```c
ADC_InjectionConfTypeDef sConfigInjected = {0};
sConfigInjected.InjectedChannel      = ADC_CHANNEL_1;
sConfigInjected.InjectedRank         = ADC_INJECTED_RANK_1;
sConfigInjected.InjectedSamplingTime = ADC_SAMPLETIME_12CYCLES_5;
sConfigInjected.InjectedSingleDiff   = ADC_SINGLE_ENDED;
sConfigInjected.InjectedOffsetNumber = ADC_OFFSET_NONE;
sConfigInjected.InjectedNbrOfConversion = 1;
sConfigInjected.InjectedTrigger      = ADC_EXTERNALTRIGINJEC_T1_TRGO;  /* 常由 HRTIM/TIM 触发 */
sConfigInjected.ExternalTrigInjecEdge = ADC_EXTERNALTRIGINJECCONV_EDGE_RISING;
HAL_ADCEx_InjectedConfigChannel(&hadc1, &sConfigInjected);

HAL_ADCEx_InjectedStart_IT(&hadc1);
void HAL_ADCEx_InjectedConvCpltCallback(ADC_HandleTypeDef *hadc)
{
  uint16_t cur = HAL_ADCEx_InjectedGetValue(hadc, ADC_INJECTED_RANK_1);
}
/* 或阻塞：HAL_ADCEx_InjectedStart() + HAL_ADCEx_InjectedPollForConversion() */
```

### 12.6 多重模式（多个 ADC 同步/交替采样）
```c
ADC_MultiModeTypeDef multimode = {0};
multimode.Mode = ADC_MODE_INDEPENDENT;                 /* 或 ADC_DUALMODE_REGSIMULT / ADC_DUALMODE_INTERL … */
HAL_ADCEx_MultiModeConfigChannel(&hadc1, &multimode);  /* 只需在主机 ADC1 上调 */

uint16_t both[2];
HAL_ADCEx_MultiModeStart_DMA(&hadc1, (uint32_t *)both, 1);   /* 主机启动，从机自动跟随 */
uint32_t raw = HAL_ADCEx_MultiModeGetValue(&hadc1);          /* 高 16 位=从机, 低 16 位=主机 */
HAL_ADCEx_MultiModeStop_DMA(&hadc1);
```
> 从机 ADC2 只需正常 `HAL_ADC_Init()` + 配通道，**不要**再调 MultiMode 配置。

### 12.7 模拟看门狗（越限中断/保护）
```c
ADC_AnalogWDGConfTypeDef awd = {0};
awd.WatchdogNumber    = ADC_ANALOGWATCHDOG_1;
awd.WatchdogMode      = ADC_ANALOGWATCHDOG_SINGLE_REG;   /* 或 ALL_REG / SINGLE_INJEC / ALL_INJEC */
awd.Channel           = ADC_CHANNEL_3;
awd.ITMode            = ENABLE;
awd.HighThreshold     = 0xF00;
awd.LowThreshold      = 0x100;
awd.FilteringConfig   = ADC_AWD_FILTERING_NONE;
HAL_ADC_AnalogWDGConfig(&hadc1, &awd);
void HAL_ADC_LevelOutOfWindowCallback(ADC_HandleTypeDef *hadc) { /* 越限 */ }
```

### 12.8 其它常用函数
`HAL_ADC_StartSampling()` / `HAL_ADC_StopSampling()`（提前启动采样，降低触发延迟）、
`HAL_ADCEx_EnableInjectedQueue()` / `HAL_ADCEx_DisableInjectedQueue()`、
`HAL_ADCEx_RegularStop[_IT/_DMA]()`、`HAL_ADCEx_InjectedStop[_IT]()`、
`HAL_ADCEx_EnterADCDeepPowerDownMode()`、`HAL_ADCEx_DisableVoltageRegulator()`、
`HAL_ADC_GetState()`、`HAL_ADC_GetError()`。

### 12.9 常用宏（注意 ADC 的宏是 `__HAL_ADC_xxx`）
```c
__HAL_ADC_ENABLE_IT(&hadc1, ADC_IT_EOC);   __HAL_ADC_DISABLE_IT(&hadc1, ADC_IT_EOC);
__HAL_ADC_GET_FLAG(&hadc1, ADC_FLAG_EOC);  __HAL_ADC_CLEAR_FLAG(&hadc1, ADC_FLAG_EOC);
/* 换算辅助（比手写 3.3/4095 更规范） */
volt  = __HAL_ADC_CALC_DATA_TO_VOLTAGE(3300, raw, ADC_RESOLUTION_12B);   /* 单位 mV */
temp  = __HAL_ADC_CALC_TEMPERATURE(3300, raw_temp, ADC_RESOLUTION_12B);  /* 芯片温度 */
vref  = __HAL_ADC_CALC_VREFANALOG_VOLTAGE(raw_vrefint, ADC_RESOLUTION_12B);
```

### 完整工程骨架（CubeMX 生成 + 你手写）

以 **ADC1 多通道扫描 + DMA 循环采集 + 注入组同步采样 + 看门狗报警**为例：

```c
/* ============ Core/Src/adc.c —— CubeMX 生成 ============ */
ADC_HandleTypeDef hadc1;
DMA_HandleTypeDef hdma_adc1;

void MX_ADC1_Init(void)
{
  ADC_MultiModeTypeDef   multimode = {0};
  ADC_ChannelConfTypeDef sConfig   = {0};

  hadc1.Instance                   = ADC1;
  hadc1.Init.ClockPrescaler        = ADC_CLOCK_SYNC_PCLK_DIV4;
  hadc1.Init.Resolution            = ADC_RESOLUTION_12B;
  hadc1.Init.DataAlign             = ADC_DATAALIGN_RIGHT;
  hadc1.Init.ScanConvMode          = ADC_SCAN_ENABLE;            /* 多通道 */
  hadc1.Init.EOCSelection          = ADC_EOC_SINGLE_CONV;
  hadc1.Init.LowPowerAutoWait      = DISABLE;
  hadc1.Init.ContinuousConvMode    = DISABLE;                   /* 靠触发 */
  hadc1.Init.NbrOfConversion       = 2;
  hadc1.Init.DiscontinuousConvMode = DISABLE;
  hadc1.Init.ExternalTrigConv      = ADC_EXTERNALTRIGCONV_T1_TRGO;  /* 由定时器触发 */
  hadc1.Init.ExternalTrigConvEdge  = ADC_EXTERNALTRIGCONVEDGE_RISING;
  hadc1.Init.DMAContinuousRequests = ENABLE;                    /* DMA 循环 */
  hadc1.Init.Overrun               = ADC_OVR_DATA_PRESERVED;
  hadc1.Init.OversamplingMode      = DISABLE;
  if (HAL_ADC_Init(&hadc1) != HAL_OK) { Error_Handler(); }

  multimode.Mode = ADC_MODE_INDEPENDENT;
  HAL_ADCEx_MultiModeConfigChannel(&hadc1, &multimode);

  sConfig.Channel = ADC_CHANNEL_3; sConfig.Rank = ADC_REGULAR_RANK_1;
  sConfig.SamplingTime = ADC_SAMPLETIME_12CYCLES_5; sConfig.SingleDiff = ADC_SINGLE_ENDED;
  sConfig.OffsetNumber = ADC_OFFSET_NONE; sConfig.Offset = 0;
  HAL_ADC_ConfigChannel(&hadc1, &sConfig);
  /* Rank2 ...（CubeMX 按你勾的通道生成）*/

  /* 注入组（如果勾了 Injected）*/
  /* HAL_ADCEx_InjectedConfigChannel(&hadc1, &sConfigInjected); */
}

void HAL_ADC_MspInit(ADC_HandleTypeDef* adcHandle)
{
  if (adcHandle->Instance == ADC1)
  {
    __HAL_RCC_ADC12_CLK_ENABLE();
    HAL_NVIC_SetPriority(ADC1_2_IRQn, 0, 0);
    HAL_NVIC_EnableIRQ(ADC1_2_IRQn);
    /* DMA：hdma_adc1 + __HAL_LINKDMA（见第 5 章骨架）*/
  }
}

/* ============ Core/Src/stm32g4xx_it.c —— CubeMX 生成 ============ */
void ADC1_2_IRQHandler(void) { HAL_ADC_IRQHandler(&hadc1); }
```

```c
/* ============ 你手写的部分 ============ */

/* ① main.c：校准（必须在启动之前，只做一次）*/
HAL_ADCEx_Calibration_Start(&hadc1, ADC_SINGLE_ENDED);

/* ② DMA 循环采集（配合 TIM 触发，每个 PWM 周期采一轮）*/
#define ADC_CH_NUM 2
uint16_t adc_buf[ADC_CH_NUM];
HAL_ADC_Start_DMA(&hadc1, (uint32_t *)adc_buf, ADC_CH_NUM);

void HAL_ADC_ConvCpltCallback(ADC_HandleTypeDef *hadc)
{
  /* 一轮转化完成（扫描到 EOS）。注意：回调里只搬数据，别做复杂运算 */
  adc_frame[0] = adc_buf[0];
  adc_frame[1] = adc_buf[1];
}

/* ③ 想要"一直在采"：让某个 TIM 周期性触发 */
HAL_TIM_Base_Start(&htim1);        /* TIM1 TRGO 由 CubeMX 里配成 Update Event */

/* ④ 注入组：在 PWM 高峰时刻插队采样（电源/电机电流环）*/
void HAL_ADCEx_InjectedConvCpltCallback(ADC_HandleTypeDef *hadc)
{
  g_current = HAL_ADCEx_InjectedGetValue(hadc, ADC_INJECTED_RANK_1);
}
// 触发方式：外部触发选 HRTIM/TIM 事件，然后 HAL_ADCEx_InjectedStart_IT(&hadc1);

/* ⑤ 同步启动 + 阻塞读一次（简单场合）*/
HAL_ADC_Start(&hadc1);
if (HAL_ADC_PollForConversion(&hadc1, 10) == HAL_OK)
{
  uint16_t raw = HAL_ADC_GetValue(&hadc1);
  uint32_t mv  = __HAL_ADC_CALC_DATA_TO_VOLTAGE(3300, raw, ADC_RESOLUTION_12B);
}
HAL_ADC_Stop(&hadc1);

/* ⑥ 模拟看门狗：越限立刻中断（过流/欠压保护）*/
void HAL_ADC_LevelOutOfWindowCallback(ADC_HandleTypeDef *hadc) { /* 报警 */ }

/* ⑦ 多 ADC 同步（ADC1+ADC2 同时采两条支路）*/
// HAL_ADCEx_MultiModeStart_DMA(&hadc1, (uint32_t *)both, 1);
uint32_t both = HAL_ADCEx_MultiModeGetValue(&hadc1);   /* 高 16 位=从机，低 16 位=主机 */
```

**CubeMX 配置入口**：`Analog → ADCx` 的 Parameter 页设 Resolution / Scan / Continuous / External Trigger /
DMA Continuous Requests / Overrun，Channel 表里逐个通道配采样时间；`DMA Settings` 加 `ADCx`；
`Injected Conversion Mode` 与 `Analog Watchdog` 在下方子页；NVIC 勾 `ADC1_2`。

---

## 13. DAC

### 概览

**常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_DAC_Init(&hdac1)` | 初始化 DAC 外设 |
| `HAL_DAC_ConfigChannel(&hdac1, &sConfig, DAC_CHANNEL_1)` | 配通道：触发源 / 输出缓冲 / 片上连接 / 校准方式 |
| `HAL_DAC_Start(&hdac1, DAC_CHANNEL_1)` / `HAL_DAC_Stop()` | 启动 / 停止输出 |
| `HAL_DAC_SetValue(&hdac1, ch, DAC_ALIGN_12B_R, value)` | 直接设置输出电平（改电压最简单） |
| `HAL_DAC_GetValue(&hdac1, ch)` | 读当前输出值 |
| `HAL_DAC_Start_DMA(&hdac1, ch, buf, len, DAC_ALIGN_12B_R)` / `Stop_DMA()` | DMA 输出任意波形（配 TIM 触发才定频） |

**不常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_DACEx_DualStart/DualStop/DualSetValue/DualStart_DMA/DualGetValue` | 双通道同时输出/控制 |
| `HAL_DACEx_NoiseWaveGenerate(&hdac1, ch, DAC_LFSRUNMASK_BITS11_0)` | 硬件产生噪声（LFSR），幅度由掩码决定 |
| `HAL_DACEx_TriangleWaveGenerate(&hdac1, ch, DAC_TRIANGLEAMPLITUDE_1023)` | 硬件产生三角波（免 DMA） |
| `HAL_DACEx_SawtoothWaveGenerate()` + `SawtoothWaveDataStep()` / `DataReset()` | 硬件锯齿波（G4 特有）及步进/复位 |
| `HAL_DACEx_SelfCalibrate()` / `GetTrimOffset()` / `SetUserTrimming()` | 自校准 / 读微调值 / 写用户微调值 |
| `HAL_DAC_IRQHandler(&hdac1)` + `ConvCpltCallbackCh1/HalfCpltCallbackCh1/DMAUnderrunCallbackCh1/ErrorCallbackCh1` | 中断与回调（通道 2 用 `HAL_DACEx_*Ch2` 版本） |

**关键选项速解**

- **`DAC_Trigger`**：`DAC_TRIGGER_NONE`（写完立即输出）／`DAC_TRIGGER_T2_TRGO` 等（**要定频输出波形必须选 TIM**）／
  `DAC_TRIGGER_SOFTWARE`（软件触发一次）。
- **`DAC_Trigger2`**：锯齿波的"步进触发"（第二触发，G4 新增）。
- **`DAC_OutputBuffer`**：开=驱动能力强但输出范围略窄、精度稍差；关=精度高但带载能力弱。
- **`DAC_ConnectOnChipPeripheral`**：输出是只给引脚，还是同时内部连到别的外设（`EXTERNAL`/`INTERNAL`/`BOTH`）。
- **`DAC_UserTrimming` + `DAC_TrimmingValue`**：用出厂校准值还是自定义微调值。
- **`DAC_SampleAndHold`**：采样保持（低功耗下保持输出电平）。
- **波形模式**：`Noise`（噪声）/ `Triangle`（三角）/ `Sawtooth`（锯齿）由硬件自动产生，不用 CPU 参与。


### 13.1 CubeMX 配置要点
`DACx → Output Channel`：**Output Buffer**（开/关，开可增强驱动但精度略降）、
**Trigger**（None=立即输出 / 软件 / TIMx TRGO / HRTIM_TRGx，做波形必须选 TIM）、
**Wave Generation Mode**（None / Noise / Triangle）、DMA Settings、NVIC。
```c
DAC_HandleTypeDef hdac1;
DAC_ChannelConfTypeDef sConfig = {0};
hdac1.Instance = DAC1;
if (HAL_DAC_Init(&hdac1) != HAL_OK) { Error_Handler(); }
sConfig.DAC_Trigger      = DAC_TRIGGER_T2_TRGO;      /* 用 TIM2 TRGO 定期触发 */
sConfig.DAC_OutputBuffer = DAC_OUTPUTBUFFER_ENABLE;
sConfig.DAC_ConnectOnChipPeripheral = DAC_CHIPCONNECT_EXTERNAL;  /* G4 新增字段 */
sConfig.DAC_UserTrimming = DAC_TRIMMING_FACTORY;
HAL_DAC_ConfigChannel(&hdac1, &sConfig, DAC_CHANNEL_1);
```

### 13.2 核心函数（`stm32g4xx_hal_dac.h` / `_ex.h`）
```c
HAL_DAC_Start(&hdac1, DAC_CHANNEL_1);                        /* 启动输出 */
HAL_DAC_Stop (&hdac1, DAC_CHANNEL_1);
HAL_DAC_SetValue(&hdac1, DAC_CHANNEL_1, DAC_ALIGN_12B_R, 2048);  /* 输出 1.65V（3.3V 参考） */
uint32_t v = HAL_DAC_GetValue(&hdac1, DAC_CHANNEL_1);

/* DMA 输出任意波形（DMA 循环 + TIM 触发） */
HAL_DAC_Start_DMA(&hdac1, DAC_CHANNEL_1, (uint32_t *)wave_buf, WAVE_LEN, DAC_ALIGN_12B_R);
HAL_DAC_Stop_DMA(&hdac1, DAC_CHANNEL_1);

/* 双通道 */
HAL_DACEx_DualStart(&hdac1);  HAL_DACEx_DualStop(&hdac1);
HAL_DACEx_DualSetValue(&hdac1, DAC_ALIGN_12B_R, ch1_val, ch2_val);
HAL_DACEx_DualStart_DMA(&hdac1, (uint32_t *)buf, len, DAC_ALIGN_12B_R);

/* 硬件波形发生（不用 DMA 也能出三角波/噪声） */
HAL_DACEx_NoiseWaveGenerate   (&hdac1, DAC_CHANNEL_1, DAC_LFSRUNMASK_BITS11_0);   /* 幅度 = LFSR 掩码 */
HAL_DACEx_TriangleWaveGenerate(&hdac1, DAC_CHANNEL_1, DAC_TRIANGLEAMPLITUDE_1023);/* 幅度 1~4095 */
/* G4 特有的锯齿波 + 步进/复位（幅度参数可选 DAC_TRIANGLEAMPLITUDE_x / DAC_LFSRUNMASK_xxx） */
HAL_DACEx_SawtoothWaveGenerate(&hdac1, DAC_CHANNEL_1, DAC_SAWTOOTH_POLARITY_INCREMENT,
                               DAC_TRIANGLEAMPLITUDE_1023);
HAL_DACEx_SawtoothWaveDataStep (&hdac1, DAC_CHANNEL_1);   /* 手动步进 */
HAL_DACEx_SawtoothWaveDataReset(&hdac1, DAC_CHANNEL_1);   /* 复位到起始值 */

/* 校准（G4） */
HAL_DACEx_SelfCalibrate(&hdac1, &sConfig, DAC_CHANNEL_1);
HAL_DACEx_GetTrimOffset(&hdac1, DAC_CHANNEL_1);
DAC_ChannelConfTypeDef c = {0}; c.DAC_UserTrimming = DAC_TRIMMING_USER; c.DAC_TrimmingValue = 0x1F;
HAL_DACEx_SetUserTrimming(&hdac1, &c, DAC_CHANNEL_1);
```
**中断与回调**
```c
void DAC1_IRQHandler(void) { HAL_DAC_IRQHandler(&hdac1); }
void HAL_DAC_ConvCpltCallbackCh1(DAC_HandleTypeDef *hdac) { }
void HAL_DAC_ConvHalfCpltCallbackCh1(DAC_HandleTypeDef *hdac) { }
void HAL_DAC_DMAUnderrunCallbackCh1(DAC_HandleTypeDef *hdac) { }   /* DMA 供数不及时！ */
void HAL_DAC_ErrorCallbackCh1(DAC_HandleTypeDef *hdac) { }
void HAL_DACEx_ConvCpltCallbackCh2(DAC_HandleTypeDef *hdac) { }     /* 通道 2 用 _ex 版本 */
```
> **要点**：① 想让 DAC 定频输出就必须选 TIM 触发 + `HAL_TIM_Base_Start(&htim)`；
> ② 输出波形用 DMA 循环模式；③ 出现 `DMAUnderrun` 说明 DMA 喂数太慢或被打断。

### 完整工程骨架（CubeMX 生成 + 你手写）

以 **DAC1 通道 1：输出可调电压 + 用 DMA 输出正弦波**为例：

```c
/* ============ Core/Src/dac.c —— CubeMX 生成 ============ */
DAC_HandleTypeDef hdac1;
DMA_HandleTypeDef hdma_dac1_ch1;

void MX_DAC1_Init(void)
{
  DAC_ChannelConfTypeDef sConfig = {0};

  hdac1.Instance = DAC1;
  if (HAL_DAC_Init(&hdac1) != HAL_OK) { Error_Handler(); }

  sConfig.DAC_HighFrequency          = DAC_HIGH_FREQUENCY_INTERFACE_MODE_AUTOMATIC;
  sConfig.DAC_DMADoubleDataMode      = DISABLE;
  sConfig.DAC_SignedFormat           = DISABLE;
  sConfig.DAC_SampleAndHold          = DAC_SAMPLEANDHOLD_DISABLE;
  sConfig.DAC_Trigger                = DAC_TRIGGER_T2_TRGO;    /* 由 TIM2 触发（定频输出）*/
  sConfig.DAC_Trigger2               = DAC_TRIGGER_NONE;       /* 锯齿波步进触发 */
  sConfig.DAC_OutputBuffer           = DAC_OUTPUTBUFFER_ENABLE;
  sConfig.DAC_ConnectOnChipPeripheral = DAC_CHIPCONNECT_EXTERNAL;
  sConfig.DAC_UserTrimming           = DAC_TRIMMING_FACTORY;
  if (HAL_DAC_ConfigChannel(&hdac1, &sConfig, DAC_CHANNEL_1) != HAL_OK) { Error_Handler(); }
}

void HAL_DAC_MspInit(DAC_HandleTypeDef* hdac)
{
  if (hdac->Instance == DAC1)
  {
    __HAL_RCC_DAC1_CLK_ENABLE();
    /* PA4 = DAC_OUT1，配成 GPIO_MODE_ANALOG */
    HAL_NVIC_SetPriority(TIM6_DAC_IRQn, 0, 0);      /* 需要中断时 */
    HAL_NVIC_EnableIRQ(TIM6_DAC_IRQn);
    /* DMA：hdma_dac1_ch1 + __HAL_LINKDMA */
  }
}

/* ============ Core/Src/stm32g4xx_it.c —— CubeMX 生成 ============ */
void TIM6_DAC_IRQHandler(void) { HAL_DAC_IRQHandler(&hdac1); }
```

```c
/* ============ 你手写的部分 ============ */

/* ① 最简单的用法：直接设置输出电平（0~4095 → 0~3.3V）*/
HAL_DAC_Start(&hdac1, DAC_CHANNEL_1);
HAL_DAC_SetValue(&hdac1, DAC_CHANNEL_1, DAC_ALIGN_12B_R, 2048);   /* ≈1.65V */
/* 之后随时改值即可改电压 */
HAL_DAC_SetValue(&hdac1, DAC_CHANNEL_1, DAC_ALIGN_12B_R, 3641);   /* ≈2.93V */

/* ② 输出正弦波：自己造表 + DMA 循环 + TIM 触发 */
#define WAVE_LEN 64
uint32_t sine_tab[WAVE_LEN];                     /* 注意：DMA 用 32 位元素 */

void Wave_Init(void)
{
  for (int i = 0; i < WAVE_LEN; i++)
  {
    /* 12 位右对齐，偏置到中点 2048 */
    sine_tab[i] = (uint32_t)(2048 + 2000 * sinf(2 * 3.1415926f * i / WAVE_LEN));
  }
  HAL_DAC_Start_DMA(&hdac1, DAC_CHANNEL_1, sine_tab, WAVE_LEN, DAC_ALIGN_12B_R);
  HAL_TIM_Base_Start(&htim2);          /* 触发源必须跑起来，波形才有频率 */
}
/* 输出频率 = f_TIM2 / WAVE_LEN，改 TIM2 的 ARR 就改频率 */

/* ③ 停止波形输出 */
HAL_DAC_Stop_DMA(&hdac1, DAC_CHANNEL_1);

/* ④ 校正/微调（G4 支持）*/
DAC_ChannelConfTypeDef cfg = {0};
HAL_DACEx_SelfCalibrate(&hdac1, &cfg, DAC_CHANNEL_1);
HAL_DACEx_GetTrimOffset(&hdac1, DAC_CHANNEL_1);

/* ⑤ 回调：DMA 供数不及时会进 DMAUnderrun，说明 TIM 太快或 DMA 被打断 */
void HAL_DAC_DMAUnderrunCallbackCh1(DAC_HandleTypeDef *hdac) { /* 处理丢数 */ }
```

**CubeMX 配置入口**：`Analog → DAC1` 勾 `Output Channel`，Parameter 页设 Output Buffer、
Trigger（要定频/波形就选某个 `TIMx TRGO`）、Wave Generation Mode；DMA 在 `DMA Settings` 加 `DAC1_CH1`。

---

## 14. COMP 比较器 / OPAMP 运算放大器

### 概览

**COMP 常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_COMP_Init(&hcomp1)` | 初始化：输入正负端 / 迟滞 / 极性 / 消隐 / 触发模式 |
| `HAL_COMP_Start(&hcomp1)` / `HAL_COMP_Stop()` | 使能 / 停用比较器（**G4 没有 `Start_IT`**，中断由 `TriggerMode` 决定） |
| `HAL_COMP_GetOutputLevel(&hcomp1)` | 读比较结果（`COMP_OUTPUT_LEVEL_HIGH/LOW`） |
| `HAL_COMP_TriggerCallback(&hcomp)` | 越阈中断回调 |
| `HAL_COMP_IRQHandler(&hcomp1)` | 中断入口（`COMP1_2_3_IRQHandler` / `COMP4_5_6_...` / `COMP7_...`） |

**COMP 不常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_COMP_Lock(&hcomp1)` | 锁定配置位，防止误改 |
| `HAL_COMP_GetState()` / `GetError()`、`RegisterCallback()` | 诊断与注册式回调 |
| `__HAL_COMP_COMPx_EXTI_ENABLE_RISING_EDGE()` 等 | 直接操作 COMP 对应的 EXTI 线（边沿/事件） |

**OPAMP 常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_OPAMP_Init(&hopamp1)` | 初始化：模式 / 供电档 / 输入 / PGA 增益 / 连接 / 校准 |
| `HAL_OPAMP_Start(&hopamp1)` / `HAL_OPAMP_Stop()` | 使能 / 停用运放 |
| `HAL_OPAMP_SelfCalibrate(&hopamp1)` | 自校准（消除失调，建议每次启动前做） |

**OPAMP 不常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_OPAMP_Lock()` / `HAL_OPAMP_LockTimerMux()` | 锁定配置 / 锁定定时器控制的输入开关 |
| `HAL_OPAMP_GetTrimOffset()` / `HAL_OPAMPEx_SelfCalibrateAll()` | 读微调值 / 一次校准多个运放 |
| `HAL_OPAMP_GetState()`、`RegisterCallback()` | 诊断 |

**关键选项速解**

- **COMP `InputPlus`**：同相端来源（`IO1`/`IO2` 两种引脚）。
- **COMP `InputMinus`**：反相端来源（`IO1`/`IO2` 引脚、`VREFINT`、内部 1/4、1/2、3/4 VREF、`DACx_CHx`）。
- **COMP `Hysteresis`**：迟滞（NONE/LOW/MEDIUM/HIGH），抑制输入噪声引起的抖动。
- **COMP `OutputPol`**：输出极性反相与否。
- **COMP `BlankingSrce`**：消隐源（用 PWM 的 OC5 等信号遮住开关噪声时刻，避免误触发）——功率电路很关键。
- **COMP `TriggerMode`**：`IT_RISING/FALLING/RISING_FALLING`（中断）或 `EVENT_*`（只产生事件，可触发 TIM/ADC）。
- **OPAMP `Mode`**：`STANDALONE_MODE`（普通运放）/ `FOLLOWER_MODE`（跟随器）/ `PGA_MODE`（内部电阻做可编程增益）/
  `TIMERCONTROLLEDMUXMODE`（定时器控制输入切换）。
- **OPAMP `PowerMode`**：`NORMALSPEED`（省电）/ `HIGHSPEED`（快、耗电多）。
- **OPAMP `PgaGain` / `PgaConnect`**：内部增益（2/4/8/16/32/64 或反相 x-1…）与负端内部接法。
- **OPAMP 输出可内部直连 ADC 通道**，省掉外部走线。


### 14.1 COMP（模拟比较器）
CubeMX：**Input Minus / Input Plus**（选引脚或内部参考：VREFINT、DAC、内部 3/4 分压）、
**Output Polarity**、**Hysteresis**、**Speed Mode**、**Inverted Output**、Window Mode、
**Trigger Mode**（在哪个边沿产生中断）、Blanking 源、NVIC。
```c
COMP_HandleTypeDef hcomp1;
hcomp1.Instance = COMP1;
hcomp1.Init.InputMinus        = COMP_INPUT_MINUS_IO1;
hcomp1.Init.InputPlus         = COMP_INPUT_PLUS_IO1;
hcomp1.Init.OutputPol         = COMP_OUTPUTPOL_NONINVERTED;
hcomp1.Init.Hysteresis        = COMP_HYSTERESIS_HIGH;
hcomp1.Init.BlankingSrce      = COMP_BLANKINGSRC_NONE;
hcomp1.Init.TriggerMode       = COMP_TRIGGERMODE_IT_RISING;
if (HAL_COMP_Init(&hcomp1) != HAL_OK) { Error_Handler(); }

HAL_COMP_Start(&hcomp1);   /* G4 没有 HAL_COMP_Start_IT，中断由上面的 TriggerMode 决定 */
if (HAL_COMP_GetOutputLevel(&hcomp1) == COMP_OUTPUT_LEVEL_HIGH) { /* 比较结果 */ }
HAL_COMP_Stop(&hcomp1);   HAL_COMP_Lock(&hcomp1);   /* 锁定配置 */
void COMP1_2_3_IRQHandler(void) { HAL_COMP_IRQHandler(&hcomp1); }   /* COMP4~6 → COMP4_5_6_IRQHandler; COMP7 → COMP7_IRQHandler */
void HAL_COMP_TriggerCallback(COMP_HandleTypeDef *hcomp) { /* 越阈中断 */ }
/* 直接操作 EXTI 触发边沿的宏 */
__HAL_COMP_COMP1_EXTI_ENABLE_RISING_EDGE();
```
> 典型组合：`COMP → TIM Break 输入`（硬件过流关断）、`COMP → HRTIM Fault`、
> `COMP` 输出直接连到定时器/触发 ADC（CubeMX 里在 TIM/ADC 侧选触发源）。

### 14.2 OPAMP（内部运放/跟随器/PGA）
CubeMX：**Mode**（Standalone / Follower / PGA / Timer-controlled PGA）、Power Mode、
**PGA Gain**、输入/输出引脚映射、Timer 控制源；输出可内部连到 ADC 通道。
```c
OPAMP_HandleTypeDef hopamp1;
hopamp1.Instance = OPAMP1;
hopamp1.Init.PowerMode        = OPAMP_POWERMODE_NORMALSPEED;   /* 或 OPAMP_POWERMODE_HIGHSPEED */
hopamp1.Init.Mode             = OPAMP_PGA_MODE;          /* 或 OPAMP_STANDALONE_MODE / FOLLOWER_MODE */
hopamp1.Init.InvertingInput   = OPAMP_INVERTINGINPUT_IO0;
hopamp1.Init.NonInvertingInput= OPAMP_NONINVERTINGINPUT_IO0;
hopamp1.Init.PgaGain          = OPAMP_PGA_GAIN_4_OR_MINUS_3;
hopamp1.Init.PgaConnect       = OPAMP_PGA_CONNECT_INVERTINGINPUT_IO0_BIAS;
hopamp1.Init.UserTrimming     = OPAMP_TRIMMING_FACTORY;
if (HAL_OPAMP_Init(&hopamp1) != HAL_OK) { Error_Handler(); }

HAL_OPAMP_SelfCalibrate(&hopamp1);        /* 自校准，建议启动前做一次 */
HAL_OPAMP_Start(&hopamp1);                /* 使能运放 */
HAL_OPAMP_Stop(&hopamp1);
HAL_OPAMP_Lock(&hopamp1);                 /* 锁定配置位 */
HAL_OPAMP_LockTimerMux(&hopamp1);         /* Timer 控制模式下锁定多路开关 */
HAL_OPAMP_GetTrimOffset(&hopamp1);
HAL_OPAMPEx_SelfCalibrateAll(&hopamp1, &hopamp2);   /* 一次校准多个 */
```
MspInit 里不要忘记：`__HAL_RCC_OPAMP_CLK_ENABLE();` + 把引脚配成 `GPIO_MODE_ANALOG`。

### 完整工程骨架（CubeMX 生成 + 你手写）

以 **COMP1 做过流检测（输出接 TIM1 刹车）+ OPAMP1 做电流信号放大送 ADC** 为例：

```c
/* ============ Core/Src/comp.c —— CubeMX 生成 ============ */
COMP_HandleTypeDef hcomp1;

void MX_COMP1_Init(void)
{
  hcomp1.Instance = COMP1;
  hcomp1.Init.InputPlus    = COMP_INPUT_PLUS_IO1;      /* 同相端引脚 */
  hcomp1.Init.InputMinus   = COMP_INPUT_MINUS_IO1;     /* 反相端（或 DAC/VREFINT）*/
  hcomp1.Init.Hysteresis   = COMP_HYSTERESIS_HIGH;
  hcomp1.Init.OutputPol    = COMP_OUTPUTPOL_NONINVERTED;
  hcomp1.Init.BlankingSrce = COMP_BLANKINGSRC_NONE;    /* 可与 TIM1_OC5 消隐 */
  hcomp1.Init.TriggerMode  = COMP_TRIGGERMODE_IT_RISING;
  if (HAL_COMP_Init(&hcomp1) != HAL_OK) { Error_Handler(); }
}

void HAL_COMP_MspInit(COMP_HandleTypeDef* hcomp)
{
  GPIO_InitTypeDef GPIO_InitStruct = {0};
  if (hcomp->Instance == COMP1)
  {
    __HAL_RCC_SYSCFG_CLK_ENABLE();
    /* 输入引脚配成 GPIO_MODE_ANALOG */
    HAL_NVIC_SetPriority(COMP1_2_3_IRQn, 0, 0);
    HAL_NVIC_EnableIRQ(COMP1_2_3_IRQn);
  }
}

/* ============ Core/Src/stm32g4xx_it.c —— CubeMX 生成 ============ */
void COMP1_2_3_IRQHandler(void) { HAL_COMP_IRQHandler(&hcomp1); }
```

```c
/* ============ Core/Src/opamp.c —— CubeMX 生成 ============ */
OPAMP_HandleTypeDef hopamp1;

void MX_OPAMP1_Init(void)
{
  hopamp1.Instance = OPAMP1;
  hopamp1.Init.PowerMode         = OPAMP_POWERMODE_NORMALSPEED;
  hopamp1.Init.Mode              = OPAMP_PGA_MODE;     /* 或 FOLLOWER_MODE / STANDALONE_MODE */
  hopamp1.Init.InvertingInput    = OPAMP_INVERTINGINPUT_IO0;
  hopamp1.Init.InvertingInputSecondary = OPAMP_INVERTINGINPUT_IO0;
  hopamp1.Init.NonInvertingInput = OPAMP_NONINVERTINGINPUT_IO0;
  hopamp1.Init.NonInvertingInputSecondary = OPAMP_NONINVERTINGINPUT_IO0;
  hopamp1.Init.PgaConnect        = OPAMP_PGA_CONNECT_INVERTINGINPUT_IO0_BIAS;
  hopamp1.Init.PgaGain           = OPAMP_PGA_GAIN_8_OR_MINUS_7;
  hopamp1.Init.UserTrimming      = OPAMP_TRIMMING_FACTORY;
  if (HAL_OPAMP_Init(&hopamp1) != HAL_OK) { Error_Handler(); }
}
```

```c
/* ============ 你手写的部分 ============ */

/* ① 上电顺序：先校准运放，再启动运放，最后启动比较器 */
HAL_OPAMP_SelfCalibrate(&hopamp1);      /* 消失调，建议每次上电都做 */
HAL_OPAMP_Start(&hopamp1);
HAL_COMP_Start(&hcomp1);                /* 注意 G4 没有 HAL_COMP_Start_IT */

/* ② 比较器中断：过流/欠压事件（回调里只做标志或关输出）*/
void HAL_COMP_TriggerCallback(COMP_HandleTypeDef *hcomp)
{
  if (hcomp->Instance == COMP1)
  {
    g_ocp_flag = 1;                     /* 也可在这里 HAL_TIM_PWM_Stop() 关输出 */
  }
}

/* ③ 随时查询比较结果（不用中断时）*/
if (HAL_COMP_GetOutputLevel(&hcomp1) == COMP_OUTPUT_LEVEL_HIGH) { /* 过阈 */ }

/* ④ 硬件级联动（最推荐的做法，不靠软件）：
      CubeMX 里把 COMP1 输出配给 TIM1 的 Break 输入，
      过流时 TIM1 硬件立即关 PWM，比中断快得多。 */

/* ⑤ 运放输出已经在片内接到 ADC 通道，直接采即可 */
HAL_ADC_Start(&hadc1);
HAL_ADC_PollForConversion(&hadc1, 10);
uint16_t i_raw = HAL_ADC_GetValue(&hadc1);     /* 已放大 8 倍的电流信号 */

/* ⑥ 锁定配置（量产前防止被意外改写）*/
HAL_OPAMP_Lock(&hopamp1);
HAL_COMP_Lock(&hcomp1);
```

**CubeMX 配置入口**：`Analog → COMPx` 选输入正负端/迟滞/极性/消隐源/触发模式与 NVIC；
`Analog → OPAMPx` 选 Mode（Standalone/Follower/PGA/Timer-controlled）、Power Mode、输入与增益。
两个外设的输入引脚必须配成 `GPIO_MODE_ANALOG`。

---

## 15. CORDIC / FMAC

### 概览

**CORDIC 常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_CORDIC_Init(&hcordic)` | 初始化 CORDIC 外设 |
| `HAL_CORDIC_Configure(&hcordic, &sConfig)` | 配功能与格式：Function / Precision / Scale / NbWrite / NbRead / InSize / OutSize |
| `HAL_CORDIC_Calculate(&hcordic, in, out, nb, timeout)` | 阻塞式批量计算（一次算 nb 组） |
| `HAL_CORDIC_CalculateZO(&hcordic, in, out, nb, timeout)` | **零开销版**：算完立刻读上一次结果，吞吐最高 |

**CORDIC 不常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_CORDIC_Calculate_IT()` / `HAL_CORDIC_Calculate_DMA(..., CORDIC_DMA_DIR_IN_OUT)` | 中断 / DMA 方式计算（方向可选 IN/OUT/IN_OUT） |
| `HAL_CORDIC_CalculateCpltCallback()` / `HAL_CORDIC_ErrorCallback()` | 计算完成 / 出错回调 |
| `HAL_CORDIC_IRQHandler(&hcordic)` | 中断入口 |
| `HAL_CORDIC_DeInit()` / `GetState()` / `GetError()` / `RegisterCallback()` | 诊断 |

**FMAC 常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_FMAC_Init(&hfmac)` | 初始化 FMAC 滤波器加速器 |
| `HAL_FMAC_FilterConfig(&hfmac, &sConfig)` | 配滤波器：类型（FIR/IIR）、系数、输入/输出缓冲、访问方式 |
| `HAL_FMAC_FilterStart(&hfmac, InputSize, OutputSize)` | 启动滤波运算 |
| `HAL_FMAC_PollFilterData(&hfmac, pOutput, timeout, &OutputSize)` | 阻塞读取输出数据 |

**FMAC 不常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_FMAC_AppendFilterData()` | 追加上输入数据（流式处理） |
| `HAL_FMAC_ConfigFilterOutputBuffer()` | 运行中重配输出缓冲 |
| `HAL_FMAC_FilterConfig_DMA()` / `HAL_FMAC_FilterPreload[_DMA]()` | DMA 方式配置 / 预载系数与数据 |
| `HAL_FMAC_FilterStop()`、`HAL_FMAC_IRQHandler()` | 停止 / 中断入口 |
| `HAL_FMAC_GetDataCallback()` / `HalfGetDataCallback()` / `OutputDataReadyCallback()` / `HalfOutputDataReadyCallback()` | 数据就绪回调（半满/全满） |
| `HAL_FMAC_FilterConfigCallback()` / `FilterPreloadCallback()` / `ErrorCallback()` | 配置完成 / 预载完成 / 出错回调 |

**关键选项速解**

- **CORDIC `Function`**：`COSINE` / `SINE` / `PHASE` / `MODULUS` / `ARCTANGENT` / `SQUAREROOT` /
  `NATURALLOG` / 双曲函数等——决定这次算什么。
- **CORDIC `Precision`**：迭代周期数（`1CYCLE` ~ `15CYCLES`），越多越准越慢。
- **CORDIC `Scale`**：输入/输出的缩放（定点归一化），做幅相/三角函数时最容易搞错的地方。
- **CORDIC `NbWrite` / `NbRead`**：一次计算要写几个 32 位、读几个 32 位（如 sin+cos 要读 2 个）。
- **CORDIC `InSize` / `OutSize`**：16 位还是 32 位数据宽度，决定吞吐（16 位可以一次算两路）。
- **FMAC `Filter`**：FIR（`FMAC_FUNCTION_FIR`）或 IIR（`FMAC_FUNCTION_IIR`）——决定系数含义。
- **FMAC `P` / `Q` / `R`**：P=向量长度/抽头数、Q=另一路长度、R=增益，按滤波器类型解释。
- **FMAC `Clip`**：超出 q1.15 范围时是饱和（`FMAC_CLIP_ENABLED`）还是回绕——音频/控制建议开饱和。
- **FMAC `InputAccess` / `OutputAccess`**：输入输出缓冲的搬运方式（Polling / IT / DMA / None）。


> 这两个是 G4 独有的硬件数学加速器，把三角函数、开方、滤波从 CPU 卸载下来，
> 常用于电机 FOC（Clark/Park、atan2、SVPWM 幅相）、数字电源环路、音频滤波。

### 15.1 CORDIC（三角函数/幅相/开方）
CubeMX：Function（cos/sin/atan/modulus/phase…）、Precision（迭代次数）、Scale、
Write/Read 数量。API：
```c
CORDIC_HandleTypeDef hcordic;
CORDIC_ConfigTypeDef sCordicConfig = {0};

hcordic.Instance = CORDIC;
if (HAL_CORDIC_Init(&hcordic) != HAL_OK) { Error_Handler(); }

sCordicConfig.Function = CORDIC_FUNCTION_SINE;
sCordicConfig.Precision = CORDIC_PRECISION_6CYCLES;
sCordicConfig.Scale     = CORDIC_SCALE_0;
sCordicConfig.NbWrite   = CORDIC_NBWRITE_1;
sCordicConfig.NbRead    = CORDIC_NBREAD_1;
sCordicConfig.InSize    = CORDIC_INSIZE_32BITS;
sCordicConfig.OutSize   = CORDIC_OUTSIZE_32BITS;
HAL_CORDIC_Configure(&hcordic, &sCordicConfig);

/* 阻塞计算：一次算 N 组 */
HAL_CORDIC_Calculate(&hcordic, (int32_t *)in, (int32_t *)out, N, 100);
/* 零开销版本：本次算完紧接着读下一次结果（流水线，最快） */
HAL_CORDIC_CalculateZO(&hcordic, in, out, N, 100);
/* 中断 / DMA */
HAL_CORDIC_Calculate_IT (&hcordic, in, out, N);
HAL_CORDIC_Calculate_DMA(&hcordic, in, out, N, CORDIC_DMA_DIR_IN_OUT);   /* 方向：DIR_IN / DIR_OUT / DIR_IN_OUT / DIR_NONE */
void HAL_CORDIC_CalculateCpltCallback(CORDIC_HandleTypeDef *hcordic) { }
void HAL_CORDIC_ErrorCallback(CORDIC_HandleTypeDef *hcordic) { }
void CORDIC_IRQHandler(void) { HAL_CORDIC_IRQHandler(&hcordic); }
```
> 注意：CORDIC 是定点运算，输入格式 Q1.31、输出 Q1.31（角度用弧度归一化），
> 做归一化和 `Scale` 设置是唯一的难点。

### 15.2 FMAC（有限脉冲响应/IIR 滤波加速器）
API 一览（`stm32g4xx_hal_fmac.h`）：
`HAL_FMAC_Init()` / `HAL_FMAC_DeInit()`、`HAL_FMAC_FilterConfig(&hfmac, &sConfig)`、
`HAL_FMAC_FilterConfig_DMA(&hfmac, &sConfig)`、`HAL_FMAC_AppendFilterData()`、
`HAL_FMAC_ConfigFilterOutputBuffer()`、`HAL_FMAC_FilterPreload[_DMA]()`、
`HAL_FMAC_FilterStart(&hfmac, InputSize, OutputSize)`、`HAL_FMAC_FilterStop()`、
`HAL_FMAC_PollFilterData(&hfmac, pOutput, Timeout, &OutputSize)`、`HAL_FMAC_GetState()`、
`HAL_FMAC_IRQHandler()`。
回调：`HAL_FMAC_GetDataCallback()`、`HAL_FMAC_HalfGetDataCallback()`、
`HAL_FMAC_OutputDataReadyCallback()`、`HAL_FMAC_HalfOutputDataReadyCallback()`、
`HAL_FMAC_FilterConfigCallback()`、`HAL_FMAC_FilterPreloadCallback()`、`HAL_FMAC_ErrorCallback()`。
```c
/* 最小骨架：配置系数与输入/输出缓冲，然后启动 */
HAL_FMAC_FilterStart(&hfmac, 64, 64);                       /* 输入 64 点、输出 64 点 */
HAL_FMAC_PollFilterData(&hfmac, out, 10, &out_size);        /* 阻塞取结果 */
```
> FMAC 结构体字段较多（`Filter`、`InputAccess`、`OutputAccess`、`CoefAccess`、
> `InputBaseAddress`、`CoefBaseAddress`、`OutputBaseAddress`、`InputBufferSize`、
> `CoefBufferSize`、`OutputBufferSize`、`pCoeffA/B`…），实际字段请以
> `Drivers/STM32G4xx_HAL_Driver/Inc/stm32g4xx_hal_fmac.h` 中 `FMAC_FilterConfigTypeDef` 为准，
> CubeMX 的 FMAC 配置页会把它们生成好。

### 完整工程骨架（CubeMX 生成 + 你手写）

以 **CORDIC 算 atan2/开方（电机 FOC）+ FMAC 做 FIR 滤波**为例：

```c
/* ============ Core/Src/cordic.c —— CubeMX 生成 ============ */
CORDIC_HandleTypeDef hcordic;
DMA_HandleTypeDef    hdma_cordic_in;
DMA_HandleTypeDef    hdma_cordic_out;

void MX_CORDIC_Init(void)
{
  hcordic.Instance = CORDIC;
  if (HAL_CORDIC_Init(&hcordic) != HAL_OK) { Error_Handler(); }
  /* 中断/DMA 相关由 CubeMX 按勾选生成 */
}

void HAL_CORDIC_MspInit(CORDIC_HandleTypeDef* hcordic)
{
  if (hcordic->Instance == CORDIC)
  {
    __HAL_RCC_CORDIC_CLK_ENABLE();
    HAL_NVIC_SetPriority(CORDIC_IRQn, 0, 0);
    HAL_NVIC_EnableIRQ(CORDIC_IRQn);
    /* DMA：hdma_cordic_in / hdma_cordic_out + __HAL_LINKDMA */
  }
}

/* ============ Core/Src/fmac.c —— CubeMX 生成 ============ */
FMAC_HandleTypeDef hfmac;

void MX_FMAC_Init(void)
{
  hfmac.Instance = FMAC;
  if (HAL_FMAC_Init(&hfmac) != HAL_OK) { Error_Handler(); }
}

/* ============ Core/Src/stm32g4xx_it.c —— CubeMX 生成 ============ */
void CORDIC_IRQHandler(void) { HAL_CORDIC_IRQHandler(&hcordic); }
void FMAC_IRQHandler(void)   { HAL_FMAC_IRQHandler(&hfmac); }
```

```c
/* ============ 你手写的部分 ============ */

/* ① CORDIC：配置一次，之后可以一直复用（切换功能时才需要重新 Configure）*/
CORDIC_ConfigTypeDef sCfg = {0};
void CORDIC_Setup_Atan2(void)
{
  sCfg.Function  = CORDIC_FUNCTION_PHASE;        /* 相位 = atan2(y,x) */
  sCfg.Precision = CORDIC_PRECISION_6CYCLES;
  sCfg.Scale     = CORDIC_SCALE_0;
  sCfg.NbWrite   = CORDIC_NBWRITE_2;             /* atan2 需要写 2 个数（y,x）*/
  sCfg.NbRead    = CORDIC_NBREAD_1;              /* 读 1 个结果（角度）*/
  sCfg.InSize    = CORDIC_INSIZE_32BITS;
  sCfg.OutSize   = CORDIC_OUTSIZE_32BITS;
  HAL_CORDIC_Configure(&hcordic, &sCfg);
}

/* ② 一次算一组（阻塞），输入输出都是 Q1.31 定点 */
int32_t in[2], out[1];
void Calc_Angle(int32_t i_alpha, int32_t i_beta, int32_t *angle)
{
  in[0] = i_alpha; in[1] = i_beta;              /* 注意写入顺序：y 在前 */
  HAL_CORDIC_Calculate(&hcordic, in, out, 1, 10);
  *angle = out[0];
}

/* ③ 批量 + 零开销（每个 PWM 周期算一批，吞吐最高）*/
HAL_CORDIC_CalculateZO(&hcordic, in_buf, out_buf, 16, 10);

/* ④ 换功能（如改算模长/开方）——重新 Configure 即可 */
sCfg.Function = CORDIC_FUNCTION_MODULUS;  sCfg.NbRead = CORDIC_NBREAD_1;
HAL_CORDIC_Configure(&hcordic, &sCfg);
sCfg.Function = CORDIC_FUNCTION_SQUAREROOT;  sCfg.NbWrite = CORDIC_NBWRITE_1;
HAL_CORDIC_Configure(&hcordic, &sCfg);

/* ⑤ FMAC：配 FIR 滤波器（系数 q1.15）+ 启动 + 取结果 */
#define TAPS   16
#define IN_LEN 64
int16_t coef_b[TAPS];
int16_t fmac_in[IN_LEN], fmac_out[IN_LEN];
FMAC_FilterConfigTypeDef fmacCfg = {0};

void FMAC_FIR_Init(void)
{
  /* coef_b 里放你自己算好的滤波器系数（q1.15：1.0 → 32767）*/
  fmacCfg.InputBaseAddress  = (uint32_t)fmac_in;
  fmacCfg.InputBufferSize   = IN_LEN;
  fmacCfg.InputThreshold    = FMAC_THRESHOLD_1;
  fmacCfg.OutputBaseAddress = (uint32_t)fmac_out;
  fmacCfg.OutputBufferSize  = IN_LEN;
  fmacCfg.OutputThreshold   = FMAC_THRESHOLD_1;
  fmacCfg.pCoeffA           = NULL;
  fmacCfg.CoeffASize        = 0;
  fmacCfg.pCoeffB           = coef_b;
  fmacCfg.CoeffBSize        = TAPS;
  fmacCfg.InputAccess       = FMAC_BUFFER_ACCESS_POLLING;
  fmacCfg.OutputAccess      = FMAC_BUFFER_ACCESS_POLLING;
  fmacCfg.Clip              = FMAC_CLIP_ENABLED;
  fmacCfg.Filter            = FMAC_FUNCTION_FIR;
  fmacCfg.P                 = TAPS;
  fmacCfg.Q                 = 0;
  fmacCfg.R                 = 0;
  HAL_FMAC_FilterConfig(&hfmac, &fmacCfg);
}

void FMAC_Run(void)
{
  uint32_t out_size = IN_LEN;
  HAL_FMAC_FilterStart(&hfmac, IN_LEN, IN_LEN);                 /* 输入/输出长度 */
  HAL_FMAC_PollFilterData(&hfmac, fmac_out, 10, &out_size);      /* 阻塞取结果 */
  HAL_FMAC_FilterStop(&hfmac);
}
```

**CubeMX 配置入口**：`Computing → CORDIC / FMAC` 使能即可（具体功能在代码里的 `CORDIC_Configure`
与 `HAL_FMAC_FilterConfig` 里设定）；需要中断/DMA 时在 NVIC 与 DMA Settings 里勾选。

---

## 16. CRC / RNG

### 概览

**CRC 常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_CRC_Init(&hcrc)` | 初始化：多项式、初值、输入/输出反转、数据格式 |
| `HAL_CRC_Calculate(&hcrc, (uint32_t*)buf, len)` | 从零开始算一次 CRC（会复位内部寄存器） |
| `HAL_CRC_Accumulate(&hcrc, (uint32_t*)buf, len)` | 累积计算（分块数据的后续块） |

**CRC 不常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_CRCEx_Polynomial_Set(&hcrc, poly, len)` | 运行期改多项式与长度 |
| `HAL_CRCEx_Input_Data_Reverse(&hcrc, mode)` | 输入数据按字节/半字/字位反转 |
| `HAL_CRCEx_Output_Data_Reverse(&hcrc, ENABLE)` | 输出结果位反转 |
| `HAL_CRC_DeInit()` / `HAL_CRC_GetState()` / `MspInit` / `MspDeInit` | 反初始化与状态 |

**RNG 常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_RNG_Init(&hrng)` | 初始化（**前提：RNG 有 48MHz 时钟**） |
| `HAL_RNG_GenerateRandomNumber(&hrng, &rnd32)` | 阻塞取一个 32 位随机数 |
| `HAL_RNG_GenerateRandomNumber_IT(&hrng)` | 中断方式取随机数 |
| `HAL_RNG_ReadyDataCallback(hrng, random32)` | 随机数就绪回调（配套 `_IT` 用） |
| `HAL_RNG_ErrorCallback(hrng)` | 出错回调（**种子错误在这里重试**） |
| `HAL_RNG_IRQHandler(&hrng)` | 中断入口 |

**RNG 不常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_RNG_ReadLastRandomNumber(&hrng)` | 读上次生成的随机数（不触发新生成） |
| `HAL_RNG_RegisterCallback()` / `RegisterReadyDataCallback()` | 注册式回调 |
| `HAL_RNG_DeInit()` / `GetState()` / `GetError()` | 诊断 |
| `__HAL_RNG_ENABLE/DISABLE`、`__HAL_RNG_GET_FLAG`、`__HAL_RNG_CLEAR_FLAG` | 直接控制与清标志 |

**关键选项速解**

- **CRC `DefaultPolynomialUse`**：用 ST 默认多项式（`DEFAULT_POLYNOMIAL_ENABLE`）或自定义
  （`DISABLE` + `GeneratingPolynomial` + `CRCLength`）——要与对端协议一致。
- **CRC `DefaultInitValueUse` / `InitValue`**：初始值，常见 0xFFFFFFFF 或 0x00000000。
- **CRC `InputDataInversionMode`**：输入按 BYTE/HALFWORD/WORD 位反转（很多协议要求反转）。
- **CRC `OutputDataInversionMode`**：输出再取反（结束异或值）。
- **CRC `InputDataFormat`**：`BYTES` / `HALFWORDS` / `WORDS`——**决定 `len` 的含义**，用错就算错。
- **RNG 唯一要点**：时钟必须是 48MHz（PLLQ 或 HSI48）；报种子错误（SEIS）时重初始化即可。


### 16.1 CRC（硬件校验，通信/Flash 校验常用）
CubeMX：**Default Polynomial State**（Enable=用默认多项式 / Disable=自定义）、
**CRC Length**、**Default Init Value**、**Input Data Format**（按字节/半字/字）、
Input/Output 反转。生成 `hcrc`。
```c
CRC_HandleTypeDef hcrc;
hcrc.Instance = CRC;
hcrc.Init.DefaultPolynomialUse    = DEFAULT_POLYNOMIAL_ENABLE;   /* 自定义则 DISABLE + GeneratingPolynomial */
hcrc.Init.DefaultInitValueUse     = DEFAULT_INIT_VALUE_ENABLE;
hcrc.Init.InputDataInversionMode  = CRC_INPUTDATA_INVERSION_NONE;
hcrc.Init.OutputDataInversionMode = CRC_OUTPUTDATA_INVERSION_DISABLE;
hcrc.InputDataFormat              = CRC_INPUTDATA_FORMAT_WORDS;  /* BYTES / HALFWORDS / WORDS */
if (HAL_CRC_Init(&hcrc) != HAL_OK) { Error_Handler(); }

uint32_t crc = HAL_CRC_Calculate(&hcrc, (uint32_t *)buf, len);   /* 重新计算（会复位 CRC） */
crc = HAL_CRC_Accumulate(&hcrc, (uint32_t *)buf2, len2);         /* 累积计算（分块） */
/* 扩展配置 */
HAL_CRCEx_Polynomial_Set(&hcrc, poly, CRC_POLYLENGTH_32B);
HAL_CRCEx_Input_Data_Reverse (&hcrc, CRC_INPUTDATA_INVERSION_BYTE);
HAL_CRCEx_Output_Data_Reverse(&hcrc, ENABLE);
```
> 坑：`HAL_CRC_Calculate()` 的 `len` 是**按字（32 位）**的个数（当 `InputDataFormat = WORDS`），
> 数据长度不是 4 的倍数时要么补 0，要么改用 `CRC_INPUTDATA_FORMAT_BYTES`。

### 16.2 RNG（硬件随机数）
CubeMX：只需要使能 RNG 并给它 48MHz 时钟源（Clock Configuration 里 RNG 时钟选 PLL48/HSI48）。
```c
RNG_HandleTypeDef hrng;
hrng.Instance = RNG;
if (HAL_RNG_Init(&hrng) != HAL_OK) { Error_Handler(); }

uint32_t rnd;
if (HAL_RNG_GenerateRandomNumber(&hrng, &rnd) == HAL_OK) { /* 得到一个 32 位随机数 */ }
HAL_RNG_GenerateRandomNumber_IT(&hrng);          /* 中断版 */
uint32_t last = HAL_RNG_ReadLastRandomNumber(&hrng);
void RNG_IRQHandler(void) { HAL_RNG_IRQHandler(&hrng); }
void HAL_RNG_ReadyDataCallback(RNG_HandleTypeDef *hrng, uint32_t random32) { }
void HAL_RNG_ErrorCallback(RNG_HandleTypeDef *hrng) { }
/* 宏 */
__HAL_RNG_ENABLE(&hrng); __HAL_RNG_DISABLE(&hrng);
__HAL_RNG_GET_FLAG(&hrng, RNG_FLAG_DRDY); __HAL_RNG_CLEAR_FLAG(&hrng, RNG_FLAG_SEIS);
```
> 常见坑：时钟没配好会一直报 **种子错误（SEIS）**，在 `HAL_RNG_ErrorCallback` 里
> 调 `HAL_RNG_Init(&hrng)` 重试即可；另外启用 RNG 时 `HAL_RCCEx_PeriphCLKConfig()` 必须给 48MHz 时钟。

### 完整工程骨架（CubeMX 生成 + 你手写）

以 **CRC 校验串口固件包 + RNG 生成随机数**为例：

```c
/* ============ Core/Src/crc.c —— CubeMX 生成 ============ */
CRC_HandleTypeDef hcrc;

void MX_CRC_Init(void)
{
  hcrc.Instance = CRC;
  hcrc.Init.DefaultPolynomialUse    = DEFAULT_POLYNOMIAL_ENABLE;
  hcrc.Init.DefaultInitValueUse     = DEFAULT_INIT_VALUE_ENABLE;
  hcrc.Init.InputDataInversionMode  = CRC_INPUTDATA_INVERSION_NONE;
  hcrc.Init.OutputDataInversionMode = CRC_OUTPUTDATA_INVERSION_DISABLE;
  hcrc.InputDataFormat              = CRC_INPUTDATA_FORMAT_BYTES;   /* 按字节算最方便 */
  if (HAL_CRC_Init(&hcrc) != HAL_OK) { Error_Handler(); }
}

/* ============ Core/Src/rng.c —— CubeMX 生成 ============ */
RNG_HandleTypeDef hrng;

void MX_RNG_Init(void)
{
  hrng.Instance = RNG;
  if (HAL_RNG_Init(&hrng) != HAL_OK) { Error_Handler(); }
}

/* ============ Core/Src/stm32g4xx_it.c —— CubeMX 生成 ============ */
void RNG_IRQHandler(void) { HAL_RNG_IRQHandler(&hrng); }
```

```c
/* ============ 你手写的部分 ============ */

/* ① CRC：算一段数据的校验值（按字节格式时 len = 字节数）*/
uint32_t crc = HAL_CRC_Calculate(&hcrc, (uint32_t *)packet, packet_len);
/* 分块累加（比如先算包头再算负载）*/
uint32_t crc2 = HAL_CRC_Accumulate(&hcrc, (uint32_t *)payload, payload_len);

/* ② 与协议对齐时可能要反转（多数 MCU 网络协议要求）*/
HAL_CRCEx_Input_Data_Reverse(&hcrc, CRC_INPUTDATA_INVERSION_BYTE);
HAL_CRCEx_Output_Data_Reverse(&hcrc, ENABLE);
/* 或运行期换多项式 */
HAL_CRCEx_Polynomial_Set(&hcrc, 0x04C11DB7, CRC_POLYLENGTH_32B);

/* ③ RNG：取随机数（阻塞式，内部会等 DRDY）*/
uint32_t rnd = 0;
if (HAL_RNG_GenerateRandomNumber(&hrng, &rnd) != HAL_OK)
{
  Error_Handler();                       /* 常见：被中断打断 → 调用 HAL_RNG_Init 重试 */
}

/* ④ RNG：中断方式 */
HAL_RNG_GenerateRandomNumber_IT(&hrng);
void HAL_RNG_ReadyDataCallback(RNG_HandleTypeDef *hrng, uint32_t random32)
{
  g_seed = random32;                     /* 随机数到了 */
}

/* ⑤ RNG 种子错误（SEIS）恢复：在错误回调里重新初始化，别死等 */
void HAL_RNG_ErrorCallback(RNG_HandleTypeDef *hrng)
{
  if (hrng->ErrorCode == HAL_RNG_ERROR_SEED)
  {
    HAL_RNG_Init(&hrng);
  }
}

/* ⑥ 想连续生成一串随机数 */
uint32_t key[4];
for (int i = 0; i < 4; i++) { HAL_RNG_GenerateRandomNumber(&hrng, &key[i]); }
```

**CubeMX 配置入口**：`Computing → CRC` 选默认/自定义多项式、初值、输入输出反转与数据格式；
`Computing → RNG` 使能即可……**但一定要在 Clock Configuration 里给 RNG 配 48MHz 时钟源**
（PLLQ 或 HSI48），否则 `HAL_RNG_Init()` 会失败或一直报种子错误。

---

## 17. RTC 实时时钟

### 概览

**常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_RTC_Init(&hrtc)` | 初始化：小时制、异步/同步分频（凑出 1Hz）、输出 |
| `HAL_RTC_SetTime(&hrtc, &sTime, RTC_FORMAT_BIN)` / `HAL_RTC_GetTime(...)` | 写 / 读时分秒（含亚秒） |
| `HAL_RTC_SetDate(&hrtc, &sDate, RTC_FORMAT_BIN)` / `HAL_RTC_GetDate(...)` | 写 / 读年月日星期 |
| `HAL_RTC_SetAlarm_IT(&hrtc, &sAlarm, RTC_ALARM_A)` | 设定闹钟并开中断（A 或 B） |
| `HAL_RTC_AlarmAEventCallback()` / `HAL_RTCEx_AlarmBEventCallback()` | 闹钟到点回调 |
| `HAL_RTCEx_SetWakeUpTimer_IT(&hrtc, cnt, clk)` | 周期性唤醒（Stop 模式下也能唤醒） |
| `HAL_RTCEx_WakeUpTimerEventCallback()` | 唤醒定时器回调 |
| `HAL_RTC_AlarmIRQHandler()` / `HAL_RTCEx_WakeUpTimerIRQHandler()` | 闹钟 / 唤醒中断入口 |
| `HAL_RTCEx_BKUPWrite()` / `HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DRx, val)` | 备份寄存器读写（掉电不丢，存标志位好用） |

**较常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_RTC_DeactivateAlarm(&hrtc, RTC_ALARM_A)` / `HAL_RTC_GetAlarm()` | 关闭 / 读取闹钟配置 |
| `HAL_RTCEx_SetTimeStamp_IT()` / `GetTimeStamp()` / `TimeStampEventCallback()` | 记录事件发生的精确时刻 |
| `HAL_RTC_WaitForSynchro(&hrtc)` | 等影子寄存器同步（切换时钟/低功耗后用） |
| `HAL_RTCEx_SetSmoothCalib()` | 走时微调（晶振偏差补偿） |
| `HAL_RTCEx_SetCalibrationOutPut()` / `DeactivateCalibrationOutPut()` | 输出 512Hz/1Hz 校准信号（示波器量） |

**不常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_RTC_PollForAlarmAEvent()` / `HAL_RTCEx_PollForAlarmBEvent()` | 阻塞等闹钟（不用中断时） |
| `HAL_RTCEx_SetTamper[_IT]()` / `Tamper1~3EventCallback()` / `DeactivateTamper()` / `TamperIRQHandler()` | 防拆引脚检测 |
| `HAL_RTCEx_SetInternalTamper[_IT]()` + `InternalTamper1~7EventCallback()` | 内部防拆源（温度/电压/时钟异常） |
| `HAL_RTCEx_SetSynchroShift()` | 同步移位（微调时钟，不改硬件分频） |
| `HAL_RTCEx_EnableBypassShadow()` / `DisableBypassShadow()` | 旁路影子寄存器（想直接读当前值时） |
| `HAL_RTC_DeInit()` / `GetState()`、`HAL_RTCEx_DeactivateTimeStamp()` | 诊断与关闭功能 |

**关键选项速解**

- **`HourFormat`**：12 或 24 小时制。
- **`AsynchPrediv` / `SynchPrediv`**：把 RTC 时钟分频成 1Hz，例如 32768Hz → 127 / 255。
- **`OutPut` / `OutPutRemap` / `OutPutPolarity` / `OutPutType`**：报警/唤醒/校准信号从哪个引脚、什么极性、推挽还是开漏输出。
- **`AlarmMask`**：哪些字段参与比较（不参与的位置 1），可做"每分钟/每小时/每周"闹钟。
- **`AlarmSubSecondMask`**：亚秒级闹钟精度。
- **`AlarmDateWeekDaySel`**：闹钟匹配的是"日期"还是"星期"。
- **`WakeUpClock`**：唤醒定时器的时钟分频档（如 `RTC_WAKEUPCLOCK_RTCCLK_DIV16`），配合 `cnt` 决定周期。
- **读时钟顺序**：必须先 `HAL_RTC_GetTime()` 再 `HAL_RTC_GetDate()`（读时间会锁影子寄存器）。
- **时钟源**：LSE 32.768kHz 最准；LSE 不起振可用 LSI（精度差）。


### 17.1 CubeMX 配置要点
**Clock Source**（LSE 最准；LSI 精度差；HSE/32 可替代）、**Calendar**（BCD/二进制、24/12 小时制、
异步/同步分频）、**Alarm A / Alarm B**、**WakeUp Timer**（自动唤醒周期）、**Timestamp**、
**Tamper**（防拆）、**Output/AutoWakeUp 输出**、NVIC 勾 `RTC alarm / RTC wakeup / TAMP`；
时钟源在 Clock Configuration 里选（RTC 时钟 = LSE 32768Hz 最佳）。

### 17.2 初始化与读写时间日期
```c
RTC_HandleTypeDef hrtc;
RTC_TimeTypeDef  sTime = {0};
RTC_DateTypeDef  sDate = {0};

hrtc.Instance = RTC;
hrtc.Init.HourFormat     = RTC_HOURFORMAT_24;
hrtc.Init.AsynchPrediv   = 127;      /* (127+1)*(255+1) = 32768 → 1Hz */
hrtc.Init.SynchPrediv    = 255;
hrtc.Init.OutPut         = RTC_OUTPUT_DISABLE;
hrtc.Init.OutPutRemap    = RTC_OUTPUT_REMAP_NONE;
hrtc.Init.OutPutPolarity = RTC_OUTPUT_POLARITY_HIGH;
hrtc.Init.OutPutType     = RTC_OUTPUT_TYPE_OPENDRAIN;
if (HAL_RTC_Init(&hrtc) != HAL_OK) { Error_Handler(); }

/* 设置时间/日期 */
sTime.Hours = 12; sTime.Minutes = 30; sTime.Seconds = 0; sTime.DayLightSaving = RTC_DAYLIGHTSAVING_NONE;
sTime.StoreOperation = RTC_STOREOPERATION_RESET;
HAL_RTC_SetTime(&hrtc, &sTime, RTC_FORMAT_BIN);
sDate.WeekDay = RTC_WEEKDAY_MONDAY; sDate.Month = RTC_MONTH_OCTOBER;
sDate.Date = 16; sDate.Year = 26;
HAL_RTC_SetDate(&hrtc, &sDate, RTC_FORMAT_BIN);

/* 读取：注意顺序！先 GetTime（读时会锁影子寄存器）再 GetDate */
HAL_RTC_GetTime(&hrtc, &sTime, RTC_FORMAT_BIN);
HAL_RTC_GetDate(&hrtc, &sDate, RTC_FORMAT_BIN);
/* 亚秒：sTime.SubSeconds / SecondFraction 可算毫秒 */
```

### 17.3 闹钟 / 唤醒 / 时间戳 / 防拆（全部靠中断或轮询）

```c
/* ① 闹钟 A（每小时 30 分 0 秒响） */
RTC_AlarmTypeDef sAlarm = {0};
sAlarm.AlarmTime.Hours = 0x30; ... /* 见生成的字段 */
sAlarm.AlarmMask       = RTC_ALARMMASK_DATEWEEKDAY | RTC_ALARMMASK_HOURS;
sAlarm.AlarmSubSecondMask = RTC_ALARMSUBSECONDMASK_ALL;
sAlarm.AlarmDateWeekDaySel = RTC_ALARMDATEWEEKDAYSEL_DATE;
sAlarm.AlarmDateWeekDay    = 0x1;
sAlarm.Alarm              = RTC_ALARM_A;
HAL_RTC_SetAlarm_IT(&hrtc, &sAlarm, RTC_ALARM_A);
void HAL_RTC_AlarmAEventCallback(RTC_HandleTypeDef *hrtc) { /* 闹钟 A 到点 */ }
/* 闹钟 B 同法：HAL_RTC_SetAlarm_IT(..., RTC_ALARM_B) + HAL_RTCEx_AlarmBEventCallback() */
HAL_RTC_DeactivateAlarm(&hrtc, RTC_ALARM_A);            /* 关闭闹钟 */

/* ② 周期性唤醒（Stop 模式下也能唤醒） */
HAL_RTCEx_SetWakeUpTimer_IT(&hrtc, 0x2000, RTC_WAKEUPCLOCK_RTCCLK_DIV16);
void HAL_RTCEx_WakeUpTimerEventCallback(RTC_HandleTypeDef *hrtc) { }
HAL_RTCEx_DeactivateWakeUpTimer(&hrtc);
HAL_RTCEx_GetWakeUpTimer(&hrtc);

/* ③ 时间戳（记录事件发生的时刻） */
HAL_RTCEx_SetTimeStamp_IT(&hrtc, RTC_TIMESTAMPEDGE_RISING, RTC_TIMESTAMPPIN_DEFAULT);
void HAL_RTCEx_TimeStampEventCallback(RTC_HandleTypeDef *hrtc) {
  RTC_TimeTypeDef t; RTC_DateTypeDef d;
  HAL_RTCEx_GetTimeStamp(hrtc, &t, &d, RTC_FORMAT_BIN);
}

/* ④ 防拆 Tamper */
HAL_RTCEx_SetTamper_IT(&hrtc, &sTamper);
void HAL_RTCEx_Tamper1EventCallback(RTC_HandleTypeDef *hrtc) { }

/* ⑤ 备份寄存器（VBAT 保存，复位/掉电不丢） */
HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR1, 0xA5A5);
uint32_t v = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR1);

/* 中断入口 */
void RTC_Alarm_IRQHandler (void) { HAL_RTC_AlarmIRQHandler(&hrtc); }
void RTC_WKUP_IRQHandler  (void) { HAL_RTCEx_WakeUpTimerIRQHandler(&hrtc); }
void TAMP_STAMP_IRQHandler(void) { HAL_RTCEx_TamperIRQHandler(&hrtc); }
```
**其它**：`HAL_RTC_WaitForSynchro(&hrtc)`、`HAL_RTCEx_SetSmoothCalib()`（走时微调）、
`HAL_RTCEx_SetCalibrationOutPut()`（输出 512Hz/1Hz 校准）、`HAL_RTC_DST_Add1Hour()`（夏令时）。
**坑**：① 必须先 `HAL_RTC_GetTime()` 再 `HAL_RTC_GetDate()`；② LSE 起振失败会卡在
`HAL_RCC_OscConfig()`，可把 `RCC_OscInitStruct.LSEState` 改成 LSI 兜底；
③ `HAL_RTC_Init()` 会做一次“时钟同步”等待，超时说明 RTC 时钟没配好；
④ LSE 只能由 RTC/备份域引脚（OSC32_IN/OUT）提供，**不要**在 CubeMX 里把这两个引脚配成 GPIO。

### 完整工程骨架（CubeMX 生成 + 你手写）

以 **RTC 走时 + 每天定时闹钟 + 周期唤醒（低功耗）**为例：

```c
/* ============ Core/Src/rtc.c —— CubeMX 生成 ============ */
RTC_HandleTypeDef hrtc;

void MX_RTC_Init(void)
{
  RTC_TimeTypeDef sTime = {0};
  RTC_DateTypeDef sDate = {0};
  RTC_AlarmTypeDef sAlarm = {0};

  hrtc.Instance = RTC;
  hrtc.Init.HourFormat     = RTC_HOURFORMAT_24;
  hrtc.Init.AsynchPrediv   = 127;                   /* (127+1)*(255+1) = 32768 → 1Hz */
  hrtc.Init.SynchPrediv    = 255;
  hrtc.Init.OutPut         = RTC_OUTPUT_DISABLE;
  hrtc.Init.OutPutRemap    = RTC_OUTPUT_REMAP_NONE;
  hrtc.Init.OutPutPolarity = RTC_OUTPUT_POLARITY_HIGH;
  hrtc.Init.OutPutType     = RTC_OUTPUT_TYPE_OPENDRAIN;
  if (HAL_RTC_Init(&hrtc) != HAL_OK) { Error_Handler(); }

  /* CubeMX 里如果填了初始时间/日期，会生成下面这段（只在首次配置时执行）*/
  sTime.Hours = 0; sTime.Minutes = 0; sTime.Seconds = 0;
  sTime.DayLightSaving = RTC_DAYLIGHTSAVING_NONE;
  sTime.StoreOperation = RTC_STOREOPERATION_RESET;
  HAL_RTC_SetTime(&hrtc, &sTime, RTC_FORMAT_BIN);
  sDate.WeekDay = RTC_WEEKDAY_MONDAY; sDate.Month = RTC_MONTH_JANUARY;
  sDate.Date = 1; sDate.Year = 26;
  HAL_RTC_SetDate(&hrtc, &sDate, RTC_FORMAT_BIN);

  /* 闹钟（CubeMX 勾了 Alarm A 才有）*/
  sAlarm.AlarmTime.Hours = 8; sAlarm.AlarmTime.Minutes = 0; sAlarm.AlarmTime.Seconds = 0;
  sAlarm.AlarmMask          = RTC_ALARMMASK_DATEWEEKDAY;   /* 每天 8:00 响 */
  sAlarm.AlarmSubSecondMask = RTC_ALARMSUBSECONDMASK_ALL;
  sAlarm.AlarmDateWeekDaySel = RTC_ALARMDATEWEEKDAYSEL_DATE;
  sAlarm.AlarmDateWeekDay   = 1;
  sAlarm.Alarm              = RTC_ALARM_A;
  HAL_RTC_SetAlarm_IT(&hrtc, &sAlarm, RTC_ALARM_A);
}

void HAL_RTC_MspInit(RTC_HandleTypeDef* hrtc)
{
  RCC_PeriphCLKInitTypeDef PeriphClkInit = {0};
  if (hrtc->Instance == RTC)
  {
    PeriphClkInit.PeriphClockSelection = RCC_PERIPHCLK_RTC;
    PeriphClkInit.RTCClockSelection    = RCC_RTCCLKSOURCE_LSE;    /* LSE 最准 */
    HAL_RCCEx_PeriphCLKConfig(&PeriphClkInit);
    __HAL_RCC_RTC_ENABLE();
    HAL_NVIC_SetPriority(RTC_Alarm_IRQn, 0, 0);
    HAL_NVIC_EnableIRQ(RTC_Alarm_IRQn);
    HAL_NVIC_SetPriority(RTC_WKUP_IRQn, 0, 0);
    HAL_NVIC_EnableIRQ(RTC_WKUP_IRQn);
  }
}

/* ============ Core/Src/stm32g4xx_it.c —— CubeMX 生成 ============ */
void RTC_Alarm_IRQHandler(void) { HAL_RTC_AlarmIRQHandler(&hrtc); }
void RTC_WKUP_IRQHandler(void)  { HAL_RTCEx_WakeUpTimerIRQHandler(&hrtc); }
```

```c
/* ============ 你手写的部分 ============ */

/* ① 上电先判断是不是第一次配置（用备份寄存器存标志，掉电不丢）*/
if (HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR1) != 0xA55A)
{
  RTC_TimeTypeDef t = {.Hours = 12, .Minutes = 0, .Seconds = 0,
                       .DayLightSaving = RTC_DAYLIGHTSAVING_NONE,
                       .StoreOperation = RTC_STOREOPERATION_RESET};
  RTC_DateTypeDef d = {.WeekDay = RTC_WEEKDAY_MONDAY, .Month = RTC_MONTH_OCTOBER,
                       .Date = 16, .Year = 26};
  HAL_RTC_SetTime(&hrtc, &t, RTC_FORMAT_BIN);
  HAL_RTC_SetDate(&hrtc, &d, RTC_FORMAT_BIN);
  HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR1, 0xA55A);      /* 标记已配置 */
}

/* ② 读时间：必须"先时间后日期"（读时间会锁住影子寄存器）*/
RTC_TimeTypeDef now_t;  RTC_DateTypeDef now_d;
HAL_RTC_GetTime(&hrtc, &now_t, RTC_FORMAT_BIN);
HAL_RTC_GetDate(&hrtc, &now_d, RTC_FORMAT_BIN);
printf("20%02d-%02d-%02d %02d:%02d:%02d\r\n",
       now_d.Year, now_d.Month, now_d.Date, now_t.Hours, now_t.Minutes, now_t.Seconds);

/* ③ 闹钟回调（闹钟在 MX_RTC_Init 里已经设好并开中断）*/
void HAL_RTC_AlarmAEventCallback(RTC_HandleTypeDef *hrtc)
{
  /* 到点了：做事前先清标志由 HAL 完成；这里只处理业务 */
}

/* ④ 周期性唤醒（比如每 1s 醒一次做采样，其他时间睡）*/
HAL_RTCEx_SetWakeUpTimer_IT(&hrtc, 2047, RTC_WAKEUPCLOCK_RTCCLK_DIV16);
void HAL_RTCEx_WakeUpTimerEventCallback(RTC_HandleTypeDef *hrtc)
{
  g_tick_1s = 1;                       /* 置标志，主循环处理 */
}

/* ⑤ 低功耗主循环：Stop + RTC 唤醒（唤醒后必须重配时钟）*/
while (1)
{
  HAL_PWR_EnterSTOPMode(PWR_LOWPOWERREGULATOR_ON, PWR_STOPENTRY_WFI);
  SystemClock_Config();
  if (g_tick_1s) { g_tick_1s = 0; DoSampling(); }
}

/* ⑥ 记录事件发生时刻（时间戳）*/
void HAL_RTCEx_TimeStampEventCallback(RTC_HandleTypeDef *hrtc)
{
  RTC_TimeTypeDef t; RTC_DateTypeDef d;
  HAL_RTCEx_GetTimeStamp(hrtc, &t, &d, RTC_FORMAT_BIN);
}
```

**CubeMX 配置入口**：`Timers → RTC` 勾 `Activate Clock Source` 与 `Activate Calendar`，
在下方 `Alarm A/B`、`WakeUp`、`Timestamp`、`Tamper` 页分别使能；NVIC 里勾 `RTC alarm`、
`RTC wakeup`、`TAMP_STAMP`；时钟在 Clock Configuration 里选 LSE。

---

## 18. IWDG / WWDG 看门狗

### 概览

**IWDG 常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_IWDG_Init(&hiwdg)` | 初始化（Prescaler + Reload 决定超时时间）；**一旦启动无法停止** |
| `HAL_IWDG_Refresh(&hiwdg)` | 喂狗（必须在超时前周期性调用） |
| `__HAL_IWDG_START(&hiwdg)` / `__HAL_IWDG_RELOAD_COUNTER(&hiwdg)` | 直接启动 / 重装计数（LL 风格） |
| `__HAL_IWDG_ENABLE_WRITE_ACCESS()` / `DISABLE_WRITE_ACCESS()` | 打开 / 关闭配置写保护 |
| `__HAL_IWDG_GET_FLAG(&hiwdg, IWDG_FLAG_PVU)` | 查寄存器更新状态 |

**WWDG 常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_WWDG_Init(&hwwdg)` | 初始化：Prescaler / Window / Counter / EWI 模式 |
| `HAL_WWDG_Refresh(&hwwdg, counter)` | 喂狗（值必须落在窗口内，否则立即复位） |
| `HAL_WWDG_EarlyWakeupCallback(&hwwdg)` | 早期唤醒中断：最后一次喂狗机会 |
| `HAL_WWDG_IRQHandler(&hwwdg)` | 中断入口（`WWDG_IRQHandler` 里调用） |
| `HAL_WWDG_MspInit()` | 底层：开时钟 + 使能 NVIC |

**不常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_IWDG_GetState()` / `HAL_WWDG_GetState()` | 查状态 |
| `HAL_WWDG_RegisterCallback()` / `UnRegisterCallback()` | 注册式回调 |
| `__HAL_WWDG_ENABLE/DISABLE`、`__HAL_WWDG_ENABLE_IT(DISABLE_IT)`、`__HAL_WWDG_GET_FLAG/CLEAR_FLAG` | 直接控制与标志操作 |

**关键选项速解**

- **IWDG `Prescaler`**：4/8/16/…/256 分频；**IWDG `Reload`**：12 位重装值；
  超时 ≈ `(4 × 2^Prescaler × Reload) / LSI(≈32kHz)`。
- **WWDG `Prescaler`**：1/2/4/8；**`Counter`**：喂狗写入的计数值（0x40~0x7F）；
  **`Window`**：允许喂狗的上限，计数值必须已降到 Window 以下才能喂。
- **`EWIMode`**：开启"早期唤醒中断"，在计数器还没到 0x3F 前给你一次中断机会。
- **两者区别**：IWDG 用**独立 LSI 时钟**，主时钟挂了也能复位（最可靠）；
  WWDG 用 **PCLK1**，能同时监控"程序跑飞"和"执行太快/太慢"（喂早也复位）。
- **调试注意**：IWDG 启动后停在断点会被复位，可用 DBGMCU 冻结（`__HAL_DBGMCU_FREEZE_IWDG()`）。


### 18.1 IWDG 独立看门狗（LSI 驱动，独立于主时钟）
CubeMX：勾 `IWDG`，设 **Prescaler** 和 **Reload**（`超时 = (4 × 2^Prescaler × Reload) / LSI(≈32kHz)`）。
```c
IWDG_HandleTypeDef hiwdg;
hiwdg.Instance       = IWDG;
hiwdg.Init.Prescaler = IWDG_PRESCALER_64;
hiwdg.Init.Reload    = 4095;                 /* 约 8 秒超时 */
if (HAL_IWDG_Init(&hiwdg) != HAL_OK) { Error_Handler(); }

HAL_IWDG_Refresh(&hiwdg);                    /* 喂狗：必须在超时前周期性调用 */
/* 宏 */
__HAL_IWDG_START(&hiwdg);   __HAL_IWDG_RELOAD_COUNTER(&hiwdg);
__HAL_IWDG_ENABLE_WRITE_ACCESS(&hiwdg); __HAL_IWDG_DISABLE_WRITE_ACCESS(&hiwdg);
__HAL_IWDG_GET_FLAG(&hiwdg, IWDG_FLAG_PVU);
```
> IWDG 一旦启动就**不能停**（只能复位）；调试时停在断点会触发复位，注意在 Debug 里冻结 IWDG
> （`DBGMCU_APB1FZR1_DBG_IWDG_STOP`）或调试期先不启动。

### 18.2 WWDG 窗口看门狗（喂早了也会复位）
CubeMX：勾 `WWDG`，设 **Prescaler**、**Window value**、**Counter value**、**EWI Mode**、NVIC。
```c
WWDG_HandleTypeDef hwwdg;
hwwdg.Instance       = WWDG;
hwwdg.Init.Prescaler = WWDG_PRESCALER_8;
hwwdg.Init.Window    = 0x50;                 /* 计数器必须降到 Window 以下才能喂 */
hwwdg.Init.Counter   = 0x7F;
hwwdg.Init.EWIMode   = WWDG_EWI_ENABLE;      /* 早期唤醒中断 */
if (HAL_WWDG_Init(&hwwdg) != HAL_OK) { Error_Handler(); }

HAL_WWDG_Refresh(&hwwdg, counter);           /* 喂狗，counter ∈ 0x40..0x7F 且 ≤ Window */
void WWDG_IRQHandler(void) { HAL_WWDG_IRQHandler(&hwwdg); }
void HAL_WWDG_EarlyWakeupCallback(WWDG_HandleTypeDef *hwwdg) { /* 即将溢出，最后机会喂狗 */ }
/* 宏 */
__HAL_WWDG_ENABLE(&hwwdg); __HAL_WWDG_ENABLE_IT(&hwwdg, WWDG_IT_EWI);
__HAL_WWDG_GET_FLAG(&hwwdg, WWDG_FLAG_EWIF); __HAL_WWDG_CLEAR_FLAG(&hwwdg, WWDG_FLAG_EWIF);
```
> 区别记忆：**IWDG 超时未喂狗才复位；WWDG 喂太早/太晚都复位**（喂狗必须在窗口内）。
> WWDG 时钟来自 PCLK1，可用来监控程序跑飞或任务卡死。

### 完整工程骨架（CubeMX 生成 + 你手写）

以 **IWDG 8 秒超时 + WWDG 窗口喂狗（带早期唤醒中断）**为例：

```c
/* ============ Core/Src/iwdg.c —— CubeMX 生成 ============ */
IWDG_HandleTypeDef hiwdg;

void MX_IWDG_Init(void)
{
  hiwdg.Instance       = IWDG;
  hiwdg.Init.Prescaler = IWDG_PRESCALER_64;
  hiwdg.Init.Reload    = 4095;          /* 超时 ≈ 4*64*4096/32kHz ≈ 8s */
  if (HAL_IWDG_Init(&hiwdg) != HAL_OK) { Error_Handler(); }
  /* 注意：HAL_IWDG_Init() 一执行，看门狗就开始跑了 */
}

/* ============ Core/Src/wwdg.c —— CubeMX 生成 ============ */
WWDG_HandleTypeDef hwwdg;

void MX_WWDG_Init(void)
{
  hwwdg.Instance       = WWDG;
  hwwdg.Init.Prescaler = WWDG_PRESCALER_8;
  hwwdg.Init.Window    = 0x50;          /* 只有计数值 < 0x50 时喂狗才合法 */
  hwwdg.Init.Counter   = 0x7F;
  hwwdg.Init.EWIMode   = WWDG_EWI_ENABLE;
  if (HAL_WWDG_Init(&hwwdg) != HAL_OK) { Error_Handler(); }
}

void HAL_WWDG_MspInit(WWDG_HandleTypeDef* hwwdg)
{
  if (hwwdg->Instance == WWDG)
  {
    __HAL_RCC_WWDG_CLK_ENABLE();
    HAL_NVIC_SetPriority(WWDG_IRQn, 0, 0);
    HAL_NVIC_EnableIRQ(WWDG_IRQn);
  }
}

/* ============ Core/Src/stm32g4xx_it.c —— CubeMX 生成 ============ */
void WWDG_IRQHandler(void) { HAL_WWDG_IRQHandler(&hwwdg); }
```

```c
/* ============ 你手写的部分 ============ */

/* ① 主循环里喂狗（放在"所有任务都跑完"的位置，才能真正检测卡死）*/
while (1)
{
  Task1_Run();
  Task2_Run();
  Task3_Run();

  HAL_IWDG_Refresh(&hiwdg);              /* 喂 IWDG */

  /* WWDG 要等计数值降入窗口再喂，所以放在主循环末尾、周期可预测的位置 */
  HAL_WWDG_Refresh(&hwwdg, 0x7F);
}

/* ② WWDG 早期唤醒中断：最后的救命机会（计数器快到 0x3F）*/
void HAL_WWDG_EarlyWakeupCallback(WWDG_HandleTypeDef *hwwdg)
{
  /* 例：在这里记录现场 / 关掉危险输出 / 快速喂狗 */
  HAL_WWDG_Refresh(hwwdg, 0x7F);
}

/* ③ 不想用 WWDG 中断时：用宏关闭中断使能 */
// __HAL_WWDG_DISABLE_IT(&hwwdg, WWDG_IT_EWI);

/* ④ 调试期临时冻结看门狗（否则打断点必复位）*/
__HAL_DBGMCU_FREEZE_IWDG();
__HAL_DBGMCU_FREEZE_WWDG();

/* ⑤ 若在中断里也想喂狗（注意：中断优先级要够高，且不能喂在卡死路径上）*/
// HAL_IWDG_Refresh(&hiwdg);
```

**CubeMX 配置入口**：`System Core → IWDG` 勾 `Activated` 并设 Prescaler/Reload；
`System Core → WWDG` 勾 `Activated`，设 Prescaler/Window/Counter、使能 EWI 与 NVIC。
**上电后 IWDG 立即生效**，所以如果程序里有长时间的初始化或等待，记得先喂几次或把超时设长些。

---

## 19. FDCAN（CAN-FD）

### 概览

**常用 API（收发一帧的最小集合）**

| API | 一句话作用 |
|---|---|
| `HAL_FDCAN_Init(&hfdcan1)` | 初始化：帧格式、模式、位时序、FIFO 深度 |
| `HAL_FDCAN_ConfigFilter(&hfdcan1, &sFilterConfig)` | **配过滤器——不配就一帧都收不到** |
| `HAL_FDCAN_ConfigGlobalFilter()` | 未被过滤器匹配的帧怎么处理（接收/拒绝） |
| `HAL_FDCAN_ConfigInterruptLines()` | 把中断组分配到 IT0 / IT1 两条中断线 |
| `HAL_FDCAN_ActivateNotification(&hfdcan1, IT, 0)` | 打开指定中断源（收帧、错误…） |
| `HAL_FDCAN_Start(&hfdcan1)` / `HAL_FDCAN_Stop()` | 进入 / 退出正常通信 |
| `HAL_FDCAN_AddMessageToTxFifoQ(&hfdcan1, &TxHeader, data)` | 发送一帧（放进 Tx FIFO/Queue） |
| `HAL_FDCAN_GetRxMessage(&hfdcan1, FDCAN_RX_FIFO0, &RxHeader, data)` | 从 FIFO 取出一帧 |
| `HAL_FDCAN_RxFifo0Callback()` / `HAL_FDCAN_RxFifo1Callback()` | 收到新报文回调 |
| `HAL_FDCAN_IRQHandler(&hfdcan1)` | 中断入口（`FDCAN1_IT0/IT1_IRQHandler` 里调用） |

**较常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_FDCAN_GetRxFifoFillLevel()` / `GetTxFifoFreeLevel()` | 还能读几帧 / 还能发几帧 |
| `HAL_FDCAN_DeactivateNotification()` | 关闭中断源 |
| `HAL_FDCAN_GetProtocolStatus()` | 总线状态（Error Active/Passive/Bus-Off） |
| `HAL_FDCAN_GetErrorCounters()` | TEC/REC 错误计数（排查总线问题神器） |
| `HAL_FDCAN_AbortTxRequest()` | 取消尚未发出的请求 |
| `HAL_FDCAN_GetHighPriorityMessageStatus()` / `IsTxBufferMessagePending()` / `GetLatestTxFifoQRequestBuffer()` | 发送队列诊断 |

**不常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_FDCAN_TxFifoEmptyCallback/TxBufferCompleteCallback/TxBufferAbortCallback/TxEventFifoCallback` | 发送侧各种事件回调 |
| `HAL_FDCAN_ErrorStatusCallback/ErrorCallback` | 错误状态变化 / 出错回调 |
| `HAL_FDCAN_HighPriorityMessageCallback/TimeoutOccurredCallback/TimestampWraparoundCallback` | 高优先级消息 / 超时 / 时间戳回绕回调 |
| `HAL_FDCAN_EnableTimestampCounter/ConfigTimestampCounter/GetTimestampCounter/ResetTimestampCounter` | 帧时间戳 |
| `HAL_FDCAN_EnableTxDelayCompensation/ConfigTxDelayCompensation` | BRS 高速段的发送延迟补偿 |
| `HAL_FDCAN_EnableTimeoutCounter/ConfigTimeoutCounter/GetTimeoutCounter/ResetTimeoutCounter` | 超时监控 |
| `HAL_FDCAN_ConfigRxFifoOverwrite/ConfigExtendedIdMask/ConfigRamWatchdog` | FIFO 覆盖策略 / 扩展 ID 掩码 / RAM 看门狗 |
| `HAL_FDCAN_EnableEdgeFiltering/DisableEdgeFiltering`、`EnableISOMode/DisableISOMode` | 边沿滤波、ISO 模式 |
| `HAL_FDCAN_EnterPowerDownMode/ExitPowerDownMode`、`IsRestrictedOperationMode/ExitRestrictedOperationMode` | 低功耗 / 受限模式 |
| `HAL_FDCAN_RegisterXxxCallback()` 系列 | 注册式回调 |

**关键选项速解**

- **`FrameFormat`**：`CLASSIC`（经典 CAN）/ `FD_NO_BRS`（FD 不改速率）/ `FD_BRS`（数据段加速）。
- **`Mode`**：`NORMAL` / `LOOPBACK`（自测）/ `SILENT`（只听不发）/ `LOOPBACK_SILENT` / `RESTRICTED`。
- **`AutoRetransmission`**：是否自动重发（不等 ACK 也重发，CANopen 场景要注意）。
- **`TransmitPause`**：两帧之间的最小间隔（给慢节点留处理时间）。
- **`ProtocolException`**：协议异常检测（非 FD 帧却带 FD 格式等）。
- **位时序**：`NominalPrescaler / SyncJumpWidth / TimeSeg1 / TimeSeg2` 决定波特率与**采样点**
  （常用 75%~87.5%）；FD 另有 `Data*` 一组。
- **`ClockDivider`**：FDCAN 内核时钟分频（全局共用，**只在第一个 FDCAN 实例初始化时生效**）。
- **`StdFiltersNbr` / `ExtFiltersNbr`**：标准/扩展过滤器数量上限（G4 会用它们自动分配报文 RAM，所以这两个值必须和实际配置一致）。
- **`TxFifoQueueMode`**：发送用 **FIFO**（先进先出）还是 **Queue**（按 ID 优先级发送）。
- ⚠️ **G4 的 `FDCAN_InitTypeDef` 里没有 FIFO 深度/元素大小字段**（不像 H7/F7 那一套
  `RxFifo0ElmtsNbr`/`TxElmtSize`），报文 RAM 的分配由 HAL 依据过滤器数量自动计算，
  初始化时不要写那些字段。
- **过滤器 `FilterType`**：`RANGE`（范围）、`MASK`（掩码，最常用）、`DUAL`；`FilterConfig` 决定进
  `FIFO0/FIFO1` 还是 `REJECT`；`IdType` 区分标准帧/扩展帧。
- **`TxHeader`**：`Identifier`、`IdType`、`TxFrameType`（数据/远程）、`DataLength`(DLC)、
  `BitRateSwitch`、`FDFormat`、`TxEventFifoControl`（要不要记录发送事件）、`MessageMarker`。


### 19.1 CubeMX 配置要点
`FDCAN1 → Parameter Settings`：**Frame Format**（Classic / FD without BRS / FD with BRS）、
**Mode**（Normal / Loopback / Silent…）、**Auto Retransmission**、**Transmit Pause**、
**Protocol Exception**；**Bit Timings**（Nominal Prescaler / Seg1 / Seg2 / SJW，看 Sample Point）、
**Data Bit Timings**（只有 FD 才用）；**Std/Ext Filters**（Filter 0..127，可分配到 RXFIFO0/1 或 reject）、
**Tx FIFO/Queue 模式**、**接收 FIFO 与各类中断**、**Timestamp**、**Tx Delay Compensation（BRS 时需要）**；
Clock Configuration 里给 FDCAN 选时钟（PCLK1 或 PLLQ 或 HSE）；NVIC 勾 `FDCAN1_IT0/IT1`。
> ⚠️ G4 的 FDCAN 初始化结构体里**没有** FIFO 深度/元素大小字段（不同于 H7/F7），
> 报文 RAM 由 HAL 按过滤器数量自动分配——所以生成的 `hfdcan1.Init.*` 只有
> `ClockDivider / FrameFormat / Mode / AutoRetransmission / TransmitPause / ProtocolException /
> Nominal* / Data* / StdFiltersNbr / ExtFiltersNbr / TxFifoQueueMode` 这些。

### 19.2 初始化 + 配置过滤器（必须！否则收不到任何报文）
```c
FDCAN_HandleTypeDef hfdcan1;
hfdcan1.Instance                  = FDCAN1;
hfdcan1.Init.FrameFormat          = FDCAN_FRAME_FD_BRS;   /* 经典 CAN 用 FDCAN_FRAME_CLASSIC */
hfdcan1.Init.Mode                 = FDCAN_MODE_NORMAL;
hfdcan1.Init.AutoRetransmission   = ENABLE;
hfdcan1.Init.TransmitPause        = DISABLE;
hfdcan1.Init.ProtocolException    = DISABLE;
hfdcan1.Init.NominalPrescaler     = 0x4;                  /* 由 CubeMX 算好 */
hfdcan1.Init.NominalSyncJumpWidth = 0x4;
hfdcan1.Init.NominalTimeSeg1      = 0x1D;
hfdcan1.Init.NominalTimeSeg2      = 0x4;
hfdcan1.Init.DataPrescaler        = 0x1;
hfdcan1.Init.DataSyncJumpWidth    = 0x4;
hfdcan1.Init.DataTimeSeg1         = 0xF;
hfdcan1.Init.DataTimeSeg2         = 0x4;
hfdcan1.Init.ClockDivider         = FDCAN_CLOCK_DIV1;    /* 全局，只在第一个实例生效 */
hfdcan1.Init.StdFiltersNbr        = 1;
hfdcan1.Init.ExtFiltersNbr        = 0;
hfdcan1.Init.TxFifoQueueMode      = FDCAN_TX_FIFO_OPERATION;   /* FIFO 发送；Queue 则用 FDCAN_TX_QUEUE */
if (HAL_FDCAN_Init(&hfdcan1) != HAL_OK) { Error_Handler(); }

/* 过滤器：接收全部标准帧到 FIFO0 */
FDCAN_FilterTypeDef sFilterConfig = {0};
sFilterConfig.IdType       = FDCAN_STANDARD_ID;
sFilterConfig.FilterIndex  = 0;
sFilterConfig.FilterType   = FDCAN_FILTER_MASK;
sFilterConfig.FilterConfig = FDCAN_FILTER_TO_RXFIFO0;
sFilterConfig.FilterID1    = 0x000;
sFilterConfig.FilterID2    = 0x7FF;                 /* 掩码：全 0 表示全部接收 */
HAL_FDCAN_ConfigFilter(&hfdcan1, &sFilterConfig);
HAL_FDCAN_ConfigGlobalFilter(&hfdcan1, FDCAN_ACCEPT_IN_RX_FIFO0, FDCAN_ACCEPT_IN_RX_FIFO0,
                             FDCAN_REJECT_REMOTE, FDCAN_REJECT_REMOTE);
HAL_FDCAN_ConfigInterruptLines(&hfdcan1, FDCAN_IT_GROUP_RX_FIFO0, FDCAN_INTERRUPT_LINE0);
HAL_FDCAN_ActivateNotification(&hfdcan1, FDCAN_IT_RX_FIFO0_NEW_MESSAGE, 0);
HAL_FDCAN_Start(&hfdcan1);                          /* 进入正常通信 */
```

### 19.3 发送 / 接收
```c
/* 发送（放入 Tx FIFO/Queue） */
FDCAN_TxHeaderTypeDef TxHeader;
uint8_t tx_data[8] = {1,2,3,4,5,6,7,8};
TxHeader.Identifier          = 0x123;
TxHeader.IdType              = FDCAN_STANDARD_ID;
TxHeader.TxFrameType         = FDCAN_DATA_FRAME;
TxHeader.DataLength          = FDCAN_DLC_BYTES_8;
TxHeader.ErrorStateIndicator = FDCAN_ESI_ACTIVE;
TxHeader.BitRateSwitch       = FDCAN_BRS_OFF;        /* FD 用 FDCAN_BRS_ON */
TxHeader.FDFormat            = FDCAN_CLASSIC_CAN;    /* FD 用 FDCAN_FD_CAN */
TxHeader.TxEventFifoControl  = FDCAN_NO_TX_EVENTS;
TxHeader.MessageMarker       = 0;
HAL_FDCAN_AddMessageToTxFifoQ(&hfdcan1, &TxHeader, tx_data);

/* 接收（中断回调里取） */
void HAL_FDCAN_RxFifo0Callback(FDCAN_HandleTypeDef *hfdcan, uint32_t RxFifo0ITs)
{
  if ((RxFifo0ITs & FDCAN_IT_RX_FIFO0_NEW_MESSAGE) != 0)
  {
    FDCAN_RxHeaderTypeDef RxHeader; uint8_t rx[8];
    HAL_FDCAN_GetRxMessage(hfdcan, FDCAN_RX_FIFO0, &RxHeader, rx);
    /* RxHeader.Identifier / DataLength / RxTimestamp … */
  }
}
/* 阻塞轮询接收（不用中断时） */
if (HAL_FDCAN_GetRxFifoFillLevel(&hfdcan1, FDCAN_RX_FIFO0) > 0)
{ HAL_FDCAN_GetRxMessage(&hfdcan1, FDCAN_RX_FIFO0, &RxHeader, rx); }
```

### 19.4 中断入口、回调与常用函数
```c
void FDCAN1_IT0_IRQHandler(void) { HAL_FDCAN_IRQHandler(&hfdcan1); }
void FDCAN1_IT1_IRQHandler(void) { HAL_FDCAN_IRQHandler(&hfdcan1); }

void HAL_FDCAN_RxFifo1Callback      (FDCAN_HandleTypeDef *h, uint32_t ITs) { }
void HAL_FDCAN_TxFifoEmptyCallback  (FDCAN_HandleTypeDef *h) { }
void HAL_FDCAN_TxBufferCompleteCallback(FDCAN_HandleTypeDef *h, uint32_t BufferIndexes) { }
void HAL_FDCAN_TxBufferAbortCallback (FDCAN_HandleTypeDef *h, uint32_t BufferIndexes) { }
void HAL_FDCAN_TxEventFifoCallback  (FDCAN_HandleTypeDef *h, uint32_t ITs) { }
void HAL_FDCAN_ErrorStatusCallback  (FDCAN_HandleTypeDef *h, uint32_t ErrorStatusITs) { }
void HAL_FDCAN_ErrorCallback        (FDCAN_HandleTypeDef *h) { }
void HAL_FDCAN_HighPriorityMessageCallback(FDCAN_HandleTypeDef *h, uint32_t ITs) { }
void HAL_FDCAN_TimeoutOccurredCallback(FDCAN_HandleTypeDef *h) { }
void HAL_FDCAN_TimestampWraparoundCallback(FDCAN_HandleTypeDef *h) { }

/* 常用操作 */
HAL_FDCAN_GetTxFifoFreeLevel(&hfdcan1);            /* 还能发几帧 */
HAL_FDCAN_GetRxFifoFillLevel(&hfdcan1, FDCAN_RX_FIFO0);
HAL_FDCAN_GetProtocolStatus(&hfdcan1, &ProtocolStatus);   /* 总线状态 */
HAL_FDCAN_GetErrorCounters(&hfdcan1, &ErrorCounters);     /* TEC/REC 错误计数 */
HAL_FDCAN_AbortTxRequest(&hfdcan1, FDCAN_TX_BUFFER0);
HAL_FDCAN_EnableTimestampCounter(&hfdcan1, FDCAN_TIMESTAMP_EXTERNAL);
HAL_FDCAN_GetTimestampCounter(&hfdcan1);
HAL_FDCAN_EnableTxDelayCompensation(&hfdcan1);  HAL_FDCAN_ConfigTxDelayCompensation(&hfdcan1, 0, 0);
HAL_FDCAN_EnterPowerDownMode(&hfdcan1);   HAL_FDCAN_ExitPowerDownMode(&hfdcan1);
HAL_FDCAN_DeactivateNotification(&hfdcan1, FDCAN_IT_RX_FIFO0_NEW_MESSAGE);
HAL_FDCAN_Stop(&hfdcan1);  HAL_FDCAN_DeInit(&hfdcan1);
```
> **要点**：① 没配过滤器 = 一帧都收不到；② 总线上必须有 120Ω 终端电阻，采样点要匹配（常用 75~87.5%）；
> ③ 用 FD+BRS 时收发器要支持 FD，且建议开 `Tx Delay Compensation`；
> ④ 想降低 CPU 占用可以 `FDCAN_FILTER_TO_RXFIFO0` + 只开 `FDCAN_IT_RX_FIFO0_NEW_MESSAGE`。

### 完整工程骨架（CubeMX 生成 + 你手写）

以 **FDCAN1 经典 CAN 收发（500k，标准帧）**为例：

```c
/* ============ Core/Src/fdcan.c —— CubeMX 生成 ============ */
FDCAN_HandleTypeDef hfdcan1;

void MX_FDCAN1_Init(void)
{
  hfdcan1.Instance                  = FDCAN1;
  hfdcan1.Init.FrameFormat          = FDCAN_FRAME_CLASSIC;   /* 经典 CAN */
  hfdcan1.Init.Mode                 = FDCAN_MODE_NORMAL;
  hfdcan1.Init.AutoRetransmission   = ENABLE;
  hfdcan1.Init.TransmitPause        = DISABLE;
  hfdcan1.Init.ProtocolException    = DISABLE;
  hfdcan1.Init.NominalPrescaler     = 0x10;                  /* 位时序：CubeMX 算好 */
  hfdcan1.Init.NominalSyncJumpWidth = 0x1;
  hfdcan1.Init.NominalTimeSeg1      = 0xE;
  hfdcan1.Init.NominalTimeSeg2      = 0x1;
  hfdcan1.Init.DataPrescaler        = 0x1;
  hfdcan1.Init.DataSyncJumpWidth    = 0x1;
  hfdcan1.Init.DataTimeSeg1         = 0x1;
  hfdcan1.Init.DataTimeSeg2         = 0x1;
  hfdcan1.Init.ClockDivider         = FDCAN_CLOCK_DIV1;   /* 全局，只在第一个实例生效 */
  hfdcan1.Init.StdFiltersNbr        = 1;
  hfdcan1.Init.ExtFiltersNbr        = 0;
  hfdcan1.Init.TxFifoQueueMode      = FDCAN_TX_FIFO_OPERATION;
  if (HAL_FDCAN_Init(&hfdcan1) != HAL_OK) { Error_Handler(); }

  /* CubeMX 勾了过滤器就会生成这段（不配过滤器 = 收不到任何帧）*/
  FDCAN_FilterTypeDef sFilterConfig = {0};
  sFilterConfig.IdType       = FDCAN_STANDARD_ID;
  sFilterConfig.FilterIndex  = 0;
  sFilterConfig.FilterType   = FDCAN_FILTER_MASK;
  sFilterConfig.FilterConfig = FDCAN_FILTER_TO_RXFIFO0;
  sFilterConfig.FilterID1    = 0x000;
  sFilterConfig.FilterID2    = 0x000;            /* 掩码全 0 = 全部接收 */
  if (HAL_FDCAN_ConfigFilter(&hfdcan1, &sFilterConfig) != HAL_OK) { Error_Handler(); }

  /* 中断源（CubeMX 里勾了"接收新报文中断"就会生成）*/
  if (HAL_FDCAN_ActivateNotification(&hfdcan1, FDCAN_IT_RX_FIFO0_NEW_MESSAGE, 0) != HAL_OK)
  { Error_Handler(); }
}

void HAL_FDCAN_MspInit(FDCAN_HandleTypeDef* fdcanHandle)
{
  RCC_PeriphCLKInitTypeDef PeriphClkInit = {0};
  if (fdcanHandle->Instance == FDCAN1)
  {
    PeriphClkInit.PeriphClockSelection = RCC_PERIPHCLK_FDCAN;
    PeriphClkInit.FdcanClockSelection  = RCC_FDCANCLKSOURCE_PCLK1;   /* CAN 时钟源 */
    HAL_RCCEx_PeriphCLKConfig(&PeriphClkInit);
    __HAL_RCC_FDCAN_CLK_ENABLE();
    /* GPIO：FDCAN1_RX/TX 复用（CubeMX 配好）*/
    HAL_NVIC_SetPriority(FDCAN1_IT0_IRQn, 0, 0);
    HAL_NVIC_EnableIRQ(FDCAN1_IT0_IRQn);
  }
}

/* ============ Core/Src/stm32g4xx_it.c —— CubeMX 生成 ============ */
void FDCAN1_IT0_IRQHandler(void) { HAL_FDCAN_IRQHandler(&hfdcan1); }
```

```c
/* ============ 你手写的部分 ============ */

/* ① 启动 CAN（CubeMX 不生成这句，必须自己调）*/
HAL_FDCAN_Start(&hfdcan1);                 /* 调用后才能真正收发 */
/* 需要停止时：HAL_FDCAN_Stop(&hfdcan1); */

/* ② 发送一帧（封装成函数方便到处调用）*/
uint8_t CAN_SendStd(uint16_t id, uint8_t *data, uint8_t len)
{
  FDCAN_TxHeaderTypeDef tx = {0};
  tx.Identifier          = id;
  tx.IdType              = FDCAN_STANDARD_ID;
  tx.TxFrameType         = FDCAN_DATA_FRAME;
  tx.DataLength          = (uint32_t)(len << 16);      /* FDCAN_DLC_BYTES_8 等 */
  tx.ErrorStateIndicator = FDCAN_ESI_ACTIVE;
  tx.BitRateSwitch       = FDCAN_BRS_OFF;
  tx.FDFormat            = FDCAN_CLASSIC_CAN;
  tx.TxEventFifoControl  = FDCAN_NO_TX_EVENTS;
  tx.MessageMarker       = 0;
  return (HAL_FDCAN_AddMessageToTxFifoQ(&hfdcan1, &tx, data) == HAL_OK);
}

/* ③ 接收：中断回调里把报文取出来（否则 FIFO 会满）*/
void HAL_FDCAN_RxFifo0Callback(FDCAN_HandleTypeDef *hfdcan, uint32_t RxFifo0ITs)
{
  if ((RxFifo0ITs & FDCAN_IT_RX_FIFO0_NEW_MESSAGE) != 0)
  {
    FDCAN_RxHeaderTypeDef rx;
    uint8_t data[8];
    HAL_FDCAN_GetRxMessage(hfdcan, FDCAN_RX_FIFO0, &rx, data);
    /* rx.Identifier / rx.DataLength 判断后分发处理 */
  }
}

/* ④ 总线异常/错误状态（Bus-Off 恢复必看）*/
void HAL_FDCAN_ErrorStatusCallback(FDCAN_HandleTypeDef *hfdcan, uint32_t ErrorStatusITs)
{
  if ((ErrorStatusITs & FDCAN_IT_BUS_OFF) != 0)
  {
    /* 总线恢复：重新初始化 + 启动 */
    HAL_FDCAN_Stop(hfdcan);
    MX_FDCAN1_Init();
    HAL_FDCAN_Start(hfdcan);
  }
}

/* ⑤ 调试期打印总线状态与错误计数（排查丢帧/干扰）*/
FDCAN_ProtocolStatusTypeDef ps;
FDCAN_ErrorCountersTypeDef  ec;
HAL_FDCAN_GetProtocolStatus(&hfdcan1, &ps);
HAL_FDCAN_GetErrorCounters(&hfdcan1, &ec);
printf("BusOff=%d TEC=%d REC=%d\r\n", ps.BusOff, ec.TxErrorCnt, ec.RxErrorCnt);
```

**CubeMX 配置入口**：`Connectivity → FDCAN1` 设 Frame Format / Mode / Bit Timings（填波特率即可看
Sample Point）、FIFO 深度；`Std Filters` 表里加过滤器；NVIC 勾 `FDCAN1_IT0_IT1`；
**上位机侧别忘了 120Ω 终端电阻**，否则总线不通。

---

## 20. USB Device（PCD）

### 概览

**常用 API（应用层：用 USB Device 中间件）**

| API | 一句话作用 |
|---|---|
| `MX_USB_PCD_Init()` → `HAL_PCD_Init(&hpcd_USB_FS)` | 底层 USB 设备控制器初始化（CubeMX 生成） |
| `MX_USB_DEVICE_Init()` → `USBD_Init()/USBD_RegisterClass()/USBD_Start()` | 初始化中间件、注册设备类、启动枚举 |
| `USBD_CDC_RegisterInterface(&hUsbDeviceFS, &USBD_Interface_fops_FS)` | 把 CDC 的收发回调绑定到中间件 |
| `CDC_Transmit_FS(buf, len)` | **虚拟串口发送**（返回 `USBD_BUSY` 要重试，别丢数据） |
| `CDC_Receive_FS(Buf, Len)` | 主机数据到达回调（务必 `USBD_CDC_ReceivePacket()` 重新武装） |
| `USBD_HID_SendReport(&hUsbDeviceFS, report, len)` | HID 上报（键盘/鼠标/自定义） |
| `HAL_PCD_IRQHandler(&hpcd_USB_FS)` | USB 中断入口（CubeMX 生成的 `USB_IRQHandler` 里调用） |
| `USBD_MSC` 的 `STORAGE_Read_FS/Write_FS` | U 盘功能只需实现这两个读写函数 |

**底层 API（一般由中间件调用，手写设备栈才直接用）**

| API | 一句话作用 |
|---|---|
| `HAL_PCD_Start()/Stop()` | 使能 / 关闭 USB 设备 |
| `HAL_PCD_SetAddress()`、`DevConnect()`、`DevDisconnect()` | 设地址、软连接/断开（可用于复位重枚举） |
| `HAL_PCD_EP_Open()` / `EP_Close()` | 打开 / 关闭端点并指定类型与包长 |
| `HAL_PCD_EP_Transmit()` / `EP_Receive()` / `EP_GetRxCount()` | 端点收发与本次接收长度 |
| `HAL_PCD_EP_SetStall()` / `EP_ClrStall()` / `EP_Flush()` / `EP_Abort()` | 端点握手与清理 |
| `HAL_PCD_ActivateRemoteWakeup()` / `DeActivateRemoteWakeup()` | 远程唤醒主机 |
| `HAL_PCDEx_PMAConfig()` | 分配端点缓冲区（FS 设备的 PMA 512B 划分） |
| `HAL_PCDEx_ActivateLPM/DeActivateLPM`、`ActivateBCD/DeActivateBCD/BCD_VBUSDetect` | LPM 低功耗、BC1.2 充电检测 |
| `HAL_PCD_RegisterCallback()` | 注册式回调 |
| 回调：`SetupStageCallback`/`DataInStageCallback`/`DataOutStageCallback`/`ResetCallback`/`SuspendCallback`/`ResumeCallback`/`SOFCallback`/`ConnectCallback`/`DisconnectCallback`/`ISOIN|ISOOUTIncompleteCallback` | **中间件已实现，一般不要重写** |

**关键选项速解**

- **`dev_endpoints`**：启用多少个端点（改端点数量要同步改 PMA 分配）。
- **`speed`**：`PCD_SPEED_FULL`（G4 只有全速）；`phy_itface`：内部 PHY。
- **`Sof_enable`**：要不要每 1ms 的 SOF 中断（一般不用）。
- **`low_power_enable` / `lpm_enable` / `battery_charging_enable`**：低功耗模式 / LPM / BC1.2 检测。
- **`HAL_PCDEx_PMAConfig(ep, SNG_BUF/DBL_BUF, offset)`**：端点双缓冲可提吞吐。
- **中间件 `Class`**：CDC（虚拟串口）/ HID / Custom HID / MSC / Audio / DFU——决定你调用哪个上层库。
- **48MHz 时钟**：USB 必须有时钟（HSI48 或 PLLQ = 48MHz），否则电脑永远认不到设备。


### 20.1 CubeMX 配置要点
`Connectivity → USB（G4 是 USB FS Device）/ USB_OTG_FS`：**Mode = Device_Only**；
`Middleware → USB_DEVICE`：**Class for FS IP** 选 `Communication Device Class (CDC)`（虚拟串口）/
`HID` / `Custom Human Interface` / `Mass Storage Class` / `Audio` / `DFU`；
Clock Configuration 里必须给 **USB 48MHz 时钟**（HSI48 或 PLLQ）；NVIC 勾 `USB_IRQn`（或 `OTG_FS_IRQn`）。

生成的文件：`Core/Src/usb.c`（`MX_USB_PCD_Init`）、`USB_DEVICE/App/usb_device.c`（`MX_USB_DEVICE_Init`）、
`USB_DEVICE/App/usbd_cdc_if.c`（CDC 收发接口）、`USB_DEVICE/Target/usbd_conf.c`（底层对接）。

### 20.2 生成的代码骨架
```c
PCD_HandleTypeDef hpcd_USB_FS;                     /* G4：USB FS */
void MX_USB_PCD_Init(void)
{
  hpcd_USB_FS.Instance                 = USB;
  hpcd_USB_FS.Init.dev_endpoints       = 8;
  hpcd_USB_FS.Init.speed               = PCD_SPEED_FULL;
  hpcd_USB_FS.Init.phy_itface          = PCD_PHY_EMBEDDED;
  hpcd_USB_FS.Init.Sof_enable          = DISABLE;
  hpcd_USB_FS.Init.low_power_enable    = DISABLE;
  hpcd_USB_FS.Init.lpm_enable          = DISABLE;
  hpcd_USB_FS.Init.battery_charging_enable = DISABLE;
  if (HAL_PCD_Init(&hpcd_USB_FS) != HAL_OK) { Error_Handler(); }
  HAL_PCDEx_PMAConfig(&hpcd_USB_FS, 0x00, PCD_SNG_BUF, 0x18);   /* 端点缓冲区分配 */
  /* ... 其它端点 ... */
}
void USB_IRQHandler(void) { HAL_PCD_IRQHandler(&hpcd_USB_FS); }  /* 由 CubeMX 生成 */
```

### 20.3 底层 API（`stm32g4xx_hal_pcd.h`，一般由 USB 中间件调用）

| 函数 | 用途 |
|---|---|
| `HAL_PCD_Init()` / `DeInit()` / `Start()` / `Stop()` / `GetState()` | USB 设备控制器启停 |
| `HAL_PCD_EP_Open(ep_addr, ep_mps, ep_type)` / `EP_Close()` | 打开/关闭端点 |
| `HAL_PCD_EP_Transmit(ep, buf, len)` / `EP_Receive(ep, buf, len)` | 端点收发 |
| `HAL_PCD_EP_SetStall()` / `EP_ClrStall()` / `EP_Flush()` / `EP_Abort()` / `EP_GetRxCount()` | 端点控制 |
| `HAL_PCD_SetAddress()` / `HAL_PCD_DevConnect()` / `DevDisconnect()` | 地址与连接状态 |
| `HAL_PCD_ActivateRemoteWakeup()` / `DeActivateRemoteWakeup()` | 远程唤醒 |
| `HAL_PCD_IRQHandler(&hpcd)` | 中断入口（Core/Src/xxx_it.c 调用） |
| `HAL_PCD_RegisterCallback()` | 自定义回调 |
| `HAL_PCDEx_PMAConfig()`、`HAL_PCDEx_ActivateLPM()`、`HAL_PCDEx_ActivateBCD()`、`HAL_PCDEx_BCD_VBUSDetect()` | 扩展：PMA/LPM/BC1.2 |

回调（通常**由中间件实现，你不要重写**）：
`HAL_PCD_SetupStageCallback`、`DataInStageCallback`、`DataOutStageCallback`、`ResetCallback`、
`SuspendCallback`、`ResumeCallback`、`SOFCallback`、`ConnectCallback`、`DisconnectCallback`、
`ISOINIncompleteCallback`、`ISOOUTIncompleteCallback`。

### 20.4 应用层真正要写的代码（USB Device 中间件）
```c
/* usb_device.c —— CubeMX 生成，main() 里调用 */
USBD_Init(&hUsbDeviceFS, &FS_Desc, DEVICE_FS);
USBD_RegisterClass(&hUsbDeviceFS, &USBD_CDC);
USBD_CDC_RegisterInterface(&hUsbDeviceFS, &USBD_Interface_fops_FS);
USBD_Start(&hUsbDeviceFS);

/* CDC（虚拟串口）发送 —— 在 usbd_cdc_if.c 里已有现成的 CDC_Transmit_FS() */
uint8_t msg[] = "hello from STM32\r\n";
if (CDC_Transmit_FS(msg, sizeof(msg)) == USBD_BUSY) { /* 忙，稍后重试 */ }
/* CDC 接收：主机数据到达时中间件回调，CubeMX 已生成框架 */
static int8_t CDC_Receive_FS(uint8_t *Buf, uint32_t *Len)
{
  /* 这里处理主机发来的数据 Buf[0..*Len-1] */
  USBD_CDC_SetRxBuffer(&hUsbDeviceFS, &Buf[0]);
  USBD_CDC_ReceivePacket(&hUsbDeviceFS);      /* 重新武装，别删！ */
  return USBD_OK;
}
/* HID：USBD_HID_SendReport(&hUsbDeviceFS, report, len); */
/* MSC：在 usbd_storage_if.c 里实现 STORAGE_Read_FS/Write_FS 即可 */
/* 其它 API：USBD_SetClassConfig / USBD_DeInit / USBD_LL_*（在 usbd_conf.c 中对接 HAL_PCD_*）*/
```

### 20.5 常见坑
1. **48MHz 时钟没配好 → 电脑永远认不到设备**（HSI48 要开，或 PLLQ = 48MHz）。
2. CDC 发送前必须检查返回值，`USBD_BUSY` 时不能重复调用（会丢数据）。
3. `CDC_Receive_FS` 里如果忘了 `USBD_CDC_ReceivePacket()`，收完一包就再也不收了。
4. 端点/PMA 缓冲区在 `usbd_conf.c` 的 `HAL_PCD_MspInit()` 与 `HAL_PCDEx_PMAConfig()`，
   手改端点数量要同步改 `dev_endpoints`。
5. 调试时不要在 USB 中断里打断点，容易枚举失败；必要时用 `HAL_PCD_DevDisconnect()` 复位重连。

### 完整工程骨架（CubeMX 生成 + 你手写）

以 **CDC 虚拟串口（电脑端当 COM 口收发数据）**为例，这是最常用的 USB 场景：

```c
/* ============ Core/Src/usb.c —— CubeMX 生成 ============ */
PCD_HandleTypeDef hpcd_USB_FS;

void MX_USB_PCD_Init(void)
{
  hpcd_USB_FS.Instance                 = USB;
  hpcd_USB_FS.Init.dev_endpoints       = 8;
  hpcd_USB_FS.Init.speed               = PCD_SPEED_FULL;
  hpcd_USB_FS.Init.phy_itface          = PCD_PHY_EMBEDDED;
  hpcd_USB_FS.Init.Sof_enable          = DISABLE;
  hpcd_USB_FS.Init.low_power_enable    = DISABLE;
  hpcd_USB_FS.Init.lpm_enable          = DISABLE;
  hpcd_USB_FS.Init.battery_charging_enable = DISABLE;
  if (HAL_PCD_Init(&hpcd_USB_FS) != HAL_OK) { Error_Handler(); }

  HAL_PCDEx_PMAConfig(&hpcd_USB_FS, 0x00, PCD_SNG_BUF, 0x18);   /* 端点 PMA 分配 */
  HAL_PCDEx_PMAConfig(&hpcd_USB_FS, 0x80, PCD_SNG_BUF, 0x58);
  /* ... 其余端点由 CubeMX 生成 ... */
}

/* ============ Core/Src/stm32g4xx_it.c —— CubeMX 生成 ============ */
void USB_IRQHandler(void) { HAL_PCD_IRQHandler(&hpcd_USB_FS); }

/* ============ USB_DEVICE/App/usb_device.c —— CubeMX 生成 ============ */
void MX_USB_DEVICE_Init(void)
{
  USBD_Init(&hUsbDeviceFS, &FS_Desc, DEVICE_FS);
  USBD_RegisterClass(&hUsbDeviceFS, &USBD_CDC);
  USBD_CDC_RegisterInterface(&hUsbDeviceFS, &USBD_Interface_fops_FS);
  USBD_Start(&hUsbDeviceFS);
}

/* ============ USB_DEVICE/App/usbd_cdc_if.c —— CubeMX 生成（含收发函数框架）============ */
static int8_t CDC_Init_FS(void);
static int8_t CDC_DeInit_FS(void);
static int8_t CDC_Control_FS(uint8_t cmd, uint8_t* pbuf, uint16_t length);
static int8_t CDC_Receive_FS(uint8_t* Buf, uint32_t *Len);   /* ← 主机数据到达回调 */
uint8_t CDC_Transmit_FS(uint8_t* Buf, uint16_t Len);         /* ← 你要用的发送函数 */
```

```c
/* ============ 你手写的部分 ============ */

/* ① main.c USER CODE BEGIN 2：确认设备已枚举（可选）*/
if (hUsbDeviceFS.dev_state == USBD_STATE_CONFIGURED)
{
  CDC_Transmit_FS((uint8_t *)"USB CDC ready\r\n", 16);
}

/* ② 发送数据（在 usbd_cdc_if.c 里已提供，直接调用即可）*/
uint8_t msg[] = "hello from STM32\r\n";
if (CDC_Transmit_FS(msg, sizeof(msg) - 1) == USBD_BUSY)
{
  /* 上一包还没发完：这里要缓存/稍后重发，不能直接丢弃 */
}

/* ③ 接收主机数据：在 usbd_cdc_if.c 的 CDC_Receive_FS 里加你的处理逻辑
      （CubeMX 已生成框架，你只需在中间插入解析代码，切勿删掉重新武装）*/
static int8_t CDC_Receive_FS(uint8_t* Buf, uint32_t *Len)
{
  /* ↓↓↓ 你手写：处理主机发来的 Buf[0..*Len-1] ↓↓↓ */
  HandleHostCommand(Buf, (uint16_t)*Len);

  /* ↓↓↓ 这两句是 CubeMX 生成的，必须保留：重新武装接收 ↓↓↓ */
  USBD_CDC_SetRxBuffer(&hUsbDeviceFS, &Buf[0]);
  USBD_CDC_ReceivePacket(&hUsbDeviceFS);
  return (USBD_OK);
}

/* ④ 想把 printf 打到 USB 虚拟串口（而不是 UART）*/
int _write(int fd, char *ptr, int len)      /* 或重写 printf 底层 */
{
  CDC_Transmit_FS((uint8_t *)ptr, len);
  return len;
}

/* ⑤ HID 类：定期上报（鼠标/自定义设备）*/
// USBD_HID_SendReport(&hUsbDeviceFS, report, sizeof(report));

/* ⑥ MSC 类：只要实现 usbd_storage_if.c 里的读写函数即可
      int8_t STORAGE_Read_FS (uint8_t lun, uint8_t *buf, uint32_t blk_addr, uint16_t blk_len);
      int8_t STORAGE_Write_FS(uint8_t lun, uint8_t *buf, uint32_t blk_addr, uint16_t blk_len); */

/* ⑦ 需要强制重新枚举（调试时很有用）*/
HAL_PCD_DevDisconnect(&hpcd_USB_FS);
HAL_Delay(100);
HAL_PCD_DevConnect(&hpcd_USB_FS);
```

**CubeMX 配置入口**：`Connectivity → USB_OTG_FS（G4 下显示为 USB）` 选 `Device_Only`；
`Middleware → USB_DEVICE` 的 Class 选 `Communication Device Class (CDC)`；
**Clock Configuration 里必须给 USB 48MHz**（HSI48 或 PLLQ）；NVIC 勾 `USB_IRQn`。
USB 中间件会额外生成 `USB_DEVICE/` 目录（App / Target 两个子目录），
**改代码只改 `App` 下的业务文件，`Target/usbd_conf.c` 一般不用动**。

---

## 21. QSPI（外部 Flash）

### 概览

**常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_QSPI_Init(&hqspi)` | 初始化：时钟分频 / FIFO 阈值 / Flash 大小 / CS 时间 / 时钟模式 |
| `HAL_QSPI_Command(&hqspi, &sCommand, timeout)` | 发一条指令（读 ID、写使能、擦除、写状态寄存器） |
| `HAL_QSPI_Transmit[_IT/_DMA](&hqspi, pData, timeout)` | 发数据（通常紧跟 Command） |
| `HAL_QSPI_Receive[_IT/_DMA](&hqspi, pData, timeout)` | 读数据 |
| `HAL_QSPI_AutoPolling[_IT](&hqspi, &sConfig, timeout)` | 轮询状态寄存器（等擦/写完成） |
| `HAL_QSPI_MemoryMapped(&hqspi, &sMemMappedCfg)` | 进入**内存映射**模式，之后像读内存一样读 Flash |
| `HAL_QSPI_IRQHandler(&hqspi)` | 中断入口 |
| 回调 `CmdCplt/RxCplt/TxCplt/RxHalfCplt/TxHalfCplt/StatusMatch/TimeOut/AbortCplt/Error/FifoThreshold` | 各类完成与错误回调 |

**不常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_QSPI_Abort()` / `HAL_QSPI_Abort_IT()` | 终止当前操作（如 AutoPolling 卡住时） |
| `HAL_QSPI_SetTimeout()` / `SetFifoThreshold()` / `GetFifoThreshold()` / `SetFlashID()` | 运行期调参数 |
| `HAL_QSPI_GetState()` / `GetError()` / `RegisterCallback()` | 诊断 |

**关键选项速解**

- **`ClockPrescaler`**：QSPI 时钟分频，**不能超过 Flash 手册允许的最高频率**。
- **`FIFOThreshold`**：FIFO 触发阈值（开中断/切换方向用）。
- **`FlashSize`**：Flash 容量对应的地址位数（决定可寻址范围）。
- **`ChipSelectHighTime`**：CS 两次操作之间拉高的最短时间（高速时不够会误触发）。
- **`ClockMode`**：Mode 0 或 Mode 3（按 Flash 手册选）。
- **`SampleShifting`**：采样移位，>50MHz 时选 Half Cycle 才能采稳。
- **`QSPI_CommandTypeDef` 各字段**：`Instruction` + `InstructionMode`（1/2/4 线）、
  `AddressSize/AddressMode`、`AlternateByteMode`、`DummyCycles`（高速读必须给够）、
  `DataMode`、`NbData`——**这些要和 Flash 指令表逐条对上**。


### 21.1 CubeMX 配置要点
`QUADSPI`：**Clock Prescaler**（分频到 Flash 支持的最高频率，如 2 分频）、**FIFO Threshold**、
**Flash Size**（地址位宽，如 2 字节 / 3 字节）、**Chip Select High Time**、
**Clock Mode**（Mode 0 或 Mode 3）、**Sample Shifting**（Half Cycle，高速时必开）、Flash ID。

### 21.2 关键 API（`stm32g4xx_hal_qspi.h`）

| 函数 | 用途 |
|---|---|
| `HAL_QSPI_Init(&hqspi)` / `DeInit()` / `GetState()` / `GetError()` | 初始化 |
| `HAL_QSPI_Command(&hqspi, &sCommand, Timeout)` / `HAL_QSPI_Command_IT()` | 发指令（擦除/写使能/写寄存器等） |
| `HAL_QSPI_Transmit[_IT/_DMA](&hqspi, pData, Timeout)` | 写数据（配合 `HAL_QSPI_Command`） |
| `HAL_QSPI_Receive[_IT/_DMA](&hqspi, pData, Timeout)` | 读数据 |
| `HAL_QSPI_AutoPolling(&hqspi, &sConfig, Timeout)` / `_IT()` | 轮询状态寄存器（等 WIP 清零） |
| `HAL_QSPI_MemoryMapped(&hqspi, &sMmdConfig)` | **内存映射模式**：之后像读数组一样读 Flash |
| `HAL_QSPI_Abort()` / `Abort_IT()`、`SetTimeout()`、`SetFifoThreshold()`、`SetFlashID()` | 控制类 |
| `HAL_QSPI_IRQHandler(&hqspi)` | 中断入口 |

回调：`HAL_QSPI_CmdCpltCallback`、`TxCpltCallback`、`RxCpltCallback`、`TxHalfCpltCallback`、
`RxHalfCpltCallback`、`StatusMatchCallback`、`TimeOutCallback`、`AbortCpltCallback`、
`ErrorCallback`、`FifoThresholdCallback`。

```c
/* 例：读 JEDEC ID（0x9F） */
QSPI_CommandTypeDef sCommand = {0};
uint8_t id[3];
sCommand.Instruction       = 0x9F;
sCommand.InstructionMode   = QSPI_INSTRUCTION_1_LINE;
sCommand.AddressMode       = QSPI_ADDRESS_NONE;
sCommand.AlternateByteMode = QSPI_ALTERNATE_BYTES_NONE;
sCommand.DataMode          = QSPI_DATA_1_LINE;
sCommand.DummyCycles       = 0;
sCommand.NbData            = 3;
HAL_QSPI_Command(&hqspi, &sCommand, HAL_QSPI_TIMEOUT_DEFAULT_VALUE);
HAL_QSPI_Receive(&hqspi, id, HAL_QSPI_TIMEOUT_DEFAULT_VALUE);

/* 例：等待写入完成（读状态寄存器直到 WIP=0） */
QSPI_AutoPollingTypeDef sConfig = {0};
sConfig.Match              = 0x00;
sConfig.Mask               = 0x01;
sConfig.MatchMode          = QSPI_MATCH_MODE_AND;
sConfig.StatusBytesSize    = 1;
sConfig.Interval           = 0x10;
sConfig.AutomaticStop      = QSPI_AUTOMATIC_STOP_ENABLE;
HAL_QSPI_AutoPolling(&hqspi, &sConfig, HAL_QSPI_TIMEOUT_DEFAULT_VALUE);

/* 例：进入内存映射，之后可直接用指针读 */
QSPI_MemoryMappedTypeDef sMemMappedCfg = {0};
sMemMappedCfg.MemoryMappedMode  = QSPI_MEMORYMAPPED_ENABLE;
sMemMappedCfg.TimeOutPeriod     = 0xFFFF;   /* 超时后退出映射模式 */
sMemMappedCfg.TimeOutActivation = QSPI_TIMEOUT_COUNTER_DISABLE;
sCommand.Instruction       = 0xEB;          /* 4 线快速读 */
sCommand.AddressMode       = QSPI_ADDRESS_4_LINES;
sCommand.AddressSize      = QSPI_ADDRESS_24_BITS;
sCommand.DataMode          = QSPI_DATA_4_LINES;
sCommand.DummyCycles       = 6;
HAL_QSPI_MemoryMapped(&hqspi, &sMemMappedCfg);
const uint8_t *flash = (uint8_t *)0x90000000;   /* 映射后直接读，支持 memcpy/送屏 */
```
> 注意：① 写/擦除 Flash 前必须发 Write Enable，写完要 AutoPolling 等完成；
> ② 超时时间统一用宏 `HAL_QSPI_TIMEOUT_DEFAULT_VALUE`（=5000ms）；
> ③ 高速时钟（>50MHz）记得开 `Sample Shifting = Half Cycle` 并把 CS High Time 调够。

### 完整工程骨架（CubeMX 生成 + 你手写）

以 **W25Q 系列 SPI Flash：读 ID / 擦除 / 写 / 内存映射读取**为例：

```c
/* ============ Core/Src/quadspi.c —— CubeMX 生成 ============ */
QSPI_HandleTypeDef hqspi;
DMA_HandleTypeDef  hdma_quadspi;

void MX_QUADSPI_Init(void)
{
  hqspi.Instance = QUADSPI;
  hqspi.Init.ClockPrescaler     = 1;                        /* 分频，别超 Flash 上限 */
  hqspi.Init.FifoThreshold      = 4;
  hqspi.Init.SampleShifting     = QSPI_SAMPLE_SHIFTING_HALFCYCLE;
  hqspi.Init.FlashSize          = POSITION_VAL(0x800000) - 1;  /* 8MB Flash */
  hqspi.Init.ChipSelectHighTime = QSPI_CS_HIGH_TIME_2_CYCLE;
  hqspi.Init.ClockMode          = QSPI_CLOCK_MODE_0;
  hqspi.Init.FlashID            = QSPI_FLASH_ID_1;
  hqspi.Init.DualFlash          = QSPI_DUALFLASH_DISABLE;
  if (HAL_QSPI_Init(&hqspi) != HAL_OK) { Error_Handler(); }
}

void HAL_QSPI_MspInit(QSPI_HandleTypeDef* hqspi)
{
  if (hqspi->Instance == QUADSPI)
  {
    __HAL_RCC_QSPI_CLK_ENABLE();
    /* GPIO：CLK/BK1/NCS/IO0~IO3 全部 AF10 + GPIO_SPEED_FREQ_VERY_HIGH */
    HAL_NVIC_SetPriority(QUADSPI_IRQn, 0, 0);
    HAL_NVIC_EnableIRQ(QUADSPI_IRQn);
    /* DMA：hdma_quadspi + __HAL_LINKDMA */
  }
}

/* ============ Core/Src/stm32g4xx_it.c —— CubeMX 生成 ============ */
void QUADSPI_IRQHandler(void) { HAL_QSPI_IRQHandler(&hqspi); }
```

```c
/* ============ 你手写的部分 ============ */

/* ① 读 JEDEC ID（上电自检：确认 Flash 型号与接线正确）*/
uint8_t Flash_ReadID(uint8_t *id)
{
  QSPI_CommandTypeDef sCmd = {0};
  sCmd.Instruction     = 0x9F;
  sCmd.InstructionMode = QSPI_INSTRUCTION_1_LINE;
  sCmd.AddressMode     = QSPI_ADDRESS_NONE;
  sCmd.AlternateByteMode = QSPI_ALTERNATE_BYTES_NONE;
  sCmd.DataMode        = QSPI_DATA_1_LINE;
  sCmd.DummyCycles     = 0;
  sCmd.NbData          = 3;
  if (HAL_QSPI_Command(&hqspi, &sCmd, HAL_QSPI_TIMEOUT_DEFAULT_VALUE) != HAL_OK) return 0;
  return (HAL_QSPI_Receive(&hqspi, id, HAL_QSPI_TIMEOUT_DEFAULT_VALUE) == HAL_OK);
}

/* ② 擦除一个扇区（流程：写使能 → 擦除指令 → 轮询等完成）*/
uint8_t Flash_EraseSector(uint32_t addr)
{
  QSPI_CommandTypeDef sCmd = {0};
  QSPI_AutoPollingTypeDef sPoll = {0};

  /* 2.1 写使能 0x06 */
  sCmd.Instruction = 0x06; sCmd.InstructionMode = QSPI_INSTRUCTION_1_LINE;
  sCmd.AddressMode = QSPI_ADDRESS_NONE;   sCmd.DataMode = QSPI_DATA_NONE;
  sCmd.DummyCycles = 0; sCmd.AlternateByteMode = QSPI_ALTERNATE_BYTES_NONE;
  if (HAL_QSPI_Command(&hqspi, &sCmd, 100) != HAL_OK) return 0;

  /* 2.2 扇区擦除 0x20 + 24 位地址 */
  sCmd.Instruction   = 0x20;
  sCmd.AddressMode   = QSPI_ADDRESS_1_LINE;
  sCmd.AddressSize   = QSPI_ADDRESS_24_BITS;
  sCmd.Address       = addr;
  if (HAL_QSPI_Command(&hqspi, &sCmd, 100) != HAL_OK) return 0;

  /* 2.3 轮询状态寄存器（等 WIP 位清零）*/
  sPoll.Match           = 0x00;
  sPoll.Mask            = 0x01;             /* bit0 = WIP */
  sPoll.MatchMode       = QSPI_MATCH_MODE_AND;
  sPoll.StatusBytesSize = 1;
  sPoll.Interval        = 0x10;
  sPoll.AutomaticStop   = QSPI_AUTOMATIC_STOP_ENABLE;
  sCmd.Instruction = 0x05;                  /* 读状态寄存器 1 */
  sCmd.DataMode    = QSPI_DATA_1_LINE; sCmd.NbData = 1;
  sCmd.DummyCycles = 0;
  return (HAL_QSPI_AutoPolling(&hqspi, &sPoll, 1000) == HAL_OK);
}

/* ③ 写入数据（同样先写使能，再 0x02 页编程）*/
uint8_t Flash_PageProgram(uint32_t addr, uint8_t *buf, uint32_t len)
{
  QSPI_CommandTypeDef sCmd = {0};
  sCmd.Instruction     = 0x02;
  sCmd.InstructionMode = QSPI_INSTRUCTION_1_LINE;
  sCmd.AddressMode     = QSPI_ADDRESS_1_LINE;
  sCmd.AddressSize     = QSPI_ADDRESS_24_BITS;
  sCmd.Address         = addr;
  sCmd.AlternateByteMode = QSPI_ALTERNATE_BYTES_NONE;
  sCmd.DataMode        = QSPI_DATA_1_LINE;
  sCmd.DummyCycles     = 0;
  sCmd.NbData          = len;
  if (HAL_QSPI_Command(&hqspi, &sCmd, 100) != HAL_OK) return 0;
  if (HAL_QSPI_Transmit(&hqspi, buf, 1000) != HAL_OK) return 0;
  /* 之后同样要 AutoPolling 等写入完成（可复用 ② 的轮询段）*/
  return 1;
}

/* ④ 内存映射：之后可以像读内存一样读 Flash（最快，适合放字体/图片）*/
void Flash_EnterMemoryMapped(void)
{
  QSPI_CommandTypeDef sCmd = {0};
  QSPI_MemoryMappedTypeDef sMem = {0};
  sCmd.Instruction     = 0xEB;                 /* 4 线快速读 */
  sCmd.InstructionMode = QSPI_INSTRUCTION_1_LINE;
  sCmd.AddressMode     = QSPI_ADDRESS_4_LINES;
  sCmd.AddressSize     = QSPI_ADDRESS_24_BITS;
  sCmd.AlternateByteMode = QSPI_ALTERNATE_BYTES_NONE;
  sCmd.DataMode        = QSPI_DATA_4_LINES;
  sCmd.DummyCycles     = 6;
  sMem.MemoryMappedMode  = QSPI_MEMORYMAPPED_ENABLE;
  sMem.TimeOutPeriod     = 0xFFFF;
  sMem.TimeOutActivation = QSPI_TIMEOUT_COUNTER_DISABLE;
  HAL_QSPI_MemoryMapped(&hqspi, &sMem);
}
/* 映射后直接读：*/
const uint8_t *res = (const uint8_t *)(0x90000000 + addr);
uint8_t  byte0 = res[0];
/* 也可以用 DMA 把大块数据直接搬到显存 */

/* ⑤ 出错时终止操作（AutoPolling 卡住 / 超时）*/
HAL_QSPI_Abort(&hqspi);
```

**CubeMX 配置入口**：`Connectivity → QUADSPI` 设 Clock Prescaler、FIFO Threshold、Flash Size、
Chip Select High Time、Clock Mode、Sample Shifting；DMA 在 `DMA Settings` 加 `QUADSPI`；
NVIC 勾 `QUADSPI global interrupt`。**引脚必须全部配成 AF10 且速度设 VERY_HIGH**。

---

## 22. FMC：SRAM / NOR / NAND

### 概览

**常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_SRAM_Init(&hsram1, &Timing, &TimingExt)` | 初始化 NOR/SRAM 控制器（并口屏、外部 RAM 都走这里） |
| 指针直写 `*(__IO uint16_t*)0x60000000 = data;` | 访问外部总线**最快**的方式（并口屏刷数据） |
| `HAL_SRAM_Write_8b/16b/32b()`、`HAL_SRAM_Read_8b/16b/32b()` | 带长度参数的读 / 写 |
| `HAL_SRAM_Write_DMA()` / `HAL_SRAM_Read_DMA()` | DMA 批量读写 |
| `HAL_SRAM_WriteOperation_Enable()` / `Disable()` | 使能 / 禁止写操作（禁止可防误写） |
| `HAL_NOR_Init/Read/ReadBuffer/Program/Erase_Block/Read_ID/GetStatus` | NOR Flash 基本操作 |
| `HAL_NAND_Init/Reset/Read_ID/Read_Page_8b/Write_Page_8b/Erase_Block/Read_Status` | NAND Flash 基本操作 |

**不常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_NOR_ProgramBuffer()` / `Erase_Chip()` / `Read_CFI()` / `ReturnToReadMode()` | NOR 的缓冲编程、整片擦除、CFI 查询、回读模式 |
| `HAL_NOR_WriteOperation_Enable/Disable` | NOR 写保护开关 |
| `HAL_NAND_ECC_Enable/GetECC` | NAND 硬件 ECC 计算校验 |
| `HAL_NAND_Read_SpareArea_8b/16b`、`Write_SpareArea_*` | NAND 冗余区读写（存 ECC/坏块标记） |
| `HAL_NAND_ConfigDevice()` / `Address_Inc()` / `GetState()` | 器件配置 / 地址递增 / 状态 |
| `HAL_NAND_IRQHandler()` + `HAL_NAND_ITCallback()` | NAND 中断 |
| `HAL_SRAM_MspInit/MspDeInit`、`HAL_NOR_MspWait`、`HAL_SRAM_GetState/RegisterCallback/RegisterDmaCallback` | 底层与诊断 |

**关键选项速解**

- **`DataWidth`**：8 或 16 位总线宽度（并口屏常见 16 位）。
- **时序四要素**：`AddressSetupTime`、`AddressHoldTime`、`DataSetupTime`、`BusTurnaroundTime`
  —— 必须按外部器件手册的 ns 值换算成 HCLK 周期数，**时序不对就是随机读写错误**。
- **`ExtendedMode`**：开启后读/写可用两套时序（读慢写快时有用）。
- **地址映射**：FMC Bank1 从 `0x6000_0000` 开始，每个片选 64MB；用第 2 个片选就 `0x6400_0000` 起。
- **并口屏技巧**：把 RS（命令/数据选择）接到某根地址线（如 A16），
  于是 `写 0x60000000` = 发命令，`写 0x60020000` = 发数据。


### 22.1 CubeMX 配置要点
`FMC` 页选 **SRAM / NOR / NAND**，设 **Data Width**（8/16 位）、**Address Setup/Hold**、
**Data Setup**、**Bus Turnaround**、**Clock Division**（NOR）、是否用 **Extended Mode**。
用于并口 LCD（8080/6800 总线）时通常配成 "SRAM" 模式。

### 22.2 API 一览

**SRAM（并口屏/外部 RAM 常用）**
```c
SRAM_HandleTypeDef hsram1;
hsram1.Instance = FMC_NORSRAM_DEVICE;
hsram1.Extended = FMC_NORSRAM_EXTENDED_DEVICE;
HAL_SRAM_Init(&hsram1, &FMC_NORSRAM_Timing, &FMC_NORSRAM_Timing);   /* 时序结构由 CubeMX 生成 */

uint8_t  b;  uint16_t h;  uint32_t w;
HAL_SRAM_Write_8b (&hsram1, (uint32_t *)0x60000000, &b, 1);
HAL_SRAM_Read_8b  (&hsram1, (uint32_t *)0x60000000, &b, 1);
HAL_SRAM_Write_16b(&hsram1, addr, &h, 1);   HAL_SRAM_Read_16b(&hsram1, addr, &h, 1);
HAL_SRAM_Write_32b(&hsram1, addr, &w, 1);   HAL_SRAM_Read_32b(&hsram1, addr, &w, 1);
HAL_SRAM_Write_DMA(&hsram1, addr, buf, len);   HAL_SRAM_Read_DMA(&hsram1, addr, buf, len);
HAL_SRAM_WriteOperation_Enable(&hsram1);       /* 使能写（不写外部器件时可关掉保护总线） */
HAL_SRAM_WriteOperation_Disable(&hsram1);
/* 大多数时候直接指针访问最快：*(__IO uint16_t*)0x60000000 = data; */
```

**NOR Flash**
```c
NOR_HandleTypeDef hnor;
HAL_NOR_Init(&hnor, &FMC_NORSRAM_Timing, &FMC_NORSRAM_Timing);
uint16_t id[3]; HAL_NOR_Read_ID(&hnor, &nor_id);
HAL_NOR_Read(&hnor, addr, &data);            HAL_NOR_ReadBuffer(&hnor, addr, pbuf, len);
HAL_NOR_Erase_Block(&hnor, blockaddr, addr); HAL_NOR_Erase_Chip(&hnor);
HAL_NOR_Program(&hnor, addr, &data);         HAL_NOR_ProgramBuffer(&hnor, addr, pbuf, len);
HAL_NOR_GetStatus(&hnor, addr, timeout);     HAL_NOR_ReturnToReadMode(&hnor);
HAL_NOR_Read_CFI(&hnor, (uint16_t*)addr, &cfi, HAL_NOR_STATUS_TIMEOUT);
HAL_NOR_WriteOperation_Enable(&hnor);        /* 写之前必须使能 */
```

**NAND Flash**
```c
NAND_HandleTypeDef hnand;
NAND_IDTypeDef nand_id;
HAL_NAND_Init(&hnand, &FMC_NAND_PCC_TimingStruct);
HAL_NAND_Reset(&hnand);   HAL_NAND_Read_ID(&hnand, &nand_id);
HAL_NAND_Read_Page_8b (&hnand, &nand_addr, pbuf, len);
HAL_NAND_Write_Page_8b(&hnand, &nand_addr, pbuf, len);
HAL_NAND_Read_Page_16b/Write_Page_16b(...);
HAL_NAND_Erase_Block(&hnand, &nand_addr);
HAL_NAND_ECC_Enable(&hnand);  HAL_NAND_GetECC(&hnand, &ecc, HAL_NAND_TIMEOUT_DEFAULT);
HAL_NAND_Read_Status(&hnand); HAL_NAND_Address_Inc(&hnand, &nand_addr);
HAL_NAND_IRQHandler(&hnand);  void HAL_NAND_ITCallback(NAND_HandleTypeDef *hnand) { }
```
> FMC 的 GPIO 和时序都在 `HAL_SRAM_MspInit()` / 生成的 `MX_FMC_Init()` 里；
> 并口屏（ST7796/ILI9488 等）一般是"写地址域 + 直写数据"：`*(__IO uint16_t*)0x60000000 = cmd;`
> `*(__IO uint16_t*)0x60020000 = data;`（地址线 RS 接 A16 之类，取决于你的接线）。

### 完整工程骨架（CubeMX 生成 + 你手写）

以 **FMC 驱动并口 LCD（8080 总线，16 位数据，RS 接 A16）**为例：

```c
/* ============ Core/Src/fmc.c —— CubeMX 生成 ============ */
SRAM_HandleTypeDef hsram1;

void MX_FMC_Init(void)
{
  FMC_NORSRAM_TimingTypeDef Timing = {0};
  FMC_NORSRAM_TimingTypeDef ExtTiming = {0};

  hsram1.Instance = FMC_NORSRAM_DEVICE;
  hsram1.Extended = FMC_NORSRAM_EXTENDED_DEVICE;
  hsram1.Init.NSBank             = FMC_NORSRAM_BANK1;
  hsram1.Init.DataAddressMux     = FMC_DATA_ADDRESS_MUX_DISABLE;
  hsram1.Init.MemoryType         = FMC_MEMORY_TYPE_SRAM;
  hsram1.Init.MemoryDataWidth    = FMC_NORSRAM_MEM_BUS_WIDTH_16;
  hsram1.Init.BurstAccessMode    = FMC_BURST_ACCESS_MODE_DISABLE;
  hsram1.Init.WaitSignalPolarity = FMC_WAIT_SIGNAL_POLARITY_LOW;
  hsram1.Init.WaitSignalActive   = FMC_WAIT_TIMING_BEFORE_WS;
  hsram1.Init.WriteOperation     = FMC_WRITE_OPERATION_ENABLE;
  hsram1.Init.WaitSignal         = FMC_WAIT_SIGNAL_DISABLE;
  hsram1.Init.ExtendedMode       = FMC_EXTENDED_MODE_DISABLE;
  hsram1.Init.AsynchronousWait   = FMC_ASYNCHRONOUS_WAIT_DISABLE;
  hsram1.Init.WriteBurst         = FMC_WRITE_BURST_DISABLE;
  hsram1.Init.ContinuousClock    = FMC_CONTINUOUS_CLOCK_SYNC_ONLY;

  /* 时序：按 LCD 手册（如 tAS/tWR ≥ 15ns）折算成 HCLK 周期 */
  Timing.AddressSetupTime      = 3;
  Timing.AddressHoldTime       = 1;
  Timing.DataSetupTime         = 6;
  Timing.BusTurnAroundDuration = 1;
  Timing.CLKDivision           = 2;
  Timing.DataLatency           = 2;
  Timing.AccessMode            = FMC_ACCESS_MODE_A;
  if (HAL_SRAM_Init(&hsram1, &Timing, &ExtTiming) != HAL_OK) { Error_Handler(); }
}

void HAL_SRAM_MspInit(SRAM_HandleTypeDef* hsram)
{
  GPIO_InitTypeDef GPIO_InitStruct = {0};
  if (hsram->Instance == FMC_NORSRAM_DEVICE)
  {
    __HAL_RCC_FMC_CLK_ENABLE();
    __HAL_RCC_GPIOD_CLK_ENABLE();  __HAL_RCC_GPIOE_CLK_ENABLE();
    /* 数据/地址/控制引脚全部配成 GPIO_MODE_AF_PP + GPIO_AF12_FMC + VERY_HIGH */
    GPIO_InitStruct.Mode      = GPIO_MODE_AF_PP;
    GPIO_InitStruct.Pull      = GPIO_NOPULL;
    GPIO_InitStruct.Speed     = GPIO_SPEED_FREQ_VERY_HIGH;
    GPIO_InitStruct.Alternate = GPIO_AF12_FMC;
    /* ... 具体引脚由 CubeMX 生成 ... */
    HAL_GPIO_Init(GPIOD, &GPIO_InitStruct);
  }
}
```

```c
/* ============ 你手写的部分 ============ */

/* ① 基址宏（RS=A16 → 地址偏移 0x20000；16 位总线要 ×2）*/
#define LCD_BASE        ((uint32_t)0x60000000)
#define LCD_CMD_ADDR    ((__IO uint16_t *)(LCD_BASE))
#define LCD_DATA_ADDR   ((__IO uint16_t *)(LCD_BASE + 0x40000))

/* ② 写命令 / 写数据 / 读数据（直写指针最快）*/
static inline void LCD_WriteCmd(uint16_t cmd) { *LCD_CMD_ADDR  = cmd; }
static inline void LCD_WriteData(uint16_t dat){ *LCD_DATA_ADDR = dat; }
static inline uint16_t LCD_ReadData(void)     { return *LCD_DATA_ADDR; }

/* ③ 典型初始化片段 */
LCD_WriteCmd(0x2C);                       /* 进入写显存模式 */
for (uint32_t i = 0; i < 320 * 480; i++) { *LCD_DATA_ADDR = 0xF800; }   /* 刷红 */

/* ④ 用 DMA 批量刷屏（比软件循环快得多）*/
void LCD_FlushDMA(uint16_t *buf, uint32_t pixels)
{
  HAL_SRAM_Write_DMA(&hsram1, LCD_DATA_ADDR, buf, pixels);
}

/* ⑤ 外部 SRAM 用法（Bank1 直读直写，就像一个数组）*/
#define EXRAM_BASE  ((uint32_t)0x60000000)
uint16_t *ext_buf = (uint16_t *)EXRAM_BASE;
ext_buf[0] = 0x1234;
uint16_t v = ext_buf[0];

/* ⑥ 需要禁止/使能写（防止误写外部器件）*/
HAL_SRAM_WriteOperation_Disable(&hsram1);
HAL_SRAM_WriteOperation_Enable(&hsram1);

/* ⑦ 如果用 NOR Flash（不是 SRAM）*/
// uint16_t id[3]; HAL_NOR_Read_ID(&hnor, &nor_id);
// HAL_NOR_WriteOperation_Enable(&hnor);
// HAL_NOR_Erase_Block(&hnor, blockAddr, addr);
// HAL_NOR_Program(&hnor, addr, &data);
```

**CubeMX 配置入口**：`Connectivity → FMC → NOR/PSRAM/SRAM` 选 `LCD Interface` 或 `SRAM`，
设 Data Width（16 位）、时序四要素；生成 `fmc.c` 与全部引脚配置。
**并口屏最常见的问题就是时序太快**——先按较慢的时序点亮，再逐步优化。

---

## 23. FLASH 内部 Flash 读写与选项字节

### 概览

**常用 API（擦 → 写 → 锁）**

| API | 一句话作用 |
|---|---|
| `HAL_FLASH_Unlock()` / `HAL_FLASH_Lock()` | 解锁 / 上锁 Flash 控制寄存器 |
| `HAL_FLASHEx_Erase(&EraseInitStruct, &PageError)` | 按页（或整片）擦除 |
| `HAL_FLASH_Program(FLASH_TYPEPROGRAM_DOUBLEWORD, addr, data64)` | 编程（G4 一次必须写 64 位） |
| `HAL_FLASH_GetError()` | 取错误码（WRP/PGA/SIZE/PGS/OPERR…） |
| `__HAL_FLASH_GET_FLAG()` / `__HAL_FLASH_CLEAR_FLAG()` | 查 / 清标志（BSY、EOP、各类错误） |

**不常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_FLASHEx_Erase_IT()` + `HAL_FLASH_IRQHandler()` | 中断方式擦除（擦除期间还能干别的活） |
| `HAL_FLASH_EndOfOperationCallback()` / `HAL_FLASH_OperationErrorCallback()` | 擦/写完成 / 出错回调 |
| `HAL_FLASH_OB_Unlock()` / `OB_Lock()` / `OB_Launch()` | 选项字节解锁 / 上锁 / **生效（会触发复位）** |
| `HAL_FLASHEx_OBProgram(&OBInit)` / `OBGetConfig(&OBInit)` | 写 / 读选项字节（写保护、读保护、BOR、用户选项、PCROP、安全区） |
| `HAL_FLASHEx_EnableDebugger()` / `DisableDebugger()` | 调试端口开关（安全/低功耗场景） |
| `HAL_FLASHEx_EnableRunPowerDown()` / `DisableRunPowerDown()` | 运行模式掉电（RAMFUNC 区） |

**关键选项速解**

- **`TypeErase`**：`FLASH_TYPEERASE_PAGES` 按页擦；`FLASH_TYPEERASE_MASSERASE` 整片擦。
- **`Banks` / `Page` / `NbPages`**：擦哪个 Bank、从第几页开始、擦几页（G4 双 Bank 时别搞错）。
- **`TypeProgram`**：`DOUBLEWORD`（常规，64 位对齐）；`FAST` / `FAST_AND_LAST`（连续快写，速度更快）。
- **写前必擦**：Flash 只能 1→0，想改回 1 必须先擦除。
- **地址对齐**：双字编程要求地址 8 字节对齐。
- **`OptionType`**：`WRP` 写保护（用 `WRPArea` + `WRPStartOffset/WRPEndOffset`）／`RDP` 读保护（`OB_RDP_LEVEL_x`）／
  `USER` 用户选项（`USERType`+`USERConfig`，如 IWDG 硬件/软件、复位行为、BOR 等级）／`PCROP` 专有代码保护／
  `SEC` 安全存储区／`BOOT_LOCK`。
- **注意**：`HAL_FLASH_OB_Launch()` 会**立即复位**芯片；擦写期间不能从同一 Bank 取指。


### 23.1 编程基本流程（擦 → 写 → 锁）
```c
FLASH_EraseInitTypeDef EraseInitStruct = {0};
uint32_t PageError = 0;

HAL_FLASH_Unlock();                                     /* ① 解锁 */
__HAL_FLASH_CLEAR_FLAG(FLASH_FLAG_EOP | FLASH_FLAG_OPERR | FLASH_FLAG_WRPERR |
                       FLASH_FLAG_PGAERR | FLASH_FLAG_PGSERR);   /* 清标志 */

/* ② 擦除（G4 按页，双 Bank 时注意 Banks 参数；也可以整片擦除 FLASH_TYPEERASE_MASSERASE） */
EraseInitStruct.TypeErase = FLASH_TYPEERASE_PAGES;
EraseInitStruct.Banks     = FLASH_BANK_1;
EraseInitStruct.Page      = 30;
EraseInitStruct.NbPages   = 1;
if (HAL_FLASHEx_Erase(&EraseInitStruct, &PageError) != HAL_OK) { Error_Handler(); }

/* ③ 写入：G4 一次写 64 位（双字） */
uint64_t data = 0x1234567890ABCDEFULL;
if (HAL_FLASH_Program(FLASH_TYPEPROGRAM_DOUBLEWORD, 0x0801F000, data) != HAL_OK)
{
  /* 出错码：HAL_FLASH_GetError() → FLASH_ERROR_WRP / PGA / SIZE / PGS / EOP */
  Error_Handler();
}
HAL_FLASH_Lock();                                       /* ④ 加锁 */
/* 中断方式擦除（需要 NVIC 使能 FLASH_IRQn） */
HAL_FLASHEx_Erase_IT(&EraseInitStruct);
void FLASH_IRQHandler(void) { HAL_FLASH_IRQHandler(); }  /* 注意：不传句柄 */
void HAL_FLASH_EndOfOperationCallback(uint32_t ReturnValue) { }
void HAL_FLASH_OperationErrorCallback(uint32_t ReturnValue)  { }
```
> 要点：① 擦除/写入是阻塞的（几 ms），操作期间**代码不能从同一 Bank 取指**，
> 一般把操作放在 RAM 或另一个 Bank，或接受短暂阻塞；
> ② 写之前必须先擦除（只能 1→0）；③ 地址必须 8 字节对齐（双字编程）；
> ④ 中断向量表放在被擦的页上时要先重映射（`HAL_FLASHEx_OBProgram` 改 BFB2 或做向量搬移）。

### 23.2 选项字节（复位保护、读写保护、BOR 等）
```c
FLASH_OBProgramInitTypeDef OBInit = {0};
HAL_FLASH_OB_Unlock();
OBInit.OptionType     = OPTIONBYTE_WRP;
OBInit.WRPArea        = OB_WRPAREA_BANK1_AREAA;
OBInit.WRPStartOffset = 0;               /* 写保护起始页 */
OBInit.WRPEndOffset   = 3;               /* 写保护结束页 */
HAL_FLASHEx_OBProgram(&OBInit);
HAL_FLASHEx_OBGetConfig(&OBInit);        /* 回读当前配置 */
HAL_FLASH_OB_Launch();                   /* 生效（会触发系统复位！） */
HAL_FLASH_OB_Lock();
/* 其它 OptionType：OPTIONBYTE_RDP + OBInit.RDPLevel = OB_RDP_LEVEL_1；
   OPTIONBYTE_USER + USERType/USERConfig = OB_USER_IWDG_SW | OB_BOR_LEVEL_3 … */
/* 调试端口控制（低功耗/安全场景） */
HAL_FLASHEx_EnableDebugger();   HAL_FLASHEx_DisableDebugger();
```
常用判断：`__HAL_FLASH_GET_FLAG(FLASH_FLAG_BSY)`（忙）、`__HAL_FLASH_CLEAR_FLAG(...)`。

### 完整工程骨架（CubeMX 生成 + 你手写）

**FLASH 没有 CubeMX 生成的外设文件**（`Core/Src/` 里不会有 `flash.c`），
所有代码都是你在自己的文件里手写。下面是可直接复用的最小实现：

```c
/* ============ 你手写的部分（建议单独建 Core/Src/flash_io.c）============ */

/* 注意：G4 一次编程必须写 64 位（双字），所以先做成缓冲区 */
typedef struct
{
  uint32_t magic;              /* 0xA5A5A5A5 表示数据有效 */
  uint32_t counter;
  float    calib;
  uint8_t  reserved[48];
} AppParam_t;

#define PARAM_ADDR   0x0801F800U        /* 选一个独立扇区做参数区 */
#define PARAM_PAGE   31                 /* 对应页号（按你的 Flash 容量算） */

/* ① 阻塞写一个双字（底层）*/
static uint8_t Flash_WriteDoubleWord(uint64_t dword, uint32_t addr)
{
  if (HAL_FLASH_Program(FLASH_TYPEPROGRAM_DOUBLEWORD, addr, dword) != HAL_OK)
  {
    return 0;                        /* 失败原因看 HAL_FLASH_GetError() */
  }
  return 1;
}

/* ② 擦除参数所在页（写之前必须先擦）*/
static uint8_t Flash_EraseParamPage(void)
{
  FLASH_EraseInitTypeDef EraseInit = {0};
  uint32_t PageError = 0;

  EraseInit.TypeErase = FLASH_TYPEERASE_PAGES;
  EraseInit.Banks     = FLASH_BANK_1;
  EraseInit.Page      = PARAM_PAGE;
  EraseInit.NbPages   = 1;

  return (HAL_FLASHEx_Erase(&EraseInit, &PageError) == HAL_OK);
}

/* ③ 保存参数（擦 → 按双字写 → 上锁）*/
uint8_t Param_Save(AppParam_t *p)
{
  uint8_t ok = 1;
  uint64_t *src = (uint64_t *)p;
  uint32_t n = (sizeof(AppParam_t) + 7) / 8;      /* 双字个数 */

  HAL_FLASH_Unlock();
  __HAL_FLASH_CLEAR_FLAG(FLASH_FLAG_ALL_ERRORS);

  ok &= Flash_EraseParamPage();
  for (uint32_t i = 0; i < n && ok; i++)
  {
    ok &= Flash_WriteDoubleWord(src[i], PARAM_ADDR + i * 8);
  }

  HAL_FLASH_Lock();
  return ok;
}

/* ④ 读取参数（Flash 可以直接像内存一样读）*/
const AppParam_t *Param_Get(void)
{
  const AppParam_t *p = (const AppParam_t *)PARAM_ADDR;
  return (p->magic == 0xA5A5A5A5U) ? p : 0;       /* 校验魔数 */
}

/* ⑤ 主流程用法 */
void Param_InitOrDefault(void)
{
  const AppParam_t *p = Param_Get();
  if (p) { g_param = *p; }                        /* 用掉电保存的值 */
  else
  {
    g_param.magic = 0xA5A5A5A5U;                  /* 首次上电写默认值 */
    g_param.counter = 0;
    g_param.calib = 1.0f;
    Param_Save(&g_param);
  }
}

/* ⑥ 中断方式擦除（擦除几毫秒，不想被阻塞时）*/
// FLASH_EraseInitTypeDef ei = {...};
// HAL_FLASHEx_Erase_IT(&ei);
void FLASH_IRQHandler(void) { HAL_FLASH_IRQHandler(); }          /* 注意：不传句柄 */
void HAL_FLASH_EndOfOperationCallback(uint32_t ReturnValue) { /* 擦完 */ }
void HAL_FLASH_OperationErrorCallback(uint32_t ReturnValue)  { /* 出错 */ }

/* ⑦ 选项字节：写保护 / 读保护 / BOR 等（会复位生效）*/
void OptionBytes_Setup(void)
{
  FLASH_OBProgramInitTypeDef ob = {0};
  HAL_FLASH_OB_Unlock();
  ob.OptionType     = OPTIONBYTE_USER;
  ob.USERType       = OB_USER_IWDG_SW | OB_USER_BOR_LEV;
  ob.USERConfig     = OB_IWDG_SW | OB_BOR_LEVEL_3;               /* 软件看门狗 + BOR3 */
  HAL_FLASHEx_OBProgram(&ob);
  HAL_FLASH_OB_Launch();                                          /* 立即复位生效 */
}

/* ⑧ 常用检查 */
if (__HAL_FLASH_GET_FLAG(FLASH_FLAG_BSY)) { /* 还在擦写，不能取指 */ }
uint32_t err = HAL_FLASH_GetError();        /* 出错码 */
```

**CubeMX 配置入口**：Flash 本体不需要配置；**选项字节**可以在 `System Core → ... → Option Bytes`
页里图形化配置（写保护/BOR/IWDG 硬件还是软件），生成到 `.ioc` 里，由 CubeMX 在下载时写入。

**关键约束（写错必翻车）**：
① 写之前必须先擦除；② 地址 8 字节对齐（双字）；③ 擦写期间不能从同一 Bank 取指（代码要放 RAM 或另一个 Bank）；
④ 参数区要挑一个**单独不与其他数据共用**的页；⑤ 别把参数区放到中断向量表所在页。

---

## 24. PWR 电源与低功耗模式

### 概览

**常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_PWR_EnterSLEEPMode(regulator, entry)` | Sleep：只停 CPU，外设照跑，任何中断都能唤醒 |
| `HAL_PWR_EnterSTOPMode(regulator, entry)` | Stop：时钟全停、SRAM 与寄存器保留，**唤醒后要重配时钟** |
| `HAL_PWREx_EnterSTOP0Mode(entry)` / `EnterSTOP1Mode(entry)` | G4 的 Stop0 / Stop1（Stop1 更省电、唤醒更慢） |
| `HAL_PWR_EnterSTANDBYMode()` | Standby：功耗极低，唤醒相当于复位重启 |
| `HAL_PWREx_EnterSHUTDOWNMode()` | Shutdown：最低功耗，唤醒也是复位重启 |
| `HAL_PWR_EnableWakeUpPin(polarity)` / `DisableWakeUpPin()` | 使能 / 关闭 WKUP 引脚唤醒（高/低电平） |
| `HAL_PWR_EnableBkUpAccess()` / `DisableBkUpAccess()` | 打开 / 关闭备份域访问（RTC、备份寄存器需要） |
| `__HAL_PWR_GET_FLAG(PWR_FLAG_WU/SB)` / `__HAL_PWR_CLEAR_FLAG(...)` | 判断唤醒来源、清标志 |

**不常用 API**

| API | 一句话作用 |
|---|---|
| `HAL_PWREx_EnableInternalWakeUpLine()` / `DisableInternalWakeUpLine()` | 内部唤醒线（RTC/LPTIM 等内部源唤醒） |
| `HAL_PWREx_EnableSRAM2ContentRetention()` / `Disable...` | Stop 模式下是否保留 SRAM2 内容 |
| `HAL_PWREx_EnablePullUpPullDownConfig()` / `EnableGPIOPullUp/Down()` / `Disable...` | 低功耗时给引脚维持上/下拉，避免漏电与误触发 |
| `HAL_PWR_ConfigPVD()` + `EnablePVD/DisablePVD` + `HAL_PWR_PVDCallback()` | 主电压监测（掉电预警） |
| `HAL_PWREx_ConfigPVM()` + `EnablePVM1~4/DisablePVM1~4` + `PVMxCallback()` | 外设电压监测（监控某个电源域） |
| `HAL_PWR_EnableSleepOnExit()` / `DisableSleepOnExit()` / `EnableSEVOnPend()` | 中断退出后是否直接回睡眠 / 挂起也发事件 |
| `HAL_PWREx_EnableLowPowerRunMode()` / `DisableLowPowerRunMode()` | LPRun（更低电压档运行） |
| `HAL_PWREx_EnableBatteryCharging()` / `DisableBatteryCharging()` | VBAT 电池充电 |
| `HAL_PWREx_GetVoltageRange()` / `HAL_PWR_DeInit()` | 查询电压档 / 复位 PWR |

**关键选项速解**

- **`regulator`**：`PWR_MAINREGULATOR_ON`（主调压器，唤醒快）/ `PWR_LOWPOWERREGULATOR_ON`（低功耗调压器，更省电）。
- **`entry`**：`PWR_SLEEPENTRY_WFI`（等中断唤醒）或 `_WFE`（等事件唤醒）。
- **电压档**：`PWR_REGULATOR_VOLTAGE_SCALE1/2`，档位越低越省电但主频上限越低（在 RCC 段配置）。
- **唤醒源**：EXTI（引脚）、RTC 闹钟/唤醒定时器、LPTIM、UART 唤醒…——**配完还要在 NVIC 里使能对应中断**。
- **Standby/Shutdown 区别**：都能达到 µA 级；Shutdown 更低但要靠 WKUP 引脚/RTC 唤醒，唤醒后靠
  `__HAL_PWR_GET_FLAG(PWR_FLAG_SB)` 判断是不是从待机唤醒。
- **低功耗前必做**：关掉不用的外设时钟、未用引脚设模拟输入、必要时保留 GPIO 上下拉。


CubeMX：**RCC/SYS** 里选调压器档位（`HAL_PWREx_ControlVoltageScaling(PWR_REGULATOR_VOLTAGE_SCALE1)`）；
`SYS → Power` 可设置 PVD/PVM；低功耗相关的唤醒源（EXTI、RTC、LPTIM、UART 唤醒）在各自外设里配置。

```c
/* ① Sleep：CPU 停、外设继续跑，任何中断唤醒（最省事的低功耗） */
HAL_PWR_EnterSLEEPMode(PWR_MAINREGULATOR_ON, PWR_SLEEPENTRY_WFI);

/* ② Stop：时钟全停（保留 SRAM/寄存器），功耗 ~µA 级 */
HAL_PWREx_EnterSTOP0Mode(PWR_STOPENTRY_WFI);      /* 或 HAL_PWR_EnterSTOPMode(PWR_LOWPOWERREGULATOR_ON, PWR_STOPENTRY_WFI) */
/* 唤醒后第一件事：时钟变回 HSI，必须重新配置时钟树！ */
SystemClock_Config();

/* ③ Standby：功耗最低（~1µA），唤醒相当于一次复位（走 main 从头开始） */
HAL_PWR_EnterSTANDBYMode();

/* ④ Shutdown（G4 特有，最低功耗） */
HAL_PWREx_EnterSHUTDOWNMode();

/* 唤醒引脚与备份域 */
HAL_PWR_EnableWakeUpPin(PWR_WAKEUP_PIN1_HIGH);
HAL_PWR_DisableWakeUpPin(PWR_WAKEUP_PIN1_HIGH);
HAL_PWR_EnableBkUpAccess();          /* 访问 RTC/备份寄存器前需要 */
HAL_PWREx_EnableInternalWakeUpLine();
HAL_PWREx_EnableSRAM2ContentRetention();   /* Stop 时保留 SRAM2 */
/* 状态标志 */
__HAL_PWR_GET_FLAG(PWR_FLAG_WU);  __HAL_PWR_CLEAR_FLAG(PWR_FLAG_WU);
/* 电压监测 */
HAL_PWR_ConfigPVD(&sConfigPVD);  HAL_PWR_EnablePVD();   HAL_PWR_PVDCallback();
HAL_PWREx_EnablePVM1();  HAL_PWREx_PVM1Callback();
```
> **重点**：① 低功耗前把未使用的 GPIO 设为模拟输入、关闭外设时钟；
> ② 唤醒后如果是 Stop 模式，`SystemClock_Config()` 必须重新调用（HSI 兜底）；
> ③ Standby/Shutdown 唤醒后程序是复位重启，靠 `__HAL_PWR_GET_FLAG(PWR_FLAG_SB)` 区分；
> ④ 调试低功耗时开 `HAL_DBGMCU_EnableDBGStopMode()`（在 `stm32g4xx_hal.h` 里，LL 也有）避免调试连不上。

### 完整工程骨架（CubeMX 生成 + 你手写）

**PWR 也没有独立的生成文件**（除了 `SystemClock_Config()` 里那句电压档设置），
低功耗的代码全在自己手里。下面是一套"能直接抄"的骨架：

```c
/* ============ main.c —— CubeMX 生成（电压档就这一句）============ */
void SystemClock_Config(void)
{
  HAL_PWREx_ControlVoltageScaling(PWR_REGULATOR_VOLTAGE_SCALE1);   /* 生成 */
  /* ... RCC 配置 ... */
}
```

```c
/* ============ 你手写的部分 ============ */

/* ① 低功耗前的统一准备：把不用的 GPIO 设成模拟输入，避免漏电 */
static void GPIO_LowPowerPrepare(void)
{
  GPIO_InitTypeDef g = {0};
  g.Mode = GPIO_MODE_ANALOG;
  g.Pull = GPIO_NOPULL;
  /* 逐个把未使用的 GPIO 端口配置一遍（只配用不到的引脚）*/
  __HAL_RCC_GPIOA_CLK_ENABLE();
  g.Pin = GPIO_PIN_All;                      /* 实际项目里要排除在用的引脚 */
  HAL_GPIO_Init(GPIOA, &g);
  /* ... 其它端口同理 ... */
}

/* ② 进入 Sleep：CPU 停、外设继续、任何中断唤醒 */
void Enter_Sleep(void)
{
  HAL_SuspendTick();                          /* 不想被 SysTick 立刻唤醒就挂起滴答 */
  HAL_PWR_EnterSLEEPMode(PWR_MAINREGULATOR_ON, PWR_SLEEPENTRY_WFI);
  HAL_ResumeTick();
}

/* ③ 进入 Stop（推荐用 Stop0/Stop1，G4 专用）：唤醒后必须重配时钟 */
void Enter_Stop_WithRTC(void)
{
  /* 3.1 先配置好唤醒源：RTC 唤醒定时器（见第 17 章）*/
  HAL_RTCEx_SetWakeUpTimer_IT(&hrtc, 2047, RTC_WAKEUPCLOCK_RTCCLK_DIV16);

  /* 3.2 挂起滴答、准备 GPIO */
  HAL_SuspendTick();
  GPIO_LowPowerPrepare();

  /* 3.3 进入 Stop0（低功耗调压器、WFI 唤醒）*/
  HAL_PWREx_EnterSTOP0Mode(PWR_STOPENTRY_WFI);

  /* 3.4 唤醒后：时钟变回 HSI，必须重新配置时钟树 */
  SystemClock_Config();
  HAL_ResumeTick();
  /* 重新初始化依赖时钟的外设（UART/SPI/ADC… 视情况而定）*/
}

/* ④ 进入 Standby / Shutdown：唤醒即复位重启，靠标志位区分 */
void Enter_Standby(void)
{
  HAL_PWR_EnableWakeUpPin(PWR_WAKEUP_PIN1_HIGH);   /* 用 WKUP 引脚唤醒 */
  __HAL_PWR_CLEAR_FLAG(PWR_FLAG_WU);
  HAL_PWR_EnterSTANDBYMode();                      /* 不会返回 */
}

/* ⑤ 上电先判断"是不是从低功耗醒来的" */
void CheckWakeupSource(void)
{
  if (__HAL_PWR_GET_FLAG(PWR_FLAG_SB))             /* Standby 唤醒 */
  {
    __HAL_PWR_CLEAR_FLAG(PWR_FLAG_SB);
    g_boot_reason = BOOT_FROM_STANDBY;
  }
  if (__HAL_PWR_GET_FLAG(PWR_FLAG_WU))             /* 唤醒引脚/内部唤醒线 */
  {
    __HAL_PWR_CLEAR_FLAG(PWR_FLAG_WU);
    g_boot_reason = BOOT_FROM_WAKEUP_PIN;
  }
}

/* ⑥ 备份域访问（读 RTC / 备份寄存器之前必须解锁）*/
HAL_PWR_EnableBkUpAccess();
uint32_t retained = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR2);

/* ⑦ 低功耗调试：冻结调试口，避免一进 Stop 就连不上 */
HAL_DBGMCU_EnableDBGStopMode();          /* 在 stm32g4xx_hal.h 里 */
HAL_PWREx_EnableInternalWakeUpLine();    /* 内部唤醒线（RTC/LPTIM）*/

/* ⑧ 主循环模板 */
while (1)
{
  DoSomething();
  if (idle_timeout) { Enter_Stop_WithRTC(); }     /* 空闲就睡 */
}
```

**CubeMX 配置入口**：PWR 本身在 `System Core → PWR` 里可开 PVD/PVM 监控；
低功耗模式不需要额外生成代码，但**唤醒源要在各自外设里配好**
（RTC 唤醒定时器 / LPTIM / EXTI 引脚 / UART 唤醒），并在 NVIC 里使能相应中断。

---

## 25. UCPD（USB Type-C PD，仅 LL 驱动）

### 概览

**常用（CubeMX 生成的 LL 调用 + 时钟）**

| API / 宏 | 一句话作用 |
|---|---|
| `__HAL_RCC_UCPD1_CLK_ENABLE()` | 打开 UCPD 外设时钟 |
| `HAL_RCCEx_PeriphCLKConfig(&PeriphClkInit)` | 给 UCPD 选时钟源（CubeMX 里生成在 MspInit） |
| `LL_UCPD_Init(UCPD1, &init)` | 初始化 UCPD（CC 引脚、滤波、接收顺序等） |
| `LL_UCPD_Enable(UCPD1)` / `LL_UCPD_Disable(UCPD1)` | 使能 / 关闭 UCPD |
| `LL_UCPD_SetCCPin(UCPD1, pin)` / `LL_UCPD_GetCCPinState()` | 选择当前使用的 CC 引脚 / 读 CC 状态 |
| `USBPD_DPM_*` 回调（中间件） | PD 协议层回调：连接、请求、接受、切换供电等 |

**不常用**

| API / 宏 | 一句话作用 |
|---|---|
| `HAL_PWREx_EnableUCPDDeadBattery()` / `Disable...` | 掉电电池模式（无 MCU 供电时也能被识别为 Sink） |
| `HAL_PWREx_EnableUCPDStandbyMode()` / `Disable...` | Standby 下保持 UCPD 唤醒能力 |
| `LL_UCPD_*` 其余宏（中断使能/标志/寄存器读写） | 低层收发与中断控制 |
| `HAL_PWREx_EnableBatteryCharging()` | VBAT 充电（与 PD 供电方案相关） |

**关键选项速解**

- **无 HAL 层**：G4 只提供 `stm32g4xx_ll_ucpd.h`，所以 CubeMX 生成的是 `LL_UCPD_*` 调用；
  协议栈要靠 ST 的 **USB-PD 中间件 / X-CUBE-TCPP**。
- **时钟源**：UCPD 需要专门的 UCPD 时钟（CubeMX 里选），漏了就不工作。
- **CC1 / CC2**：Type-C 的通道引脚，正插/反插各用一根，需按连接状态切换。
- **Dead Battery / Standby**：分别是"MCU 没供电时的识别"和"待机时的唤醒"，做 PD 产品必配。
- **硬件配套**：CC 线上一般要接 TCPP01-M12 类保护器件，VBUS 检测/泄放电路也要按 PD 方案设计。


G4 的 UCPD **没有 HAL 层驱动**（`Drivers/STM32G4xx_HAL_Driver/Inc` 里只有 `stm32g4xx_ll_ucpd.h`），
所以用法分两种：

1. **CubeMX 勾选 UCPD 后生成的是 LL 调用**，例如 `LL_UCPD_Init()`、`LL_UCPD_Enable()`、
   `LL_UCPD_Disable()`、`LL_UCPD_SetCCPin()`、`LL_UCPD_GetCCPinState()` 等
   （配合 `__HAL_RCC_UCPD1_CLK_ENABLE()` 与 `HAL_RCCEx_PeriphCLKConfig()` 给 UCPD 选时钟）。
2. **USB PD 协议栈**用 ST 的中间件：`X-CUBE-TCPP`（TCPP01/02 保护芯片）或 STM32 USB-PD
   中间件（CubeMX 中 `Middleware → USB-PD`），里面封装了策略引擎（PE）、协议层（PRL）、
   设备策略管理器（DPM），你只需要重写 `USBPD_DPM_*` 回调。

低功耗相关（掉电时 UCPD 仍要能识别连接）：
```c
HAL_PWREx_EnableUCPDDeadBattery();      /* Dead-battery 模式 */
HAL_PWREx_DisableUCPDDeadBattery();
HAL_PWREx_EnableUCPDStandbyMode();      /* Standby 下保持 UCPD 唤醒能力 */
HAL_PWREx_DisableUCPDStandbyMode();
```
> 典型硬件：CC1/CC2 需要接 TCPP01-M12 之类的保护器件，VDD 供电也要按 PD 方案设计（VBUS 检测/泄放）。

### 完整工程骨架（CubeMX 生成 + 你手写）

UCPD 的生成代码是 **LL 调用**（因为 G4 没有 UCPD 的 HAL 驱动），协议栈通常用 ST 的 USB-PD 中间件：

```c
/* ============ Core/Src/ucpd.c —— CubeMX 生成（LL 风格）============ */
UCPD_HandleTypeDef hucpd1;          /* 具体类型名以 CubeMX 生成为准 */

void MX_UCPD1_Init(void)
{
  /* 时钟源 + 时钟使能（CubeMX 生成）*/
  RCC_PeriphCLKInitTypeDef PeriphClkInit = {0};
  PeriphClkInit.PeriphClockSelection = RCC_PERIPHCLK_UCPD1;
  PeriphClkInit.Ucpd1ClockSelection  = RCC_UCPD1CLKSOURCE_HSI;    /* UCPD 专用时钟 */
  HAL_RCCEx_PeriphCLKConfig(&PeriphClkInit);
  __HAL_RCC_UCPD1_CLK_ENABLE();

  /* LL 初始化：CC 引脚、滤波、接收顺序等 */
  LL_UCPD_Init(UCPD1, &hucpd1);
  LL_UCPD_Enable(UCPD1);

  /* CC1/CC2 引脚配置（CubeMX 生成在 MspInit 里）*/
  LL_UCPD_SetCCPin(UCPD1, LL_UCPD_CCPIN_CC1);
}

/* ============ Core/Src/stm32g4xx_it.c —— CubeMX 生成 ============ */
void UCPD1_IRQHandler(void) { /* 由中间件/你的 LL 处理函数接管 */ }
```

```c
/* ============ 你手写的部分 ============ */

/* ① 用 ST 的 USB-PD 中间件时，主要工作是实现 DPM 回调（CubeMX 会生成回调框架）*/
void USBPD_DPM_Init(void)
{
  /* Middleware 里 USBD_PD / USBPD core 的初始化通常已经在 MX_USBPD_Init 里完成 */
}

/* 典型要你填的回调（函数名以你用的中间件版本为准）*/
void USBPD_DPM_Notification(uint8_t PortNum, USBPD_NotifyEventValue_TypeDef EventVal)
{
  switch (EventVal)
  {
    case USBPD_NOTIFY_POWER_EXPLICIT_CONTRACT:   /* PD 合同建立 */
      /* 通知电源部分按协商电压输出 */
      break;
    case USBPD_NOTIFY_DETACH:                    /* 拔出 */
      /* 复位供电状态 */
      break;
    default: break;
  }
}

/* ② 只要 CC 检测（不做完整 PD 协议）时，直接用 LL 读状态 */
uint32_t cc_state = LL_UCPD_GetCCPinState(UCPD1);
/* 切换使用哪根 CC（正插/反插识别后）*/
LL_UCPD_SetCCPin(UCPD1, LL_UCPD_CCPIN_CC2);

/* ③ 掉电电池/待机场景（PD 产品常配）*/
HAL_PWREx_EnableUCPDDeadBattery();        /* 无 MCU 供电时也能被识别 */
HAL_PWREx_EnableUCPDStandbyMode();        /* Standby 下保持 UCPD 唤醒 */

/* ④ 关闭 UCPD（不需要时省电）*/
LL_UCPD_Disable(UCPD1);
```

**CubeMX 配置入口**：`Connectivity → UCPD1` 勾选并配置 CC 引脚与时钟；
`Middleware → USB-PD`（如已安装）选择角色（Source / Sink / DRP）后，CubeMX 会生成协议栈框架，
你只需要在 `USBPD_DPM_*` 回调里写业务。
**硬件上 CC 线要接 TCPP01-M12 类保护器件**，VBUS 检测/泄放电路也要按 PD 方案设计。

---

## 附录 A：最常用宏速查

### 概览

本附录是**速查表**，不含新知识：

- **用法**：知道用哪个外设、但忘了宏/函数名时，按模块扫一眼即可；`&hxxx` 表示要传句柄。
- **下面的宏表**：按外设分组的最常用宏（改占空比、清标志、开关中断等"高频一行代码"）。
- **下面的回调表**：各外设的完成回调与错误回调，全部是 `__weak`，在任意 .c 里重写同名函数就生效。
- 想找**不常用**的 API，回对应章节的"概览 → 不常用 API"即可。


| 模块 | 宏 | 说明 |
|---|---|---|
| 时钟 | `__HAL_RCC_<外设>_CLK_ENABLE() / _DISABLE()` | 开/关外设时钟（MspInit 里必须） |
| 时钟 | `__HAL_RCC_GET_SYSCLK_SOURCE()`、`__HAL_RCC_GET_FLAG(RCC_FLAG_HSERDY)` | 查时钟状态 |
| GPIO | `HAL_GPIO_WritePin(x, pin, GPIO_PIN_SET/RESET)`、`HAL_GPIO_TogglePin()`、`HAL_GPIO_ReadPin()` | 读写/翻转 |
| EXTI | `__HAL_GPIO_EXTI_CLEAR_IT(pin)`、`__HAL_GPIO_EXTI_GET_IT(pin)` | 手动清/查 EXTI 标志 |
| TIM | `__HAL_TIM_SET_COMPARE(&htim, ch, v)` | **改占空比** |
| TIM | `__HAL_TIM_SET_AUTORELOAD(&htim, v)`、`__HAL_TIM_SET_PRESCALER()` | 改频率 |
| TIM | `__HAL_TIM_GET_COUNTER()/SET_COUNTER()` | 读/写计数（编码器位置） |
| TIM | `__HAL_TIM_ENABLE_IT(&htim, TIM_IT_UPDATE)`、`__HAL_TIM_GET_FLAG()`、`__HAL_TIM_CLEAR_FLAG()` | 中断源/标志 |
| HRTIM | `__HAL_HRTIM_SETCOMPARE/GETCOMPARE(&hhrtim, TimerIdx, CmpUnit, v)` | **改比较值（占空比）** |
| HRTIM | `__HAL_HRTIM_SETPERIOD/GETPERIOD`、`SETCOUNTER/GETCOUNTER`、`SETCLOCKPRESCALER` | 周期/计数/预分频 |
| HRTIM | `__HAL_HRTIM_ENABLE/DISABLE(&hhrtim, HRTIM_TIMERID_TIMER_x)` | 启停某个定时器 |
| HRTIM | `__HAL_HRTIM_TIMER_ENABLE_IT/DISABLE_IT/GET_FLAG/CLEAR_FLAG` | 定时器中断与标志 |
| UART | `__HAL_UART_ENABLE_IT(&huart, UART_IT_IDLE)`、`__HAL_UART_CLEAR_IDLEFLAG()` | 空闲中断 |
| UART | `__HAL_UART_CLEAR_OREFLAG(&huart)` | 清溢出（救活接收） |
| SPI/I2C | `__HAL_SPI_ENABLE/DISABLE`、`__HAL_I2C_ENABLE/DISABLE`、`__HAL_I2C_GET_FLAG()` | 基本控制 |
| ADC | `__HAL_ADC_ENABLE_IT(&hadc, ADC_IT_EOC)`、`__HAL_ADC_GET_FLAG/CLEAR_FLAG` | 中断与标志 |
| ADC | `__HAL_ADC_CALC_DATA_TO_VOLTAGE(vref_mV, raw, res)` | 电压换算 |
| DMA | `__HAL_DMA_GET_COUNTER(&hdma)`、`__HAL_DMA_ENABLE_IT(&hdma, DMA_IT_HT)`、`__HAL_LINKDMA()` | 计数/中断/关联 |
| RTC | `__HAL_RTC_ALARM_ENABLE_IT()`、`__HAL_RTC_ALARM_CLEAR_FLAG()`、`__HAL_RTC_WAKEUPTIMER_ENABLE_IT()` | 闹钟/唤醒 |
| Flash | `__HAL_FLASH_GET_FLAG(FLASH_FLAG_BSY)`、`__HAL_FLASH_CLEAR_FLAG(FLASH_FLAG_EOP)` | 状态与清标志 |
| PWR | `__HAL_PWR_GET_FLAG(PWR_FLAG_WU)`、`__HAL_PWR_CLEAR_FLAG(PWR_FLAG_SB)` | 唤醒源判断 |
| 看门狗 | `__HAL_IWDG_START/RELOAD_COUNTER`、`__HAL_WWDG_ENABLE_IT(WWDG_IT_EWI)` | 看门狗 |
| CORDIC | `HAL_CORDIC_CalculateZO()` | 零开销流水计算 |

**回调速查（`__weak`，重写即可）**

| 外设 | 完成/事件回调 | 错误回调 |
|---|---|---|
| GPIO | `HAL_GPIO_EXTI_Callback(pin)` | — |
| TIM | `HAL_TIM_PeriodElapsedCallback` / `IC_CaptureCallback` / `PWM_PulseFinishedCallback` / `TriggerCallback` | `HAL_TIM_ErrorCallback` |
| HRTIM | `RepetitionEventCallback` / `CompareNEventCallback` / `CaptureNEventCallback` / `FaultNCallback` | `HAL_HRTIM_ErrorCallback` |
| UART | `TxCpltCallback` / `RxCpltCallback` / `HAL_UARTEx_RxEventCallback` | `HAL_UART_ErrorCallback` |
| SPI | `TxCpltCallback` / `RxCpltCallback` / `TxRxCpltCallback` | `HAL_SPI_ErrorCallback` |
| I2C | `MasterTxCpltCallback` / `MemRxCpltCallback` / `AddrCallback` | `HAL_I2C_ErrorCallback` |
| ADC | `HAL_ADC_ConvCpltCallback` / `HAL_ADCEx_InjectedConvCpltCallback` | `HAL_ADC_ErrorCallback` |
| DAC | `HAL_DAC_ConvCpltCallbackCh1` | `HAL_DAC_ErrorCallbackCh1` |
| CAN | `HAL_FDCAN_RxFifo0Callback` / `TxFifoEmptyCallback` | `HAL_FDCAN_ErrorStatusCallback` |
| 其它 | `HAL_RTC_AlarmAEventCallback`、`HAL_RTCEx_WakeUpTimerEventCallback`、`HAL_IWDG/WWDG_...`、`HAL_CORDIC_CalculateCpltCallback`、`HAL_FMAC_OutputDataReadyCallback` | 各自的 `ErrorCallback` |

---

## 附录 B：常见坑与排查清单

### 概览

本附录是**排错流程**，不含新知识：

- **第一步**：先看"通用"8 条 —— 外设"完全不工作"的原因 90% 在这几条里（时钟没开、NVIC 没使能、回调没对上）。
- **第二步**：按"症状"查下面那张逐外设表（症状 → 原因 → 解决），对号入座。
- **第三步**：还找不到就用 `HAL_xxx_GetState()` / `HAL_xxx_GetError()` 打印状态与错误码，
  再用示波器/逻辑分析仪看引脚波形，比改代码快得多。


**通用**
1. 忘了 `__HAL_RCC_xxx_CLK_ENABLE()` → 外设写不进配置、寄存器全 0。
2. 用了 `_IT`/`_DMA` 版本但没在 NVIC 里使能对应中断 → 只有第一次成功（轮询完成）后面全卡。
3. 回调没触发：先确认 `xxx_IRQHandler` 在 `stm32g4xx_it.c` 里、NVIC 使能、`HAL_xxx_IRQHandler(&h)` 被调用。
4. 用 `_DMA` 时缓冲区不能是**局部变量**（函数退出就失效）。
5. 同一外设重复调用 `HAL_xxx_Init()` 会 reset 状态机，运行中改参数应使用 `_Config`/宏。
6. `HAL_Delay()` 依赖 SysTick：中断里、关中断时、RTOS 下要特别注意。
7. 时钟树改错（尤其 APB 分频）会让所有外设速率、串口波特率都不对。
8. 低功耗 Stop 唤醒后忘记 `SystemClock_Config()`。

**逐外设高频坑**

| 外设 | 症状 | 原因与解决 |
|---|---|---|
| GPIO/EXTI | 中断进不去或进多次 | EXTI 线号复用冲突；标志未清；抖动需滤波/消抖 |
| TIM | PWM 无输出 | `HAL_TIM_PWM_Start()` 没调用；引脚没在 MspPostInit 配成 AF；ARR/PSC 算错 |
| TIM | 占空比不变 | 改了 `Pulse` 但没 `HAL_TIM_PWM_ConfigChannel()` 重新配置；或有预装载需等更新事件 |
| HRTIM | 输出一直是错误电平 | 先启动计数后使能输出；`IdleLevel` 设反；DLL 没校准 |
| HRTIM | 分辨率只有普通定时器水平 | 没用 MUL32 预分频 或 没做 DLL 校准 |
| UART | 只能收到一帧 | 忘了在回调里重新 `HAL_UART_Receive_IT/DMA()`；ORE 错误没清 |
| UART | 波特率不对 | 时钟源选择（`RCC_USART1CLKSOURCE_*`）与 CubeMX 计算不一致 |
| SPI | 数据错位 | CPOL/CPHA 与从机不匹配；NSS 时序；高速时需延时 |
| I2C | 一直 BUSY / AF | 从机地址没左移、上拉缺失、总线被拉死（DeInit+重初始化恢复） |
| ADC | 值漂移/不准 | 没校准 `HAL_ADCEx_Calibration_Start()`；采样时间太短；参考电压/地干扰 |
| ADC+DMA | 只采一次 | `DMAContinuousRequests = DISABLE` 且 DMA 非循环模式 |
| DAC | 波形频率不对 | 触发源没选 TIM，或 TIM 没 Start；DMA 不是循环模式 |
| FDCAN | 收不到任何报文 | 过滤器未配置/配置为 reject；终端电阻缺失；采样点不对 |
| RTC | 时间不走 / Init 超时 | LSE 未起振（换 LSI 或等起振）；没给 RTC 时钟源 |
| USB | 电脑不识别 | 48MHz 时钟（HSI48/PLLQ）；CDC 忘了 `USBD_CDC_ReceivePacket` |
| QSPI | 读出的数据全 FF | 指令/线宽/DummyCycles 与 Flash 型号不匹配；没进 MemoryMapped |
| Flash | 写失败 | 没解锁、没先擦除、地址未 8 字节对齐、在写的同时从该 Bank 取指 |
| 看门狗 | 莫名复位 | IWDG 调试断点触发；WWDG 喂狗不在窗口内 |

---

*文档完。基准工程：`D:\project\STM32\HAL\STM32G474RBT6`（STM32G474RBT6，STM32Cube HAL for STM32G4）。
文中函数/宏均与该工程 `Drivers/STM32G4xx_HAL_Driver/Inc` 下的头文件核对过；
换其它系列时请以对应系列头文件为准（差异主要在 `xxxEx_` 扩展函数与新增外设）。*
