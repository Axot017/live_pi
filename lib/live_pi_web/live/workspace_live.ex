defmodule LivePiWeb.WorkspaceLive do
  use LivePiWeb, :live_view

  alias LivePi.Projects.Project
  alias LivePiWeb.Layouts
  alias LivePiWeb.WorkspaceComponents

  @impl true
  def mount(_params, session, socket) do
    browser_session_id = Map.get(session, "browser_session_id", default_browser_session_id())
    projects = LivePi.list_projects()
    browse = initial_browse_state()

    socket =
      socket
      |> stream_configure(:messages, dom_id: &message_dom_id/1)
      |> assign(:current_scope, nil)
      |> assign(:browser_session_id, browser_session_id)
      |> assign(:page_title, "Pi Workspace")
      |> assign(:projects, projects)
      |> assign(:browse, browse)
      |> assign(:selected_project, nil)
      |> assign(:session_ref, nil)
      |> assign(:chat_disabled?, true)
      |> assign(:streaming_text, "")
      |> assign(:streaming?, false)
      |> assign(:busy_action, nil)
      |> assign(:chat_form, chat_form())
      |> assign(:clone_form, clone_form())
      |> stream(:messages, [])

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-[calc(100vh-9rem)]">
        <div class="grid gap-6 xl:grid-cols-[22rem_minmax(0,1fr)]">
          <aside class="space-y-5">
            <section class="rounded-3xl border border-base-300/80 bg-base-100/90 p-5 shadow-sm">
              <div class="flex items-start justify-between gap-4">
                <div>
                  <p class="text-xs font-semibold uppercase tracking-[0.22em] text-primary">
                    Projects
                  </p>
                  <h1 class="mt-2 text-2xl font-semibold tracking-tight text-base-content">
                    Connected workspaces
                  </h1>
                </div>
                <div class="rounded-2xl bg-primary/10 px-3 py-2 text-right text-xs font-medium text-primary">
                  {length(@projects)} loaded
                </div>
              </div>

              <div class="mt-5 space-y-3" id="project-list">
                <button
                  :for={project <- @projects}
                  id={"project-select-#{project.id}"}
                  type="button"
                  phx-click="select_project"
                  phx-value-path={project.path}
                  class="w-full"
                >
                  <WorkspaceComponents.project_card
                    project={project}
                    selected={selected_project?(@selected_project, project)}
                  />
                </button>

                <div
                  :if={@projects == []}
                  id="project-list-empty"
                  class="rounded-2xl border border-dashed border-base-300 bg-base-200/40 px-4 py-5 text-sm text-base-content/60"
                >
                  No projects discovered yet. Browse a configured root or clone a repository.
                </div>
              </div>
            </section>

            <section class="rounded-3xl border border-base-300/80 bg-base-100/90 p-5 shadow-sm">
              <div class="flex items-center justify-between gap-3">
                <div>
                  <p class="text-xs font-semibold uppercase tracking-[0.22em] text-secondary">
                    Server filesystem
                  </p>
                  <h2 class="mt-2 text-lg font-semibold text-base-content">Browse allowed roots</h2>
                </div>
                <button
                  :if={@browse[:parent_path]}
                  id="browse-parent"
                  type="button"
                  phx-click="browse"
                  phx-value-path={@browse.parent_path}
                  class="rounded-xl border border-base-300 px-3 py-2 text-xs font-medium text-base-content/70 transition hover:border-primary/40 hover:text-primary"
                >
                  Up
                </button>
              </div>

              <div
                class="mt-4 rounded-2xl bg-base-200/60 px-4 py-3 text-xs text-base-content/60"
                id="browse-current-path"
              >
                {browse_label(@browse)}
              </div>

              <div class="mt-4 space-y-2" id="browse-entry-list">
                <button
                  :for={entry <- @browse[:entries] || []}
                  id={"browse-entry-#{entry_key(entry.path)}"}
                  type="button"
                  phx-click="browse"
                  phx-value-path={entry.path}
                  class="flex w-full items-center justify-between rounded-2xl border border-base-300/80 bg-base-100 px-4 py-3 text-left transition hover:border-primary/40 hover:bg-base-200/70"
                >
                  <div class="min-w-0">
                    <p class="truncate text-sm font-medium text-base-content">{entry.name}</p>
                    <p class="truncate text-xs text-base-content/55">{entry.path}</p>
                  </div>
                  <span class="inline-flex items-center gap-2 text-xs font-medium text-base-content/55">
                    <span
                      :if={entry.selectable?}
                      class="rounded-full bg-success/15 px-2 py-1 text-success"
                    >
                      project
                    </span>
                    <.icon name="hero-chevron-right" class="size-4" />
                  </span>
                </button>

                <div
                  :if={(@browse[:entries] || []) == []}
                  id="browse-empty"
                  class="rounded-2xl border border-dashed border-base-300 bg-base-200/40 px-4 py-5 text-sm text-base-content/60"
                >
                  This directory has no child folders available for selection.
                </div>
              </div>
            </section>

            <section class="rounded-3xl border border-base-300/80 bg-base-100/90 p-5 shadow-sm">
              <div>
                <p class="text-xs font-semibold uppercase tracking-[0.22em] text-accent">Clone</p>
                <h2 class="mt-2 text-lg font-semibold text-base-content">Add a repository</h2>
              </div>

              <.form
                for={@clone_form}
                id="clone-form"
                phx-submit="clone_project"
                class="mt-4 space-y-3"
              >
                <.input
                  field={@clone_form[:repo_url]}
                  type="url"
                  label="Repository URL"
                  placeholder="https://github.com/example/repo.git"
                />
                <.input
                  field={@clone_form[:name]}
                  type="text"
                  label="Destination name"
                  placeholder="optional"
                />
                <.button
                  id="clone-submit"
                  type="submit"
                  class="w-full"
                  disabled={@busy_action == :cloning}
                >
                  <span :if={@busy_action == :cloning}>Cloning…</span>
                  <span :if={@busy_action != :cloning}>Clone project</span>
                </.button>
              </.form>
            </section>
          </aside>

          <section class="flex min-h-[42rem] flex-col overflow-hidden rounded-[2rem] border border-base-300/80 bg-base-100/95 shadow-sm">
            <div class="border-b border-base-300/80 px-6 py-5">
              <div class="flex flex-wrap items-center justify-between gap-4">
                <div>
                  <p class="text-xs font-semibold uppercase tracking-[0.22em] text-secondary">Chat</p>
                  <h2 class="mt-2 text-2xl font-semibold tracking-tight text-base-content">
                    {selected_project_name(@selected_project)}
                  </h2>
                  <p class="mt-1 text-sm text-base-content/60">
                    {selected_project_description(@selected_project, @streaming?, @busy_action)}
                  </p>
                </div>
                <button
                  :if={@streaming? and @session_ref}
                  id="abort-button"
                  type="button"
                  phx-click="abort"
                  class="rounded-2xl border border-error/30 bg-error/10 px-4 py-2 text-sm font-medium text-error transition hover:bg-error/15"
                >
                  Abort
                </button>
              </div>
            </div>

            <div id="messages" class="flex-1 space-y-4 overflow-y-auto px-6 py-6" phx-update="stream">
              <div
                id="messages-empty"
                class="hidden only:block rounded-3xl border border-dashed border-base-300 bg-base-200/40 px-6 py-10 text-center text-sm text-base-content/60"
              >
                Select a project and send your first prompt.
              </div>
              <div :for={{id, message} <- @streams.messages} id={id} class="contents">
                <WorkspaceComponents.chat_message message={message} />
              </div>
              <div :if={@streaming_text != ""} id="streaming-message">
                <WorkspaceComponents.streaming_message text={@streaming_text} />
              </div>
            </div>

            <div class="border-t border-base-300/80 bg-base-100/90 px-6 py-5">
              <.form for={@chat_form} id="chat-form" phx-submit="send_prompt" class="space-y-3">
                <.input
                  field={@chat_form[:message]}
                  type="textarea"
                  label="Prompt"
                  rows="4"
                  placeholder="Ask pi to inspect code, explain architecture, or make a change."
                  disabled={@chat_disabled?}
                />
                <div class="flex items-center justify-between gap-3">
                  <p class="text-xs text-base-content/50">
                    Streaming responses appear live as the pi RPC session emits events.
                  </p>
                  <.button
                    id="chat-submit"
                    type="submit"
                    disabled={@chat_disabled? or @busy_action == :sending}
                  >
                    <span :if={@busy_action == :sending}>Sending…</span>
                    <span :if={@busy_action != :sending}>Send prompt</span>
                  </.button>
                </div>
              </.form>
            </div>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("browse", %{"path" => path}, socket) do
    case LivePi.browse_projects(path) do
      {:ok, browse} -> {:noreply, assign(socket, :browse, browse)}
      {:error, reason} -> {:noreply, put_flash(socket, :error, browse_error_message(reason))}
    end
  end

  def handle_event("select_project", %{"path" => path}, socket) do
    with {:ok, project} <- LivePi.select_project(path),
         {:ok, socket} <- attach_project_session(socket, project) do
      {:noreply, socket}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, project_error_message(reason))}
    end
  end

  def handle_event("clone_project", %{"clone" => params}, socket) do
    repo_url = Map.get(params, "repo_url", "")
    name = Map.get(params, "name", "")

    socket = assign(socket, :busy_action, :cloning)

    case LivePi.clone_project(repo_url, clone_options(name)) do
      {:ok, project} ->
        {:ok, socket} = attach_project_session(socket, project)

        {:noreply,
         socket
         |> assign(:busy_action, nil)
         |> assign(:projects, LivePi.list_projects())
         |> assign(:clone_form, clone_form())
         |> put_flash(:info, "Project cloned successfully.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:busy_action, nil)
         |> put_flash(:error, clone_error_message(reason))}
    end
  end

  def handle_event("send_prompt", %{"chat" => %{"message" => message}}, socket) do
    trimmed = String.trim(message || "")

    cond do
      trimmed == "" ->
        {:noreply, socket}

      is_nil(socket.assigns.session_ref) ->
        {:noreply, put_flash(socket, :error, "Select a project before chatting.")}

      true ->
        case LivePi.prompt(socket.assigns.session_ref, trimmed, []) do
          :ok ->
            local_user_message = %{
              "role" => "user",
              "content" => trimmed,
              "timestamp" => System.system_time(:millisecond)
            }

            {:noreply,
             socket
             |> assign(:busy_action, :sending)
             |> assign(:streaming?, true)
             |> assign(:streaming_text, "")
             |> assign(:chat_form, chat_form())
             |> stream_insert(:messages, local_user_message)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, prompt_error_message(reason))}
        end
    end
  end

  def handle_event("abort", _params, socket) do
    case socket.assigns.session_ref do
      nil ->
        {:noreply, socket}

      session_ref ->
        case LivePi.abort(session_ref) do
          :ok ->
            {:noreply,
             socket
             |> assign(:busy_action, nil)
             |> assign(:streaming?, false)
             |> assign(:streaming_text, "")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, prompt_error_message(reason))}
        end
    end
  end

  @impl true
  def handle_info(
        {:pi_event, session_ref,
         %{
           "type" => "message_update",
           "assistantMessageEvent" => %{"type" => "text_delta", "delta" => delta}
         }},
        %{assigns: %{session_ref: session_ref}} = socket
      ) do
    {:noreply,
     socket
     |> assign(:streaming?, true)
     |> assign(:streaming_text, socket.assigns.streaming_text <> delta)
     |> assign(:busy_action, :sending)}
  end

  def handle_info(
        {:pi_event, session_ref, %{"type" => "agent_end", "messages" => messages}},
        %{assigns: %{session_ref: session_ref}} = socket
      ) do
    {:noreply,
     socket
     |> assign(:streaming?, false)
     |> assign(:streaming_text, "")
     |> assign(:busy_action, nil)
     |> stream(:messages, messages, reset: true)}
  end

  def handle_info(
        {:pi_event, session_ref, %{type: "rpc_error", error: error}},
        %{assigns: %{session_ref: session_ref}} = socket
      ) do
    {:noreply,
     socket
     |> assign(:streaming?, false)
     |> assign(:streaming_text, "")
     |> assign(:busy_action, nil)
     |> put_flash(:error, error)}
  end

  def handle_info(
        {:pi_event, session_ref, %{"type" => "rpc_error", "error" => error}},
        %{assigns: %{session_ref: session_ref}} = socket
      ) do
    {:noreply,
     socket
     |> assign(:streaming?, false)
     |> assign(:streaming_text, "")
     |> assign(:busy_action, nil)
     |> put_flash(:error, error)}
  end

  def handle_info(
        {:pi_exit, session_ref, _reason},
        %{assigns: %{session_ref: session_ref}} = socket
      ) do
    {:noreply,
     socket
     |> assign(:session_ref, nil)
     |> assign(:chat_disabled?, true)
     |> assign(:streaming?, false)
     |> assign(:streaming_text, "")
     |> assign(:busy_action, nil)
     |> put_flash(:error, "Pi session stopped unexpectedly.")}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp attach_project_session(socket, %Project{} = project) do
    case LivePi.start_session(socket.assigns.browser_session_id, project.path,
           subscriber: self(),
           session_name: project.name
         ) do
      {:ok, session_ref} ->
        finalize_project_selection(socket, project, session_ref)

      {:error, {:already_started, session_ref}} ->
        :ok = LivePi.subscribe(session_ref, self())
        finalize_project_selection(socket, project, session_ref)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp finalize_project_selection(socket, project, session_ref) do
    messages =
      case LivePi.session_messages(session_ref) do
        {:ok, messages} -> messages
        {:error, _reason} -> []
      end

    {:ok,
     socket
     |> assign(:selected_project, project)
     |> assign(:session_ref, session_ref)
     |> assign(:chat_disabled?, false)
     |> assign(:streaming?, false)
     |> assign(:streaming_text, "")
     |> assign(:busy_action, nil)
     |> stream(:messages, messages, reset: true)}
  end

  defp initial_browse_state do
    case LivePi.browse_projects() do
      {:ok, browse} -> browse
      {:error, _reason} -> %{current_path: nil, root_path: nil, parent_path: nil, entries: []}
    end
  end

  defp selected_project?(nil, _project), do: false
  defp selected_project?(%Project{id: id}, %Project{id: id}), do: true
  defp selected_project?(_, _), do: false

  defp selected_project_name(nil), do: "Select a project"
  defp selected_project_name(%Project{name: name}), do: name

  defp selected_project_description(nil, _streaming?, _busy_action) do
    "Choose a project from the sidebar to open a pi RPC session in that directory."
  end

  defp selected_project_description(%Project{path: path}, true, _busy_action) do
    "Streaming live from #{path}"
  end

  defp selected_project_description(%Project{path: path}, false, :cloning) do
    "Cloning into #{path}"
  end

  defp selected_project_description(%Project{path: path}, false, _busy_action) do
    path
  end

  defp chat_form do
    to_form(%{"message" => ""}, as: :chat)
  end

  defp clone_form do
    to_form(%{"repo_url" => "", "name" => ""}, as: :clone)
  end

  defp clone_options(name) do
    if String.trim(name) == "", do: [], else: [name: name]
  end

  defp browse_label(%{current_path: nil}), do: "No project roots configured"
  defp browse_label(%{current_path: path}), do: path

  defp project_error_message(:path_not_found), do: "The selected directory no longer exists."

  defp project_error_message(:path_outside_roots),
    do: "That directory is outside the configured project roots."

  defp project_error_message(:not_a_directory), do: "Please choose a directory."
  defp project_error_message(reason), do: "Unable to open project: #{inspect(reason)}"

  defp browse_error_message(:path_outside_roots),
    do: "You can only browse directories inside configured project roots."

  defp browse_error_message(:path_not_found), do: "That directory no longer exists."
  defp browse_error_message(reason), do: "Unable to browse directory: #{inspect(reason)}"

  defp clone_error_message(:invalid_repo_url), do: "Enter a valid HTTP(S) Git repository URL."

  defp clone_error_message(:destination_exists),
    do: "A project with that destination name already exists."

  defp clone_error_message(:managed_clone_root_not_configured),
    do: "Managed clone root is not configured on the server."

  defp clone_error_message({:clone_failed, output}),
    do: if(output == "", do: "Git clone failed.", else: output)

  defp clone_error_message(reason), do: "Unable to clone project: #{inspect(reason)}"

  defp prompt_error_message(reason) when is_binary(reason), do: reason
  defp prompt_error_message(reason), do: "Unable to send prompt: #{inspect(reason)}"

  defp default_browser_session_id do
    12
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp entry_key(path) do
    path
    |> :erlang.phash2()
    |> Integer.to_string()
  end

  defp message_dom_id(message) do
    role = Map.get(message, "role") || Map.get(message, :role) || "message"

    timestamp =
      Map.get(message, "timestamp") || Map.get(message, :timestamp) ||
        System.unique_integer([:positive])

    "message-#{role}-#{timestamp}"
  end
end
