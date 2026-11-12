/* /variants/kjern32u4hidc/kjern_boot.c
 *
 * Kjern-32u4HID-C early boot hook. Runs in .init3, before any sketch code, USB setup or
 * global constructors, so a misbehaving sketch (for example a keyboard that types on its own)
 * can never lock the user out.
 *
 * Rules, checked on every reset:
 *   1. watchdog reset with the IDE's 0x7777 upload key set  -> DFU (Arduino IDE upload button)
 *   2. PB0 pulled LOW (strap to GND)                        -> DFU
 *   3. anything else                                         -> sketch
 * PB0 is read with the internal pull-up on (the AVR has no internal pull-downs), so an open PB0
 * reads HIGH and the sketch runs. Afterwards PB0 is put back to its reset state (input, no pull-up).
 * Hardware fallback stays: HWB-GND jumper (JP3) + RESET forces DFU through the HWBE fuse.
 *
 * Bootloader: DFU in the 4 KB boot section at 0x7000 (Microchip factory or the Kjern LUFA build),
 * BOOTRST off so every reset starts here. Works with CKDIV8 programmed or not.
 *
 * Upload key location: the core writes 0x7777 to MAGIC_KEY_POS (0x0800), or to RAMEND-1 when the
 * bootloader carries the LUFA signature at FLASHEND-1. RAMEND-1 is the top of the stack, so it is
 * read in the naked .init3 stub before the first call overwrites it.
 */
#include <avr/io.h>
#include <avr/wdt.h>
#include <avr/power.h>
#include <util/delay.h>
#include <stdint.h>

#define KJERN_BOOTLOADER_START 0x7000          /* byte address of the DFU bootloader */
#ifndef MAGIC_KEY_POS
#define MAGIC_KEY_POS 0x0800
#endif
#define KJERN_MAGIC_KEY        0x7777          /* written by the core's CDC 1200 bps touch */

/* reset cause, readable from a sketch: extern "C" volatile uint8_t kjern_reset_flags; */
volatile uint8_t kjern_reset_flags __attribute__((section(".noinit"), used));

static void kjern_enter_dfu(void)
{
    *(volatile uint16_t *)(MAGIC_KEY_POS) = 0;     /* clear so "launch" after flashing runs the sketch */
    *(volatile uint16_t *)(RAMEND - 1) = 0;
    asm volatile ("jmp %0" :: "i" (KJERN_BOOTLOADER_START));
}

static uint8_t kjern_strap_low(void)
{
    uint8_t low = 0, i;
    DDRB  &= ~_BV(PB0);                         /* input */
    PORTB |=  _BV(PB0);                         /* internal pull-up */
    _delay_ms(2);                               /* let the pin settle through any trace capacitance */
    for (i = 0; i < 8; i++) {                   /* must read LOW every time, ignores a single glitch */
        if (PINB & _BV(PB0)) { low = 0; break; }
        low = 1;
        _delay_us(100);
    }
    PORTB &= ~_BV(PB0);                         /* back to reset state: input, no pull-up */
    return low;
}

static void kjern_boot_check(uint16_t stack_top_key) __attribute__((used, noinline));
static void kjern_boot_check(uint16_t stack_top_key)
{
    uint8_t flags = MCUSR;
    MCUSR = 0;
    wdt_disable();                              /* must happen early after a watchdog reset */
#ifdef KJERN_CPU_DIV2
    clock_prescale_set(clock_div_2);            /* diagnostic: CPU at 8 MHz, USB PLL still fed 16 MHz */
#else
    clock_prescale_set(clock_div_1);            /* in case CKDIV8 is programmed: run at 16 MHz */
#endif
    kjern_reset_flags = flags;

    if ((flags & _BV(WDRF)) &&
        (stack_top_key == KJERN_MAGIC_KEY || *(volatile uint16_t *)(MAGIC_KEY_POS) == KJERN_MAGIC_KEY))
        kjern_enter_dfu();

    if (kjern_strap_low())
        kjern_enter_dfu();
}

/* .init3 runs after the stack pointer and r1 are set, before .data/.bss init and main() */
void kjern_init3(void) __attribute__((naked, used, section(".init3")));
void kjern_init3(void)
{
    kjern_boot_check(*(volatile uint16_t *)(RAMEND - 1));
}
