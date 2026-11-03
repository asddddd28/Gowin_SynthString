"""Use the installed FTDI driver for bounded UART transfers at 1 ms latency.

Only the previously identified UART channel B is opened. Latency is restored
on close. No registry changes, driver installation or MPSSE pin changes.
"""
import ctypes as c
import sys
import time

from pathlib import Path

DIAG=Path(__file__).resolve().parents[4]/'demo_test/diagnostics/sd_card'
sys.path.insert(0,str(DIAG))
from sd_transport import Bridge
from spec.semantic_model import encode,decode


class D2xxBridge(Bridge):
    def __init__(self):
        self.dll=c.WinDLL('C:/Gowin/Gowin_V1.9.11.03_Education_x64/Programmer/bin/data/DLL/ftdi/x64/ftd2xx64.dll')
        self.handle=c.c_void_p()
        self.original_latency=c.c_ubyte()
        self.seq=0;self.frames=0;self.fast=False;self.cs=True
        self.open=False
        dword=c.c_ulong;ptr=c.c_void_p
        signatures={'FT_OpenEx':[ptr,dword,c.POINTER(ptr)],'FT_Close':[ptr],
            'FT_GetDeviceInfo':[ptr,c.POINTER(dword),c.POINTER(dword),ptr,ptr,ptr],
            'FT_SetBaudRate':[ptr,dword],'FT_SetDataCharacteristics':[ptr,c.c_ubyte,c.c_ubyte,c.c_ubyte],
            'FT_SetFlowControl':[ptr,c.c_ushort,c.c_ubyte,c.c_ubyte],
            'FT_ClrDtr':[ptr],'FT_ClrRts':[ptr],'FT_Purge':[ptr,dword],
            'FT_SetTimeouts':[ptr,dword,dword],
            'FT_GetLatencyTimer':[ptr,c.POINTER(c.c_ubyte)],'FT_SetLatencyTimer':[ptr,c.c_ubyte],
            'FT_Read':[ptr,ptr,dword,c.POINTER(dword)],'FT_Write':[ptr,ptr,dword,c.POINTER(dword)]}
        for name,args in signatures.items():
            f=getattr(self.dll,name);f.argtypes=args;f.restype=dword
        self.call('FT_OpenEx',c.cast(c.c_char_p(b'2025030317B'),ptr),1,c.byref(self.handle));self.open=True
        try:
            kind=dword();identity=dword();serial=c.create_string_buffer(16);description=c.create_string_buffer(64)
            self.call('FT_GetDeviceInfo',self.handle,c.byref(kind),c.byref(identity),serial,description,None)
            assert serial.value==b'2025030317B' and identity.value==0x04036010,(serial.value,hex(identity.value))
            self.call('FT_GetLatencyTimer',self.handle,c.byref(self.original_latency))
            self.call('FT_ClrDtr',self.handle);self.call('FT_ClrRts',self.handle)
            self.call('FT_SetBaudRate',self.handle,115200)
            self.call('FT_SetDataCharacteristics',self.handle,8,0,0)
            self.call('FT_SetFlowControl',self.handle,0,0,0)
            self.call('FT_SetTimeouts',self.handle,1000,1000)
            self.call('FT_SetLatencyTimer',self.handle,1)
            self.call('FT_Purge',self.handle,3)
            assert self.packet(8,bytes(8))==b'SDBR01\0\1'
        except BaseException:
            self.close_driver();raise
    def call(self,name,*args):
        result=getattr(self.dll,name)(*args)
        if result!=0:raise IOError(f'{name}: FT_STATUS={result}')
    def read_exact(self,size):
        result=bytearray();deadline=time.monotonic()+4
        while len(result)<size and time.monotonic()<deadline:
            buf=c.create_string_buffer(size-len(result));received=c.c_ulong()
            self.call('FT_Read',self.handle,buf,len(buf),c.byref(received))
            result+=buf.raw[:received.value]
        if len(result)!=size:
            raise IOError(f'FTDI response short: {len(result)}/{size}, prefix={result[:100]!r}')
        return bytes(result)
    def packet(self,flags,data):
        payload=bytes([flags,self.seq])+data.ljust(8,b'\xff');frame=encode(payload)
        sent=c.c_ulong();self.call('FT_Write',self.handle,c.create_string_buffer(frame),len(frame),c.byref(sent))
        if sent.value!=len(frame):raise IOError('Short FTDI write')
        reply=decode(self.read_exact(25))
        if reply[:2]!=payload[:2]:raise IOError('FTDI reply sequence mismatch')
        self.seq=(self.seq+1)&255;self.frames+=1
        return reply[2:]
    def close_driver(self):
        if self.open:
            try:
                if self.original_latency.value:self.call('FT_SetLatencyTimer',self.handle,self.original_latency.value)
            finally:
                self.call('FT_Close',self.handle);self.open=False
    def close(self):
        if self.open:
            try:self.packet(8,bytes(8))
            finally:self.close_driver()
