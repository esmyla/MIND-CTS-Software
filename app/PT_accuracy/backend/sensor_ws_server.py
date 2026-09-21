"""Glove sensor bridge: USB serial -> WebSocket.

The glove's ESP32 (firmware/CTS_IC2.ino) has BLE characteristics defined but BLE
is not commissioned yet, so the board is wired over USB and we read its serial
debug line instead:

    IR=61234 BPM=72 TempC=33.41 FSR=2048

Flutter web cannot open a serial port, so this process is the bridge: it reads
the port, parses each line, and broadcasts JSON to any connected web client.

Deliberately dumb by design. This process does *transport only* — it never
touches Supabase. Session logic (hold windows, top-60% aggregation, baseline
ratios) and all database writes live in the Flutter app, which already holds the
signed-in user's JWT so row-level security applies to the write. Writing from
here would require a service-role key and would bypass RLS.

Usage
-----
    # Real glove
    python sensor_ws_server.py --port /dev/cu.usbmodem1101

    # No hardware — replays the firmware's exact line format
    python sensor_ws_server.py --simulate

    # List candidate ports and exit
    python sensor_ws_server.py --list-ports
"""

from __future__ import annotations

import argparse
import asyncio
import json
import math
import random
import re
import sys
import threading
import time
from dataclasses import dataclass, asdict
from typing import Optional, Set

import serial
import serial.tools.list_ports
import websockets

# =============================================================================
# CONFIG
# =============================================================================

DEFAULT_BAUD = 115200          # matches Serial.begin(115200) in CTS_IC2.ino
DEFAULT_WS_PORT = 8766         # 8765 belongs to flexion_ws_server.py
BROADCAST_HZ = 20              # firmware emits ~200 Hz; 20 Hz is plenty for a
                               # 5 s hold (100 samples) and keeps the socket calm

# The firmware's line looks like: "IR=61234 BPM=72 TempC=33.41 FSR=2048".
# Tolerant of extra whitespace, missing fields, and partial lines.
_LINE_RE = re.compile(
    r"IR=(?P<ir>-?\d+)\s+"
    r"BPM=(?P<bpm>-?\d+)\s+"
    r"TempC=(?P<temp>-?\d+(?:\.\d+)?)\s+"
    r"FSR=(?P<fsr>-?\d+)"
)

# CTS_IC2.ino treats IR > 50000 as "finger is on the sensor". Below that the BPM
# reading is meaningless, and the firmware zeroes beatAvg.
IR_FINGER_THRESHOLD = 50_000


# =============================================================================
# SHARED STATE
# =============================================================================

@dataclass
class SensorSample:
    """Most recent reading from the glove."""

    ir: int = 0
    bpm: int = 0
    temp_c: float = 0.0
    fsr: int = 0

    # Transport health, so the UI can tell "resting hand" from "unplugged".
    connected: bool = False
    source: str = "none"          # "serial" | "simulate" | "none"
    error: Optional[str] = None
    updated_at: float = 0.0

    @property
    def finger_present(self) -> bool:
        return self.ir > IR_FINGER_THRESHOLD


class SensorState:
    """Thread-safe holder. The reader thread writes; the asyncio loop reads."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._sample = SensorSample()

    def update(self, **fields) -> None:
        with self._lock:
            for key, value in fields.items():
                setattr(self._sample, key, value)
            self._sample.updated_at = time.time()

    def snapshot(self) -> SensorSample:
        with self._lock:
            return SensorSample(**asdict(self._sample))


# =============================================================================
# SERIAL READER
# =============================================================================

def serial_reader(state: SensorState, port: str, baud: int, stop: threading.Event) -> None:
    """Read the glove's serial stream until stopped.

    Runs on its own thread because pyserial is blocking. Reconnects on its own
    so unplugging the glove mid-session degrades instead of crashing.
    """
    while not stop.is_set():
        ser = None
        try:
            ser = serial.Serial(port, baud, timeout=1)
            state.update(connected=True, source="serial", error=None)
            print(f"[serial] connected: {port} @ {baud}", flush=True)

            # The board resets when the port opens; the first line is usually
            # a fragment. Drop whatever is already buffered.
            time.sleep(2.0)
            ser.reset_input_buffer()

            while not stop.is_set():
                raw = ser.readline()
                if not raw:
                    continue  # timeout, not an error — the board may be quiet

                line = raw.decode("utf-8", errors="replace").strip()
                match = _LINE_RE.search(line)
                if not match:
                    continue  # boot banner, partial line, or BLE log noise

                state.update(
                    ir=int(match.group("ir")),
                    bpm=int(match.group("bpm")),
                    temp_c=float(match.group("temp")),
                    fsr=int(match.group("fsr")),
                    connected=True,
                    error=None,
                )

        except serial.SerialException as exc:
            state.update(connected=False, error=f"serial: {exc}")
            print(f"[serial] {exc} — retrying in 2s", flush=True)
            stop.wait(2.0)
        except Exception as exc:  # noqa: BLE001 - reader thread must not die
            state.update(connected=False, error=f"reader: {exc!r}")
            print(f"[serial] unexpected: {exc!r} — retrying in 2s", flush=True)
            stop.wait(2.0)
        finally:
            if ser is not None and ser.is_open:
                try:
                    ser.close()
                except Exception:
                    pass

    state.update(connected=False, source="none")


# =============================================================================
# SIMULATOR
# =============================================================================

def simulate_reader(state: SensorState, stop: threading.Event) -> None:
    """Emit plausible glove data in the firmware's exact shape.

    Not a replay of real captures — we have none yet. It produces a slow
    squeeze/release cycle on the FSR plus a wandering heart rate, so every UI
    state (resting, ramping, holding, releasing) is reachable without hardware.
    Real ADC ranges must still be confirmed against the actual glove.
    """
    state.update(connected=True, source="simulate", error=None)
    print("[simulate] generating synthetic glove data", flush=True)

    t0 = time.time()
    bpm = 72.0

    while not stop.is_set():
        t = time.time() - t0

        # ~12 s squeeze/release cycle, raised-cosine so it ramps rather than
        # jumping. Peaks near 3000 of the ESP32's 12-bit 0..4095 range.
        cycle = (1.0 - math.cos(2.0 * math.pi * t / 12.0)) / 2.0
        fsr = int(120 + 2900 * (cycle ** 1.6) + random.gauss(0, 25))
        fsr = max(0, min(4095, fsr))

        # Heart rate drifts, and rises a little under load.
        bpm += random.gauss(0, 0.6) + 0.02 * (72 + 25 * cycle - bpm)
        bpm = max(50.0, min(150.0, bpm))

        state.update(
            ir=int(60_000 + 4_000 * cycle + random.gauss(0, 500)),
            bpm=int(round(bpm)),
            temp_c=round(33.0 + 0.6 * cycle + random.gauss(0, 0.05), 2),
            fsr=fsr,
            connected=True,
            error=None,
        )

        stop.wait(0.005)  # match the firmware's delay(5)

    state.update(connected=False, source="none")


# =============================================================================
# WEBSOCKET BROADCAST
# =============================================================================

CLIENTS: Set[websockets.WebSocketServerProtocol] = set()


async def handler(conn) -> None:
    CLIENTS.add(conn)
    print(f"[ws] client connected ({len(CLIENTS)} total)", flush=True)
    try:
        # Clients have nothing to say to us — this bridge is one-directional.
        # Draining anyway keeps pings flowing and detects a dead peer.
        async for _ in conn:
            pass
    except websockets.ConnectionClosed:
        pass
    finally:
        CLIENTS.discard(conn)
        print(f"[ws] client disconnected ({len(CLIENTS)} left)", flush=True)


async def broadcaster(state: SensorState) -> None:
    interval = 1.0 / BROADCAST_HZ
    while True:
        await asyncio.sleep(interval)
        if not CLIENTS:
            continue

        sample = state.snapshot()

        # A stale sample means the reader stalled even though the socket is up.
        stale = sample.updated_at > 0 and (time.time() - sample.updated_at) > 2.0

        payload = json.dumps({
            "type": "sensor_update",
            "ts": time.time(),
            "ir": sample.ir,
            "bpm": sample.bpm,
            "temp_c": sample.temp_c,
            "fsr": sample.fsr,
            "fsr_max": 4095,               # ESP32-C6 12-bit ADC full scale
            "finger_present": sample.finger_present,
            "connected": sample.connected and not stale,
            "stale": stale,
            "source": sample.source,
            "error": sample.error,
        })

        await asyncio.gather(
            *(c.send(payload) for c in list(CLIENTS)),
            return_exceptions=True,      # a slow client must not stall the rest
        )


# =============================================================================
# MAIN
# =============================================================================

def list_ports() -> None:
    ports = list(serial.tools.list_ports.comports())
    if not ports:
        print("No serial ports found. Is the glove plugged in?")
        return
    print("Available serial ports:")
    for p in ports:
        print(f"  {p.device:<28} {p.description}")


def guess_port() -> Optional[str]:
    """Pick the most likely glove port, ignoring macOS built-ins."""
    for p in serial.tools.list_ports.comports():
        name = p.device.lower()
        if "bluetooth" in name or "debug-console" in name:
            continue
        if "usbmodem" in name or "usbserial" in name or "wchusb" in name or "slab" in name:
            return p.device
    return None


async def main_async(args: argparse.Namespace) -> None:
    state = SensorState()
    stop = threading.Event()

    if args.simulate:
        reader = threading.Thread(target=simulate_reader, args=(state, stop), daemon=True)
    else:
        port = args.port or guess_port()
        if not port:
            print(
                "No glove serial port found.\n"
                "  Plug the board in, or run with --simulate for synthetic data.\n"
                "  Use --list-ports to see what's attached.",
                file=sys.stderr,
            )
            sys.exit(2)
        reader = threading.Thread(
            target=serial_reader, args=(state, port, args.baud, stop), daemon=True
        )

    reader.start()

    print(f"[ws] listening on ws://{args.ws_host}:{args.ws_port}", flush=True)
    try:
        async with websockets.serve(
            handler, args.ws_host, args.ws_port, ping_interval=20, ping_timeout=20
        ):
            await broadcaster(state)
    finally:
        stop.set()
        reader.join(timeout=3.0)


def main() -> None:
    parser = argparse.ArgumentParser(description="Glove USB-serial to WebSocket bridge")
    parser.add_argument("--port", help="Serial device (default: autodetect)")
    parser.add_argument("--baud", type=int, default=DEFAULT_BAUD)
    parser.add_argument("--ws-host", default="0.0.0.0")
    parser.add_argument("--ws-port", type=int, default=DEFAULT_WS_PORT)
    parser.add_argument("--simulate", action="store_true",
                        help="Generate synthetic data instead of reading hardware")
    parser.add_argument("--list-ports", action="store_true",
                        help="List serial ports and exit")
    args = parser.parse_args()

    if args.list_ports:
        list_ports()
        return

    try:
        asyncio.run(main_async(args))
    except KeyboardInterrupt:
        print("\n[server] stopped", flush=True)


if __name__ == "__main__":
    main()
