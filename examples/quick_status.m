%% 讀取放大器目前狀態（只讀，不改變任何設定）
% 先關閉 AmpCon；port 不確定時執行 DSAmp.list_ports()

port = "COM6";

amp = DSAmp(port);
st = amp.status();
fprintf('%s\n', st.idn);
fprintf('  output : %s\n', mat2str(st.on));
fprintf('  gain   : %.1f dB\n', st.gain_db);
fprintf('  temp   : %.0f C\n', st.temp_c);
fprintf('  USB    : %.2f V%s\n', st.usb_v, low_volt_note(st.usb_v));
fprintf('  errors : %s\n', st.errors);
clear amp            % 釋放 COM port，之後才能再開 AmpCon

function s = low_volt_note(v)
    % 原廠建議使用有 12 V 外接電源的 USB 3.0 hub；供電不足時放大器行為不可預期
    if v < 4.75, s = '  <-- 偏低，建議改用有外接電源的 USB 3.0 hub'; else, s = ''; end
end
