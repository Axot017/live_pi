defmodule LivePiWeb.WorkspaceLive do
  use LivePiWeb, :live_view

  alias LivePiWeb.WorkspaceComponents

  @impl true
  def mount(_params, _session, socket) do
    projects = mock_projects()
    selected_project = List.first(projects)

    {:ok,
     socket
     |> assign(:page_title, "pi")
     |> assign(:projects, projects)
     |> assign(:selected_project_id, selected_project.id)
     |> assign(:selected_project, selected_project)
     |> assign(:messages, project_messages(selected_project.id))
     |> assign(:repo_url, "")
     |> assign(:message, "")
     |> assign(:sidebar_open, false)}
  end

  @impl true
  def handle_event("select_project", %{"id" => id}, socket) do
    project =
      Enum.find(socket.assigns.projects, &(&1.id == id)) || socket.assigns.selected_project

    {:noreply,
     socket
     |> assign(:selected_project_id, project.id)
     |> assign(:selected_project, project)
     |> assign(:messages, project_messages(project.id))
     |> assign(:sidebar_open, false)}
  end

  @impl true
  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, update(socket, :sidebar_open, &(!&1))}
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

      {:noreply,
       socket
       |> assign(:projects, [project | socket.assigns.projects])
       |> assign(:selected_project_id, project.id)
       |> assign(:selected_project, project)
       |> assign(:messages, project_messages(project.id))
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
       |> append_mock_exchange(message)}
    end
  end

  defp append_mock_exchange(socket, prompt) do
    project = socket.assigns.selected_project

    user_message = %{
      id: unique_id("user"),
      role: :user,
      author: "you",
      at: "now",
      body: prompt
    }

    reply = %{
      id: unique_id("assistant"),
      role: :assistant,
      author: "pi",
      at: "now",
      body:
        "Mocked response for #{project.name}. I would inspect the repo and propose the next smallest step."
    }

    assign(socket, :messages, socket.assigns.messages ++ [user_message, reply])
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

  defp project_messages("live-pi") do
    [
      %{
        id: "m1",
        role: :assistant,
        author: "pi",
        at: "09:11",
        body: "UI shell is ready for mocked interaction."
      },
      %{id: "m2", role: :user, author: "you", at: "09:14", body: "Keep it minimal and readable."},
      %{id: "m3", role: :assistant, author: "pi", at: "09:16", body: "Understood."}
    ]
  end

  defp project_messages("dotfiles") do
    [
      %{
        id: "d1",
        role: :assistant,
        author: "pi",
        at: "Yesterday",
        body: "Shell workspace loaded."
      },
      %{id: "d2", role: :user, author: "you", at: "Yesterday", body: "Flag risky changes first."}
    ]
  end

  defp project_messages("ml-notes") do
    [
      %{
        id: "r1",
        role: :assistant,
        author: "pi",
        at: "Monday",
        body: "Research workspace loaded."
      },
      %{
        id: "r2",
        role: :user,
        author: "you",
        at: "Monday",
        body: "Keep only the strongest directions."
      }
    ]
  end

  defp project_messages(_id) do
    [
      %{
        id: unique_id("seed"),
        role: :assistant,
        author: "pi",
        at: "now",
        body: "Repository added. Backend integration will come later."
      }
    ]
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
          <WorkspaceComponents.message_list messages={@messages} />
          <WorkspaceComponents.composer message={@message} />
        </main>
      </div>

      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end
end
