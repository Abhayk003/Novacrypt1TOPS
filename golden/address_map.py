from memory import (
    BOOT_ROM_BASE, BOOT_ROM_LIMIT,
    IMEM_BASE, IMEM_LIMIT,
    DMEM_BASE, DMEM_LIMIT,
    UART_BASE, TIMER_BASE,
    I2C_BASE, SPI_BASE, GPIO_BASE,
    CLINT_BASE,
    PLIC_BASE, PLIC_LIMIT,
)

def decode_address(addr):

    addr &= 0xFFFFFFFF

    # Boot ROM
    if BOOT_ROM_BASE <= addr <= BOOT_ROM_LIMIT:
        return "BOOT_ROM"

    # Instruction SRAM
    if IMEM_BASE <= addr <= IMEM_LIMIT:
        return "IMEM"

    # Data SRAM
    if DMEM_BASE <= addr <= DMEM_LIMIT:
        return "DMEM"

    # PLIC has priority over the broad APB window.
    if PLIC_BASE <= addr <= PLIC_LIMIT:
        return "PLIC"

    # APB peripherals
    if UART_BASE <= addr < UART_BASE + 0x1000:
        return "UART"

    if TIMER_BASE <= addr < TIMER_BASE + 0x1000:
        return "TIMER"

    if I2C_BASE <= addr < I2C_BASE + 0x1000:
        return "I2C"

    if SPI_BASE <= addr < SPI_BASE + 0x1000:
        return "SPI"

    if GPIO_BASE <= addr < GPIO_BASE + 0x1000:
        return "GPIO"

    # CLINT
    if CLINT_BASE <= addr < CLINT_BASE + 0xC000:
        return "CLINT"

    # Remaining APB window
    if 0x10000000 <= addr <= 0x10BFFFFF:
        return "APB_RESERVED"

    return "UNMAPPED"