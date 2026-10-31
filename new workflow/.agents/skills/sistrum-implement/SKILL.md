---
name: sistrum-implement
description: "Use automatically for approved features, bug fixes and bounded refactors; read callers, implement completely and verify behavior."
---

# Implement

1. Read the code and consumers; identify the root cause or intended behavior before editing. Reuse the repository's healthy implementation rather than add a second mechanism.
2. Select the smallest complete change. Include callers, fixtures, configuration and error handling affected by it. Preserve validation, data-loss protection, accessibility and hardware calibration. Avoid speculative flexibility and forwarding-only layers.
3. For risky behavior, write a meaningful failing regression/characterization test first when feasible. Do not write tests for a trivial reversible prose/style edit. Document when reproduction needs a device.
4. Implement one coherent step and run the real covering check; read actual failures. If the same attempted approach fails twice, identify and test the shared assumption before another attempt.
5. Validate bad inputs, shutdown, cancellation and failure at boundaries. Use typed domain results/exceptions; keep serialization in adapters. Measure performance before proposing a transport or buffer optimization.
6. Run the verification skill, then independent review for nontrivial changes. Address confirmed findings in related batches. Re-run affected checks after fixes; no redundant full-suite loop without a new reason.
7. Update accepted docs when responsibilities or contracts changed. Keep the final report short and evidence-backed.
