# ADR Format

ADRs live in `docs/adr/`, sequential numbering: `0001-slug.md`, `0002-slug.md`, …

Create `docs/adr/` lazily — only when first ADR needed.

## Template

```md
# {Short title of the decision}

{1-3 sentences: what's the context, what did we decide, and why.}
```

That's it. ADR can be single paragraph. Value = recording *that* decision was made + *why* — not filling sections.

## Optional sections

Only when genuine value. Most ADRs won't need:

- **Status** frontmatter (`proposed | accepted | deprecated | superseded by ADR-NNNN`) — when decisions revisited
- **Considered Options** — only when rejected alternatives worth remembering
- **Consequences** — only when non-obvious downstream effects need calling out

## Numbering

Scan `docs/adr/` for highest number, increment by one.

## When to offer ADR

All three must be true:

1. **Hard to reverse** — cost of changing mind later meaningful
2. **Surprising without context** — future reader wonders "why on earth this way?"
3. **Result of real trade-off** — genuine alternatives, picked one for specific reasons

Easy to reverse -> skip (you'll just reverse it). Not surprising -> nobody wonders why. No real alternative -> nothing to record beyond "did the obvious thing."

### What qualifies

- **Architectural shape.** "Monorepo." "Write model event-sourced, read model projected into Postgres."
- **Integration patterns between contexts.** "Ordering and Billing communicate via domain events, not synchronous HTTP."
- **Tech choices with lock-in.** Database, message bus, auth provider, deployment target. Not every library — only ones taking a quarter to swap.
- **Boundary/scope decisions.** "Customer data owned by Customer context; others reference by ID only." Explicit no-s as valuable as yes-s.
- **Deliberate deviations from obvious path.** "Manual SQL not ORM because X." Anything where reasonable reader assumes opposite. Stops next engineer "fixing" the deliberate.
- **Constraints invisible in code.** "No AWS — compliance." "Response < 200ms — partner API contract."
- **Rejected alternatives, non-obvious rejection.** Considered GraphQL, picked REST for subtle reasons -> record, else someone suggests GraphQL again in six months.
