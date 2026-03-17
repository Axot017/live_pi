# TODO

## Phase 1 - Foundation
- [ ] Read pi RPC docs in detail and map required commands/events for the web UI
- [ ] Add missing dependencies for implementation and tests (`Req` only if later needed, `Mox`)
- [ ] Add runtime config for pi executable path, default model/provider options, and allowed project root directories
- [ ] Define behaviour boundaries for pi communication and project management
- [ ] Configure env-based dependency injection so tests can swap real pi integration for mocks
- [ ] Add supervised infrastructure for per-browser-session pi processes and async clone work

## Phase 2 - Pi RPC integration
- [ ] Design a supervised pi session process abstraction keyed by browser session + selected project
- [ ] Implement RPC transport over JSONL stdin/stdout to `pi --mode rpc`
- [ ] Start pi sessions with the selected project as the process working directory so project-specific skills/commands load correctly
- [ ] Implement command handling for `prompt`, `abort`, `get_state`, `get_messages`, and `new_session`
- [ ] Consume streaming pi events (`message_start`, `message_update`, `message_end`, `tool_execution_*`, `agent_end`) and translate them into UI updates
- [ ] Normalize RPC failures, process exits, and malformed output into app-friendly errors
- [ ] Ensure one active prompt per session is enforced, including steering/abort behavior decisions for later

## Phase 3 - Project management without DB
- [ ] Implement filesystem-backed project discovery rooted in configured server directories
- [ ] Build a server-side directory browser/picker constrained to allowed root directories
- [ ] Support selecting an existing project directory from the allowed roots
- [ ] Support cloning a new Git repository into a managed local root
- [ ] Validate clone URLs, derive safe destination names, and prevent unsafe paths/duplicates
- [ ] Decide whether known projects are discovered purely by directory scan or also cached in a local file
- [ ] Expose project metadata needed by the UI (name, path, source, clone status)

## Phase 4 - Web UI
- [ ] Replace the stock landing page with a LiveView workspace at `/`
- [ ] Build a polished project sidebar with existing-project picker, directory browser, and clone form
- [ ] Build a basic chat UI with transcript, prompt composer, and clear loading states
- [ ] Render streaming assistant output incrementally as pi RPC events arrive
- [ ] Show selected project, session state, and agent activity clearly in the UI
- [ ] Handle empty/error states: no projects yet, no selected project, RPC unavailable, clone failure, session crash
- [ ] Keep the UI simple, responsive, and aligned with existing Phoenix component conventions

## Phase 5 - Session and state management
- [ ] Store selected project and active session reference in the browser session
- [ ] Rehydrate the workspace cleanly on refresh within the same browser session
- [ ] Define what happens when switching projects: reuse session, create a new session, or reset transcript
- [ ] Clean up orphaned pi session processes when browser sessions expire or disconnect

## Phase 6 - Testing
- [ ] Add Mox and define mocks for pi integration boundaries
- [ ] Update `test/test_helper.exs` and shared test cases for Mox verification
- [ ] Add unit tests for project discovery, directory browsing constraints, and clone validation
- [ ] Add unit tests for pi session orchestration and streaming event handling using mocks/fakes
- [ ] Add LiveView tests for project selection, cloning, streaming chat, abort/error states, and reconnect behavior
- [ ] Ensure tests never use real pi tokens or a real pi backend

## Phase 7 - Docs and verification
- [ ] Update `README.md` with local setup and configuration for pi RPC + allowed project roots
- [ ] Document key architectural decisions and constraints
- [ ] Run `mix precommit` and fix all warnings/test/style issues
