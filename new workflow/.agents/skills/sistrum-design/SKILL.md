---
name: sistrum-design
description: "Use automatically for architecture changes, new ownership boundaries or migration batches with unresolved API/lifecycle design."
---

# Design

Read `workflow/architecture.md`, `workflow/quality.md`, applicable contracts and migration decisions. Write only the design detail needed for implementation, using `workflow/templates/design.md`.

For substantial features/ports, start from the behavior spec prepared by `sistrum-spec`. The design is the technical plan, not a competing statement of requirements. Check existing project principles before and after design, map decisions to requirement IDs, and leave executable steps in the single task record. A simple feature can keep its technical approach there without another design document.

1. Separate current facts, accepted target and open choices. Trace related implementations before inventing new types/modules.
2. Specify ownership and dependency direction, initialization, public API and wire contracts, errors, cancellation and disposal. Explain what continues without Flutter. Define data compatibility and measurable acceptance criteria.
3. Prefer existing healthy code, standard/platform APIs, then installed dependencies. Introduce new abstraction only for a present boundary or shared behavior. File splitting alone is not architecture.
4. Provide a staged implementation/removal plan and failure recovery. Preserve deliberate feature removals and explicit product decisions. New-repository adaptation must not silently reorder approved migration dependencies.
5. Send the self-contained design, source references and accepted constraints to a fresh reviewer without the author conversation. Review missing assumptions, real code fit and implementation readiness. Resolve findings with evidence.
6. Continue routine implementation decisions autonomously. Present genuinely unresolved architecture/product trade-offs to the owner before dependent work. Record acceptance; a reviewer cannot approve a product change on the owner's behalf.

Compare the design to implementation after the change; update facts or raise unexplained drift. Do not rubber-stamp an outdated design.
