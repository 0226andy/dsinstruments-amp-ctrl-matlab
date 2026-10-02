# dsinstruments-amp-ctrl-matlab

[English](README.md)

用 MATLAB 腳本控制 DS Instruments **PA / GB 系列** USB 放大器，取代 AmpCon GUI。
放大器以 USB 虛擬 COM port 接受 SCPI 文字指令，本專案把這些指令包成一個 MATLAB class：`DSAmp`。

> **只在一個機種上測試過：PA20000（韌體 V5.16）。**
> 原廠的 SCPI 指令表涵蓋 PA / GB 系列，所以其他機種預期可用，但作者一台都沒有測過。
> 用在其他機種時，請先執行 [`tests/hardware_checklist.m`](tests/hardware_checklist.m)，它會記錄你的裝置實際回應什麼。
>
> **這裡的「測試過」是什麼意思。** `DSAmp.m` 的每個方法、兩支測試腳本與三支範例都在 PA20000 上執行過。
> 少數分支沒有跑到：見 [`docs/COMMANDS.md`](docs/COMMANDS.md) 的「Not verified」。

這是獨立專案，與 DS Instruments 沒有關係，也未經其背書。

## 需求

- MATLAB R2020b 以上（使用內建 `serialport`，不需要額外 toolbox）。實際執行過的是 R2024a 與 R2025b，較舊的版本未測試。
- 放大器以 USB 連接電腦。**先關閉 AmpCon**：同一個 COM port 只能被一個程式開啟。

## 快速開始

```matlab
addpath("C:\path\to\dsinstruments-amp-ctrl-matlab")   % 或把它設為目前資料夾

DSAmp.list_ports()                 % 找出可用的 COM port
amp = DSAmp("COM6");

amp.status()                       % IDN、增益、輸出狀態、溫度、USB 電壓、錯誤碼
amp.set_gain(25);                  % 設定增益（0.5 dB 步進），並讀回確認
amp.fan(true);                     % 風扇常開，溫度較穩定

amp.output_on("LoadConnected", true);   % 開啟輸出：見下方安全須知
amp.output_off();                       % 關閉輸出

clear amp                          % 釋放 COM port
```

沒有硬體時可用模擬裝置練習：`amp = DSAmp("SIM");`

增益的本地檢查範圍預設取自指令表（0–31 dB、0.5 dB 步進）。
你的機種範圍不同時，請明確指定：`amp = DSAmp("COM6", "GainMax", 30);`

## 安全須知

1. **RF 輸出端沒有接 50 Ω 負載時，絕對不可開啟輸出。** 原廠警告：反射能量會在數秒內燒毀末級放大器。
   程式無法偵測負載，所以 `output_on` 要求你明確寫出 `"LoadConnected", true`。
2. **遵守你的機種的最大輸入功率**（PA20000 為 +10 dBm）。本程式不控制訊號源。
3. 把量測寫成 **function**，並用 `onCleanup` 確保結束、出錯或被中斷時關閉輸出（範例：[`examples/session_template.m`](examples/session_template.m)）。
   寫成 script 沒有用：出錯或 Ctrl+C 之後 `onCleanup` 變數還留在 base workspace，輸出會一直開著。
4. 原廠建議使用有 12 V 外接電源的 USB 3.0 hub。

## 功能

| 功能 | 方法 |
|---|---|
| 連線 / 找 port | `DSAmp(port)`、`DSAmp.list_ports()`、`DSAmp.find()` |
| 識別 | `idn()`、`rev()`、`ping()`、`unit_name()`、屬性 `model` |
| 增益 | `gain()`、`set_gain(db)` |
| 輸出 | `is_on()`、`output_on("LoadConnected", true)`、`output_off()` |
| 健康狀態 | `temp()`、`volts()`、`errors()`、`debug()`、`clear_errors()`、`status()` |
| 其他 | `fan(tf)`、`buzzer(tf)`、`enable_buttons()` |
| 原始指令 | `query(cmd)`、`send(cmd)`、`send_raw(cmd, wait_s)` |

AmpCon 上的電流讀數沒有對應的公開指令，無法以腳本讀取。
會改變裝置持久狀態的指令（`*UNITNAME <name>`、`*SAVESTATE`、`*RST`）刻意不包裝。
完整的 GUI ↔ SCPI ↔ 方法對照與各指令的驗證狀態見 [`docs/COMMANDS.md`](docs/COMMANDS.md)（英文）。

每個設定類方法都會讀回確認，裝置回報的值與要求不符就報錯。
這很重要，因為裝置拒絕一個值的時候自己不會回報任何東西（見下一節）。

## PA20000 的實際行為

本節內容皆為 PA20000（韌體 V5.16）、MATLAB R2024a 上的實際觀察。

讀取狀態與設定增益（輸出 OFF）：

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

（序號已遮蔽。）

風扇常開下的暖機，取自 [`examples/session_template.m`](examples/session_template.m)（gain 30 dB、輸出 ON、無 RF 輸入）：

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

逐字回應，每個回應以 `\r\n` 結尾：

| 指令 | 回應 | 指令 | 回應 |
|---|---|---|---|
| `*PING?` | `PONG!` | `*TEMP?` | `55C` |
| `*IDN?` | `DS Instruments,PA20000,<序號>,V5.16` | `*SYSVOLTS?` | `4.67` |
| `*REV?` | `Rev 6` | `SYST:ERR?` | `0,No error` |
| `GAIN?` | `30.0`（0 dB 時為 `00.0`） | `SYST:DBG?` | `DeltaRFO=200`，之後為 `Out of range value!` |
| `OUTP:STAT?` | `ON` / `OFF` | 不認得的指令 | `[BADCOMMAND]` |

- 被接受的設定類指令（`GAIN 25`、`OUTP:STAT ON`、`FAN ON` …）**完全沒有回應**。
- 不認得的指令回 `[BADCOMMAND]`，之後 `SYST:ERR?` 仍是 `0,No error`。
- 不合法的增益值**不會被回報為錯誤**：`GAIN 10.3` 被靜默改成 10.5，`GAIN -1` 被靜默忽略。
- `GAIN 31` 會被接受，雖然 PA20000 的規格只標 0–30 dB。
- `SYST:DBG?` 回傳最後一則除錯訊息。在先前送過超界的增益值之後，它讀到 `Out of range value!`，所以設定被靜默拒絕時可以用 `amp.debug()` 查看。這是由兩次讀值推論的，不是測試過的規則。

設定在 RF 輸出上的效果，以 NI vector signal transceiver 在 5.5 GHz、小輸入訊號（約 −25 dBm）下量測，只看相對功率：

| 項目 | 實測 |
|---|---|
| 輸出 ON 相對 OFF | +81 dB |
| 增益 10 → 15 → 20 → 25 → 30 dB | 每步 4.91–5.09 dB |
| 增益 29.5 → 30 dB | 0.53 dB |
| 增益 30 → 31 dB | 0.96 dB |
| 同一設定（30 dB），放大器由 29 °C 升到 37 °C | −0.4 dB |

所以 SCPI 設定確實會在 RF 上生效，這台的 31 dB 是真的，而且增益會隨放大器升溫而下降。
這只在一個頻率、一個驅動位準下確認過。量測腳本依賴實驗室特定的設備，不包含在本 repo。

## 常見錯誤排除

標示「實機」的項目在 PA20000 上實際遇過；其餘是依程式行為整理，尚未在實機重現。

| 現象 | 原因與處理 |
|---|---|
| `DSAmp is not found in the current folder or on the MATLAB path`（實機） | repo 資料夾不在 path 上。請 `addpath` 或 `cd` 進去；範例與測試不會自動加入。 |
| `DSAmp.find()` 印出 `Warning: The specified amount of data was not returned within the Timeout period for 'readline'`（實機） | 屬正常。`find()` 會對每個可用的 port 送 `*PING?`，不是放大器的 port 會 timeout 並出現這個警告；回傳的清單仍然正確。 |
| `DSAmp:open`：無法開啟 COMx | COM port 被占用或名稱不對。關閉 AmpCon；若 MATLAB 裡還有舊的物件，先 `clear amp`（或 `clear all`）；以 `DSAmp.list_ports()` 確認名稱。重新插拔 USB 後 port 編號可能改變。 |
| `DSAmp:ping`：沒有回應 `*PING?` | 該 port 不是 DS Instruments 放大器。 |
| `DSAmp:load`：拒絕開啟輸出 | 這是刻意的保護。確認 RF OUT 已接 50 Ω 負載後，以 `amp.output_on("LoadConnected", true)` 呼叫。 |
| `DSAmp:gain_range` / `DSAmp:gain_step` | 增益需在設定的範圍內、且為步進的整數倍。因為裝置不會回報不合法的值，所以由程式在本地檢查。機種不同時以 `"GainMin"`、`"GainMax"`、`"GainStep"` 調整。 |
| `DSAmp:gain_readback` | 裝置沒有接受要求的增益。多半是超出你的機種支援的範圍：請調低 `"GainMax"`。 |
| `DSAmp:badcommand`（實機） | 裝置不認得這個指令。`amp.errors()` 查不到更多資訊；請對照 [`docs/COMMANDS.md`](docs/COMMANDS.md) 檢查拼字。在其他機種上，也可能是該指令不存在。 |
| `DSAmp:timeout` | 對不會回應的指令使用了 `query`（設定類指令請用 `send`），或裝置已斷線。 |
| `amp.volts()` 約 4.67 V（實機） | USB 直插電腦且輸出為 ON 時的讀值；輸出 OFF 時為 4.98 V。此電壓下一切正常，但低於原廠建議（12 V 供電的 USB 3.0 hub）。 |
| 開啟輸出後量到的功率慢慢下降（實機） | 增益隨溫度下降。先 `amp.fan(true)`，並以 [`examples/pa_warmup.m`](examples/pa_warmup.m) 等到熱穩定。 |
| `amp.unit_name()` 回傳空字串（實機） | 裝置沒有設定過名稱，屬正常。 |

錯誤訊息目前是繁體中文。上表的錯誤 ID（`DSAmp:...`）是穩定的，程式判斷請以 ID 為準。

## 目錄

| 路徑 | 內容 |
|---|---|
| `DSAmp.m` | 控制 class |
| `examples/` | `quick_status`（讀狀態）、`pa_warmup`（暖機監控）、`session_template`（量測範本，是 function） |
| `tests/selftest_sim.m` | 無硬體自我測試 |
| `tests/hardware_checklist.m` | 分階段實機檢查，逐字記錄原始回應 |
| `docs/COMMANDS.md` | GUI ↔ SCPI ↔ 方法對照與驗證狀態（英文） |
| `docs/hardware_log/` | `hardware_checklist` 寫入 log 的位置 |

## 測試

無硬體：

```matlab
addpath tests
selftest_sim                      % 預期：SELFTEST PASSED (41 checks)
```

這裡通過只代表 class 的邏輯與安全檢查在模擬裝置上正確，不代表實機可用。

有硬體時分四個階段，對裝置的影響逐步增加。請依序執行，看完每一階段的結果再往下：

```matlab
addpath tests
hardware_checklist("COM6", 1)                        % 只讀查詢：任何時候都安全
hardware_checklist("COM6", 2)                        % 風扇 / 蜂鳴器 / 按鈕
hardware_checklist("COM6", 3)                        % 增益：需輸出 OFF；結束時還原原增益
hardware_checklist("COM6", 4, "LoadConnected", true) % 輸出 ON/OFF：需已接負載；結束時輸出 OFF
```

Stage 3 會在輸出 OFF 的狀態下刻意送出超界值（`GAIN 32`、`GAIN -1` …），記錄裝置如何反應。
檢查只涵蓋 `DSAmp` 有包裝的指令。

## 其他機種

如果你在 [`docs/COMMANDS.md`](docs/COMMANDS.md) 尚未列為已驗證的機種上跑了檢查，歡迎把 log 以 issue 或 pull request 分享。
這是本 repo 能誠實宣稱支援多個機種的唯一方式。

## 參考

- [PA/GB Amplifier SCPI Command List v3.1](https://www.dsinstruments.com/wp-content/uploads/2022/11/GB6000L-Command-List.pdf)
- [PA & GB Series User Manual](https://www.dsinstruments.com/wp-content/uploads/2026/02/PA-GB-Series-Amplifiers-User-Manual.pdf)
- [RF Output Termination Warning](https://www.dsinstruments.com/wp-content/uploads/2024/03/Termination-Warning-Pro.pdf)
- [DS Instruments Downloads](https://www.dsinstruments.com/downloads/)（AmpCon 控制軟體）

## 授權

[MIT](LICENSE)
