#!/usr/bin/env python3
"""Scan the local network for FlaschenTaschen (FT) displays advertised over mDNS/Bonjour.

The iOS/macOS app browses for the Bonjour service type `_flaschen-taschen._tcp`. If a
scan finds nothing, the useful question is: *what are the displays actually advertising?*
So this tool has two modes:

  * default        — browse for the FT service type and print every responder
                     (name, hostname, IP addresses, port, TXT records).
  * --all          — enumerate EVERY service type advertised on the LAN and list the
                     instances under each. Use this to discover the real service type
                     your ESP32 / Mac app / Apple TV app publish, in case it isn't
                     `_flaschen-taschen._tcp`.

  * --probe HOST[:PORT]
                   — independent of mDNS, send a tiny FlaschenTaschen UDP frame to a
                     known host to confirm the FT *server* is reachable (lights one
                     pixel at a far corner). Handy for the ESP32 / Mac / Apple TV you
                     already know the IP of.

Backends, tried in order:
  1. `zeroconf` Python package (cross-platform, richest output) — `pip install zeroconf`.
  2. macOS built-in `dns-sd` (no install needed) — used automatically when zeroconf
     is absent and you're on macOS.

Examples:
  ./scan-ft-displays.py                       # browse _flaschen-taschen._tcp for 5s
  ./scan-ft-displays.py --all                 # list every mDNS service type on the LAN
  ./scan-ft-displays.py -t 10                 # browse for 10s
  ./scan-ft-displays.py --probe 192.168.4.99  # poke a known FT server on UDP 1337
"""

from __future__ import annotations

import argparse
import shutil
import socket
import subprocess
import sys
import time

FT_SERVICE_TYPE = "_flaschen-taschen._tcp"
FT_DEFAULT_PORT = 1337


# --------------------------------------------------------------------------- #
# Backend 1: zeroconf (preferred)
# --------------------------------------------------------------------------- #
def have_zeroconf() -> bool:
    try:
        import zeroconf  # noqa: F401
        return True
    except ImportError:
        return False


def browse_with_zeroconf(service_type: str, timeout: float) -> int:
    from zeroconf import ServiceBrowser, ServiceListener, Zeroconf

    fqtype = service_type + ".local." if not service_type.endswith(".local.") else service_type
    found: dict[str, dict] = {}

    class Listener(ServiceListener):
        def _record(self, zc: "Zeroconf", type_: str, name: str) -> None:
            info = zc.get_service_info(type_, name, timeout=2000)
            if not info:
                return
            addrs = []
            try:
                addrs = [socket.inet_ntoa(a) for a in info.addresses]
            except Exception:
                addrs = [str(a) for a in getattr(info, "parsed_addresses", lambda: [])()]
            txt = {}
            for k, v in (info.properties or {}).items():
                key = k.decode() if isinstance(k, bytes) else str(k)
                val = v.decode(errors="replace") if isinstance(v, bytes) else v
                txt[key] = val
            found[name] = {
                "host": (info.server or "").rstrip("."),
                "addresses": addrs,
                "port": info.port,
                "txt": txt,
            }

        def add_service(self, zc, type_, name):
            self._record(zc, type_, name)

        def update_service(self, zc, type_, name):
            self._record(zc, type_, name)

        def remove_service(self, zc, type_, name):
            pass

    zc = Zeroconf()
    print(f"Browsing {service_type} for {timeout:.0f}s via zeroconf ...")
    ServiceBrowser(zc, fqtype, Listener())
    try:
        time.sleep(timeout)
    finally:
        zc.close()

    _print_found(service_type, found)
    return len(found)


def enumerate_all_with_zeroconf(timeout: float) -> int:
    from zeroconf import ServiceBrowser, ServiceListener, Zeroconf, ZeroconfServiceTypes

    print(f"Enumerating all mDNS service types on the LAN ({timeout:.0f}s) ...\n")
    types = sorted(ZeroconfServiceTypes.find(timeout=min(timeout, 5.0)))
    if not types:
        print("No service types discovered. Are you on the same subnet as the displays?")
        return 0

    zc = Zeroconf()
    instances: dict[str, list[str]] = {t: [] for t in types}

    class Listener(ServiceListener):
        def __init__(self, type_):
            self.type_ = type_

        def add_service(self, zc, type_, name):
            info = zc.get_service_info(type_, name, timeout=1500)
            detail = name
            if info:
                addrs = ",".join(socket.inet_ntoa(a) for a in info.addresses) or "?"
                detail = f"{name}  ->  {addrs}:{info.port}"
            instances[self.type_].append(detail)

        def update_service(self, zc, type_, name):
            pass

        def remove_service(self, zc, type_, name):
            pass

    for t in types:
        ServiceBrowser(zc, t, Listener(t))
    time.sleep(min(timeout, 5.0))
    zc.close()

    total = 0
    for t in types:
        insts = instances.get(t, [])
        total += len(insts)
        marker = "  <== looks FlaschenTaschen-ish" if "flaschen" in t.lower() or "taschen" in t.lower() else ""
        print(f"{t}{marker}")
        for inst in insts:
            print(f"    {inst}")
        if not insts:
            print("    (advertised type, no instance resolved in time)")
    print(f"\nTotal service types: {len(types)}")
    return total


# --------------------------------------------------------------------------- #
# Backend 2: macOS dns-sd fallback (no dependencies)
# --------------------------------------------------------------------------- #
def _run_dns_sd(args: list[str], timeout: float) -> str:
    """Run `dns-sd` for `timeout` seconds and return whatever it streamed."""
    try:
        proc = subprocess.Popen(
            ["dns-sd", *args],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
    except FileNotFoundError:
        return ""
    try:
        out, _ = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        proc.terminate()
        try:
            out, _ = proc.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            out, _ = proc.communicate()
    return out or ""


def browse_with_dns_sd(service_type: str, timeout: float) -> int:
    print(f"Browsing {service_type} for {timeout:.0f}s via dns-sd ...")
    # -B lists instances; each "Add" line ends with the instance name.
    browse_out = _run_dns_sd(["-B", service_type, "local."], timeout)
    names = []
    for line in browse_out.splitlines():
        parts = line.split()
        if len(parts) >= 7 and parts[1] == "Add":
            # The instance name is everything after the service-type column, which
            # dns-sd prints with a trailing dot (e.g. "_flaschen-taschen._udp.").
            idx = line.find(service_type)
            if idx == -1:
                continue
            name = line[idx + len(service_type):].lstrip(". ").rstrip()
            if name and name not in names:
                names.append(name)

    found: dict[str, dict] = {}
    for name in names:
        # -L resolves instance -> host:port and TXT
        lookup = _run_dns_sd(["-L", name, service_type, "local."], min(timeout, 3.0))
        host, port, txt = "", None, {}
        for line in lookup.splitlines():
            if "can be reached at" in line:
                # e.g. "... can be reached at host.local.:1337 (interface 8)"
                tail = line.split("can be reached at", 1)[1].strip()
                hostport = tail.split()[0]
                if ":" in hostport:
                    host, p = hostport.rsplit(":", 1)
                    host = host.rstrip(".")
                    try:
                        port = int(p)
                    except ValueError:
                        port = None
        addrs = _resolve_host_dns_sd(host, min(timeout, 3.0)) if host else []
        found[name] = {"host": host, "addresses": addrs, "port": port, "txt": txt}

    _print_found(service_type, found)
    return len(found)


def _resolve_host_dns_sd(host: str, timeout: float) -> list[str]:
    fqhost = host if host.endswith(".") else host + "."
    out = _run_dns_sd(["-G", "v4", fqhost], timeout)
    addrs = []
    for line in out.splitlines():
        parts = line.split()
        if "Add" in parts:
            for p in parts:
                if p.count(".") == 3 and all(seg.isdigit() for seg in p.split(".")):
                    if p not in addrs:
                        addrs.append(p)
    # Fall back to the OS resolver.
    if not addrs and host:
        try:
            addrs = list({ai[4][0] for ai in socket.getaddrinfo(host, None, socket.AF_INET)})
        except socket.gaierror:
            pass
    return addrs


def enumerate_all_with_dns_sd(timeout: float) -> int:
    print(f"Enumerating all mDNS service types on the LAN ({timeout:.0f}s) via dns-sd ...\n")
    out = _run_dns_sd(["-B", "_services._dns-sd._udp", "local."], timeout)
    types = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 7 and parts[1] == "Add":
            # `dns-sd -B _services._dns-sd._udp` prints, per row:
            #   <date> <time> Add <flags> <if> local. <proto>.local. <serviceName>
            # e.g. "... local.  _tcp.local.  _airplay"  ->  service type "_airplay._tcp"
            name = parts[-1]                 # "_airplay"
            proto_domain = parts[-2]         # "_tcp.local."
            proto = proto_domain.split(".", 1)[0]   # "_tcp"
            t = f"{name}.{proto}"
            if t not in types:
                types.append(t)

    if not types:
        print("No service types discovered via dns-sd. Are you on the displays' subnet?")
        return 0

    ft_like = [t for t in types if "flaschen" in t.lower() or "taschen" in t.lower()]
    for t in sorted(types):
        marker = "  <== looks FlaschenTaschen-ish" if t in ft_like else ""
        print(f"{t}{marker}")
    print(f"\nTotal service types: {len(types)}")
    if ft_like:
        print("\nBrowse an FT-ish type in detail with:")
        print(f"    {sys.argv[0]} --type {ft_like[0]}")
    return len(types)


# --------------------------------------------------------------------------- #
# Direct UDP probe of a known FT server (independent of mDNS)
# --------------------------------------------------------------------------- #
def probe_ft_server(target: str) -> int:
    host, _, port_s = target.partition(":")
    port = int(port_s) if port_s else FT_DEFAULT_PORT
    # Minimal FlaschenTaschen frame: a 1x1 PPM (P6) black pixel, placed via the footer
    # offset far off-screen so it doesn't visibly disturb a running display.
    #   header: "P6\n<w> <h>\n255\n", then w*h*3 bytes, then optional footer:
    #   "\n<x>\n<y>\n<layer>\n" to position the frame.
    header = b"P6\n1 1\n255\n"
    pixel = b"\x00\x00\x00"
    footer = b"\n9999\n9999\n15\n"   # push to a corner, top layer 15
    frame = header + pixel + footer
    try:
        addr = socket.gethostbyname(host)
    except socket.gaierror as e:
        print(f"Cannot resolve {host!r}: {e}")
        return 1
    print(f"Sending a 1x1 FT probe frame to {host} ({addr}) UDP :{port} ...")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.sendto(frame, (addr, port))
        print("UDP frame sent (UDP is connectionless, so 'sent' != 'received').")
        print("If the target is a real display, a pixel briefly appeared at a far corner.")
        print("This confirms the host is routable and something accepted the datagram at")
        print("the OS level. It does NOT confirm the FT server parsed it — watch the display")
        print("or the ESP32 serial log to be sure.")
        return 0
    except OSError as e:
        print(f"Send failed: {e}")
        return 1
    finally:
        sock.close()


# --------------------------------------------------------------------------- #
# Shared output
# --------------------------------------------------------------------------- #
def _print_found(service_type: str, found: dict[str, dict]) -> None:
    print()
    if not found:
        print(f"No {service_type} responders found.")
        print("Next steps:")
        print(f"  * Run with --all to see what IS advertised — the displays may use a")
        print(f"    different service type than {service_type}.")
        print("  * Confirm you're on the same subnet/VLAN as the displays (mDNS is")
        print("    link-local; it does not cross subnets or most guest/IoT VLANs).")
        return
    print(f"Discovered {len(found)} {service_type} display(s):\n")
    for name, d in found.items():
        print(f"  • {name}")
        if d.get("host"):
            print(f"      host : {d['host']}")
        if d.get("addresses"):
            print(f"      addr : {', '.join(d['addresses'])}")
        if d.get("port"):
            print(f"      port : {d['port']}")
        if d.get("txt"):
            print(f"      txt  : {d['txt']}")
        print()


# --------------------------------------------------------------------------- #
def main() -> int:
    ap = argparse.ArgumentParser(
        description="Scan the LAN for FlaschenTaschen displays over mDNS/Bonjour.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("-t", "--timeout", type=float, default=5.0,
                    help="seconds to browse (default: 5)")
    ap.add_argument("--type", dest="service_type", default=FT_SERVICE_TYPE,
                    help=f"Bonjour service type to browse (default: {FT_SERVICE_TYPE})")
    ap.add_argument("--all", action="store_true",
                    help="enumerate every mDNS service type on the LAN (diagnostic)")
    ap.add_argument("--probe", metavar="HOST[:PORT]",
                    help="send a tiny FT UDP frame to a known host (default port 1337)")
    args = ap.parse_args()

    if args.probe:
        return probe_ft_server(args.probe)

    zc = have_zeroconf()
    have_dns_sd = shutil.which("dns-sd") is not None

    if not zc and not have_dns_sd:
        print("Neither the `zeroconf` package nor macOS `dns-sd` is available.")
        print("Install the cross-platform backend with:")
        print("    python3 -m pip install zeroconf")
        return 2

    if args.all:
        if zc:
            enumerate_all_with_zeroconf(args.timeout)
        else:
            enumerate_all_with_dns_sd(args.timeout)
        return 0

    if zc:
        browse_with_zeroconf(args.service_type, args.timeout)
    else:
        browse_with_dns_sd(args.service_type, args.timeout)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\nInterrupted.")
        sys.exit(130)
