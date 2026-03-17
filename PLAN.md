# Pi Web UI Implementation Plan

## Goal
Build a Phoenix LiveView web UI for the pi coding agent with:
- server-side project browsing limited to configured filesystem roots
- Git HTTP(S) cloning into managed roots
- basic chat with streaming assistant output
- no database
- Mox-based tests for pi integration

## Product decisions
- The workspace replaces `/`
- Projects are selected from server-side configured root directories
- V1 supports public/private Git over HTTP(S) as long as the server environment already has access configured
- Assistant responses stream live from pi RPC events
- Selection/session state is per browser session
- Long-running clone/chat work may be cancelled when the browser session disconnects in V1

## Architecture

### 1. Web layer
A single LiveView at `/` drives the whole workspace.

Primary responsibilities:
- render project browser and clone form
- render chat transcript and composer
- subscribe to session updates from a server-side pi session process
- persist selected project/session reference in browser session

Suggested module:
- `LivePiWeb.WorkspaceLive`

### 2. Project management layer
Filesystem-backed service for:
- listing allowed root directories
- browsing subdirectories safely
- validating that selected paths stay inside allowed roots
- detecting project directories
- cloning repositories into managed roots

Suggested modules:
- `LivePi.Projects`
- `LivePi.Projects.Project`
- `LivePi.Projects.Local`

Data shape:
- `%Project{id, name, path, source, root, clone_status}`

Notes:
- no DB
- project inventory comes from directory scan and/or explicitly selected path within allowed roots
- path traversal must be rejected after full path normalization

### 3. Pi integration layer
A behaviour-backed RPC client over stdin/stdout using `pi --mode rpc`.

Suggested modules:
- `LivePi.Pi`
- `LivePi.Pi.SessionSupervisor`
- `LivePi.Pi.Session`
- `LivePi.Pi.RPC`
- `LivePi.Chat`

Responsibilities:
- spawn `pi --mode rpc` with `cwd` set to selected project path
- write JSONL commands to stdin
- parse JSONL responses/events from stdout
- stream updates to subscribers
- expose a small public API for prompting, aborting, resetting session, and fetching state

### 4. Session lifecycle
Each browser session gets its own pi session process for the currently selected project.

V1 rules:
- selecting a project creates or reuses a pi session tied to that browser session + project path
- switching projects resets chat context by starting a fresh pi session for the new project
- disconnect cleanup is acceptable in V1

Suggested session identity:
- `browser_session_id + project_path`

### 5. Test strategy
All direct pi access is hidden behind behaviours.

Testing split:
- unit tests for project/path/clone logic
- unit tests for chat/session orchestration
- LiveView tests with Mox-backed fake pi service
- no real tokens, no real pi subprocesses in tests unless using a local fake process for parser/unit coverage only

## Phased delivery

## Phase 1: Contracts and config
1. Add dependencies:
   - `:mox`
   - optionally `:req` only if needed later
2. Add runtime config for:
   - allowed project roots
   - managed clone root
   - pi executable path
   - pi default args/provider/model
3. Define behaviours and public APIs:
   - `LivePi.Projects`
   - `LivePi.Pi`
4. Add supervision tree pieces:
   - dynamic supervisor for pi sessions
   - optional task supervisor for clone work

## Phase 2: Project management
1. Implement safe path normalization
2. Implement root browsing
3. Implement project selection
4. Implement clone workflow with `git clone`
5. Add unit tests for:
   - valid/invalid paths
   - traversal rejection
   - duplicate clone destination handling
   - listing and browsing

## Phase 3: Pi RPC session process
1. Build a process wrapper around `Port.open/2`
2. Implement JSONL framing/parser
3. Support commands:
   - `prompt`
   - `abort`
   - `get_state`
   - `get_messages`
   - `new_session`
4. Handle streamed events:
   - `message_start`
   - `message_update`
   - `message_end`
   - `tool_execution_start`
   - `tool_execution_update`
   - `tool_execution_end`
   - `agent_end`
5. Publish updates to subscribers via PubSub or direct process subscription
6. Add tests for event parsing and state transitions

## Phase 4: Workspace LiveView
1. Replace `/` route with `WorkspaceLive`
2. Build layout:
   - sidebar for projects
   - main chat area
3. Add server-side directory browser UI
4. Add clone form UI
5. Add chat composer and transcript
6. Render streaming assistant message updates incrementally
7. Add loading/error/empty states

## Phase 5: Session persistence and UX
1. Persist selected project in browser session
2. Rehydrate LiveView state on refresh
3. Reset transcript when changing projects
4. Handle crashed pi process with retry/restart affordance
5. Add polish to spacing, hierarchy, and responsive layout

## Phase 6: Tests and docs
1. Add Mox setup in test support
2. Add LiveView tests for:
   - initial empty state
   - project browsing and selection
   - clone success/failure
   - prompt submit
   - streaming updates
   - session reset on project switch
3. Update README
4. Run `mix precommit`

## Initial file plan

### New domain files
- `lib/live_pi/projects.ex`
- `lib/live_pi/projects/project.ex`
- `lib/live_pi/projects/local.ex`
- `lib/live_pi/pi.ex`
- `lib/live_pi/pi/session.ex`
- `lib/live_pi/pi/session_supervisor.ex`
- `lib/live_pi/chat.ex`

### New web files
- `lib/live_pi_web/live/workspace_live.ex`
- `lib/live_pi_web/components/workspace_components.ex`

### Test support
- `test/support/mocks.ex`
- `test/support/live_view_case.ex`
- `test/live_pi/projects/local_test.exs`
- `test/live_pi/chat_test.exs`
- `test/live_pi_web/live/workspace_live_test.exs`

### Existing files to update
- `mix.exs`
- `config/config.exs`
- `config/runtime.exs`
- `config/test.exs`
- `lib/live_pi/application.ex`
- `lib/live_pi.ex`
- `lib/live_pi_web/router.ex`
- `test/test_helper.exs`
- `README.md`

## Notes
- Use `Port`, not HTTP, for pi RPC because the protocol is JSONL over stdin/stdout
- Use LiveView streaming on the UI side, but keep the domain API simple and event-oriented
- Avoid storing chat history in a DB; rehydrate from the running pi session or browser session as needed
- Keep V1 simple: one active conversation per selected project per browser session
