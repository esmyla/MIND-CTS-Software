"""Glove sensor bridge: USB serial -> WebSocket, with device pairing.

The glove's ESP32 (firmware/CTS_IC2.ino) has BLE characteristics defined but BLE
is not commissioned yet, so the board is wired over USB and we read its serial
debug line instead:

    IR=61234 BPM=72 TempC=33.41 FSR=2048

Flutter web cannot open a serial port, so this process is the bridge: it reads
the port and broadcasts JSON to any connected web client.

Each patient has their own glove and runs their own copy of this bridge, so the
app has to know WHICH glove it is talking to. Clients can list the attached
devices and pair with one; the bridge remembers the pairing by the USB serial
number, so the same glove is recognised even if it comes back on a different
port after a replug.

Deliberately dumb by design. This process does *transport only* — it never
touches Supabase. Session logic (hold windows, top-60% aggregation, baseline
ratios) and all database writes live in the Flutter app, which already holds the
signed-in user's JWT so row-level security applies to the write. Writing from
here would require a service-role key and would bypass RLS.

Usage
-----
    # Autodetect and attach to the only glove present
    python sensor_ws_server.py

    # Attach to a specific port
    python sensor_ws_server.py --port /dev/cu.usbmodem1101

    # No hardware — replays the firmware's exact line format
    python sensor_ws_server.py --simulate

    # List candidate devices and exit
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
from dataclasses import dataclass, asdict, field
from typing import Optional, Set, List, Dict, Any, Tuple

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
_LINE_RE = re.compile(
    r"IR=(?P<ir>-?\d+)\s+"
    r"BPM=(?P<bpm>-?\d+)\s+"
    r"TempC=(?P<temp>-?\d+(?:\.\d+)?)\s+"
    r"FSR=(?P<fsr>-?\d+)"
)

# CTS_IC2.ino treats IR > 50000 as "finger is on the sensor".
IR_FINGER_THRESHOLD = 50_000

# USB vendor ids seen on ESP32 dev boards: Espressif's native USB-serial, and
# the CP210x / CH340 / FTDI bridges used on third-party boards. Only used to
# SORT likely gloves to the top — never to hide a port, since a board we don't
# recognise must still be pairable.
KNOWN_VENDOR_IDS = {0x303A, 0x10C4, 0x1A86, 0x0403}

# macOS and Linux both expose built-ins that are never a glove.
_BUILTIN_HINTS = ("bluetooth", "debug-console", "ttys0", "ttyama")

SIMULATED_DEVICE_ID = "simulated-glove"


# =============================================================================
# DEVICE DISCOVERY
# =============================================================================

def _is_builtin(device_path: str) -> bool:
    lowered = device_path.lower()
    return any(hint in lowered for hint in _BUILTIN_HINTS)


def describe_port(p) -> Dict[str, Any]:
    """One serial port as the app sees it.

    `id` is the pairing key. The USB serial number is stable across replugs and
    across ports, so prefer it; boards that do not report one fall back to the
    device path, which is the best we can do but will change if it is moved to
    another USB socket.
    """
    serial_number = getattr(p, "serial_number", None)
    return {
        "id": serial_number or p.device,
        "port": p.device,
        "description": (p.description or "").strip() or p.device,
        "manufacturer": getattr(p, "manufacturer", None),
        "product": getattr(p, "product", None),
        "vid": getattr(p, "vid", None),
        "pid": getattr(p, "pid", None),
        "stable_id": serial_number is not None,
        "likely_glove": getattr(p, "vid", None) in KNOWN_VENDOR_IDS,
    }


def scan_devices() -> List[Dict[str, Any]]:
    """Candidate gloves, most likely first."""
    found = [
        describe_port(p)
        for p in serial.tools.list_ports.comports()
        if not _is_builtin(p.device)
    ]
    found.sort(key=lambda d: (not d["likely_glove"], d["port"]))
    return found


def resolve_device(device_id: str) -> Optional[Dict[str, Any]]:
    """Find an attached device by pairing id, or None if it is not plugged in."""
    for d in scan_devices():
        if d["id"] == device_id:
            return d
    return None


def autodetect() -> Optional[Dict[str, Any]]:
    """Pick a glove when the user has not chosen one.

    Only auto-attaches to a RECOGNISED board, and only when there is exactly
    one. With two gloves on the bench, guessing would silently record the wrong
    patient's hand, so we make the client pair explicitly instead.
    """
    likely = [d for d in scan_devices() if d["likely_glove"]]
    if len(likely) == 1:
        return likely[0]
    if not likely:
        others = scan_devices()
        if len(others) == 1:
            return others[0]
    return None


# =============================================================================
# TARGET
# =============================================================================

class DeviceTarget:
    """Which glove the reader should be attached to. Changeable at runtime.

    `generation` bumps on every change so the reader thread notices and
    reconnects without needing to be torn down and restarted.
    """

    def __init__(self, device: Optional[Dict[str, Any]] = None, simulate: bool = False):
        self._lock = threading.Lock()
        self._device = device
        self._simulate = simulate
        self._generation = 0

    def set(self, device: Optional[Dict[str, Any]], simulate: bool = False) -> None:
        with self._lock:
            self._device = device
            self._simulate = simulate
            self._generation += 1

    def get(self) -> Tuple[Optional[Dict[str, Any]], bool, int]:
        with self._lock:
            return self._device, self._simulate, self._generation


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

    connected: bool = False
    source: str = "none"          # "serial" | "simulate" | "none"
    error: Optional[str] = None
    updated_at: float = 0.0
    device: Optional[Dict[str, Any]] = field(default=None)

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
# READER
# =============================================================================

def _changed(target: DeviceTarget, generation: int) -> bool:
    return target.get()[2] != generation


def read_serial(state: SensorState, device: Dict[str, Any], baud: int,
                target: DeviceTarget, generation: int, stop: threading.Event) -> None:
    """Stream one glove until it disappears, the target changes, or we stop."""
    ser = None
    try:
        ser = serial.Serial(device["port"], baud, timeout=1)
        state.update(connected=True, source="serial", error=None, device=device)
        print(f"[serial] attached: {device['port']} ({device['description']}) @ {baud}", flush=True)

        # The board resets when the port opens; the first line is usually a
        # fragment. Drop whatever is already buffered.
        time.sleep(2.0)
        ser.reset_input_buffer()

        while not stop.is_set() and not _changed(target, generation):
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
        print(f"[serial] {exc}", flush=True)
        stop.wait(2.0)
    except Exception as exc:  # noqa: BLE001 - the reader thread must not die
        state.update(connected=False, error=f"reader: {exc!r}")
        print(f"[serial] unexpected: {exc!r}", flush=True)
        stop.wait(2.0)
    finally:
        if ser is not None and ser.is_open:
            try:
                ser.close()
            except Exception:
                pass


def run_simulator(state: SensorState, target: DeviceTarget, generation: int,
                  stop: threading.Event) -> None:
    """Emit plausible glove data in the firmware's exact shape.

    Not a replay of real captures — we have none yet. It produces a slow
    squeeze/release cycle on the FSR plus a wandering heart rate, so every UI
    state is reachable without hardware. Real ADC ranges must still be confirmed
    against an actual glove.
    """
    device = {
        "id": SIMULATED_DEVICE_ID,
        "port": "simulated",
        "description": "Simulated glove",
        "manufacturer": None,
        "product": None,
        "vid": None,
        "pid": None,
        "stable_id": True,
        "likely_glove": True,
    }
    state.update(connected=True, source="simulate", error=None, device=device)
    print("[simulate] generating synthetic glove data", flush=True)

    t0 = time.time()
    bpm = 72.0

    while not stop.is_set() and not _changed(target, generation):
        t = time.time() - t0

        # ~12 s squeeze/release cycle, raised-cosine so it ramps rather than
        # jumping. Peaks near 3000 of the ESP32's 12-bit 0..4095 range.
        cycle = (1.0 - math.cos(2.0 * math.pi * t / 12.0)) / 2.0
        fsr = int(120 + 2900 * (cycle ** 1.6) + random.gauss(0, 25))
        fsr = max(0, min(4095, fsr))

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


def reader_thread(state: SensorState, target: DeviceTarget, baud: int,
                  stop: threading.Event) -> None:
    """Follow whatever the target currently points at."""
    while not stop.is_set():
        device, simulate, generation = target.get()

        if simulate:
            run_simulator(state, target, generation, stop)
            continue

        if device is None:
            state.update(connected=False, source="none", device=None,
                         error="No glove paired.")
            stop.wait(1.0)
            continue

        # Re-resolve by pairing id: the glove may have come back on a different
        # port since it was paired.
        live = resolve_device(device["id"]) or (
            device if device["port"] in [d["port"] for d in scan_devices()] else None
        )
        if live is None:
            state.update(connected=False, source="none", device=device,
                         error=f"{device['description']} is not plugged in.")
            stop.wait(2.0)
            continue

        read_serial(state, live, baud, target, generation, stop)

    state.update(connected=False, source="none")


# =============================================================================
# WEBSOCKET
# =============================================================================

CLIENTS: Set[Any] = set()


async def send_json(conn, payload: Dict[str, Any]) -> None:
    try:
        await conn.send(json.dumps(payload))
    except Exception:
        pass


async def handle_command(conn, data: Dict[str, Any], state: SensorState,
                         target: DeviceTarget) -> None:
    cmd = data.get("command")

    if cmd == "list_devices":
        await send_json(conn, {
            "type": "device_list",
            "devices": scan_devices(),
            "paired": (target.get()[0] or {}).get("id"),
            "simulated": target.get()[1],
        })
        return

    if cmd == "pair":
        device_id = data.get("device_id")

        if device_id == SIMULATED_DEVICE_ID:
            target.set(None, simulate=True)
            await send_json(conn, {"type": "pair_result", "ok": True,
                                   "device_id": SIMULATED_DEVICE_ID})
            print("[pair] switched to the simulator", flush=True)
            return

        device = resolve_device(device_id) if device_id else None
        if device is None:
            await send_json(conn, {
                "type": "pair_result", "ok": False, "device_id": device_id,
                "error": "That glove is not plugged in.",
            })
            return

        target.set(device, simulate=False)
        await send_json(conn, {"type": "pair_result", "ok": True,
                               "device_id": device["id"]})
        print(f"[pair] paired with {device['description']} ({device['id']})", flush=True)
        return

    if cmd == "unpair":
        target.set(None, simulate=False)
        await send_json(conn, {"type": "pair_result", "ok": True, "device_id": None})
        return


def make_handler(state: SensorState, target: DeviceTarget):
    async def handler(conn) -> None:
        CLIENTS.add(conn)
        print(f"[ws] client connected ({len(CLIENTS)} total)", flush=True)

        # Tell a new client what is attached right away, so its pairing screen
        # is populated before the first sensor frame arrives.
        await send_json(conn, {
            "type": "device_list",
            "devices": scan_devices(),
            "paired": (target.get()[0] or {}).get("id"),
            "simulated": target.get()[1],
        })

        try:
            async for message in conn:
                if not isinstance(message, str):
                    continue
                try:
                    data = json.loads(message)
                except Exception:
                    continue
                if isinstance(data, dict):
                    await handle_command(conn, data, state, target)
        except websockets.ConnectionClosed:
            pass
        finally:
            CLIENTS.discard(conn)
            print(f"[ws] client disconnected ({len(CLIENTS)} left)", flush=True)

    return handler


async def broadcaster(state: SensorState, target: DeviceTarget) -> None:
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
            "device": sample.device,
            # Normally 1: each patient runs their own bridge against their own
            # glove. Above 1 means several tabs or people are attached to THIS
            # bridge and would each save the same squeeze as their own session,
            # so the app warns. Reported rather than enforced — a forgotten
            # browser tab must not lock someone out of their own hardware.
            "viewers": len(CLIENTS),
        })

        await asyncio.gather(
            *(c.send(payload) for c in list(CLIENTS)),
            return_exceptions=True,      # a slow client must not stall the rest
        )


# =============================================================================
# MAIN
# =============================================================================

def print_ports() -> None:
    devices = scan_devices()
    if not devices:
        print("No candidate serial devices found. Is the glove plugged in?")
        return
    print("Candidate devices:")
    for d in devices:
        mark = "*" if d["likely_glove"] else " "
        stable = "" if d["stable_id"] else "   (no USB serial number — pairing is port-based)"
        print(f" {mark} {d['port']:<28} {d['description']}")
        print(f"     id: {d['id']}{stable}")
    print("\n  * = recognised USB-serial chip commonly used on ESP32 boards")


async def main_async(args: argparse.Namespace) -> None:
    state = SensorState()
    stop = threading.Event()

    if args.simulate:
        target = DeviceTarget(None, simulate=True)
    elif args.port:
        match = next((d for d in scan_devices() if d["port"] == args.port), None)
        if match is None:
            print(f"No such serial device: {args.port}\n"
                  f"  Run with --list-ports to see what is attached.", file=sys.stderr)
            sys.exit(2)
        target = DeviceTarget(match, simulate=False)
    else:
        guess = autodetect()
        if guess is not None:
            print(f"[auto] attaching to {guess['description']} ({guess['port']})", flush=True)
        else:
            print("[auto] no single obvious glove — waiting for the app to pair one",
                  flush=True)
        target = DeviceTarget(guess, simulate=False)

    reader = threading.Thread(
        target=reader_thread, args=(state, target, args.baud, stop), daemon=True
    )
    reader.start()

    print(f"[ws] listening on ws://{args.ws_host}:{args.ws_port}", flush=True)
    try:
        async with websockets.serve(
            make_handler(state, target), args.ws_host, args.ws_port,
            ping_interval=20, ping_timeout=20,
        ):
            await broadcaster(state, target)
    finally:
        stop.set()
        reader.join(timeout=3.0)


def main() -> None:
    parser = argparse.ArgumentParser(description="Glove USB-serial to WebSocket bridge")
    parser.add_argument("--port", help="Serial device (default: autodetect)")
    parser.add_argument("--baud", type=int, default=DEFAULT_BAUD)
    parser.add_argument("--ws-host", default="127.0.0.1",
                        help="Bind address (default: loopback only)")
    parser.add_argument("--ws-port", type=int, default=DEFAULT_WS_PORT)
    parser.add_argument("--simulate", action="store_true",
                        help="Generate synthetic data instead of reading hardware")
    parser.add_argument("--list-ports", action="store_true",
                        help="List candidate devices and exit")
    args = parser.parse_args()

    if args.list_ports:
        print_ports()
        return

    try:
        asyncio.run(main_async(args))
    except KeyboardInterrupt:
        print("\n[server] stopped", flush=True)


if __name__ == "__main__":
    main()
