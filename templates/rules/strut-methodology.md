---
globs: .strut-pipeline/**
---

# Methodology Rules

## Classification

1. Classification is determined by the pipeline, not by session-level Claude. run-read-truth dispatches truth-repo-impact-scan and truth-classify, which write `classification.json`. Session Claude displays the result to the human before proceeding — it does not produce, interpret, or adjust the classification.
2. The human can override modifiers upward or proceed as classified. Overriding modifiers downward is the human's prerogative at the gate — session Claude never suggests it.

## Anti-Rationalization

3. Do NOT suggest that modifiers should be lowered, that a change is simpler than the scan determined, or that ceremony can be reduced. The scan's classification stands unless the human overrides it.
4. Do NOT skip review stages, even if the change "looks simple."
5. Do NOT present bypass options when blocked. Write status and wait. Never suggest bypassing the methodology, reducing ceremony, or "temporarily" skipping the pipeline. The human can choose to override — but you do not offer it.
