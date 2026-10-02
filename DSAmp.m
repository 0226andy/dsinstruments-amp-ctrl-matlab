% ----------------------------------------------------------------%
% Class :
%   DS Instruments PA / GB 系列 Smart Amplifier 的 USB SCPI 控制，
%   用來取代 AmpCon GUI，讓放大器設定可以寫進 MATLAB 腳本。
%   Scripted USB SCPI control of DS Instruments PA / GB series amplifiers.
%
%   指令依據：DS Instruments "PA/GB Amplifier SCPI Command List" v3.1 (Sept 2022)
%   COM 設定：115200 bps, 8N1, no flow control, terminator = LF
%   同一個 COM port 同時只能被一個程式開啟：使用前必須關閉 AmpCon。
%
% Usage :
%   amp = DSAmp("COM6");            % "SIM" = 模擬裝置（無硬體測試用）
%   amp.status()                    % 一次讀取 IDN / 增益 / 輸出 / 溫度 / 電壓 / 錯誤
%   amp.set_gain(25);               % 設定增益並讀回確認
%   amp.output_off();               % 關閉輸出（永遠安全）
%   amp.output_on("LoadConnected", true);   % 開啟輸出：必須明確聲明輸出端已接 50 Ω 負載
%   clear amp                       % 釋放 COM port
%
%   amp = DSAmp("COM6", "GainMax", 30);     % 機種的增益範圍不同時，自行指定本地檢查的範圍
%
% 驗證狀態（詳見 docs/COMMANDS.md）：
%   只在 PA20000（韌體 V5.16）上驗證過。同系列其他機種依原廠文件使用同一份指令表，
%   但作者沒有測過；第一次用在其他機種時，請先執行 tests/hardware_checklist.m。
% ----------------------------------------------------------------%

classdef DSAmp < handle
    properties (SetAccess = private)
        port string
        is_sim (1,1) logical = false
        model string = ""            % *IDN? 的第二欄，例如 "PA20000"
        % set_gain 的本地檢查範圍。預設取自指令表（0–31 dB、0.5 dB 步進）；
        % PA20000 的規格只標到 30 dB，但實機接受 31 dB 且 RF 上確實多約 1 dB
        gain_min (1,1) double = 0
        gain_max (1,1) double = 31
        gain_step (1,1) double = 0.5
    end

    properties (Access = private)
        dev = []                 % serialport 物件；SIM 模式為空
        settle_s = 0.2           % 設定類指令送出後等待裝置處理的時間
        sim                      % 模擬裝置狀態
    end

    methods
        %% 連線
        function obj = DSAmp(port, opts)
            arguments
                port (1,1) string
                opts.Timeout (1,1) double {mustBePositive} = 2
                opts.GainMin (1,1) double = 0
                opts.GainMax (1,1) double = 31
                opts.GainStep (1,1) double {mustBePositive} = 0.5
            end
            if opts.GainMax <= opts.GainMin
                error('DSAmp:config', 'GainMax（%g）必須大於 GainMin（%g）。', opts.GainMax, opts.GainMin);
            end
            obj.port      = port;
            obj.gain_min  = opts.GainMin;
            obj.gain_max  = opts.GainMax;
            obj.gain_step = opts.GainStep;

            if port == "SIM"
                obj.is_sim = true;
                obj.sim = struct('gain', 30, 'on', false, 'temp', 35, 'volts', 5.0, ...
                    'fan', false, 'buzzer', true, 'name', "");
            else
                try
                    obj.dev = serialport(port, 115200, 'DataBits', 8, 'StopBits', 1, ...
                        'Parity', 'none', 'FlowControl', 'none', 'Timeout', opts.Timeout);
                    configureTerminator(obj.dev, "LF");
                    flush(obj.dev);
                catch ME
                    error('DSAmp:open', ['無法開啟 %s：%s\n' ...
                        '請確認 AmpCon 已關閉（COM port 被占用），並以 DSAmp.list_ports() 確認 port 名稱。'], ...
                        port, ME.message);
                end
                if ~obj.ping()
                    error('DSAmp:ping', '%s 沒有回應 *PING?，請確認連接的是 DS Instruments 放大器。', port);
                end
            end

            parts = split(obj.idn(), ",");
            if numel(parts) >= 2
                obj.model = strtrim(parts(2));
            end
        end

        function delete(obj)
            obj.dev = [];        % 釋放 serialport 物件即關閉 COM port
        end

        %% 識別
        function tf = ping(obj)
            tf = contains(obj.query("*PING?"), "PONG", 'IgnoreCase', true);
        end

        function s = idn(obj)
            s = obj.query("*IDN?");
        end

        function s = rev(obj)
            s = obj.query("*REV?");
        end

        function s = unit_name(obj)
            s = obj.query("*UNITNAME?");       % 沒設定過名稱的裝置回傳空字串
        end

        %% 增益
        function g = gain(obj)
            g = parse_number(obj.query("GAIN?"), "GAIN?");
        end

        function g = set_gain(obj, gain_db)
            % 設定後一律以 GAIN? 讀回；裝置實際值與要求值不符即報錯，避免以錯誤增益繼續量測。
            % 裝置對超界 / 非步進的值不會回報錯誤，只會靜默忽略或進位，所以先在本地檢查
            arguments
                obj
                gain_db (1,1) double
            end
            if gain_db < obj.gain_min || gain_db > obj.gain_max
                error('DSAmp:gain_range', '增益 %.2f dB 超出範圍 %g–%g dB。', gain_db, obj.gain_min, obj.gain_max);
            end
            if abs(gain_db/obj.gain_step - round(gain_db/obj.gain_step)) > 1e-9
                error('DSAmp:gain_step', '增益需為 %g dB 的整數倍。', obj.gain_step);
            end
            obj.send(sprintf("GAIN %g", gain_db));
            g = obj.gain();
            if abs(g - gain_db) > obj.gain_step/2
                error('DSAmp:gain_readback', '要求 %.1f dB，裝置讀回 %.1f dB。', gain_db, g);
            end
        end

        %% 輸出開關
        function on = is_on(obj)
            r = upper(obj.query("OUTP:STAT?"));
            if any(r == ["ON", "1"])
                on = true;
            elseif any(r == ["OFF", "0"])
                on = false;
            else
                error('DSAmp:parse', 'OUTP:STAT? 回應無法解析："%s"', r);
            end
        end

        function output_off(obj)
            % 關閉輸出永遠安全，可放在腳本結尾或 onCleanup 中自動執行
            obj.send("OUTP:STAT OFF");
            if obj.is_on()
                error('DSAmp:output', '送出 OUTP:STAT OFF 後裝置仍回報 ON。');
            end
        end

        function output_on(obj, opts)
            % 原廠警告：輸出埠開路時開啟放大器，反射能量會在數秒內燒毀末級。
            % 程式無法偵測輸出端是否有負載，因此要求呼叫者明確聲明。
            arguments
                obj
                opts.LoadConnected (1,1) logical = false
            end
            if ~opts.LoadConnected
                error('DSAmp:load', ['拒絕開啟輸出：請先確認 RF 輸出端已接 50 Ω 負載（衰減器 / 儀器輸入），' ...
                    '再以 amp.output_on("LoadConnected", true) 呼叫。']);
            end
            obj.send("OUTP:STAT ON");
            if ~obj.is_on()
                error('DSAmp:output', '送出 OUTP:STAT ON 後裝置仍回報 OFF（請以 amp.errors() 查看原因）。');
            end
        end

        %% 健康狀態
        function t = temp(obj)
            t = parse_number(obj.query("*TEMP?"), "*TEMP?");      % 解析度 1 °C
        end

        function v = volts(obj)
            v = parse_number(obj.query("*SYSVOLTS?"), "*SYSVOLTS?");
        end

        function s = errors(obj)
            s = obj.query("SYST:ERR?");
        end

        function s = debug(obj)
            s = obj.query("SYST:DBG?");
        end

        function clear_errors(obj)
            obj.send("*CLS");
        end

        function st = status(obj)
            st.idn     = obj.idn();
            st.gain_db = obj.gain();
            st.on      = obj.is_on();
            st.temp_c  = obj.temp();
            st.usb_v   = obj.volts();
            st.errors  = obj.errors();
            st.time    = datetime('now');
        end

        %% 其他設定
        function fan(obj, on)
            % 韌體預設以溫控開關風扇，溫度會週期振盪（PA20000 實測約 55–60 °C）；
            % 風扇常開後恆定約 50 °C，量測時增益較穩定
            arguments
                obj
                on (1,1) logical
            end
            obj.send("FAN " + onoff(on));
        end

        function buzzer(obj, on)
            arguments
                obj
                on (1,1) logical
            end
            obj.send("*BUZZER " + onoff(on));
        end

        function enable_buttons(obj)
            % 遠端控制後重新啟用前面板按鈕
            obj.send("*BUTTONS ON");
        end

        %% 原始指令（對應 AmpCon 的 Send Command）
        function r = query(obj, cmd)
            % 送出查詢指令並回傳一行回應
            arguments
                obj
                cmd (1,1) string
            end
            if obj.is_sim
                r = obj.sim_io(cmd);
                if strlength(r) == 0 && ~endsWith(strtrim(cmd), "?")
                    error('DSAmp:timeout', 'SIM 對 "%s" 沒有回應（模擬 timeout）。', cmd);
                end
                check_bad_command(r, cmd);
                return
            end
            flush(obj.dev, "input");     % 丟棄設定類指令可能殘留的回應，避免讀到錯行
            writeline(obj.dev, cmd);
            r = readline(obj.dev);
            if isempty(r)
                error('DSAmp:timeout', '%s 對 "%s" 沒有回應（timeout）。', obj.port, cmd);
            end
            r = strtrim(string(r));
            check_bad_command(r, cmd);
        end

        function send(obj, cmd)
            % 送出不期待回應的設定類指令。
            % 實機對被接受的設定類指令不回應、對不認得的指令回 [BADCOMMAND]，且 SYST:ERR? 不會留下紀錄，
            % 所以只能在這裡檢查等待期間收到的內容
            arguments
                obj
                cmd (1,1) string
            end
            if obj.is_sim
                check_bad_command(obj.sim_io(cmd), cmd);
                return
            end
            flush(obj.dev, "input");     % 避免把先前殘留的回應當成這個指令的
            writeline(obj.dev, cmd);
            pause(obj.settle_s);
            n = obj.dev.NumBytesAvailable;
            if n > 0
                check_bad_command(string(char(read(obj.dev, n, "uint8"))), cmd);
            end
        end

        function raw = send_raw(obj, cmd, wait_s)
            % 送出任意指令，等待 wait_s 秒後回傳這段時間收到的所有字元（可能為空）。
            % 用來探查實機行為：設定類指令是否有回應 / echo、回應是否多行。
            arguments
                obj
                cmd (1,1) string
                wait_s (1,1) double {mustBeNonnegative} = 0.5
            end
            if obj.is_sim
                raw = obj.sim_io(cmd);
                if strlength(raw) > 0 || endsWith(strtrim(cmd), "?")
                    raw = raw + string(char([13 10]));       % 實機每個回應以 CR LF 結尾
                end
                return
            end
            flush(obj.dev, "input");
            writeline(obj.dev, cmd);
            pause(wait_s);
            n = obj.dev.NumBytesAvailable;
            if n == 0
                raw = "";
            else
                raw = string(char(read(obj.dev, n, "uint8")));
            end
        end
    end

    methods (Static)
        function ports = list_ports()
            % 目前可開啟的 COM port（被 AmpCon 占用的不會出現）
            ports = serialportlist("available");
        end

        function found = find()
            % 對每個可用 port 送 *PING?，回傳有回應 PONG 的 port。
            % 注意：會對「所有」可用序列埠送出字串，桌上若有其他序列裝置請改用 list_ports() 手動指定。
            found = strings(1, 0);
            for p = DSAmp.list_ports()
                try
                    amp = DSAmp(p, "Timeout", 0.5); %#ok<NASGU>
                    found(end+1) = p; %#ok<AGROW>
                    clear amp
                catch
                    % 不是 DS Instruments 放大器或無法開啟：略過
                end
            end
        end
    end

    methods (Access = private)
        function r = sim_io(obj, cmd)
            % 有狀態的模擬裝置：讓設定類方法與錯誤處理在無硬體時也能測試。
            % 回應內容（不含結尾 CR LF）比照 PA20000（韌體 V5.16）實機的逐字回應：
            % 被接受的設定類指令不回應；不認得的指令回 [BADCOMMAND]；SYST:ERR? 始終為 "0,No error"。
            r = "";
            c = upper(strtrim(cmd));
            arg = strtrim(extractAfter(cmd + " ", " "));
            switch true
                case c == "*PING?",      r = "PONG!";
                case c == "*IDN?",       r = "DS Instruments,PA20000,SIM,V0.00";
                case c == "*REV?",       r = "Rev 6";
                case c == "*UNITNAME?",  r = obj.sim.name;       % 實機名稱為空時回應只有 CR LF
                case c == "GAIN?",       r = string(sprintf('%04.1f', obj.sim.gain));    % 固定寬度補零：0 dB 回 "00.0"
                case c == "OUTP:STAT?",  r = onoff(obj.sim.on);
                case c == "*TEMP?",      r = string(obj.sim.temp) + "C";
                case c == "*SYSVOLTS?",  r = string(sprintf('%.2f', obj.sim.volts));
                case c == "SYST:ERR?",   r = "0,No error";
                case c == "SYST:DBG?",   r = "DeltaRFO=200";
                case any(c == ["*CLS", "*BUTTONS ON"])
                case startsWith(c, "GAIN ")
                    % 實機（PA20000）：10.3 → 10.5（進位到 0.5 dB 步進）、-1 → 不變、32 → 維持 31（截斷或忽略無法區分）。
                    % 這裡把超界值一律當作忽略、非步進值四捨五入，皆不回報錯誤；細節是推測，不可當作實機規格。
                    % 範圍固定為模擬的那台裝置的 0–31 dB，與使用者設定的本地檢查範圍無關
                    g = str2double(arg);
                    if ~isnan(g) && g >= 0 && g <= 31
                        obj.sim.gain = round(g/0.5)*0.5;
                    end
                case c == "OUTP:STAT ON",         obj.sim.on = true;
                case c == "OUTP:STAT OFF",        obj.sim.on = false;
                case any(c == ["FAN ON", "FAN OFF"]),         obj.sim.fan = endsWith(c, " ON");
                case any(c == ["*BUZZER ON", "*BUZZER OFF"]), obj.sim.buzzer = endsWith(c, " ON");
                otherwise,               r = "[BADCOMMAND]";
            end
        end
    end
end

function s = onoff(tf)
    if tf, s = "ON"; else, s = "OFF"; end
end

function check_bad_command(r, cmd)
    if contains(r, "[BADCOMMAND]")
        error('DSAmp:badcommand', '裝置不認得指令 "%s"（回應 [BADCOMMAND]）。', cmd);
    end
end

% 回應可能為 "30.0" 或帶單位/前綴（如 "55C"），取第一個數字
function v = parse_number(r, cmd)
    tok = regexp(char(r), '[-+]?\d+(\.\d+)?', 'match', 'once');   % char 輸入：無匹配時回傳 ''
    if isempty(tok)
        error('DSAmp:parse', '%s 回應無法解析為數字："%s"', cmd, r);
    end
    v = str2double(tok);
end
