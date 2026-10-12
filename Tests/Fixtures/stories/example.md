---
title: Station clock drift fix
meta: GL-1234 · iOS 9.12
range: origin/main...HEAD
head: 4af1844a
exclude: ["*.png", "*.pbxproj"]
---
Two sentences that summarise the change. Rendered in the page header.

## Prologue · The bug in one example
Prose. A claim with a source.[^crash]

[^crash]: 412 crashes in 9.11, all in `Station.resync()`.

## Chapter 1 · The new primitive {#primitive}
Prose.

```hunks
Sources/Clock/Drift.swift
Station.swift @ "func resync("
Station.swift #3 lines 1-12
Station.swift @ "let skew" to "}"
Sources/Clock/Station.swift #1 again
```

> [!QUESTION]
> Should a skew above 5 s also log?

# Appendix

## Backend payload
```json attachment "GET /stations, anonymised"
{"id": 1, "skew_ms": 5200}
```
