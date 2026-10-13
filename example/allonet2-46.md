---
title: Fix the beat rate collapsing with the size of the place
meta: alloverse/allonet2#46 · six commits · reconstructed from the pull request and its commits
range: a2d7fa8f...7697b777
head: 7697b777
---
A place with about a hundred entities was sending one changeset every 200 ms, where the coalesce delay allows one every 20 ms. The cause was a lookup that decoded the whole place to answer a question about one entity, inside a loop over every entity, on every commit. This change makes those lookups decode one component, shares one state diff between clients that are in step, and closes a crash that the new lookup exposed.

## Prologue · A beat that slows down as the place grows {#prologue}
The place server batches changes into a **beat**: it waits for the 20 ms coalesce delay, commits what arrived, and sends every client a changeset. The beat **self-clocks**. Its period is the coalesce delay *plus* however long the commit and broadcast take, so the server never queues beats behind each other.

That design has a sharp edge. If something inside the beat costs more as the place grows, nothing looks slow: there is no slow request and no timeout. The beat simply comes around less often, and every client sees the place update at a lower rate.

That is what a knackeriet-scale place showed: 107 entities and about five clients, minting one changeset per ~200 ms instead of per 20 ms.[^report] The previous week it had been fine.

[^report]: Observed on alloplace v3.5.1. The orphan sweep (Chapter 2) landed in v3.4.8 on 2026-08-24, three days before the report; v3.4.7 has no sweep.

## Chapter 1 · Measure before blaming {#measure}
The obvious suspect was the per-client diff: every beat, the server diffs the whole place against each client's acknowledged revision, and that is the one cost that visibly grows with both the place and the client count.

It was not the culprit. Timing each stage of the beat at 5 clients and 110 entities put the diff at 0.9 ms of a 10.7 ms beat. Almost all of the rest was `sweepOrphans`, the pass that removes entities whose parent is gone: 8.6 ms of a 9.0 ms beat.[^stages]

The reason is in the component store. `ComponentLists` has a typed list subscript, `components[T.self]`, that hands back every component of one type, decoded. It decodes on every access and caches nothing {@ "as! [EntityID: T]"}. Reaching through it for one entity, as in `components[Relationships.self][eid]`, decodes the whole place's worth of that type to answer one question. The change documents that cost on the subscript itself, and in the architecture notes where the next reader will look {@ "hoist the list out of any loop"}.

[^stages]: Per-stage timings from a local harness in a release build: a place populated to scale, five clients acking at 20 ms, one of them walking. Full numbers in the appendix.

```hunks
PlaceContents.swift @ "Every component of a type, decoded" until "One entity's component of a type"
docs/architecture.md
```

## Chapter 2 · One pass over Relationships {#sweep}
`sweepOrphans` runs on every commit. It walked every entity and, for each one, asked the list subscript for that entity's Relationships {@ "[Relationships.self][$0]"}. Each ask decoded every Relationships component in the place, so one sweep decoded the whole list *N* times: quadratic in the size of the place, on every beat.

The sweep now iterates the Relationships list once {@ ".compactMap"} and keeps the entities whose parent is gone. The result is the same, because an entity with no Relationships can never be an orphan. At 110 entities the sweep went from 9.7 ms to 0.15 ms a beat.

```hunks
PlaceServer+ECS.swift #11
```

## Chapter 3 · Asking about one entity {#accessor}
The sweep was the worst case of a general pattern, so the fix is a general accessor. `components[T.self, of: eid]` looks up the one stored component {@ "lists[componentType.componentTypeId]?[entityId]"} and decodes only that {@ "stored.decoded(as: T.self)"}.

Unlike the list subscript, it does not trap when a payload fails to decode. It logs the entity and the type and reads the component as absent: one corrupt component must not take down every client in the place along with it. Chapter 6 explains why a failed decode here now means a broken invariant rather than bad input.

The tests pin the accessor to exactly what the list subscript answers {@ "matchesTheListSubscript"}, including for a component type that the entity doesn't have.

```hunks
PlaceContents.swift @ "One entity's component of a type" to end
PlaceContents.swift #2
ComponentAccessTests.swift @ "import Testing" until "aPayloadThatDoesntMatchItsTypeIdIsNotWellFormed"
```

## Chapter 4 · The simulation asks one at a time too {#callers}
The same pattern was all over the simulation. The movement tick decoded every Transform in the place to read one per client {@ "let transforms = place.current.components[Transform.self]"}. Every step of every ancestor walk in the grab path, through `transformToWorld`, `resolveActuation` and `isEntity`, decoded a whole list to look up one parent.

Each of those reads now names the entity it wants {@ "components[Transform.self, of: avatarId]"}. These changes are mechanical, but they matter: the movement tick went from 13 ms to under 1 ms at 110 entities, and it shares the main actor with the beat that it feeds.

```hunks
PlaceServer+ECS.swift #2-9
GrabSimulation.swift
```

## Chapter 5 · One diff per acknowledged revision {#diffs}
With the sweep fixed, the per-client diff became the largest remaining cost: 1.5 ms of a 2.0 ms beat at 5 clients and 110 entities.

The diff is over the whole place, against the revision a client has acknowledged. Every client that is keeping up has acknowledged the same revision, so each of them was paying for the same computation. The beat now keeps one diff per distinct acknowledged revision {@ "var deltas: [StateRevision: PlaceChangeSet] = [:]"} and computes it only when no client before has asked for that revision {@ "?? place.current.changeSet(from:"}.

The wire format is unchanged: each client still receives a changeset stamped from the revision it acknowledged. A client that has acknowledged nothing, or has fallen out of history, is caught up from revision 0, the empty place. The tests check both sides of that: clients in step get the same changeset, and a laggard is still caught up from its own revision.

```hunks
PlaceServer+ECS.swift #1
StateBroadcastTests.swift @ "import Testing" until "aComponentWhosePayloadIsNotItsTypeIsRefused"
StateBroadcastTests.swift @ "everyClientsChangesetAppliesOntoWhatItAcked" to end
```

## Chapter 6 · Refusing a component that lies about its type {#ingress}
`AnyComponent` decodes its type id and its payload independently. Nothing ties the two together, so a peer can send an Opacity payload labelled Transform, and the place will store it. Reading it back through the list subscript, which force-tries the decode, traps the whole server: reproduced on main as a SIGTRAP from a single `changeEntity` request.

The place now checks at ingress, where the entity is still in hand to name in the error. `isWellFormed` decodes the payload as the type it names {@ "guard let type = ComponentRegistry.shared.component(for: componentTypeId)"}. Both the create path {@ "for case .componentAdded(let eid, let comp) in changes"} and the change path refuse a component that fails, with an `invalidRequest` error. Components of types this binary doesn't know stay opaque and pass, because the place forwards them without ever decoding them.

That is what turns a decode failure in the new accessor into a broken invariant rather than untrusted input, and it is why the accessor logs one instead of staying silent.

```hunks
PlaceContents+Codable.swift
PlaceServer+ECS.swift #10
PlaceServer+ECS.swift #12
PlaceServer+ECS.swift #13
ComponentAccessTests.swift @ "aPayloadThatDoesntMatchItsTypeIdIsNotWellFormed" to end
StateBroadcastTests.swift @ "aComponentWhosePayloadIsNotItsTypeIsRefused" until "everyClientsChangesetAppliesOntoWhatItAcked"
```

## Epilogue · What this leaves alone {#owed}
- **Not reproduced over a real transport.** The harness drives `PlaceServer` in process over a mock transport. That is where the cost lives, since all of it is main-actor work, but it does not exercise libdatachannel.
- **Voice was not measured.** Forwarded voice frames never touch the main actor, so they cannot starve the beat. That conclusion comes from reading the receive path, not from a measurement.
- **The bigger fast path is not built.** A client that has just acknowledged could be sent the beat's own committed changeset, restamped, instead of a fresh diff. At 0.28 ms a beat, the diff isn't worth that correctness risk yet.
- **No CI guard on the complexity.** A timing assertion would be flaky. The tests pin behaviour; the performance claim rests on the harness numbers in the appendix.

> [!QUESTION]
> The diff becomes the dominant cost again past roughly 300 entities or 20 clients. Should the restamped-changeset fast path be built before places reach that size, or only when one does?

# Appendix

## The numbers {#numbers}
Beat rate counted off the wire in the local harness, release build on an M-series Mac. Before is `origin/main`, after is this branch, run back to back.

| World | Clients | Before | After |
|---|---|---|---|
| 106 entities, 35 relationships | 1 | 30.0 beats/s | 43.3 beats/s |
| 110 entities, 35 relationships | 5 | 28.9 | 42.2 |
| 125 entities, 35 relationships | 20 | 27.3 | 42.6 |
| 110 entities, 84 relationships (widget-nested) | 5 | 22.3 | 43.0 |
| 305 entities, 240 relationships | 5 | 7.5 | 40.6 |

The shape matters more than the absolute numbers. Before, the beat rate fell as the world grew. After, it is flat at about 41 to 43 beats a second across every world shape, so it is bounded by the coalesce delay and scheduling rather than by the size of the place. The reported 200 ms is what the 305-entity case looks like on a slower host.

```text attachment "Per-stage timings, 5 clients and 110 entities"
beat            10.7 ms  ->  2.0 ms
  sweep          9.7 ms  ->  0.15 ms
  diff           0.9 ms  ->  0.28 ms
movement tick   13.1 ms  ->  < 1 ms

305 entities
beat            45.1 ms  ->  3.7 ms
```
