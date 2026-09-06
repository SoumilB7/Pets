# PixelPet · Tasks & State Space — implementation plan

Status: **implemented 6 Sep 2026** (phases 1–3 and a static graph from phase 4). This doc is the design; `ARCHITECTURE.md` has the file map.
Deviations from the proposal: the default embedder is a hybrid (Apple sentence 512-d + keyword hash 512-d = 1024-d) because the sentence model alone ranked "invoice email" near "database docs"; default link threshold is 0.45 on that scale. Pet reactions to linked/unlinked windows are not built yet.

## 1. What we're building

The app window becomes three pages, chosen from a left sidebar:

| Page | Job |
|---|---|
| **Pet** | Everything that exists today (General / Zone / Movement / Physics / Animations / Context / App). Unchanged, just moved. |
| **Tasks** | A kanban board of sticky notes for the day. Each note is one task. Columns: Today · Doing · Done (renamable). Notes have a title, free text, a colour, created/finished times. |
| **State Space** | The living map. Each task is a **main node**. Every window you use becomes a **window node** with an embedding of its meaning. Edges are semantic similarity between windows and tasks. Auto-updates when a new window appears or focus changes, and does a full pass every 5 minutes. |

## 2. Vocabulary

- **Snapshot** — one reading of one window: app, title, document, URL, category, a text sample, time. Exists partially (`Context.swift` reads the focused window; no text sample yet).
- **Window node** — a snapshot that was embedded and stored. Same window seen again with the same content reuses the node; new content makes a new version.
- **Task node** — a sticky note from the Tasks board, embedded from its title + text.
- **Edge** — cosine similarity between a task node and a window node above a threshold. Weighted by recency.
- **State Space** — the set of task nodes, window nodes and edges, plus "what you're on right now".

## 3. Architecture

```
            ┌──────────── every 1 s (exists) ────────────┐
Sense  ──►  Context.refresh()  ─►  focus / new window?  ──┐
            (app, title, url, AX text sample)             │ debounce 2 s
                                                          ▼
Mind   ──►  Capture.snapshot(window)  ─►  Embed.vector(text)  ─►  Store.upsert("windows")
                 │                                                       │
                 └── Tasks board changes ─►  Embed.vector(task) ─►  Store.upsert("tasks")
                                                                          │
Link   ──►  every update + every 5 min: for each task → Store.search("windows")  ─►  edges.json
                                          for the current window → Store.search("tasks")
                                                                          │
Show   ──►  State Space page (list + graph + "now")  ◄──────────────────┘
```

New engine folders (all ENGINE-owned):

```
Engine/Mind/
  Capture.swift      builds snapshots (adds AX text sampling to what Context reads)
  Embed.swift        `Embedder` protocol + LocalEmbedder (NLEmbedding) [+ CloudEmbedder later]
  Store.swift        `VectorStore` protocol + LocalStore (JSON + brute-force cosine)
  ActianStore.swift  VectorStore over Actian VectorAI DB REST
  Link.swift         builds/refreshes edges, recency weighting, thresholds
  Tasks.swift        task model + persistence (tasks.json)
Engine/UI/
  MainWindow.swift   sidebar + 3 pages (replaces PreferencesWindow as the shell)
  PetPage.swift      today's tabs
  TasksPage.swift    kanban board
  StateSpacePage.swift  list, graph (custom NSView), "now" strip, status line
```

## 4. Capture — turning a window into text

Read per window, in this order of richness:

1. App name, bundle id, category (exists, free).
2. Window title, document path, browser URL (exists, needs Accessibility).
3. **Text sample** (new, needs Accessibility): walk the window's AX tree breadth-first, collect `AXValue` of static text / text areas / web content, cap at 2,000 characters, stop after 300 nodes or 150 ms. Browsers, Terminal, Notes, Slack expose this well; VS Code exposes it once its accessibility support is on.
4. (Later, optional) screen OCR with Vision. Needs Screen Recording permission. Not in this plan.

Text fed to the embedder: `"{app} · {title} · {url or document}\n{text sample}"`.

Triggers:
- **Focus change / new window** — the 1 s sampler already detects both (`[front]`, `[scan]`). Debounce 2 s so a title flicker doesn't cost an embedding.
- **Full sweep every 5 minutes** — re-read every visible window on the current desktop (titles + URLs for all, text only for the focused one), re-link everything, refresh the page.
- **Manual** — "Refresh now" button.

Dedupe: content hash of the text; unchanged hash → touch `lastSeen`, no re-embed.

Privacy: an exclusion list (default: password managers, banking bundle ids, Private/Incognito titles). Excluded windows get a node with title only, no text. Everything stays on this Mac unless a cloud embedder is switched on.

## 5. Embedding — "engrossing the meaning"

Two-stage, both pluggable behind `Embedder`:

| Stage | Default (local, free, offline) | Optional upgrade |
|---|---|---|
| Summarise | none (raw text) | 1–2 sentence "what is this window about" from an LLM. On-device Foundation Models (macOS 26, Apple Silicon) first; Claude Haiku 4.5 (`claude-haiku-4-5-20251001`) if a key is set. |
| Embed | Apple `NLEmbedding.sentenceEmbedding(for: .english)` → 512-d, on device | Voyage / OpenAI text embeddings (1024-d) via HTTPS |

Start local. The whole pipeline works with no keys and no network; quality upgrades are a settings toggle. Vector size is a collection property, so switching embedders means a new collection (`windows_v2`), never a silent mix.

## 6. Store — Actian VectorAI DB

Facts (from Actian's docs, verified 6 Sep 2026):

- Run locally with Docker:
  ```
  docker run -d --name vectorai \
    -v ./local_data:/var/lib/actian-vectorai \
    -p 6573-6575:6573-6575 \
    -e ACTIAN_VECTORAI_ACCEPT_EULA=YES actian/vectorai:latest
  ```
  gRPC on 6574, REST + UI on 6575. Python SDK `actian-vectorai-client`, JS SDK `@actian/vectorai`.
- REST: `Authorization: Bearer <token>`, `Content-Type: application/json`.
  - `PUT /collections/{name}` body `{"vectors":{"size":512,"distance":"Cosine"}}`
  - `PUT /collections/{name}/points` body `{"points":[{"id":"<uuid>","vector":[…],"payload":{…}}]}`
  - `POST /collections/{name}/points/search` body `{"vector":[…],"limit":10,"filter":{"must":[{"key":"kind","match":{"value":"window"}}]},"with_payload":true}` → `result[{id,score,payload}]`
  - `POST /collections/{name}/points/delete`
- **Community Edition is free and capped at 5,000 vectors.** That sets the retention policy below.

Collections:

| Collection | Points | Payload |
|---|---|---|
| `tasks` | one per sticky note | `{title, text, column, createdAt, doneAt, color}` |
| `windows` | one per distinct window content | `{app, bundle, title, url, document, category, desktop, hash, firstSeen, lastSeen, seenCount, textSample?}` |

Retention (to stay under 5K): keep at most 40 window nodes per app and 3,000 total; evict lowest `lastSeen` first; done tasks older than 30 days are archived to `tasks-archive.jsonl` and removed from the collection.

Swift client: `ActianStore` over `URLSession`, no SDK needed. `LocalStore` (arrays + JSON on disk, brute-force cosine; fine to ~10K vectors) is the fallback whenever the DB is unreachable and the source of truth for tests. On reconnect, `LocalStore` replays pending upserts.

Settings → State Space: endpoint (default `http://localhost:6575`), token, "Test connection", embedder choice, exclusion list, retention numbers.

## 7. Link — building the edges

After any upsert and on the 5-minute sweep:

1. For each open task: `search("windows", taskVector, limit 15)`; keep hits with `score ≥ 0.55`; weight = `score × recency`, where recency = `0.5^(hoursSinceLastSeen / 6)`.
2. For the current window: `search("tasks", windowVector, limit 3)` → "you're probably on **Ship PixelPet v0.3** (0.71)".
3. Write `edges.json`: `{taskId → [{windowId, score, weight}]}`, plus `now: {windowId, tasks: […]}`.
4. Log one `[space]`-style line per refresh: `[state-space] refreshed: 3 tasks · 41 windows · 27 edges · 380 ms · trigger=focus`.

Thresholds and the half-life are settings; the log line makes tuning visible.

## 8. Show — the State Space page

- **Status line**: `Updated 12 s ago · next full pass in 4:10 · DB connected (2,118 / 5,000)` + Refresh now.
- **Now strip**: current window → its top tasks with score bars.
- **Left, task list**: each task with its linked windows sorted by weight, score bar, app icon, last seen. Click a window → focus it (`NSRunningApplication.activate` + AX raise).
- **Right, graph**: custom `NSView`, force-directed, tasks fixed in a ring at centre, windows around; edge width = weight; node colour = category; hover shows title; click selects. Dozens of nodes, so a simple spring layout at 30 fps is plenty; no web view.
- Auto-refresh: the page observes `Link.didRefresh` and redraws; it never triggers work itself.

## 9. Files the app will write

| Path | What |
|---|---|
| `~/Library/Application Support/PixelPet/tasks.json` | the board |
| `…/snapshots.jsonl` | every captured snapshot (append; rolls at 20 MB) |
| `…/vectors.local.json` | LocalStore contents |
| `…/edges.json` | current graph |
| `~/Library/Logs/PixelPet.log` | `[capture] [embed] [store] [state-space]` tags added to the existing set |

## 10. Phases

| Phase | Deliverable | Test |
|---|---|---|
| **1. Pages + Tasks** | Sidebar shell; Pet page = today's tabs; Tasks board with add/edit/move/delete, colours, persistence. State Space page shows a placeholder table of the windows already seen by `Context`. | smoke: window opens, tasks.json round-trips |
| **2. Local pipeline** | Capture with AX text; LocalEmbedder; LocalStore; Link; State Space list + now strip; update on focus/new window + 5-min sweep. | `tools/test-mind.sh`: headless CLI that embeds 6 fixture texts, asserts nearest-neighbour order and edge thresholds; smoke: `[state-space] refreshed` appears within 5 min |
| **3. Actian** | `ActianStore`, settings pane, test connection, fallback + replay, retention. | integration test against a local Docker instance (skipped if not running) |
| **4. Graph + pet** | Force-layout graph; pet reacts: settles when you're on a linked window, gets restless after N minutes on an unlinked one (setting). | smoke: graph view renders N nodes without dropping frames |

Order of work: 1 → 2 → 3 → 4. Phase 2 is the heart; Phase 3 is a swap of the store behind a protocol.

## 11. Risks and decisions

- **Accessibility permission is the gate** for titles, URLs and text. Without it the space is built from app names only. The ad-hoc signature currently resets the grant on rebuild; fix by signing with a local self-signed certificate (one-time setup).
- **NLEmbedding is English-only and 512-d.** Good enough to cluster "VS Code · Behavior.swift" with "Ship PixelPet"; weaker on subtle tasks. The optional summariser closes most of that gap.
- **5,000-vector cap** in the free tier → retention above. If it bites, either upgrade or keep the local store as primary.
- **AX text reads can be slow** on giant pages; the 150 ms / 300-node cap keeps the 60 Hz pet loop smooth (capture runs on a background queue anyway).
- **Privacy**: text samples are stored locally in plain JSON. The exclusion list and a "store titles only" switch are in Phase 2, not later.

## 12. Questions for you

1. Docker locally on this Mac for Actian, or do you have a hosted instance?
2. Are cloud calls acceptable for summaries/embeddings (Claude / Voyage), or local-only for now?
3. Column names for the board: Today · Doing · Done, or your own?
4. Should "Done" tasks stay in the space for a while (default 30 days) or vanish immediately?
