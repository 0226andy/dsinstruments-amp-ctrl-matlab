# Hardware logs

`tests/hardware_checklist.m` writes `<date_time>_<port>_stage<N>.txt` here, recording the raw reply to every command.
Runs against the simulated device (`"SIM"`) are written to the system temp folder instead, so they can never be mistaken for hardware results.

The reply formats that `DSAmp.m` parses were taken from logs like these, recorded on a PA20000 (firmware V5.16).
Those logs are summarised in [`../COMMANDS.md`](../COMMANDS.md).

If you run the checklist on another model, please share the logs in an issue or pull request.
A log includes your unit's `*IDN?` reply (with its serial number) and the local path of the log file; remove them first if you prefer.

---

`tests/hardware_checklist.m` 會在這裡產生 `<日期時間>_<port>_stage<N>.txt`，逐字記錄每個指令的原始回應。
模擬裝置（`"SIM"`）的 log 會寫到系統暫存資料夾，不會出現在這裡，避免被誤認為實機結果。

`DSAmp.m` 解析的回應格式就是取自這類 log（PA20000、韌體 V5.16），摘要見 [`../COMMANDS.md`](../COMMANDS.md)。

如果你在其他機種上跑了檢查，歡迎把 log 以 issue 或 pull request 分享。
log 內含裝置的 `*IDN?` 回應（有序號）與 log 檔的本機路徑，介意的話請先移除。
