# Technical Summary

## Objective

This project models a two-stage packet-processing system using discrete-event simulation in MATLAB. The purpose is to estimate queueing and delay behavior under stochastic traffic and evaluate how the first-stage scheduling policy and second-stage congestion rule affect system performance.

## Event-Driven Architecture

The simulator does not advance time in fixed increments. Instead, it stores the time of each possible future event and jumps directly to the earliest one.

Events include external packet arrivals, Node 1 service completions, Node 1 scheduling-window switches, and Node 2 service completions. After each event, the simulator updates queue state, server state, future event times, and performance statistics.

## Node 1 Scheduling

Node 1 contains two queues and one server. A repeating wall-clock schedule gives Buffer 1 a 50 ms window and Buffer 2 a 30 ms window. Service is non-preemptive, so a packet already in service is allowed to finish when the preferred buffer changes.

When both queues are nonempty, the currently scheduled buffer is selected. When only one queue is nonempty, the available packet is served immediately.

## Queue Representation

Queues are implemented using arrays with head and tail indices. This avoids repeatedly shifting all elements when a packet is removed. The queue storage expands dynamically when necessary and is compacted periodically to limit unused array growth.

## Node 2 and Router Logic

Packets that proceed beyond Node 1 enter a router decision stage. If the waiting queue at Node 2 contains more than five packets, the arriving packet is redirected. Otherwise, it is added to the shared Node 2 queue.

Node 2 contains two parallel processors. Whenever a processor is idle and the shared queue is nonempty, the next queued packet begins service immediately.

## Performance Measurement

Time-average queue and system populations are calculated by integrating the current state over the duration between consecutive events.

Packet-level measurements are collected when service starts or completes, including waiting time and total station time.

A warm-up interval is excluded from the reported statistics to reduce initialization bias from starting the simulation with an empty system.

## Replication and Confidence Intervals

The default experiment performs 20 independent replications using different pseudorandom-number seeds. For each performance metric, the program calculates the sample mean and a two-sided 95% confidence interval using Student's t distribution.

## Distribution Analysis

A separate long simulation collects packet-level samples for histogram generation and probability-distribution fitting. Exponential, Gamma, Weibull, Lognormal, and Normal candidate distributions are fitted where valid.

The candidate with the lowest Akaike Information Criterion (AIC) is reported as the preferred candidate among the distributions tested. A Kolmogorov-Smirnov statistic is also recorded as a descriptive fit diagnostic; a standard KS p-value is not reported because the distribution parameters are estimated from the same simulation samples.

Waiting-time distributions can contain an atom at zero because some packets enter service immediately. For those datasets, the zero probability is reported separately, and both the histogram used for visual comparison and the continuous-distribution fit use the strictly positive observations only.

## Reproducibility

The simulation uses explicit random-number seeds. The base seed is fixed and each independent replication uses a deterministic offset, allowing the experiment to be reproduced while keeping replications independent at the program level.
