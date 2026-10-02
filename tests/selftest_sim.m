%% -----------------------------------------------------------------
% 無硬體自我測試：以模擬裝置 DSAmp("SIM") 驗證所有方法與安全檢查。
% 修改 DSAmp.m 後先跑這支；通過才接上硬體做 tests/hardware_checklist.m。
%
% Usage（在 repo 根目錄）：
%   addpath tests; selftest_sim
% --------------------------------------------------------------- %

clear variables; clc;
amp = DSAmp("SIM");
n = 0;

%% 識別與查詢
assert(amp.ping());                                               n = n + 1;
assert(contains(amp.idn(), "PA20000"));                           n = n + 1;
assert(strlength(amp.rev()) > 0);                                 n = n + 1;
st = amp.status();
assert(all(isfield(st, {'idn', 'gain_db', 'on', 'temp_c', 'usb_v', 'errors', 'time'}))); n = n + 1;
assert(st.gain_db == 30 && ~st.on && st.temp_c == 35);           n = n + 1;

%% 增益：正常設定、範圍、步進
assert(amp.set_gain(12.5) == 12.5 && amp.gain() == 12.5);          n = n + 1;
assert(amp.set_gain(0) == 0);                                     n = n + 1;
assert(amp.set_gain(amp.gain_max) == amp.gain_max);       n = n + 1;
expect_error(@() amp.set_gain(-0.5), 'DSAmp:gain_range');       n = n + 1;
expect_error(@() amp.set_gain(31.5), 'DSAmp:gain_range');       n = n + 1;
expect_error(@() amp.set_gain(10.3), 'DSAmp:gain_step');        n = n + 1;
assert(amp.gain() == amp.gain_max, '被拒絕的設定不可改變裝置狀態'); n = n + 1;

%% 回應格式與裝置行為：比照 PA20000（韌體 V5.16）實機的逐字回應
amp.set_gain(0);
assert(amp.query("GAIN?") == "00.0" && amp.gain() == 0, 'GAIN? 補零格式');  n = n + 1;
assert(amp.query("*TEMP?") == "35C" && amp.temp() == 35, '*TEMP? 帶單位字尾'); n = n + 1;
assert(amp.send_raw("GAIN?") == "00.0" + string(char([13 10])), '回應以 CR LF 結尾'); n = n + 1;
assert(amp.send_raw("FAN ON") == "", '被接受的設定類指令沒有回應');      n = n + 1;
amp.send("GAIN 10.3");                 % 繞過 set_gain 的檢查：裝置靜默進位到 0.5 dB 步進
assert(amp.gain() == 10.5);                                       n = n + 1;
amp.send("GAIN -1");                   % 超界值被靜默忽略，不回報錯誤
assert(amp.gain() == 10.5 && amp.errors() == "0,No error");        n = n + 1;
amp.set_gain(amp.gain_max);

%% 輸出開關：未聲明負載必須拒絕
expect_error(@() amp.output_on(), 'DSAmp:load');                n = n + 1;
expect_error(@() amp.output_on("LoadConnected", false), 'DSAmp:load'); n = n + 1;
assert(~amp.is_on(), '被拒絕的 output_on 不可開啟輸出');           n = n + 1;
amp.output_on("LoadConnected", true);  assert(amp.is_on());        n = n + 1;

amp.output_off();                      assert(~amp.is_on());       n = n + 1;

%% 其他設定
amp.fan(true); amp.fan(false); amp.buzzer(false); amp.enable_buttons(); amp.clear_errors(); n = n + 1;
assert(amp.unit_name() == "", '沒設定過名稱的裝置回傳空字串');    n = n + 1;

%% 原始指令與錯誤回報
assert(amp.query("*PING?") == "PONG!");                           n = n + 1;
expect_error(@() amp.send("BOGUS CMD"), 'DSAmp:badcommand');    n = n + 1;
expect_error(@() amp.query("NO_SUCH_QUERY?"), 'DSAmp:badcommand'); n = n + 1;
assert(amp.send_raw("BOGUS CMD") == "[BADCOMMAND]" + string(char([13 10]))); n = n + 1;
assert(amp.errors() == "0,No error", '實機：未知指令不會留下錯誤碼'); n = n + 1;
expect_error(@() amp.query("*CLS"), 'DSAmp:timeout');           n = n + 1;

%% examples/pa_warmup：輸出 OFF 必須拒絕；ON 時模擬裝置（恆溫）應立即判定穩定
addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'examples'));
expect_error(@() pa_warmup(amp), 'pa_warmup:off');                n = n + 1;
amp.output_on("LoadConnected", true);
T = pa_warmup(amp);
assert(numel(T) == 5 && all(T == 35));                           n = n + 1;

%% 機種與自訂增益範圍：其他機種可指定本地檢查的範圍
assert(amp.model == "PA20000" && amp.gain_max == 31);            n = n + 1;
amp30 = DSAmp("SIM", "GainMax", 30);
expect_error(@() amp30.set_gain(30.5), 'DSAmp:gain_range');      n = n + 1;
assert(amp30.set_gain(30) == 30);                                n = n + 1;
expect_error(@() DSAmp("SIM", "GainMin", 10, "GainMax", 5), 'DSAmp:config'); n = n + 1;
clear amp30

%% examples/session_template：未聲明負載必須拒絕；模擬裝置上可完整跑完
expect_error(@() session_template("SIM"), 'DSAmp:load');           n = n + 1;
session_template("SIM", "LoadConnected", true);                  n = n + 1;

%% onCleanup 在 function 內：出錯時區域變數被清除，輸出必須被關閉
try
    fail_with_output_on(amp);
catch ME
    assert(strcmp(ME.identifier, 'selftest:demo'));
end
assert(~amp.is_on(), '出錯後輸出應已由 onCleanup 關閉');           n = n + 1;

%% onCleanup 模式：物件清除前自動關輸出
safe_off = onCleanup(@() amp.output_off());
clear safe_off
assert(~amp.is_on(), 'onCleanup 應已關閉輸出');                    n = n + 1;

clear amp
fprintf('SELFTEST PASSED (%d checks)\n', n);

function fail_with_output_on(dev)
    safe_off = onCleanup(@() dev.output_off()); %#ok<NASGU>
    dev.output_on("LoadConnected", true);
    error('selftest:demo', '模擬量測途中出錯');
end

function expect_error(fn, id)
    % id 為空字串時只要求「有錯誤」（例如 arguments 驗證的錯誤 id 隨 MATLAB 版本不同）
    try
        fn();
    catch ME
        if strlength(id) > 0 && ~strcmp(ME.identifier, id)
            error('selftest:wrong_error', '預期 %s，實際 %s：%s', id, ME.identifier, ME.message);
        end
        return
    end
    error('selftest:no_error', '預期錯誤 %s，但沒有發生。', id);
end
