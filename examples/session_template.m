% ----------------------------------------------------------------%
% Function :
%   量測範本：設定增益 → 開輸出 → 暖機 → 量測 → 結束時自動關輸出。
%   複製這個檔案、改名，把你的量測放進標示的位置。
%
%   必須寫成 function，不能是 script：
%   onCleanup 是在「變數被清除」時才執行。function 結束、出錯或被 Ctrl+C 中斷時，
%   區域變數會被清除，輸出因此被關閉；script 的變數留在 base workspace，
%   出錯或 Ctrl+C 時不會被清除，放大器輸出會一直開著。
%
% Usage（先確認 RF OUT 已接 50 Ω 負載，所有 SMA 已鎖緊；程式無法偵測）：
%   session_template("COM6", "LoadConnected", true)
%   session_template("COM6", "LoadConnected", true, "GainDb", 25)
% ----------------------------------------------------------------%

function session_template(port, opts)
    arguments
        port (1,1) string
        opts.LoadConnected (1,1) logical = false
        opts.GainDb (1,1) double = 30
    end
    amp = DSAmp(port);
    safe_off = onCleanup(@() amp.output_off());    % 正常結束、出錯、Ctrl+C 都會執行

    amp.set_gain(opts.GainDb);     % 先設增益再開輸出，避免以舊增益瞬間輸出
    amp.fan(true);
    amp.output_on("LoadConnected", opts.LoadConnected);

    pa_warmup(amp);                % 等待熱穩定（examples/pa_warmup.m）

    % ===================== 在這裡放你的量測 ===========================
    st = amp.status();
    fprintf('Measuring at gain %.1f dB, %.0f C\n', st.gain_db, st.temp_c);
    % ==================================================================

    clear safe_off                % 觸發 output_off()；之後函式結束時釋放 COM port
end
