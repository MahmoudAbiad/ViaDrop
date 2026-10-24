"""Evaluate a pinned Cyrinx C core; no device I/O or networking in this test."""
import ctypes as C
import json
import random
import sys
import time

class Config(C.Structure):
    _fields_ = [('lo', C.c_double), ('hi', C.c_double), ('pilots', C.c_int),
                ('bits', C.c_int), ('rate', C.c_char_p), ('symbols', C.c_int),
                ('fft', C.c_int), ('cp', C.c_int), ('sr', C.c_int),
                ('amp', C.c_double), ('clip', C.c_double),
                ('chirp_lo', C.c_double), ('chirp_hi', C.c_double)]
class Geometry(C.Structure):
    _fields_ = [(name, C.c_int) for name in ['lo','hi','used','pilots','data',
        'bps','cap','info','blocks','payload','samples']]

lib = C.CDLL(sys.argv[1])
lib.cyrinx_bulk_compute_geometry.argtypes = [C.POINTER(Config), C.POINTER(Geometry)]
lib.cyrinx_bulk_modulate.argtypes = [C.POINTER(Config), C.c_void_p, C.c_size_t,
    C.c_void_p, C.c_size_t, C.c_void_p]
lib.cyrinx_bulk_modulate.restype = C.c_long
lib.cyrinx_bulk_demodulate.argtypes = [C.POINTER(Config), C.c_void_p, C.c_size_t,
    C.c_void_p, C.c_size_t, C.POINTER(C.c_int), C.POINTER(C.c_int), C.c_void_p]
lib.cyrinx_bulk_demodulate.restype = C.c_long
results = []
for bits, symbols, rate in [(2,16,b'1/2'), (4,8,b'1/2'), (4,8,b'3/4')]:
    cfg = Config(1100,16000,8,bits,rate,symbols,2048,512,48000,.5,3.3,2000,14000)
    g = Geometry()
    assert lib.cyrinx_bulk_compute_geometry(C.byref(cfg),C.byref(g)) == 0
    data = bytes((i*71+19)%256 for i in range(g.payload))
    wave = (C.c_float*g.samples)()
    assert lib.cyrinx_bulk_modulate(C.byref(cfg), data,len(data),wave,len(wave),None)==len(wave)
    for noise,echo in [(0,0),(.001,0),(.001,.2)]:
        rng=random.Random(42)
        # Unaligned capture and actual PCM16 quantization, with bounded echo.
        pcm = [0.0]*3000+[int(max(-1,min(1,x))*32767)/32768 for x in wave]+[0.0]*4000
        damaged = [x + (pcm[i-240]*echo if i>=240 else 0) + rng.uniform(-noise,noise) for i,x in enumerate(pcm)]
        rx=(C.c_float*len(damaged))(*damaged); output=(C.c_ubyte*g.payload)()
        ok=C.c_int(); total=C.c_int(); start=time.monotonic()
        n=lib.cyrinx_bulk_demodulate(C.byref(cfg),rx,len(rx),output,len(output),C.byref(ok),C.byref(total),None)
        match=n==g.payload and bytes(output)==data and ok.value==total.value==g.blocks
        results.append(dict(bits=bits,symbols=symbols,rate=rate.decode(),payload=g.payload,
            waveform_seconds=g.samples/48000,bytes_per_second=g.payload/(g.samples/48000),
            noise=noise,echo=echo,verified=match,decode_seconds=time.monotonic()-start))
print(json.dumps(results,indent=2))
if not all(x['verified'] for x in results): sys.exit(1)
