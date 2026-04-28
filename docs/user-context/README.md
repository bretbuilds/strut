# docs/user-context/

Business context for `spec-derive-intent`. Optional but recommended.

## What belongs here

- **Product decisions** — "We decided not to support X because Y."
- **Trust invariants** — expectations that go beyond code-level rules ("audit entries must survive partial failures").
- **User expectations** — what users assume or rely on that isn't obvious from the code ("a published update is visible to all recipients within 30 seconds").
- **Domain vocabulary** — words that have specific meaning in your product that the AI might misinterpret.

## What doesn't belong here

- Code documentation (the scan reads your code directly)
- API references
- Deployment configuration
- Changelog or release notes

## If this folder is empty

`spec-derive-intent` still runs, deriving intent from scan evidence alone. Specs will be thinner and less aligned with product context. The spec approval gate catches mismatches, but approval takes longer.

## Format

Any readable structure works. Markdown files are easiest for `spec-derive-intent` to parse. Organize however makes sense for your team — by feature area, by product surface, by audience. There is no required schema.
