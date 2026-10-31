# Executable assurance gates

Each feature/architecture change has `assurance.json` alongside its spec and plan. `new` creates an
unclassified declaration: explicitly classify port and bridge applicability, even if both are false.
Small fixes still use regression proof without a change folder. A port or changed bridge is architecture size.
Existing active records must add the declaration from `work/templates/assurance.json`; missing declarations
block build and later phases. Completed historical records are not automatically reopened. If a new change names one as a prerequisite,
add its prerequisite list to `assurance.json` once so the dependency graph can be validated. This metadata
migration does not rerun the historical change; inspect its actual dependencies rather than assuming a leaf.

Before build, `lint` / `advance` validate the declaration, check IDs, component dispositions, prerequisites and
contract fields. Before review, each named check needs PASS evidence for the current source fingerprint,
written by `work.py check <IDs>`; manually writing PASS in this declaration is insufficient. Before ship,
declared device checks must be passed with a recorded owner/device evidence reference. Pending device checks
may enter review but cannot ship. Checks may be added to `work/checks.json` using argv commands and requirements.

Example for a port that changes a bridge (replace all examples with actual facts):

```json
{
  "version": 1,
  "port": {
    "applies": true,
    "reason": "Port the selected DSP component",
    "source": "repository URL",
    "revision": "0123456789012345678901234567890123456789",
    "components": [{
      "name": "DSP component",
      "destination": "actual Kotlin module path",
      "disposition": "adapt",
      "rationale": "Preserve algorithm; adapt the platform boundary",
      "provenance": "source path, licence and notices",
      "checks": ["dsp-parity"]
    }]
  },
  "bridge": {
    "applies": true,
    "reason": "Change the playback command contract",
    "contracts": [{
      "name": "playback",
      "caller": "actual Dart caller path and symbol",
      "implementation": "actual Kotlin dispatcher path and symbol",
      "payload": "fields, widths, units, bounds, nullability and compatibility",
      "ordering": "acceptance/completion ordering and stale event rejection",
      "ownership": "state/resource owner, dispatcher and disposal",
      "cancellation": "before dispatch, during work, after commit; one terminal result",
      "reconnect": "authoritative snapshot and listener/service lifecycle",
      "errors": "unsupported/not found/permission/cancellation/failure mapping",
      "caller_checks": ["bridge-dart"],
      "native_checks": ["bridge-kotlin"]
    }]
  },
  "prerequisites": ["001-prerequisite-batch"],
  "device_checks": [{
    "case": "screen-off service playback and reconnect",
    "status": "pending"
  }]
}
```

Component dispositions: reuse, adapt, restructure, exclude. Exclusion still needs a named check for removal or
scope acceptance. Non-applicable sections use `{"applies": false, "reason": "specific justification"}`.
Prerequisites are existing change IDs whose phase is done; missing, unfinished or cyclic dependencies block.
For a passed device case add `evidence` identifying the actual report, device/API and source revision.

The manifest appears in review packets and fingerprints. Editing it invalidates design and code reviews;
complete or update its evidence before recording clean rounds. Re-review changes rather than reusing old approval.

Automation checks structure and runner evidence. It does not verify a remote source commit exists, licence
correctness, inventory completeness, the truth of non-applicability, test meaning, device reports, or semantic
parity. Reviewers inspect these against source, callers, fixtures and logs. The two sides should use shared
cases; listing a generic successful command cannot establish that. The skills and reviewer prompts remain
necessary for this judgment. No prose skill is removed merely because a structural gate now exists.
