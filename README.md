# dsinstruments-amp-ctrl-matlab

[繁體中文](README.zh-TW.md)

Control DS Instruments **PA / GB series** USB amplifiers from MATLAB scripts instead of the AmpCon GUI.
The amplifier accepts SCPI text commands over a USB virtual COM port; this repository wraps them in one MATLAB class, `DSAmp`.

> **Tested on one model only: PA20000 (firmware V5.16).**
> The vendor's SCPI command list covers the PA / GB series, so other models are expected to work, but the author has not tested any of them.
> On a different model, run [`tests/hardware_checklist.m`](tests/hardware_checklist.m) first. It records what your unit actually replies.
>
> **What "tested" means here.** Every method of `DSAmp.m`, both test scripts and all three examples have been run on the PA20000.
> A few branches have not: see "Not verified" in [`docs/COMMANDS.md`](docs/COMMANDS.md).

This is an independent project. It is not affiliated with or endorsed by DS Instruments.

## Requirements

- MATLAB R2020b or later (uses the built-in `serialport`; no toolbox needed). Run on R2024a and R2025b; older releases are untested.
- Amplifier connected over USB. **Close AmpCon first**: only one program can open the COM port at a time.

## Quick start

```matlab
addpath("C:\path\to\dsinstruments-amp-ctrl-matlab")   % or make it the current folder

DSAmp.list_ports()                 % find the COM port
amp = DSAmp("COM6");

amp.status()                       % IDN, gain, output state, temperature, USB voltage, error code
amp.set_gain(25);                  % set gain (0.5 dB steps) and verify by reading it back
amp.fan(true);                     % fan always on: steadier temperature

amp.output_on("LoadConnected", true);   % enable output: read the safety notes below
amp.output_off();                       % disable output

clear amp                          % release the COM port
```

No hardware? Use the simulated device: `amp = DSAmp("SIM");`

The local gain check defaults to the command list's range (0–31 dB, 0.5 dB steps).
If your model's range differs, pass it explicitly: `amp = DSAmp("COM6", "GainMax", 30);`

## Safety

1. **Never enable the output without a 50 Ω load on RF OUT.** The vendor warns that reflected power destroys the final stage within seconds.
   The software cannot detect a load, so `output_on` requires you to write `"LoadConnected", true` explicitly.
2. **Respect the maximum input power of your model** (+10 dBm for the PA20000). This code does not control the signal source.
3. Put your measurement in a **function** and use `onCleanup` so the output is switched off when it ends, fails, or is interrupted. See [`examples/session_template.m`](examples/session_template.m).
   In a script this does not work: the `onCleanup` variable stays in the base workspace after an error or Ctrl+C, and the output stays on.
4. The vendor recommends a USB 3.0 hub with a 12 V supply.

## Features

| Feature | Methods |
|---|---|
| Connect / find port | `DSAmp(port)`, `DSAmp.list_ports()`, `DSAmp.find()` |
| Identity | `idn()`, `rev()`, `ping()`, `unit_name()`, property `model` |
| Gain | `gain()`, `set_gain(db)` |
| Output | `is_on()`, `output_on("LoadConnected", true)`, `output_off()` |
| Health | `temp()`, `volts()`, `errors()`, `debug()`, `clear_errors()`, `status()` |
| Other | `fan(tf)`, `buzzer(tf)`, `enable_buttons()` |
| Raw commands | `query(cmd)`, `send(cmd)`, `send_raw(cmd, wait_s)` |

The current reading shown in AmpCon has no public command and cannot be read from a script.
Commands that change the unit's persistent state (`*UNITNAME <name>`, `*SAVESTATE`, `*RST`) are deliberately not wrapped.
The full GUI ↔ SCPI ↔ method table, with the verification status of each command, is in [`docs/COMMANDS.md`](docs/COMMANDS.md).

Every setting method reads the value back and raises an error if the device does not report what was requested.
This matters because the device itself reports nothing when it rejects a value (see below).

## What a PA20000 actually does

Everything in this section was observed on a PA20000 (firmware V5.16) with MATLAB R2024a.

Reading status and setting gain, output off:

```matlab
>> amp = DSAmp("COM6");
>> amp.set_gain(30)

ans =

    30

>> amp.status()

ans = 

  struct with fields:

        idn: "DS Instruments,PA20000,xxxx,V5.16"
    gain_db: 30
         on: 0
     temp_c: 27
      usb_v: 4.9800
     errors: "0,No error"
       time: 02-Oct-2026 13:39:20
```

(The serial number is masked.)

Warm-up with the fan on, from [`examples/session_template.m`](examples/session_template.m) (gain 30 dB, output on, no RF input):

```
Warm-up: 2 分鐘內溫度變化 <= 1.5 °C，或達到週期振盪穩態（timeout 20 分鐘）
    0.0 min  27 °C
    0.5 min  33 °C
    1.0 min  37 °C
    1.5 min  39 °C
    2.0 min  41 °C
    2.5 min  43 °C
    3.0 min  44 °C
    3.5 min  45 °C
    4.0 min  46 °C
    4.5 min  46 °C
    5.0 min  47 °C
    5.5 min  47 °C
    6.0 min  48 °C
    6.5 min  48 °C
    7.0 min  48 °C
熱穩定（48 °C）。
Measuring at gain 30.0 dB, 48 C
```

Replies, verbatim. Each ends with `\r\n`:

| Command | Reply | Command | Reply |
|---|---|---|---|
| `*PING?` | `PONG!` | `*TEMP?` | `55C` |
| `*IDN?` | `DS Instruments,PA20000,<serial>,V5.16` | `*SYSVOLTS?` | `4.67` |
| `*REV?` | `Rev 6` | `SYST:ERR?` | `0,No error` |
| `GAIN?` | `30.0` (`00.0` at 0 dB) | `SYST:DBG?` | `DeltaRFO=200`, later `Out of range value!` |
| `OUTP:STAT?` | `ON` / `OFF` | unknown command | `[BADCOMMAND]` |

- Setting commands that are accepted (`GAIN 25`, `OUTP:STAT ON`, `FAN ON`, …) produce **no reply at all**.
- An unknown command replies `[BADCOMMAND]`, and `SYST:ERR?` still says `0,No error` afterwards.
- Invalid gain values are **not reported as errors**: `GAIN 10.3` silently became 10.5, and `GAIN -1` was silently ignored.
- `GAIN 31` is accepted, although the PA20000 datasheet lists 0–30 dB.
- `SYST:DBG?` returns the last debug message. It read `Out of range value!` after out-of-range gain values had been sent earlier, so `amp.debug()` may be the place to look when a setting is silently rejected. This is an inference from two readings, not a tested rule.

Effect on the RF output, measured with an NI vector signal transceiver at 5.5 GHz with a small input signal (about −25 dBm), relative power only:

| Item | Measured |
|---|---|
| Output ON relative to OFF | +81 dB |
| Gain 10 → 15 → 20 → 25 → 30 dB | 4.91–5.09 dB per step |
| Gain 29.5 → 30 dB | 0.53 dB |
| Gain 30 → 31 dB | 0.96 dB |
| Same setting (30 dB) as the unit warmed from 29 °C to 37 °C | −0.4 dB |

So the SCPI settings do take effect on RF, 31 dB is real on this unit, and gain drops as the amplifier warms up.
This was checked at one frequency and one drive level only. The measurement script depends on lab-specific equipment and is not part of this repository.

## Troubleshooting

Entries marked *(seen)* were actually encountered on the PA20000. The others follow from how the code works and have not been reproduced on hardware.

| Symptom | Cause and fix |
|---|---|
| `DSAmp is not found in the current folder or on the MATLAB path` *(seen)* | The repository folder is not on the path. `addpath` it, or `cd` into it; the examples and tests do not add it for you. |
| `DSAmp.find()` prints `Warning: The specified amount of data was not returned within the Timeout period for 'readline'` *(seen)* | Expected. `find()` sends `*PING?` to every available port, and each port that is not an amplifier times out with this warning. The returned list is still correct. |
| `DSAmp:open`: cannot open COMx | The port is in use or the name is wrong. Close AmpCon; if an old object is still alive in MATLAB, `clear amp` (or `clear all`); check the name with `DSAmp.list_ports()`. The port number can change after re-plugging USB. |
| `DSAmp:ping`: no reply to `*PING?` | The port is not a DS Instruments amplifier. |
| `DSAmp:load`: refuses to enable output | Intentional. Confirm RF OUT has a 50 Ω load, then call `amp.output_on("LoadConnected", true)`. |
| `DSAmp:gain_range` / `DSAmp:gain_step` | Gain must be within the configured range and a multiple of the step. The check is local because the device does not report invalid values. Adjust with `"GainMin"`, `"GainMax"`, `"GainStep"` if your model differs. |
| `DSAmp:gain_readback` | The device did not take the requested gain. Likely the value is outside what your model supports: lower `"GainMax"`. |
| `DSAmp:badcommand` *(seen)* | The device does not know the command. `amp.errors()` will not tell you more; check the spelling against [`docs/COMMANDS.md`](docs/COMMANDS.md). On another model, the command may not exist. |
| `DSAmp:timeout` | `query` was used on a command that does not reply (use `send` for setting commands), or the device was unplugged. |
| `amp.volts()` reads about 4.67 V *(seen)* | Measured with USB plugged straight into the PC and the output on; 4.98 V with the output off. Everything worked at this voltage, but it is below the vendor's recommendation of a 12 V powered USB 3.0 hub. |
| Measured power slowly drops after enabling the output *(seen)* | Gain falls with temperature. Turn the fan on with `amp.fan(true)` and wait for thermal equilibrium with [`examples/pa_warmup.m`](examples/pa_warmup.m). |
| `amp.unit_name()` returns an empty string *(seen)* | No name has been stored on the unit. Normal. |

Error messages are currently in Traditional Chinese. The error identifiers above (`DSAmp:...`) are stable and are the thing to match on.

## Repository layout

| Path | Content |
|---|---|
| `DSAmp.m` | The control class |
| `examples/` | `quick_status` (read status), `pa_warmup` (warm-up monitor), `session_template` (measurement template, a function) |
| `tests/selftest_sim.m` | Self-test without hardware |
| `tests/hardware_checklist.m` | Staged hardware check that logs raw replies |
| `docs/COMMANDS.md` | GUI ↔ SCPI ↔ method table and verification status |
| `docs/hardware_log/` | Where `hardware_checklist` writes its logs |

## Testing

Without hardware:

```matlab
addpath tests
selftest_sim                      % expect: SELFTEST PASSED (41 checks)
```

A pass here means the class logic and safety checks work against the simulated device. It says nothing about a real amplifier.

With hardware, in four stages of increasing impact. Run them in order and read each result before the next:

```matlab
addpath tests
hardware_checklist("COM6", 1)                        % read-only queries: always safe
hardware_checklist("COM6", 2)                        % fan / buzzer / buttons
hardware_checklist("COM6", 3)                        % gain: output must be OFF; restores the original gain
hardware_checklist("COM6", 4, "LoadConnected", true) % output ON/OFF: load required; ends with output OFF
```

Stage 3 deliberately sends out-of-range values (`GAIN 32`, `GAIN -1`, …) with the output off, to record how the unit reacts.
The checklist only exercises commands that `DSAmp` wraps.

## Other models

If you run the checklist on a model that [`docs/COMMANDS.md`](docs/COMMANDS.md) does not list as verified, please share the logs in an issue or pull request.
That is the only way this repository can honestly claim support for more than one model.

## References

- [PA/GB Amplifier SCPI Command List v3.1](https://www.dsinstruments.com/wp-content/uploads/2022/11/GB6000L-Command-List.pdf)
- [PA & GB Series User Manual](https://www.dsinstruments.com/wp-content/uploads/2026/02/PA-GB-Series-Amplifiers-User-Manual.pdf)
- [RF Output Termination Warning](https://www.dsinstruments.com/wp-content/uploads/2024/03/Termination-Warning-Pro.pdf)
- [DS Instruments Downloads](https://www.dsinstruments.com/downloads/) (AmpCon control software)

## License

[MIT](LICENSE)
