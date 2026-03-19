defmodule LivePiWeb.WorkspaceLive do
  use LivePiWeb, :live_view

  alias LivePiWeb.WorkspaceComponents

  @impl true
  def mount(_params, _session, socket) do
    projects = mock_projects()
    selected_project = List.first(projects)

    transcript_items = prepare_transcript(project_transcript(selected_project.id))

    {:ok,
     socket
     |> assign(:page_title, "pi")
     |> assign(:projects, projects)
     |> assign(:selected_project_id, selected_project.id)
     |> assign(:selected_project, selected_project)
     |> assign(:transcript_items, transcript_items)
     |> assign(:expanded, default_expanded(transcript_items))
     |> assign(:repo_url, "")
     |> assign(:message, "")
     |> assign(:sidebar_open, false)}
  end

  @impl true
  def handle_event("select_project", %{"id" => id}, socket) do
    project =
      Enum.find(socket.assigns.projects, &(&1.id == id)) || socket.assigns.selected_project

    transcript_items = prepare_transcript(project_transcript(project.id))

    {:noreply,
     socket
     |> assign(:selected_project_id, project.id)
     |> assign(:selected_project, project)
     |> assign(:transcript_items, transcript_items)
     |> assign(:expanded, default_expanded(transcript_items))
     |> assign(:sidebar_open, false)}
  end

  @impl true
  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, update(socket, :sidebar_open, &(!&1))}
  end

  @impl true
  def handle_event("toggle_expand", %{"key" => key}, socket) do
    {:noreply, update(socket, :expanded, &Map.update(&1, key, true, fn value -> !value end))}
  end

  @impl true
  def handle_event("close_sidebar", _params, socket) do
    {:noreply, assign(socket, :sidebar_open, false)}
  end

  @impl true
  def handle_event("update_repo_url", %{"repo_url" => repo_url}, socket) do
    {:noreply, assign(socket, :repo_url, repo_url)}
  end

  @impl true
  def handle_event("clone_repo", %{"repo_url" => repo_url}, socket) do
    repo_url = String.trim(repo_url)

    if repo_url == "" do
      {:noreply, put_flash(socket, :error, "Paste a repository URL.")}
    else
      project = mock_project_from_repo(repo_url)

      transcript_items = prepare_transcript(project_transcript(project.id))

      {:noreply,
       socket
       |> assign(:projects, [project | socket.assigns.projects])
       |> assign(:selected_project_id, project.id)
       |> assign(:selected_project, project)
       |> assign(:transcript_items, transcript_items)
       |> assign(:expanded, default_expanded(transcript_items))
       |> assign(:repo_url, "")
       |> assign(:sidebar_open, false)
       |> put_flash(:info, "Added #{project.name}.")}
    end
  end

  @impl true
  def handle_event("update_message", %{"message" => message}, socket) do
    {:noreply, assign(socket, :message, message)}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    message = String.trim(message)

    if message == "" do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:message, "")
       |> append_mock_response(message)}
    end
  end

  defp append_mock_response(socket, prompt) do
    project = socket.assigns.selected_project

    user_item = %{
      id: unique_id("user"),
      kind: :user_message,
      author: "you",
      at: "now",
      body: prompt
    }

    items =
      prepare_transcript(
        socket.assigns.transcript_items ++ [user_item] ++ mock_response_items(project, prompt)
      )

    assign(socket, :transcript_items, items)
    |> assign(:expanded, Map.merge(default_expanded(items), socket.assigns.expanded))
  end

  defp mock_response_items(project, prompt) do
    prompt_downcased = String.downcase(prompt)

    cond do
      String.contains?(prompt_downcased, "subagent") ->
        [
          assistant_turn(
            "now",
            [
              text_block(
                "I would delegate this as a tool-backed subagent run so the main thread stays readable."
              ),
              tool_call_block(
                "subagent",
                ~s|{"agent":"planner","task":"Plan the next implementation slice for #{project.name}"}|
              )
            ]
          ),
          tool_run(
            "subagent",
            :ok,
            "planner completed and returned a concise build plan.",
            "1. inspect current ui\n2. design typed transcript view\n3. wire rpc events into normalized items",
            %{agent: "planner", output: "text"}
          )
        ]

      String.contains?(prompt_downcased, "tool") || String.contains?(prompt_downcased, "bash") ->
        [
          assistant_turn(
            "now",
            [
              text_block(
                "A real pi session would likely call tools here instead of replying with plain text."
              ),
              thinking_block(
                "Check project state first, then inspect files, then summarize the result back into the thread."
              ),
              tool_call_block("bash", ~s|{"command":"rg -n \"LiveView\" lib test"}|)
            ]
          ),
          tool_run(
            "bash",
            :running,
            "Streaming tool output appears as its own transcript item.",
            "lib/live_pi_web/live/workspace_live.ex:1:defmodule LivePiWeb.WorkspaceLive do\nlib/live_pi_web/components/workspace_components.ex:1:defmodule LivePiWeb.WorkspaceComponents do",
            %{exit_code: 0, streamed: true}
          )
        ]

      String.contains?(prompt_downcased, "confirm") ||
          String.contains?(prompt_downcased, "delete") ->
        [
          assistant_turn(
            "now",
            [
              text_block(
                "Extensions can request input from the UI instead of forcing everything into plain text."
              )
            ]
          ),
          %{
            id: unique_id("ui"),
            kind: :ui_request,
            method: "confirm",
            title: "Confirm destructive action",
            message: "Delete the selected session before continuing?",
            options: ["confirm", "cancel"]
          }
        ]

      true ->
        [
          assistant_turn(
            "now",
            [
              text_block(
                "For the real integration, this turn would be block-based: text, optional thinking, and tool calls inside one assistant message."
              ),
              thinking_block(
                "Keep the transcript model typed so the UI can render text, tool activity, system notices, and extension prompts differently."
              ),
              tool_call_block("read", ~s|{"path":"lib/live_pi_web/live/workspace_live.ex"}|)
            ]
          ),
          tool_run(
            "read",
            :ok,
            "Tool runs are better shown as separate operational items under the assistant turn.",
            "defmodule LivePiWeb.WorkspaceLive do\n  use LivePiWeb, :live_view\n  ...",
            %{bytes: "4.8kb"}
          ),
          system_notice(
            "now",
            "turn complete",
            "In RPC mode this would correspond to message_end / tool_execution_end / turn_end events."
          )
        ]
    end
  end

  defp mock_projects do
    [
      %{
        id: "live-pi",
        name: "live_pi",
        branch: "main",
        status: "active",
        path: "/srv/pi-projects/live_pi"
      },
      %{
        id: "dotfiles",
        name: "dotfiles",
        branch: "lab",
        status: "idle",
        path: "/srv/pi-projects/dotfiles"
      },
      %{
        id: "ml-notes",
        name: "ml-notes",
        branch: "research",
        status: "syncing",
        path: "/srv/pi-projects/ml-notes"
      }
    ]
  end

  defp project_transcript("live-pi") do
    [
      system_notice(
        "09:08",
        "session ready",
        "Mocked transcript with typed items for future pi RPC integration."
      ),
      user_message("09:10", "Start with the UI only, but make room for richer pi messages."),
      assistant_turn(
        "09:11",
        [
          text_block("This mock shows the structure we will need once real pi events arrive."),
          thinking_block(
            "Assistant output is not only text. It can stream text, thinking, and tool-call construction separately."
          ),
          tool_call_block("read", ~s|{"path":"docs/rpc.md"}|)
        ]
      ),
      tool_run(
        "read",
        :ok,
        "A future LiveView can render tool execution independently from assistant prose.",
        "# RPC Mode\n...\nmessage_update\ntool_execution_start\ntool_execution_end",
        %{source: "docs/rpc.md"}
      ),
      assistant_turn(
        "09:13",
        [
          text_block(
            "Subagent calls are not first-class transcript messages in core pi, but they can still look good in UI as specialized tool activity."
          ),
          tool_call_block(
            "subagent",
            ~s|{"agent":"planner","task":"Design event normalization for web UI"}|
          )
        ]
      ),
      tool_run(
        "subagent",
        :ok,
        "Subagent invocation shown as a tool run with its own output and status.",
        "planner → recommend transcript item kinds: assistant_turn, tool_run, system_notice, ui_request",
        %{agent: "planner"}
      ),
      %{
        id: unique_id("ui"),
        kind: :ui_request,
        method: "confirm",
        title: "Extension dialog example",
        message: "RPC mode can ask the client to confirm, select, input, or edit text.",
        options: ["confirm", "cancel"]
      }
    ]
  end

  defp project_transcript("dotfiles") do
    [
      system_notice("Yesterday", "idle", "Lower activity project."),
      user_message("Yesterday", "Flag risky changes first."),
      assistant_turn(
        "Yesterday",
        [
          text_block("This repo would mostly surface shell and file tool activity."),
          tool_call_block("bash", ~s|{"command":"git diff --stat"}|)
        ]
      ),
      tool_run(
        "bash",
        :ok,
        "Compact terminal output fits well in a transcript row.",
        " 3 files changed, 21 insertions(+), 8 deletions(-)",
        %{cwd: "dotfiles"}
      )
    ]
  end

  defp project_transcript("ml-notes") do
    [
      system_notice(
        "Monday",
        "research",
        "A quieter transcript can still mix user text, assistant text, and structured system items."
      ),
      user_message("Monday", "Keep only the strongest directions."),
      assistant_turn(
        "Monday",
        [
          text_block("This workspace is a good example of mostly textual turns."),
          thinking_block("Show thinking collapsed by default so the chat stays readable.")
        ]
      )
    ]
  end

  defp project_transcript(_id) do
    [
      system_notice(
        "now",
        "new project",
        "Repository added. Future pi activity would appear here as typed transcript items."
      ),
      assistant_turn(
        "now",
        [text_block("Fresh workspace ready."), tool_call_block("read", ~s|{"path":"README.md"}|)]
      )
    ]
  end

  defp user_message(at, body) do
    %{id: unique_id("user"), kind: :user_message, author: "you", at: at, body: body}
  end

  defp assistant_turn(at, blocks) do
    %{id: unique_id("assistant"), kind: :assistant_turn, author: "pi", at: at, blocks: blocks}
  end

  defp tool_run(tool_name, status, summary, output, meta) do
    %{
      id: unique_id("tool"),
      kind: :tool_run,
      tool_name: tool_name,
      status: status,
      summary: summary,
      output: output,
      meta: meta
    }
  end

  defp system_notice(at, title, body) do
    %{id: unique_id("system"), kind: :system_notice, at: at, title: title, body: body}
  end

  defp text_block(text), do: %{kind: :text, text: text}
  defp thinking_block(text), do: %{kind: :thinking, text: text}
  defp tool_call_block(name, arguments), do: %{kind: :tool_call, name: name, arguments: arguments}

  defp prepare_transcript(items) do
    Enum.map(items, fn
      %{kind: :assistant_turn, blocks: blocks} = item ->
        blocks =
          Enum.with_index(blocks)
          |> Enum.map(fn {block, index} ->
            Map.put_new(block, :id, "#{item.id}-block-#{index}")
          end)

        %{item | blocks: blocks}

      item ->
        item
    end)
  end

  defp default_expanded(items) do
    Enum.reduce(items, %{}, fn item, acc ->
      acc =
        if item.kind == :tool_run do
          Map.put(acc, item.id, item.status == :running)
        else
          acc
        end

      if item.kind == :assistant_turn do
        Enum.reduce(item.blocks, acc, fn block, block_acc ->
          case block.kind do
            :thinking -> Map.put(block_acc, block.id, false)
            :tool_call -> Map.put(block_acc, block.id, false)
            _ -> block_acc
          end
        end)
      else
        acc
      end
    end)
  end

  defp mock_project_from_repo(repo_url) do
    repo_name =
      repo_url
      |> String.trim_trailing("/")
      |> String.split("/")
      |> List.last()
      |> String.replace_suffix(".git", "")
      |> case do
        "" -> "new-project"
        name -> name
      end

    %{
      id: unique_id(repo_name),
      name: repo_name,
      branch: "main",
      status: "queued",
      path: "/srv/pi-projects/#{repo_name}"
    }
  end

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100 text-base-content">
      <div class="mx-auto min-h-screen max-w-[1600px] lg:grid lg:grid-cols-[280px_minmax(0,1fr)] lg:gap-px lg:bg-base-300">
        <div
          :if={@sidebar_open}
          phx-click="close_sidebar"
          class="fixed inset-0 z-30 bg-black/60 lg:hidden"
        />

        <WorkspaceComponents.sidebar
          sidebar_open={@sidebar_open}
          projects={@projects}
          selected_project_id={@selected_project_id}
          repo_url={@repo_url}
        />

        <main class="flex min-h-screen flex-col bg-base-100">
          <WorkspaceComponents.chat_header selected_project={@selected_project} />
          <WorkspaceComponents.transcript items={@transcript_items} expanded={@expanded} />
          <WorkspaceComponents.composer message={@message} />
        </main>
      </div>

      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end
end
