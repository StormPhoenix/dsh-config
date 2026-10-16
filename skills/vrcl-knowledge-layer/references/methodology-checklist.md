# VRCL methodology decision checklist

Read this before a first build or a methodology audit. The workflow is portable; this checklist makes important decisions explicit without copying another repository's schema or infrastructure.

## 1. Decide whether each candidate belongs in the knowledge layer

Make a table with source/candidate, evidence, each gate, and disposition (`include`, `exclude`, `defer`, or `query tool`). Apply all three gates independently:

1. **Freshness without a new workflow:** Can the information stay current through the source's existing lifecycle or automatic rebuild? If it requires someone to remember recurring manual maintenance or write-back, exclude/defer it unless the user explicitly accepts that burden.
2. **High correctness:** Is the content stable enough to trust, and can important claims be checked against an authoritative source? Mark uncertain, conflicting, or fast-drifting claims; do not include unsupported assumptions as facts.
3. **Information rather than mutable data:** Does value lie in reusable meaning, rules, procedures, relationships, or interpretation, rather than today's exact values? Prefer to retain the information and access path. If the actual changing values matter, expose a source-backed live query/API/CLI/tool; do not snapshot those values into derived prose. A tool can preserve expert query paths and diagnostic order without copying the data.

A valuable candidate does not override a failed correctness or maintenance gate. Record why each item was included, excluded, deferred, or routed to a tool. Date conclusions whose validity changes over time.

## 2. Minimize scope and derive schemas from questions

Before bulk extraction, list the intended questions and select the **smallest module subset** that can answer them. Do not ingest a whole repository merely because it is available. For each module and source type, ask the relevant domain owner/expert what an agent must know and what mistakes it must avoid; turn that into fixed Map fields and a sample answer. Different roles or layers may need different schemas. Obtain user/domain-owner confirmation of the module subset, question coverage, and sample Map before scaling when these choices are material or ambiguous.

Check that every schema field serves at least one target question. Keep stable anchors and source-level provenance. Do not reuse a local project's fields, headings, directory names, or size ratios by default; treat them as examples and justify the target repository's design.

## 3. Choose retrieval from evidence, not fashion

Start with complete-file reading, full text, and Markdown navigation when the corpus fits the workflow and QA passes. Add an index or retriever only when corpus size/context limits, repeated real misses, exact-symbol lookup, or automation needs justify it.

For a larger/code-heavy corpus, use representative questions and compare simple baselines before adding components:

- Lexical/BM25 retrieval is useful for exact identifiers, symbols, paths, error strings, and other literal tokens. Keep its query exact; do not rewrite code identifiers into prose.
- Dense retrieval is useful for natural-language intent and semantic questions. Preserve the user's meaning in its query rather than reducing it to disconnected symbols.
- If both address distinct query needs, evaluate hybrid retrieval. Dense similarity and lexical scores are not inherently comparable; rank-based fusion (for example, RRF) avoids pretending their raw scores share a scale. Do not assume the hybrid always wins.
- Add a reranker only when held-out QA or representative real usage shows a measurable improvement that justifies its latency/cost. Choose recall depth and final result count from evaluation, not copied constants. Provide graceful fallback when one component fails; report an error only when the required retrieval paths fail.

Evaluate using queries representative of the target workflow. Track suitable retrieval and answer metrics (for example, Hit@k, direct answer support, NDCG, stability, and latency); keep the query distribution with results because a workload heavy in exact symbols can favor lexical retrieval. Do not transfer another project's benchmark numbers or declare retrieval quality without testing.

When retrieval is deployed, make failures diagnosable. Keep enough trace data to follow an answer back through tool/route selection, original and transformed queries, corpus/index/schema/model versions, candidates and source paths from each recall leg, ranks/fusion/rerank outcome, fallbacks/failures, and per-stage timings. Keep index artifacts bound to the same corpus/version fingerprint so results from different knowledge snapshots cannot be silently mixed.

## 4. Verify content and diagnose failures

Maintain an admission QA set derived from intended questions, with expected essential answer points, expected source/derived paths, exact tokens where material, attribution requirements, and at least one unsupported question that must be refused. Require every active test to pass; do not invent a universal pass percentage. Later, where a real workflow exists, use resolved cases or user-reported failures as regressions in addition to the curated set.

For every miss, retain the question, answer, selected tool/files/chunks, and available retrieval trace. Attribute before changing anything:

- No retrieval or wrong route → tool description, routing/index, or selection instructions.
- Retrieval ran but missed needed material → names/headings/query formulation, retrieval configuration, or corpus/index mismatch.
- Retrieved content is wrong or incomplete → source selection, Map attention/schema, or Reduce.
- Evidence supports the answer but response is wrong → post-retrieval reasoning/action path.

Fix the responsible layer, regenerate dependent artifacts, and rerun the full active set. Refuse claims the accepted corpus cannot support.

## 5. Portability acceptance test

A fresh LLM with only the target repository instructions, this skill, and user-approved questions should be able to: (a) explain per-candidate dispositions using all three gates; (b) propose and justify the minimum module subset and question-derived schemas before bulk work; (c) choose simple Markdown or retrieval infrastructure from corpus and evaluation evidence; (d) build source-traceable Maps, module Reduces, navigation, manifest, and QA without copying another corpus's local conventions; and (e) prove closure with hashes/dependencies and all active QA passing. If it cannot make one of these decisions from available evidence, it must identify the missing input and ask rather than silently guess.
