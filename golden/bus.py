
"""
bus.py

Centralized data-access routing for the SoC golden model.
"""

import clint
from memory import Memory


class BusAccessError(Exception):
    pass


class MemoryBus:

    def __init__(self, memory: Memory):
        self.memory = memory

        # Peripheral models will be registered here.
        self.peripherals = {}

    def register_peripheral(self, name, peripheral):
        self.peripherals[name] = peripheral

    def read(self, state, addr, size):

        addr &= 0xFFFFFFFF

        # CLINT
        if clint.is_clint_address(addr):
            return clint.clint_read(state, addr, size)

        # Ordinary memory
        if size == 1:
            return self.memory.read8(addr)

        elif size == 2:
            return self.memory.read16(addr)

        elif size == 4:
            return self.memory.read32(addr)

        raise BusAccessError(
            f"Unsupported read size: {size}"
        )

    def write(self, state, addr, value, size):

        addr &= 0xFFFFFFFF

        # CLINT
        if clint.is_clint_address(addr):
            clint.clint_write(state, addr, value, size)
            return

        # Ordinary memory
        if size == 1:
            self.memory.write8(addr, value)

        elif size == 2:
            self.memory.write16(addr, value)

        elif size == 4:
            self.memory.write32(addr, value)

        else:
            raise BusAccessError(
                f"Unsupported write size: {size}"
            )
