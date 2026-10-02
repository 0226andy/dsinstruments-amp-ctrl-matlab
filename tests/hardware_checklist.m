% ----------------------------------------------------------------%
% Function :
%   實機驗證 DSAmp.m，並把每個指令的「原始回應」逐字記錄到
%   docs/hardware_log/<日期時間>_<port>_stage<N>.txt，作為回應格式的依據。
%   依風險分四個階段，數字越大對硬體狀態的影響越大；請由 1 開始逐階段執行。
%
%   Stage 1  只讀查詢                      任何時候都安全
%   Stage 2  風扇 / 蜂鳴器 / 按鈕           不影響 RF；結束時風扇 ON、蜂鳴器 ON
%   Stage 3  設定增益                      需輸出為 OFF；結束時還原原增益
%   Stage 4  輸出 ON / OFF                 需 RF 輸出端已接 50 Ω 負載；結束時保持 OFF
%
% Usage（repo 根目錄；先關閉 AmpCon）：
%   addpath tests
%   hardware_checklist("COM6", 1)
%   hardware_checklist("COM6", 2)
%   hardware_checklist("COM6", 3)
%   hardware_checklist("COM6", 4, "LoadConnected", true)
%
%   只測試 DSAmp 有包裝的指令。*UNITNAME <name>、*SAVESTATE、*RST 會改變裝置的持久狀態，不在此列。
% ----------------------------------------------------------------%

function hardware_checklist(port, stage, opts)
    arguments
        port (1,1) string
        stage (1,1) double {mustBeMember(stage, 1:4)}
        opts.LoadConnected (1,1) logical = false
    end
    amp = DSAmp(port);          % 先連線：連線失敗不應在實機紀錄資料夾留下空檔
    if port == "SIM"
        log_dir = fullfile(tempdir, 'dsamp_hardware_log');     % 模擬結果不可混入實機紀錄
    else
        log_dir = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'docs', 'hardware_log');
    end
    if ~isfolder(log_dir), mkdir(log_dir); end
    log_file = fullfile(log_dir, sprintf('%s_%s_stage%d.txt', ...
        char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')), port, stage));
    fid = fopen(log_file, 'w');
    if fid < 0, error('hardware_checklist:log', '無法寫入 %s', log_file); end
    closer = onCleanup(@() fclose(fid));
    out = @(varargin) tee(fid, varargin{:});

    out('DSAmp hardware checklist | port %s | stage %d | %s\n', port, stage, char(datetime('now')));
    out('MATLAB %s\n\n', version);

    switch stage
        case 1, stage1_queries(amp, out);
        case 2, stage2_misc(amp, out);
        case 3, stage3_gain(amp, out);
        case 4, stage4_output(amp, out, opts.LoadConnected);
    end
    out('\nSTAGE %d DONE. Log: %s\n', stage, log_file);
    if port ~= "SIM"
        out('若這是 docs/COMMANDS.md 尚未列為已驗證的機種，歡迎把 log 以 issue 或 pull request 回報。\n');
    end
end

%% Stage 1：所有查詢指令的原始回應
function stage1_queries(amp, out)
    for c = ["*PING?", "*IDN?", "*REV?", "*UNITNAME?", "GAIN?", "OUTP:STAT?", ...
             "*TEMP?", "*SYSVOLTS?", "SYST:ERR?", "SYST:DBG?"]
        probe(amp, out, c);
    end
    % 探查用：指令表未列出、但 AmpCon 顯示電流，試幾個常見寫法（無回應屬正常）
    out('\n-- 未公開指令探查（無回應 = 不支援）--\n');
    for c = ["*CURR?", "*SYSCURR?", "*CURRENT?", "*SYSAMPS?", "MEAS:CURR?"]
        probe(amp, out, c);
    end
    out('SYST:ERR? after probing: "%s"\n', show(amp.send_raw("SYST:ERR?", 0.5)));
    amp.clear_errors();
    st = amp.status();
    out('\nparsed status(): gain %.1f dB | on %d | %.1f C | %.2f V\n', st.gain_db, st.on, st.temp_c, st.usb_v);
end

%% Stage 2：不影響 RF 的設定
function stage2_misc(amp, out)
    for c = ["FAN ON", "FAN OFF", "FAN ON", "*BUZZER OFF", "*BUZZER ON", "*BUTTONS ON", "*CLS"]
        probe(amp, out, c);
        out('    SYST:ERR? -> "%s"\n', amp.errors());
    end
    out('*UNITNAME? -> "%s"\n', amp.unit_name());
    out('\n風扇目前為 ON（建議量測時維持）。請以聽覺 / 目視確認 FAN ON/OFF 是否真的切換，並記在 log 檔尾。\n');
end

%% Stage 3：增益設定（輸出需為 OFF）
function stage3_gain(amp, out)
    if amp.is_on()
        error('hardware_checklist:on', 'Stage 3 需在輸出 OFF 下進行：請先 amp.output_off() 或在 AmpCon 按 AMP OFF。');
    end
    g0 = amp.gain();
    restore = onCleanup(@() amp.send(sprintf("GAIN %g", g0)));
    out('original gain: %.1f dB\n', g0);
    % 30.5 / 31：指令表寫 0–31、產品規格寫 0–30，藉此確認實機上限與超界時的行為
    for g = [10, 10.5, 0, 30, 30.5, 31]
        raw = amp.send_raw(sprintf("GAIN %g", g), 0.5);
        out('GAIN %-5g -> raw "%s" | GAIN? "%s" | SYST:ERR? "%s"\n', g, show(raw), amp.query("GAIN?"), amp.errors());
    end
    out('\n-- 超界 / 非步進值的裝置行為（僅記錄，不經 set_gain 的檢查）--\n');
    for s = ["GAIN 32", "GAIN 10.3", "GAIN -1"]
        raw = amp.send_raw(s, 0.5);
        out('%-10s -> raw "%s" | GAIN? "%s" | SYST:ERR? "%s"\n', s, show(raw), amp.query("GAIN?"), amp.errors());
    end
    clear restore
    out('\nrestored gain: %.1f dB（預期 %.1f）\n', amp.gain(), g0);
    out('set_gain() 讀回測試: %.1f dB\n', amp.set_gain(g0));
end

%% Stage 4：輸出開關（需已接負載）
function stage4_output(amp, out, load_connected)
    if ~load_connected
        error('hardware_checklist:load', ['Stage 4 會開啟放大器輸出。請確認 RF OUT 已接 50 Ω 負載（功率耐受 >= 2 W 的衰減器），' ...
            '再以 hardware_checklist(port, 4, "LoadConnected", true) 執行。']);
    end
    safe_off = onCleanup(@() amp.send("OUTP:STAT OFF"));          % 任何錯誤都以 OFF 結束
    out('initial OUTP:STAT? "%s" | temp %.0f C\n', amp.query("OUTP:STAT?"), amp.temp());
    for s = ["OUTP:STAT OFF", "OUTP:STAT ON", "OUTP:STAT OFF"]
        raw = amp.send_raw(s, 0.5);
        out('%-14s -> raw "%s" | OUTP:STAT? "%s" | SYST:ERR? "%s"\n', s, show(raw), amp.query("OUTP:STAT?"), amp.errors());
    end
    amp.output_on("LoadConnected", true);
    out('output_on() -> is_on %d\n', amp.is_on());
    amp.output_off();
    out('output_off() -> is_on %d\n', amp.is_on());
    out('\n輸出已保持 OFF。\n');
end

%% 送出指令並記錄原始回應
function probe(amp, out, cmd)
    raw = amp.send_raw(cmd, 0.5);
    out('%-24s -> "%s"\n', cmd, show(raw));
end

% 讓 CR / LF 在 log 中可見，才能確認結尾字元與是否多行
function s = show(raw)
    s = replace(raw, [string(char(13)), newline], ["\r", "\n"]);
end

function tee(fid, varargin)
    fprintf(varargin{:});
    fprintf(fid, varargin{:});
end
