defmodule LivePiWeb.WorkspaceLive do
  use LivePiWeb, :live_view

  alias LivePi.PiSessions
  alias LivePi.Projects
  alias LivePiWeb.WorkspaceComponents

  @impl true
  def mount(_params, _session, socket) do
    projects = Projects.list()
    selected_project = List.first(projects)

    socket =
      socket
      |> assign(:page_title, "pi")
      |> assign(:projects_root, Projects.projects_root())
      |> assign(:projects, projects)
      |> assign(:selected_project_id, selected_project && selected_project.id)
      |> assign(:selected_project, selected_project)
      |> assign(:transcript_items, [])
      |> assign(:expanded, %{})
      |> assign(:repo_url, "")
      |> assign(:message, "")
      |> assign(:sidebar_open, false)
      |> assign(:session_ready, false)
      |> assign(:session_alive, false)
      |> assign(:session_streaming, false)
      |> assign(:session_compacting, false)
      |> assign(:session_error, nil)
      |> assign(:session_topic, nil)

    socket = attach_project_session(socket, selected_project)

    {:ok, socket}
  end

  @impl true
  def handle_event("select_project", %{"id" => id}, socket) do
    project =
      Enum.find(socket.assigns.projects, &(&1.id == id)) || socket.assigns.selected_project

    {:noreply,
     socket
     |> assign(:selected_project_id, project && project.id)
     |> assign(:selected_project, project)
     |> assign(:sidebar_open, false)
     |> attach_project_session(project)}
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

    case Projects.clone(repo_url) do
      {:ok, project} ->
        {:noreply,
         socket
         |> assign_cloned_project(project)
         |> put_flash(:info, "Cloned #{project.name}.")}

      {:exists, project} ->
        {:noreply,
         socket
         |> assign_cloned_project(project)
         |> put_flash(:info, "#{project.name} already exists.")}

      {:error, message} ->
        {:noreply,
         socket
         |> assign(:repo_url, repo_url)
         |> put_flash(:error, message)}
    end
  end

  @impl true
  def handle_event("update_message", %{"message" => message}, socket) do
    {:noreply, assign(socket, :message, message)}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    message = String.trim(message)

    cond do
      message == "" ->
        {:noreply, socket}

      is_nil(socket.assigns.selected_project) ->
        {:noreply, put_flash(socket, :error, "No project selected.")}

      socket.assigns.session_streaming ->
        {:noreply, put_flash(socket, :error, "pi is still streaming a response.")}

      true ->
        case PiSessions.send_prompt(socket.assigns.selected_project.id, message) do
          :ok ->
            {:noreply, assign(socket, :message, "")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, reason)}
        end
    end
  end

  @impl true
  def handle_info({:pi_session_snapshot, project_id, snapshot}, socket) do
    if socket.assigns.selected_project_id == project_id do
      {:noreply, apply_snapshot(socket, snapshot)}
    else
      {:noreply, socket}
    end
  end

  defp assign_cloned_project(socket, project) do
    projects = Projects.list()

    socket
    |> assign(:projects, projects)
    |> assign(:selected_project_id, project.id)
    |> assign(:selected_project, project)
    |> assign(:repo_url, "")
    |> assign(:sidebar_open, false)
    |> attach_project_session(project)
  end

  defp attach_project_session(socket, nil) do
    maybe_unsubscribe(socket.assigns.session_topic)

    socket
    |> assign(:session_topic, nil)
    |> apply_snapshot(empty_snapshot())
  end

  defp attach_project_session(socket, project) do
    maybe_unsubscribe(socket.assigns.session_topic)

    case PiSessions.ensure_started(project) do
      {:ok, _pid} ->
        topic = PiSessions.topic(project.id)

        if connected?(socket) do
          Phoenix.PubSub.subscribe(LivePi.PubSub, topic)
        end

        snapshot = PiSessions.snapshot(project.id)

        socket
        |> assign(:session_topic, topic)
        |> apply_snapshot(snapshot)

      {:error, reason} ->
        socket
        |> assign(:session_topic, nil)
        |> apply_snapshot(%{empty_snapshot() | last_error: inspect(reason)})
    end
  end

  defp maybe_unsubscribe(nil), do: :ok

  defp maybe_unsubscribe(topic) do
    Phoenix.PubSub.unsubscribe(LivePi.PubSub, topic)
  end

  defp apply_snapshot(socket, snapshot) do
    transcript_items = snapshot.transcript_items || []
    expanded = merge_expanded(socket.assigns.expanded, transcript_items)

    socket
    |> assign(:transcript_items, transcript_items)
    |> assign(:expanded, expanded)
    |> assign(:session_ready, snapshot.ready)
    |> assign(:session_alive, snapshot.alive)
    |> assign(:session_streaming, snapshot.is_streaming)
    |> assign(:session_compacting, snapshot.is_compacting)
    |> assign(:session_error, snapshot.last_error)
  end

  defp merge_expanded(previous, items) do
    Map.merge(default_expanded(items), previous)
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
            :thinking -> Map.put_new(block_acc, block.id, false)
            :tool_call -> Map.put_new(block_acc, block.id, false)
            _ -> block_acc
          end
        end)
      else
        acc
      end
    end)
  end

  defp empty_snapshot do
    %{
      ready: false,
      alive: false,
      is_streaming: false,
      is_compacting: false,
      last_error: nil,
      transcript_items: []
    }
  end

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
          projects_root={@projects_root}
        />

        <main class="flex min-h-screen flex-col bg-base-100">
          <WorkspaceComponents.chat_header
            selected_project={@selected_project}
            session_ready={@session_ready}
            session_alive={@session_alive}
            session_streaming={@session_streaming}
            session_compacting={@session_compacting}
            session_error={@session_error}
          />
          <WorkspaceComponents.transcript items={@transcript_items} expanded={@expanded} />
          <WorkspaceComponents.composer
            message={@message}
            disabled={is_nil(@selected_project) or !@session_alive}
            busy={@session_streaming or @session_compacting}
          />
        </main>
      </div>

      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end
end
