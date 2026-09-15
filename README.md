A MATLAB discrete-event simulation of a two-stage packet-processing system with stochastic arrivals, queueing, alternating service windows, probabilistic routing, parallel processors, congestion-based redirection, and statistical performance analysis.

## Overview

The model simulates two packet classes entering separate buffers at the first processing node. A single non-preemptive processor serves the buffers according to a repeating 50 ms / 30 ms scheduling cycle. After Node 1, packets may be routed to a second station containing a shared queue and two parallel processors.

The simulation is event-driven: the clock advances directly to the next arrival, service completion, or scheduling event instead of using fixed time steps.

## System Model

### External traffic

- Type I packets: exponential interarrival time with mean 4 ms
- Type II packets: exponential interarrival time with mean 12 ms

### Node 1

- Two input buffers
- One non-preemptive processor
- Repeating service schedule:
  - Buffer 1: 50 ms
  - Buffer 2: 30 ms
- Type I service time: Uniform(1, 3) ms
- Type II service time: Uniform(2, 6) ms

If both queues contain packets, the scheduled buffer has priority. If only one queue is nonempty, the processor serves that queue immediately.

### Routing and Node 2

- All Type I packets proceed toward the router after Node 1
- Type II packets proceed toward the router with probability 0.5
- The router redirects a packet when the Node 2 waiting queue contains more than five packets
- Node 2 uses one shared queue and two parallel processors
- Node 2 service time is exponential with mean 5 ms

## Simulation Method

The event loop tracks:

- Type I arrivals
- Type II arrivals
- Node 1 service completion
- Node 1 scheduling-window changes
- Node 2 service completion

The implementation maintains queue and server state explicitly and updates time-average statistics between events.

## Statistical Analysis

The default configuration uses:

- 20 independent replications
- 1,500,000 ms per replication
- 150,000 ms warm-up period
- 95% Student's t confidence intervals
- One additional 3,000,000 ms run for histogram and distribution analysis

The simulation reports:

- Average number of Type I and Type II packets at Node 1
- Average queue lengths for both Node 1 buffers
- Average waiting time in each Node 1 buffer
- Average total time through Node 1 for each packet class
- Average time through the Node 2 station
- Router redirection probability

## Distribution Fitting

The long-run sample is compared against several continuous probability distributions:

- Exponential
- Gamma
- Weibull
- Lognormal
- Normal

Candidate distributions are ranked using Akaike Information Criterion (AIC), and the lowest-AIC candidate is reported as the best candidate among the distributions tested. A Kolmogorov-Smirnov statistic is included as a descriptive goodness-of-fit diagnostic. For waiting-time datasets, the probability mass at zero is reported separately, while the histogram and continuous-distribution fit use only strictly positive waiting times.

## Repository Structure

```text
packet-processing-discrete-event-simulation/
├── README.md
├── src/
│   └── packet_processing_simulation.m
├── docs/
│   └── technical_summary.md
├── figures/
└── results/
```

## Running the Simulation

### Requirements

- MATLAB
- Statistics and Machine Learning Toolbox

### Run

Place the MATLAB source file in your working directory or add the `src` folder to the MATLAB path, then run:

```matlab
packet_processing_simulation
```

The program creates a `simulation_output` directory containing:

```text
ci_summary.csv
distribution_fits.csv
simulation_workspace.mat
hist_wait_buffer1.png
hist_wait_buffer2.png
hist_type1_node1.png
hist_type2_node1.png
hist_node2_station.png
```

## Engineering Concepts Demonstrated

- Discrete-event simulation
- Queueing systems
- Stochastic processes
- Monte Carlo simulation
- Event scheduling
- Parallel server modeling
- Warm-up period handling
- Confidence interval estimation
- Probability distribution fitting
- MATLAB data analysis and visualization

## Notes

The Node 1 scheduling rule is modeled as a fixed wall-clock 50 ms / 30 ms cycle with non-preemptive service. When the scheduled buffer is empty, the processor may immediately serve the other nonempty buffer.
