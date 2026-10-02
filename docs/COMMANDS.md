# SCPI commands and verification status

Source: DS Instruments [PA/GB Amplifier SCPI Command List v3.1 (Sept 2022)](https://www.dsinstruments.com/wp-content/uploads/2022/11/GB6000L-Command-List.pdf).
Serial settings: **115200 bps, 8 data bits, 1 stop bit, no parity, no flow control; commands end with LF**.

## Verified models

| Model | Firmware | Hardware rev | Verified by | Scope |
|---|---|---|---|---|
| PA20000 | V5.16 | Rev 6 | author, 2026-10 | see table below |

No other model has been tested. To add one, run `tests/hardware_checklist.m` and share the logs.

## Commands (status on the PA20000)

- ✅ **Hardware**: the SCPI command was sent to the PA20000 and the result was correct
- **not wrapped**: the command exists in the vendor's list, but `DSAmp` has no method for it
- ❔ **Unknown**: no corresponding command in the command list

Which methods and scripts were run is listed under "What was run on hardware" below.

| AmpCon GUI | SCPI | `DSAmp` method | Status | Notes |
|---|---|---|---|---|
| Search / Connect | (open COM port) + `*PING?` → `PONG!` | `DSAmp(port)`, `ping()`, `list_ports()`, `find()` | ✅ | `find()` prints a read-timeout warning for each port that is not an amplifier |
| Device info box | `*IDN?` | `idn()`, property `model` | ✅ | `DS Instruments,PA20000,<serial>,V5.16` |
| — | `*REV?` | `rev()` | ✅ | `Rev 6` |
| Custom Name | `*UNITNAME?` | `unit_name()` | ✅ | Empty reply when no name is stored |
| Save Name | `*UNITNAME <name>` | — | not wrapped | Writes to flash. Never sent to hardware by the author |
| Gain Control | `GAIN <x>` | `set_gain(db)` | ✅ | 0–31 dB in 0.5 dB steps accepted and read back. Verified on RF at 5.5 GHz, small signal |
| (gain display) | `GAIN?` | `gain()` | ✅ | `30.0`; fixed width, zero padded (`00.0`) |
| AMP ON | `OUTP:STAT ON` | `output_on("LoadConnected", true)` | ✅ | Verified on RF: 81 dB above OFF |
| AMP OFF | `OUTP:STAT OFF` | `output_off()` | ✅ | Verified on RF |
| (output state) | `OUTP:STAT?` | `is_on()` | ✅ | `ON` / `OFF` |
| Health: temperature | `*TEMP?` | `temp()` | ✅ | `55C`; 1 °C resolution |
| Health: voltage | `*SYSVOLTS?` | `volts()` | ✅ | `4.67` |
| Health: current | — | — | ❔ | Not in the command list. `*CURR?`, `*SYSCURR?`, `*CURRENT?`, `*SYSAMPS?`, `MEAS:CURR?` all reply `[BADCOMMAND]` |
| Read Errors | `SYST:ERR?` | `errors()` | ✅ | `0,No error` |
| Get Status | `SYST:DBG?` | `debug()` | ✅ | Last debug message. Seen: `DeltaRFO=200`, and `Out of range value!` after out-of-range gain values had been sent |
| — | `*CLS` | `clear_errors()` | ✅ | |
| Save Defaults | `*SAVESTATE` | — | not wrapped | Stores the current gain **and output state** as power-on defaults: saved with the output on, the unit transmits as soon as USB power is applied. Never sent to hardware by the author |
| — | `FAN ON` / `FAN OFF` | `fan(tf)` | ✅ | Both accepted. With the fan on, temperature settled at about 50 °C instead of cycling between 55 and 60 °C. Whether `FAN OFF` forces the fan off or returns it to thermostat control is not confirmed |
| — | `*BUZZER ON` / `OFF` | `buzzer(tf)` | ✅ | |
| — | `*BUTTONS ON` | `enable_buttons()` | ✅ | Accepted; the front-panel effect was not checked separately |
| — | `*RST` | — | not wrapped | Reboots the unit. Never sent to hardware by the author |
| Send Command | any | `query(cmd)`, `send(cmd)`, `send_raw(cmd, wait_s)` | ✅ | |

## What was run on hardware

On the PA20000, firmware V5.16, MATLAB R2024a, with `DSAmp.m` as published:

- Every public method: constructor, property `model`, `DSAmp.list_ports()`, `DSAmp.find()`, `ping()`, `idn()`, `rev()`, `unit_name()`,
  `gain()`, `set_gain()`, `is_on()`, `output_on()`, `output_off()`, `temp()`, `volts()`, `errors()`, `debug()`, `clear_errors()`, `status()`,
  `fan()`, `buzzer()`, `enable_buttons()`, `query()`, `send()`, `send_raw()`.
- The `"GainMin"`, `"GainMax"` and `"GainStep"` options: values outside the configured range or off the step were rejected with `DSAmp:gain_range` / `DSAmp:gain_step`, valid ones were set and read back.
- `tests/hardware_checklist.m` stages 1–4 and `tests/selftest_sim.m`.
- `examples/quick_status.m`, `examples/session_template.m` and, through it, `examples/pa_warmup.m`.
- `session_template` in three ways: a normal run, an error before the output was enabled, and **Ctrl+C during warm-up with the output on**. The output read back OFF afterwards every time, and the COM port was free for the next call.

"Run" means the call completed without error and any value read back was as expected.

## Device behaviour worth knowing (PA20000, V5.16)

- Every reply is a single line ending in `\r\n`.
- Accepted setting commands produce **no reply and no echo**.
- An unknown command replies `[BADCOMMAND]`. `SYST:ERR?` remains `0,No error`, so the error queue cannot be used to detect it.
  `query` and `send` raise `DSAmp:badcommand` instead.
- Invalid gain values are handled silently, with no reply and no error:
  - `GAIN 10.3` → reads back `10.5`
  - `GAIN -1` → gain unchanged
  - `GAIN 32` → reads back `31.0` (it was already 31.0, so clamping and ignoring cannot be told apart)
- The local range check plus read-back in `set_gain` is therefore the only guard against a wrong gain.
- `SYST:DBG?` read `DeltaRFO=200` before any out-of-range value had been sent and `Out of range value!` afterwards, so the debug message appears to record the rejection that `SYST:ERR?` does not. Which of `GAIN 32`, `GAIN 10.3`, `GAIN -1` triggers it was not isolated.
- `OUTP:STAT ON/OFF` reads back correctly 0.2 s after the command.
- USB voltage read 4.66–4.68 V with the output on and 4.98 V with it off (USB plugged straight into the PC).
- Gain falls as the unit warms up: about −0.4 dB from 29 °C to 37 °C at the 30 dB setting.

## Not verified

- The physical effect of `enable_buttons()`: the command is accepted, but nobody checked the front-panel buttons.
- Whether `FAN OFF` forces the fan off or returns it to thermostat control.
- In `examples/pa_warmup.m`: only the "temperature settled" exit was reached. The periodic-oscillation exit and the timeout were not.
- An error raised while the output is on, inside `session_template`. Ctrl+C in that state was verified and uses the same clean-up mechanism; the error case itself was only run on the simulator.
- `DSAmp.find()` with more than one amplifier connected.
- RF behaviour at any frequency other than 5.5 GHz, or at large signal.
- Any model other than the PA20000.
