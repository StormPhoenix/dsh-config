---
name: vrcl-knowledge-layer
description: Use when building, incrementally maintaining, or auditing a Verifiable Reproducible Cognition Layer (VRCL) over a source corpus, including Map/Reduce notes, schemas, manifests, indexes, attribution, and closed-world QA.
---

# Build and maintain a VRCL

A VRCL is a versioned, source-traceable layer of knowledge that answers defined questions from derived documents. Build it for the target repository's sources and workflows; do not transplant another project's domain schema or assume a vector database is needed. For first builds and methodology audits, read the [methodology checklist](references/methodology-checklist.md) before planning.

## Operating rules

- The repository selected by the user is the target; this skill's installation directory is not. Read its root/nested `AGENTS.md`, preservation rules, and existing VRCL guidance first.
- Preserve originals. Do not delete files, change application settings, or commit/push unless explicitly asked. Retire content by marking it stale/archived and using an archive location.
- Separate source evidence from interpretation. Anchor material claims to the source; mark uncertainty, conflicts, missing evidence, and visual-only details rather than guessing.
- Do not hand-edit a registered Map/Reduce to patch an answer. Fix the schema or extraction and regenerate affected outputs with hashes.
- Optimize for independent QA answers, not a universal compression ratio. Small corpora often need only a navigable Markdown layer; do not build retrieval infrastructure by default.

## Build workflow

### 1. Scope and triage

1. Confirm root, scope, intended questions, and build/update/audit mode; do not expand approved scope.
2. Inventory paths, types, sizes, dates/authors, SHA-256, candidate modules, and schemas. Read preservation rules.
3. Apply three gates to every candidate: freshness must not require a new maintenance workflow; content must be highly correct and verifiable; it must carry reusable information rather than mutable raw values. Exclude or defer failures; turn valuable live data into query tools rather than copied snapshots. Date time-sensitive facts.
4. Estimate corpus/context size; small corpora often need only full-file reading and Markdown navigation. Select the minimum module subset that answers target questions. Have domain owners confirm the questions and schema fields on a sample before scaling; ask the user to resolve remaining scope, density, privacy, or archive choices.

### 2. Layout, schemas, and manifest

1. Keep derived notes separate from sources in a linkable target-repository root; use unique names. Adapt `<root>/_schema/`, `<root>/<module>/`, `_archive/`, `INDEX.md`, `QA.md`, `_manifest.json`, and optional `_playbook.md` to local conventions.
2. Define schemas before bulk extraction: fixed headings, required fields, anchors, fidelity/uncertainty rules, and an initial size budget. Use different schemas for unlike source types.
3. Attribute opinions and quotes; keep speaker, exact quote, context, and relation distinct; date predictions. Preserve identifiers, code, formulas, paths, and prompts exactly when material.
4. Keep a parseable manifest as source of truth: `schema_registry` (versions); `sources[]` (path, SHA-256, module, status, Map paths); `derived[]` (path, kind `map|module|meta`, schema/version, dependencies, SHA-256, status `pending|done|stale|archived`).
5. Invalidation: changed source hash → rebuild its Map; changed Map hash or membership → rebuild its Reduce; schema version change → rebuild dependent Maps and downstream outputs. Hash raw bytes; retain exact relative paths; re-read the manifest after updates.

### 3. Map, Reduce, and index

1. Read each complete source. For long documents, process bounded overlapping ranges, record coverage, and check for truncation/omissions before synthesis.
2. Extract only supported claims. Distinguish fact, author view, prediction, recommendation, and agent inference. Preserve exact technical strings and verifiable quotations; if exact quote text is uncertain, paraphrase with attribution or mark unverified.
3. Follow the schema and add stable source anchors (heading, page, or line range). Record contradictions, limitations, unknowns, and reproduction gaps; do not pretend to have read details available only in an image or missing attachment.
4. Store source path, schema/version, and source hash in Map metadata where supported. Update manifest output hash only when the file is complete. Review against both source and expected questions; size is diagnostic, not the goal.
5. Create one module Reduce from its Maps. Include members/remit, cross-source patterns, disagreements, shared constraints, and source routes. Do not add unsupported facts or flatten incompatible attributed views. Rebuild on Map or membership changes and register dependencies.
6. Create a top-level index with module navigation, question/task entry points, reading paths, and refusal/source-consultation rules. Keep it an index, not a duplicate of the corpus.

### 4. QA and retrieval

1. Derive tests from expected use, not just headings. Cover every module, material exact identifiers/constraints, attribution-sensitive questions where relevant, and at least one unsupported question that must be refused.
2. Record each question, essential answer points, expected derived paths, and refusal behavior. Scale test count to the corpus; there is no universal quota.
3. Answer from the derived layer only. A pass requires the expected files to independently support a correct, sufficiently complete answer. Check routing, anchors, exact tokens where material, and meaning; literal search is only a smoke test.
4. Require every active test to pass. Fix the responsible layer, regenerate dependencies, and rerun the full active set; retain retired tests with an inactive status instead of deleting history.
5. Attribute misses: no retrieval/routing → tool description, index, or selection instructions; retrieval but no recall → names, headings, routing, or query formulation; wrong/incomplete content → Map/schema or Reduce; correct content but wrong answer → post-retrieval reasoning/action path.
6. Escalate from simple full-text only for measured misses, context limits, scale, code-symbol needs, or automation. Compare lexical and dense retrieval on representative queries; combine/rerank only when held-out QA improves. Log route, query, source paths, failures, and timings. See the methodology checklist for retrieval and observability decisions; do not claim quality without testing.

### 5. Closure and incremental maintenance

Before handoff, recompute every source/derived SHA-256 and compare manifest paths, hashes, statuses, schema versions, and dependencies. Check that source↔Map links and all module/index/QA paths resolve; archived content must be out of active navigation/QA. Run the full active QA set using only derived files. Do not report success with a hash inconsistency or active miss. Report counts/sizes, QA results, limitations, archive state, and uncommitted status unless asked to commit.

- **Add source:** preserve/inventory; classify; register hash/module/Map; add a schema first if needed; Map; rebuild Reduce; update index/QA; reconcile hashes and rerun QA.
- **Change source:** compare new hash; rebuild Map and owning Reduce; update affected index/QA; reconcile hashes and rerun QA.
- **Retire source/derived note:** never delete; mark stale/archived, move only if repository rules allow, retain provenance/hash, remove from active navigation, and deactivate affected tests without erasing history.
- **Change schema:** increment version; rebuild dependent Maps and downstream Reduce/index/QA; reconcile the complete graph.
- **Change retriever:** rerun the same tests and inspect routing/recall evidence before blaming content.

## Handoff

List files created/changed, source and derived counts, QA passes/misses, manifest consistency, unresolved gaps, and Git status. Link the index and maintenance playbook when present.
