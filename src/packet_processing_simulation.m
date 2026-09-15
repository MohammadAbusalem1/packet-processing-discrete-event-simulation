function packet_processing_simulation()
% Packet-processing discrete-event simulation in MATLAB

    clearvars;
    clc;
    close all;

    %% User settings
    p.runTimeMs     = 1.5e6;  
    p.warmupMs      = 1.5e5;   
    p.nRep          = 20;      
    p.histRunTimeMs = 3.0e6;   
    p.histWarmupMs  = 3.0e5;
    p.baseSeed      = 4005;
    p.outputFolder  = fullfile(pwd, 'simulation_output');

    if ~exist(p.outputFolder, 'dir')
        mkdir(p.outputFolder);
    end

    fprintf('Running %d replications for 95%% confidence intervals...\n', p.nRep);

    metricNames = {
        'L1_system', ...           % average # type I in buffer 1 + service at node 1
        'L2_system', ...           % average # type II in buffer 2 + service at node 1
        'L1_queue', ...            % average # type I waiting in buffer 1
        'L2_queue', ...            % average # type II waiting in buffer 2
        'Wq1', ...                 % average waiting time in buffer 1
        'Wq2', ...                 % average waiting time in buffer 2
        'T1_node1', ...            % average time in node 1 system for type I
        'T2_node1', ...            % average time in node 1 system for type II
        'T_node2_station', ...     % average time in node 2 station (buffer + service)
        'P_redirect_router', ...   % P(redirect | reaches router)
        'P_redirect_external'};    % overall redirect probability from external arrivals

    X = zeros(p.nRep, numel(metricNames));

    for r = 1:p.nRep
        rep = simulateOneReplication(p.runTimeMs, p.warmupMs, p.baseSeed + r, false);
        X(r, :) = [ ...
            rep.L1_system, ...
            rep.L2_system, ...
            rep.L1_queue, ...
            rep.L2_queue, ...
            rep.Wq1, ...
            rep.Wq2, ...
            rep.T1_node1, ...
            rep.T2_node1, ...
            rep.T_node2_station, ...
            rep.P_redirect_router, ...
            rep.P_redirect_external];

        fprintf('  Replication %2d/%2d finished.\n', r, p.nRep);
    end

    summaryTbl = buildCITable(X, metricNames);
    writetable(summaryTbl, fullfile(p.outputFolder, 'ci_summary.csv'));

    %% Print confidence-interval summary
    fprintf('\n================ SIMULATION RESULTS (95%% CI) ================\n');
    printMetric(summaryTbl, 'L1_system',        'Avg. number of type I packets in buffer 1 + in service at node 1');
    printMetric(summaryTbl, 'L2_system',        'Avg. number of type II packets in buffer 2 + in service at node 1');
    printMetric(summaryTbl, 'L1_queue',         'Avg. number of type I packets waiting in buffer 1');
    printMetric(summaryTbl, 'L2_queue',         'Avg. number of type II packets waiting in buffer 2');
    printMetric(summaryTbl, 'Wq1',              'Avg. waiting time in buffer 1 only [ms]');
    printMetric(summaryTbl, 'Wq2',              'Avg. waiting time in buffer 2 only [ms]');
    printMetric(summaryTbl, 'T1_node1',         'Avg. time in node 1 system for type I [ms]');
    printMetric(summaryTbl, 'T2_node1',         'Avg. time in node 1 system for type II [ms]');
    printMetric(summaryTbl, 'T_node2_station',  'Avg. time in node 2 station (buffer + service) [ms]');
    printMetric(summaryTbl, 'P_redirect_router','P(packet redirected by router | packet reaches router)');
    printMetric(summaryTbl, 'P_redirect_external','Overall redirect probability from all external arrivals');
    fprintf('============================================================\n\n');

    %% Long run for histograms and distribution fitting
    fprintf('Running one longer replication for histograms / distribution fitting...\n');
    sampleRun = simulateOneReplication(p.histRunTimeMs, p.histWarmupMs, p.baseSeed + 9999, true);

    fit1 = fitAndPlot(sampleRun.wait1, 'Buffer 1 waiting time W_q_1 [ms]', ...
        fullfile(p.outputFolder, 'hist_wait_buffer1.png'), true);
    fit2 = fitAndPlot(sampleRun.wait2, 'Buffer 2 waiting time W_q_2 [ms]', ...
        fullfile(p.outputFolder, 'hist_wait_buffer2.png'), true);
    fit3 = fitAndPlot(sampleRun.T1_samples, 'Type I time in node 1 system T_1 [ms]', ...
        fullfile(p.outputFolder, 'hist_type1_node1.png'), false);
    fit4 = fitAndPlot(sampleRun.T2_samples, 'Type II time in node 1 system T_2 [ms]', ...
        fullfile(p.outputFolder, 'hist_type2_node1.png'), false);
    fit5 = fitAndPlot(sampleRun.Tnode2_samples, 'Time in node 2 station [ms]', ...
        fullfile(p.outputFolder, 'hist_node2_station.png'), false);

    fitTbl = vertcat(fit1, fit2, fit3, fit4, fit5);
    writetable(fitTbl, fullfile(p.outputFolder, 'distribution_fits.csv'));

    save(fullfile(p.outputFolder, 'simulation_workspace.mat'), ...
        'p', 'X', 'summaryTbl', 'sampleRun', 'fitTbl');

    fprintf('Done. Output files saved in:\n  %s\n', p.outputFolder);
    fprintf('Review the PNG figures and CSV summaries for analysis.\n');
end

function rep = simulateOneReplication(runTimeMs, warmupMs, seed, collectSamples)
    rng(seed, 'twister');

    % ------------------------------
    % System state initialization
    % ------------------------------
    t = 0.0;
    lastEventTime = 0.0;
    tol = 1e-12;

    % Queues
    q1 = initQueue(20000);
    q2 = initQueue(8000);
    qNode2 = initQueue(20000);

    % Node 1 server state
    node1Busy = false;
    node1Type = 0;              % 1 => buffer 1 / type I, 2 => buffer 2 / type II
    node1Arrival = NaN;         % original arrival time into node 1 buffer
    node1Completion = Inf;

    % Alternating schedule at node 1
    desiredBuffer = 1;
    nextSwitch = 50.0;          % after first 50 ms, schedule switches to buffer 2

    % Node 2 state: two parallel servers, one common queue
    node2Busy = [false, false];
    node2Completion = [Inf, Inf];
    node2Arrival = [NaN, NaN];

    % Next arrival times
    nextA1 = exprnd(4.0);       % mean interarrival 4 ms
    nextA2 = exprnd(12.0);      % mean interarrival 12 ms

    % ------------------------------
    % Statistics accumulators
    % ------------------------------
    areaL1sys = 0.0;
    areaL2sys = 0.0;
    areaL1q = 0.0;
    areaL2q = 0.0;

    sumW1 = 0.0; countW1 = 0;
    sumW2 = 0.0; countW2 = 0;
    sumT1 = 0.0; countT1 = 0;
    sumT2 = 0.0; countT2 = 0;
    sumTnode2 = 0.0; countTnode2 = 0;

    routerAttempts = 0;
    redirectCount = 0;
    externalArrivals = 0;

    if collectSamples
        wait1 = zeros(0, 1);
        wait2 = zeros(0, 1);
        T1_samples = zeros(0, 1);
        T2_samples = zeros(0, 1);
        Tnode2_samples = zeros(0, 1);
    else
        wait1 = [];
        wait2 = [];
        T1_samples = [];
        T2_samples = [];
        Tnode2_samples = [];
    end

    % ------------------------------
    % Event loop
    % ------------------------------
    while true
        tNext = min([nextA1, nextA2, node1Completion, node2Completion, nextSwitch]);
        if tNext > runTimeMs
            tNext = runTimeMs;
        end

        % Integrate time-average statistics after warm-up only
        tStart = max(lastEventTime, warmupMs);
        if tNext > tStart
            dt = tNext - tStart;
            n1sys = queueLength(q1) + double(node1Busy && node1Type == 1);
            n2sys = queueLength(q2) + double(node1Busy && node1Type == 2);
            areaL1sys = areaL1sys + n1sys * dt;
            areaL2sys = areaL2sys + n2sys * dt;
            areaL1q = areaL1q + queueLength(q1) * dt;
            areaL2q = areaL2q + queueLength(q2) * dt;
        end

        t = tNext;
        lastEventTime = t;

        if t >= runTimeMs
            break;
        end

        % 1) Node 1 schedule switch event
        if abs(t - nextSwitch) < tol
            if desiredBuffer == 1
                desiredBuffer = 2;
                nextSwitch = t + 30.0;
            else
                desiredBuffer = 1;
                nextSwitch = t + 50.0;
            end
        end

        % 2) Node 1 completion
        if abs(t - node1Completion) < tol
            finishedType = node1Type;
            finishedArrival = node1Arrival;

            if t >= warmupMs
                sojournNode1 = t - finishedArrival;
                if finishedType == 1
                    sumT1 = sumT1 + sojournNode1;
                    countT1 = countT1 + 1;
                    if collectSamples
                        T1_samples(end+1, 1) = sojournNode1; %#ok<AGROW>
                    end
                else
                    sumT2 = sumT2 + sojournNode1;
                    countT2 = countT2 + 1;
                    if collectSamples
                        T2_samples(end+1, 1) = sojournNode1; %#ok<AGROW>
                    end
                end
            end

            % Routing after node 1
            goesToRouter = (finishedType == 1) || (rand < 0.5);
            if goesToRouter
                if t >= warmupMs
                    routerAttempts = routerAttempts + 1;
                end

                % Router checks ONLY the waiting queue at node 2
                if queueLength(qNode2) > 5
                    if t >= warmupMs
                        redirectCount = redirectCount + 1;
                    end
                else
                    qNode2 = enqueue(qNode2, t);
                    tryStartNode2();
                end
            end

            % Free node 1 and try to start the next job immediately
            node1Busy = false;
            node1Type = 0;
            node1Arrival = NaN;
            node1Completion = Inf;
            tryStartNode1();
        end

        % 3) Node 2 completions
        for s = 1:2
            if abs(t - node2Completion(s)) < tol
                if t >= warmupMs
                    timeNode2 = t - node2Arrival(s);
                    sumTnode2 = sumTnode2 + timeNode2;
                    countTnode2 = countTnode2 + 1;
                    if collectSamples
                        Tnode2_samples(end+1, 1) = timeNode2; %#ok<AGROW>
                    end
                end

                node2Busy(s) = false;
                node2Completion(s) = Inf;
                node2Arrival(s) = NaN;
            end
        end
        tryStartNode2();

        % 4) External arrivals to buffer 1
        if abs(t - nextA1) < tol
            if t >= warmupMs
                externalArrivals = externalArrivals + 1;
            end

            q1 = enqueue(q1, t);
            nextA1 = t + exprnd(4.0);
            tryStartNode1();
        end

        % 5) External arrivals to buffer 2
        if abs(t - nextA2) < tol
            if t >= warmupMs
                externalArrivals = externalArrivals + 1;
            end

            q2 = enqueue(q2, t);
            nextA2 = t + exprnd(12.0);
            tryStartNode1();
        end
    end

    observedTime = runTimeMs - warmupMs;

    rep.L1_system = areaL1sys / observedTime;
    rep.L2_system = areaL2sys / observedTime;
    rep.L1_queue = areaL1q / observedTime;
    rep.L2_queue = areaL2q / observedTime;
    rep.Wq1 = sumW1 / countW1;
    rep.Wq2 = sumW2 / countW2;
    rep.T1_node1 = sumT1 / countT1;
    rep.T2_node1 = sumT2 / countT2;
    rep.T_node2_station = sumTnode2 / countTnode2;

    if routerAttempts > 0
        rep.P_redirect_router = redirectCount / routerAttempts;
    else
        rep.P_redirect_router = NaN;
    end

    if externalArrivals > 0
        rep.P_redirect_external = redirectCount / externalArrivals;
    else
        rep.P_redirect_external = NaN;
    end

    rep.wait1 = wait1;
    rep.wait2 = wait2;
    rep.T1_samples = T1_samples;
    rep.T2_samples = T2_samples;
    rep.Tnode2_samples = Tnode2_samples;

    % ---------- nested helper functions ----------
    function tryStartNode1()
        if node1Busy
            return;
        end

        nQ1 = queueLength(q1);
        nQ2 = queueLength(q2);
        if nQ1 == 0 && nQ2 == 0
            return;
        end

        if nQ1 > 0 && nQ2 > 0
            chosen = desiredBuffer;
        elseif nQ1 > 0
            chosen = 1;
        else
            chosen = 2;
        end

        if chosen == 1
            [q1, arrTime] = dequeue(q1);
            serviceTime = 1.0 + (3.0 - 1.0) * rand;
        else
            [q2, arrTime] = dequeue(q2);
            serviceTime = 2.0 + (6.0 - 2.0) * rand;
        end

        node1Busy = true;
        node1Type = chosen;
        node1Arrival = arrTime;
        node1Completion = t + serviceTime;

        if t >= warmupMs
            w = t - arrTime;
            if chosen == 1
                sumW1 = sumW1 + w;
                countW1 = countW1 + 1;
                if collectSamples
                    wait1(end+1, 1) = w; %#ok<AGROW>
                end
            else
                sumW2 = sumW2 + w;
                countW2 = countW2 + 1;
                if collectSamples
                    wait2(end+1, 1) = w; %#ok<AGROW>
                end
            end
        end
    end

    function tryStartNode2()
        for serverIdx = 1:2
            if ~node2Busy(serverIdx) && queueLength(qNode2) > 0
                [qNode2, arrTime] = dequeue(qNode2);
                node2Busy(serverIdx) = true;
                node2Arrival(serverIdx) = arrTime;
                node2Completion(serverIdx) = t + exprnd(5.0);
            end
        end
    end
end

function tbl = buildCITable(X, metricNames)
    n = size(X, 1);
    means = mean(X, 1, 'omitnan');
    s = std(X, 0, 1, 'omitnan');
    tCrit = tinv(0.975, n - 1);
    halfWidth = tCrit .* s ./ sqrt(n);
    lower = means - halfWidth;
    upper = means + halfWidth;

    tbl = table(metricNames(:), means(:), halfWidth(:), lower(:), upper(:), ...
        'VariableNames', {'Metric', 'Mean', 'HalfWidth95', 'CI95_Lower', 'CI95_Upper'});
end

function printMetric(tbl, metricName, labelText)
    row = strcmp(tbl.Metric, metricName);
    fprintf('%s\n', labelText);
    fprintf('    Mean = %.6f, 95%% CI = [%.6f, %.6f]\n', ...
        tbl.Mean(row), tbl.CI95_Lower(row), tbl.CI95_Upper(row));
end

function fitTbl = fitAndPlot(data, plotTitleText, saveName, fitPositiveOnly)
    data = data(:);
    data = data(~isnan(data) & ~isinf(data));

    if isempty(data)
        fitTbl = table({plotTitleText}, {''}, NaN, NaN, NaN, NaN, ...
            'VariableNames', {'Dataset', 'BestFit', 'AIC', 'KSPValue', 'ZeroMass', 'NumSamples'});
        return;
    end

    % Some waiting-time datasets contain a point mass at zero because many
    % packets start service immediately. In that case we fit only the
    % strictly positive samples and report the zero-mass separately.
    if fitPositiveOnly
        zeroMass = mean(data == 0);
        fitData = data(data > 0);
    else
        zeroMass = 0;
        fitData = data;
    end

    candidateNames = {'Exponential', 'Gamma', 'Weibull', 'Lognormal', 'Normal'};
    numParams = containers.Map(candidateNames, [1, 2, 2, 2, 2]);

    bestAIC = Inf;
    bestName = '';
    bestPd = [];
    bestP = NaN;

    for i = 1:numel(candidateNames)
        distName = candidateNames{i};
        try
            if ismember(distName, {'Gamma', 'Weibull', 'Lognormal'})
                if any(fitData <= 0)
                    continue;
                end
            end

            pd = fitdist(fitData, distName);
            aic = 2 * numParams(distName) + 2 * pd.NLogL;
            [~, pVal] = kstest(fitData, 'CDF', pd);

            if aic < bestAIC
                bestAIC = aic;
                bestName = distName;
                bestPd = pd;
                bestP = pVal;
            end
        catch
          
        end
    end

    % Plot histogram and the best fitted PDF
    fig = figure('Visible', 'off');
    histogram(data, 'Normalization', 'pdf', 'NumBins', max(20, round(sqrt(numel(data)))));
    hold on;
    grid on;
    xlabel('Time [ms]');
    ylabel('Estimated pdf');

    if ~isempty(bestPd)
        xMin = min(fitData);
        xMax = max(fitData);
        x = linspace(xMin, xMax, 500);
        y = pdf(bestPd, x);
        plot(x, y, 'LineWidth', 1.8);
    end

    if fitPositiveOnly
        title(sprintf('%s | P(W=0)=%.4f | Best positive fit: %s', plotTitleText, zeroMass, bestName), ...
            'Interpreter', 'none');
    else
        title(sprintf('%s | Best fit: %s', plotTitleText, bestName), 'Interpreter', 'none');
    end
    legend({'Histogram', 'Best-fit pdf'}, 'Location', 'best');
    hold off;
    exportgraphics(fig, saveName, 'Resolution', 200);
    close(fig);

    fitTbl = table({plotTitleText}, {bestName}, bestAIC, bestP, zeroMass, numel(data), ...
        'VariableNames', {'Dataset', 'BestFit', 'AIC', 'KSPValue', 'ZeroMass', 'NumSamples'});
end

function q = initQueue(initialCapacity)
    q.data = zeros(initialCapacity, 1);
    q.head = 1;
    q.tail = 0;
end

function q = enqueue(q, value)
    q.tail = q.tail + 1;
    if q.tail > numel(q.data)
        q.data = [q.data; zeros(numel(q.data), 1)]; %#ok<AGROW>
    end
    q.data(q.tail) = value;
end

function [q, value] = dequeue(q)
    value = q.data(q.head);
    q.head = q.head + 1;

    if q.head > q.tail
        % reset indices when queue becomes empty
        q.head = 1;
        q.tail = 0;
    elseif q.head > 10000 && q.head > floor(numel(q.data) / 2)
        % compact occasionally to keep arrays from growing forever
        q.data = q.data(q.head:q.tail);
        q.tail = q.tail - q.head + 1;
        q.head = 1;
        q.data = [q.data; zeros(max(numel(q.data), 1), 1)]; %#ok<AGROW>
    end
end

function n = queueLength(q)
    if q.tail < q.head
        n = 0;
    else
        n = q.tail - q.head + 1;
    end
end
