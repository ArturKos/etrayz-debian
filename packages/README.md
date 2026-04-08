# Native Build Scripts

Scripts for compiling updated packages directly on the EtrayZ NAS
(OX810SE ARM926EJ-S 183 MHz, kernel 2.6.24.4, GCC 4.4.5).

**Run on the NAS, not on a PC.** The Docker toolchain in `toolchain/`
produces segfaulting user-space binaries on this kernel — native builds are
the only reliable path for user-space packages.

## Build Order

Dependencies must be built first:

```
1. build-openssl.sh   — base TLS library (all others depend on it)
2. build-wget.sh      — needed to download subsequent sources
3. build-curl.sh      — HTTP client
4. build-dropbear.sh  — SSH server (replaces Squeeze openssh-server)
5. build-aria2.sh     — download manager
```

## Scripts

| Script | Package | Version | Time |
|--------|---------|---------|------|
| `build-openssl.sh` | OpenSSL | 1.1.1w | ~45 min |
| `build-wget.sh` | wget | 1.20.3 | ~10 min |
| `build-curl.sh` | curl | 7.88.1 | ~15 min |
| `build-dropbear.sh` | Dropbear | 2025.89 | ~10 min |
| `build-aria2.sh` | aria2 | 1.15.1 | ~30 min |

## Notes

- All builds use `-j1` — the 183 MHz ARM cannot benefit from parallel builds,
  and old `make`/`libtool` versions have race conditions under `-j2`.
- OpenSSL is installed to `/usr/local/lib/` with system OpenSSL left untouched.
  Other packages use `-rpath /usr/local/lib` so they find the new libssl at
  runtime without `LD_LIBRARY_PATH`.
- Each script backs up the original binary before overwriting:
  `/usr/bin/wget.1.12.bak`, `/usr/bin/curl.7.21.bak`, `/usr/bin/aria2c.1.10.bak`
