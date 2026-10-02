% ----------------------------------------------------------------%
% Function :
%   暖機監控：每 30 秒讀一次溫度，符合下列任一條件即判定熱穩定
%     1. 最近 window_min 分鐘內溫度變化 <= tol_c
%        （*TEMP? 解析度為 1 °C，預設 tol_c = 1.5 即整數讀值最多差 1 °C）
%     2. 風扇溫控造成的週期振盪穩態：最近 6 分鐘前後半段平均差 < 1 °C 且振幅 <= 6 °C
%   放大器越熱增益越低（原廠手冊）；未穩定就量測會使結果隨時間漂移。
%
%   PA20000 實測（gain 30 dB、輸出 ON、無 RF 輸入）：
%   36 °C 起約 6 分鐘升到 60 °C，之後在 55–60 °C 以約 3.5 分鐘週期振盪；FAN ON 後恆定約 50 °C。
%
% Usage :
%   T = pa_warmup(amp)                                   % amp 為已連線的 DSAmp 物件
%   T = pa_warmup(amp, "TolC", 1.5, "WindowMin", 2, "TimeoutMin", 20, "PollS", 30)
% ----------------------------------------------------------------%

function T = pa_warmup(amp, opts)
    arguments
        amp (1,1) DSAmp
        opts.TolC (1,1) double {mustBePositive} = 1.5
        opts.WindowMin (1,1) double {mustBePositive} = 2
        opts.TimeoutMin (1,1) double {mustBePositive} = 20
        opts.PollS (1,1) double {mustBePositive} = 30
    end
    if ~amp.is_on()
        error('pa_warmup:off', '放大器輸出為 OFF，暖機需在輸出 ON 的狀態下進行。');
    end

    n_win = round(opts.WindowMin*60/opts.PollS) + 1;
    n_cyc = round(6*60/opts.PollS);
    t0 = tic;
    T = [];
    fprintf('Warm-up: %g 分鐘內溫度變化 <= %.1f °C，或達到週期振盪穩態（timeout %g 分鐘）\n', ...
        opts.WindowMin, opts.TolC, opts.TimeoutMin);
    while true
        T(end+1) = amp.temp(); %#ok<AGROW>
        elapsed = toc(t0)/60;
        fprintf('  %5.1f min  %.0f °C\n', elapsed, T(end));

        if numel(T) >= n_win && spread(T(end-n_win+1:end)) <= opts.TolC
            fprintf('熱穩定（%.0f °C）。\n', T(end));
            return
        end
        if numel(T) >= n_cyc
            w = T(end-n_cyc+1:end);
            h = floor(n_cyc/2);
            if abs(mean(w(1:h)) - mean(w(h+1:end))) < 1 && spread(w) <= 6
                fprintf('已達週期振盪穩態（%.0f–%.0f °C，平均 %.1f °C）。\n', min(w), max(w), mean(w));
                return
            end
        end
        if elapsed > opts.TimeoutMin
            warning('pa_warmup:timeout', '超過 %g 分鐘仍未穩定，請確認通風與風扇。', opts.TimeoutMin);
            return
        end
        if amp.is_sim
            continue             % 模擬裝置溫度固定，不需等待
        end
        pause(opts.PollS);
    end
end

function r = spread(v)
    r = max(v) - min(v);
end
