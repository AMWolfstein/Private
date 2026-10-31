# Provenance and scope

This starter contains original project-specific instructions and Python tooling, informed by publicly read concepts rather than bundling the following tools or copying their skills verbatim:

- https://github.com/peteromallet/desloppify — evidence-based mechanical/subjective review, prioritized repair and rescan. No dependency, score, detector-equivalence claim or bundled Desloppify code.
- https://github.com/DietrichGebert/ponytail — understand callers, reuse healthy code, minimum complete solution without removing validation.
- https://github.com/aicodeking/deepseek-stack — bounded verify/review loops, explicit evidence, persistent progress and enforceable lessons.
- https://github.com/google/elephant-goldfish-model — context-rich design, independent fresh-context critique and document/code drift checks.
- https://github.com/github/spec-kit — observable specifications, selective clarification, project-principle checks, traceable tasks, cross-artifact consistency and convergence against delivered behavior. Adapted through `sistrum-spec`; no Specify CLI dependency, upstream scripts or plugin commands are bundled.

Sources were inspected on 2026-10-31. They may evolve; this package does not fetch their latest instructions at runtime. External repositories do not override user/project decisions.

Spec Kit integration was reviewed against upstream commit `7370e592f3cd9c06e5b698983957e227c75b30e2`: `README.md`, `templates/spec-template.md`, `templates/plan-template.md`, `templates/tasks-template.md`, and `templates/commands/{analyze,checklist,converge}.md`. The new instructions/templates are original adaptations, not copied upstream templates. Sistrum retains its risk-based testing, existing authority hierarchy, single task record and bounded review loop. `workflow/spec-driven.md` documents deliberate differences, including no optional-testing loophole or repeated section-by-section approvals.

Project source: `AMWolfstein/Private`, `docs/AUDIO_ENGINE_MIGRATION.md` at `bf827a53`, owner-selected Media3 plan. The original plan referenced `AMWolfstein/Sistrum` (retired Compose app), branch `feature/media3-migration`, commit `88e5987`. Neither reference implementation nor its fixtures are included here. Review actual sources and licences when porting; preserve third-party notices. The owner accepted the GPL migration for importing that reference code. This package does not itself change the existing app licence.

Project-specific code/data contracts and prior audit lessons informed the policy. No test counts or runtime claims from the old application are inherited by the new repository.
