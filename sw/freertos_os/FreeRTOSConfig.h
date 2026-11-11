/* FreeRTOSConfig.h - tailored to the RV32IM custom SoC.
 *
 * CLINT (standard SiFive layout, verified):
 *   base 0x10010000 ; msip @ +0x0 ; mtimecmp @ +0x4000 ; mtime @ +0xBFF8
 *   mtime free-runs at 1 increment per CPU clock cycle.
 *
 * SIMULATION NOTE: the RISC-V port sets the tick compare to
 *   mtimecmp = mtime + (configCPU_CLOCK_HZ / configTICK_RATE_HZ).
 * Since mtime increments once per cycle, that quotient is the number of CYCLES
 * between ticks. For fast simulation keep it small (a few hundred cycles), so
 * here configCPU_CLOCK_HZ is set to a SIM-friendly fictitious value, not the
 * real 100 MHz. Raise it for hardware. See the TICK section below.
 */
#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

/* ---- CLINT / timer addresses (your SoC) ---- */
#define configMTIME_BASE_ADDRESS      ( 0x1001BFF8UL )   /* mtime    (base + 0xBFF8) */
#define configMTIMECMP_BASE_ADDRESS   ( 0x10014000UL )   /* mtimecmp (base + 0x4000) */

/* ---- Scheduler basics ---- */
#define configUSE_PREEMPTION                    1
#define configUSE_IDLE_HOOK                     0
#define configUSE_TICK_HOOK                     0
#define configUSE_16_BIT_TICKS                  0

/* ---- Clock / tick ----
 * mtime ticks once per cycle. ticks-between-interrupts = CPU_CLOCK_HZ/TICK_RATE_HZ.
 * For SIM we want that quotient SMALL. 100000/1000 = 100 cycles per tick: a tick
 * fires every 100 clocks, so you see scheduling within a short sim. For real
 * hardware set configCPU_CLOCK_HZ to the true clock (e.g. 100000000).
 */
#define configCPU_CLOCK_HZ                      ( 10000000UL ) /* SIM value: 10000 cyc/tick so tasks can run between ticks */
#define configTICK_RATE_HZ                      ( 1000 )       /* -> 100 cycles/tick in sim */

/* ---- Memory ---- */
#define configMINIMAL_STACK_SIZE                ( 128 )        /* words */
#define configTOTAL_HEAP_SIZE                   ( 16 * 1024 )  /* heap_4, in D-SRAM */
#define configENABLE_HEAP_PROTECTOR             0   /* no pointer obfuscation (no entropy source on bare metal) */
#define configHEAP_CLEAR_MEMORY_ON_FREE         0
#define configMAX_PRIORITIES                    ( 5 )
#define configMAX_TASK_NAME_LEN                 ( 12 )
#define configSUPPORT_STATIC_ALLOCATION         0
#define configSUPPORT_DYNAMIC_ALLOCATION        1

/* ---- ISR stack (the RISC-V port uses a dedicated interrupt stack) ---- */
#define configISR_STACK_SIZE_WORDS              ( 256 )

/* ---- Hooks / checks (lean for bring-up) ---- */
#define configCHECK_FOR_STACK_OVERFLOW          0
#define configUSE_MALLOC_FAILED_HOOK            0
#define configUSE_MUTEXES                       1
#define configUSE_COUNTING_SEMAPHORES           1
#define configUSE_QUEUE_SETS                    0
#define configUSE_TASK_NOTIFICATIONS            1

/* ---- Software timers (off for first bring-up; enable later) ---- */
#define configUSE_TIMERS                        0
#define configTIMER_TASK_PRIORITY               ( 2 )
#define configTIMER_QUEUE_LENGTH                10
#define configTIMER_TASK_STACK_DEPTH            ( 128 )

/* ---- API inclusion ---- */
#define INCLUDE_vTaskPrioritySet                1
#define INCLUDE_uxTaskPriorityGet               1
#define INCLUDE_vTaskDelete                     1
#define INCLUDE_vTaskSuspend                    1
#define INCLUDE_vTaskDelayUntil                 1
#define INCLUDE_vTaskDelay                      1
#define INCLUDE_xTaskGetSchedulerState          1

/* ---- Assert (route to a trap/print during bring-up) ---- */
extern void vAssertCalled( const char *file, int line );
#define configASSERT( x ) if( ( x ) == 0 ) vAssertCalled( __FILE__, __LINE__ )

/* The RISC-V port needs these mapped to the kernel handlers. portASM.S provides
 * the trap entry; we route the trap vector to freertos_risc_v_trap_handler in
 * crt0/trap setup. */
#define xPortStartScheduler             xPortStartScheduler

#endif /* FREERTOS_CONFIG_H */