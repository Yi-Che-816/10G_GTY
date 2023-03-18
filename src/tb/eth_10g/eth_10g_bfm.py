import logging

import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, Edge
from cocotb.queue import QueueEmpty, Queue
from cocotb.clock import Clock

from pyuvm import utility_classes

from cocotbext.axi import (AxiStreamBus, AxiStreamSource, AxiStreamSink, AxiStreamMonitor)

import debugpy

class Eth10gBfm(metaclass=utility_classes.Singleton):
    def __init__(self):
        self.dut = cocotb.top
        self.tx_driver_queue = Queue(maxsize=1)
        self.tx_monitor_queue = Queue(maxsize=0)
        self.rx_monitor_queue = Queue(maxsize=0)

        self.tx_axis_source = AxiStreamSource(AxiStreamBus.from_prefix(self.dut, "s00_axis"), 
                                                self.dut.xver_tx_clk, self.dut.i_rx_reset)
        

        self.tx_axis_monitor = AxiStreamMonitor(AxiStreamBus.from_prefix(self.dut, "s00_axis"), 
                                                self.dut.xver_tx_clk, self.dut.i_rx_reset)
        

        self.rx_axis_monitor = AxiStreamMonitor(AxiStreamBus.from_prefix(self.dut, "m00_axis"), 
                                                self.dut.xver_rx_clk, self.dut.i_tx_reset)
        

    def set_axis_log(self, enable):
        self.tx_axis_source.log.propagate = enable
        self.tx_axis_monitor.log.propagate = enable
        self.rx_axis_monitor.log.propagate = enable
       
    async def loopback(self, delay=1):
        async def capture_outputs(self, q, delay):
            for _ in range(delay): await q.put([0, 0, 0])
            while True:
                await RisingEdge(self.dut.xver_tx_clk)
                
                xver_tx_data = self.dut.xver_tx_data.value
                xver_tx_header = self.dut.xver_tx_header.value
                xver_tx_gearbox_sequence = self.dut.xver_tx_gearbox_sequence.value != self.gearbox_pause_val

                await q.put([xver_tx_data, xver_tx_header, xver_tx_gearbox_sequence])

        async def apply_input(self, q):
            while True:
                await RisingEdge(self.dut.xver_rx_clk)
                [xver_tx_data, xver_tx_header, xver_tx_gearbox_sequence] = await q.get()
                
                self.dut.xver_rx_data.value = xver_tx_data
                self.dut.xver_rx_header.value = xver_tx_header
                self.dut.xver_rx_gearbox_valid.value = xver_tx_gearbox_sequence

        q = Queue()
        cocotb.start_soon(capture_outputs(self, q, delay))
        cocotb.start_soon(apply_input(self, q))

    async def send_tx_packet(self, packet):
        await self.tx_driver_queue.put(packet)

    async def reset(self):
        self.dut.i_tx_reset.value = 1
        self.dut.i_rx_reset.value = 1
        self.dut.xver_rx_clk.value = 0
        self.dut.xver_rx_data.value = 0
        self.dut.xver_tx_clk.value = 0
        await RisingEdge(self.dut.xver_rx_clk)
        await RisingEdge(self.dut.xver_tx_clk)
        await FallingEdge(self.dut.xver_rx_clk)
        await FallingEdge(self.dut.xver_tx_clk)
        self.dut.i_tx_reset.value = 0
        self.dut.i_rx_reset.value = 0
        await RisingEdge(self.dut.xver_rx_clk)
        await RisingEdge(self.dut.xver_tx_clk)

    async def pause(self, cycles):
        for _ in range(cycles):
            await RisingEdge(self.dut.xver_tx_clk)

    async def driver_bfm(self):
        while True:
            packet = await self.tx_driver_queue.get()
            await self.tx_axis_source.send(packet.tobytes())
            await self.tx_axis_source.wait()


    async def tx_monitor_bfm(self):
        while True:
            packet = await self.tx_axis_monitor.recv()
            self.tx_monitor_queue.put_nowait(packet)
    
    async def rx_monitor_bfm(self):
        while True:
            packet = await self.rx_axis_monitor.recv(compact=False)
            packet = self.compact_axis_no_tuser(packet)
            self.rx_monitor_queue.put_nowait(packet)

    async def get_tx_frame(self):
        return await self.tx_monitor_queue.get()

    async def get_rx_frame(self):
        return await self.rx_monitor_queue.get()
            

    async def start_bfm(self):
        self.data_width = len(self.dut.xgmii_tx_data)
        self.data_nbytes = self.data_width // 8
        self.gearbox_pause_val = 32
        self.clk_period = round(1 / (10.3125 / self.data_width), 2) # ps precision
        
        cocotb.start_soon(Clock(self.dut.xver_tx_clk, self.clk_period, units="ns").start())
        cocotb.start_soon(Clock(self.dut.xver_rx_clk, self.clk_period, units="ns").start())
        

        await self.reset()
        cocotb.start_soon(self.loopback())
        cocotb.start_soon(self.driver_bfm())
        cocotb.start_soon(self.tx_monitor_bfm())
        cocotb.start_soon(self.rx_monitor_bfm())


    # A copy of AxiStreamFrame::compact but does not remvove tuser when tkeep = 0
    @staticmethod
    def compact_axis_no_tuser(frame):
        if len(frame.tkeep):
            # remove tkeep=0 bytes
            for k in range(len(frame.tdata)-1, -1, -1):
                if not frame.tkeep[k]:
                    if k < len(frame.tdata):
                        del frame.tdata[k]
                    if k < len(frame.tkeep):
                        del frame.tkeep[k]
                    if k < len(frame.tid):
                        del frame.tid[k]
                    if k < len(frame.tdest):
                        del frame.tdest[k]

        # remove tkeep
        frame.tkeep = None

        # clean up other sideband signals
        # either remove or consolidate if values are identical
        if len(frame.tid) == 0:
            frame.tid = None
        elif all(frame.tid[0] == i for i in frame.tid):
            frame.tid = frame.tid[0]

        if len(frame.tdest) == 0:
            frame.tdest = None
        elif all(frame.tdest[0] == i for i in frame.tdest):
            frame.tdest = frame.tdest[0]

        if len(frame.tuser) == 0:
            frame.tuser = None
        elif all(frame.tuser[0] == i for i in frame.tuser):
            frame.tuser = frame.tuser[0]

        return frame

        



    