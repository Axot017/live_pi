defmodule LivePiWeb.WorkspaceComponents do
  use LivePiWeb, :html

  attr :sidebar_open, :boolean, required: true
  attr :projects, :list, required: true
  attr :selected_project_id, :string, required: true
  attr :repo_url, :string, required: true

  def sidebar(assigns) do
    ~H"""
    <aside class={[
      sidebar_shell_classes(),
      @sidebar_open && "translate-x-0",
      !@sidebar_open && "-translate-x-full"
    ]}>
      <div class="flex items-center justify-between border-b border-base-300 px-5 py-4 lg:justify-start">
        <h1 class="text-base font-medium">pi</h1>
        <button
          type="button"
          phx-click="close_sidebar"
          class="rounded-lg border border-base-300 px-3 py-2 text-sm lg:hidden"
        >
          close
        </button>
      </div>

      <div class="border-b border-base-300 px-4 py-4">
        <.clone_form repo_url={@repo_url} />
      </div>

      <div class="pi-scroll flex-1 overflow-y-auto">
        <.project_list projects={@projects} selected_project_id={@selected_project_id} />
      </div>
    </aside>
    """
  end

  attr :repo_url, :string, required: true

  def clone_form(assigns) do
    ~H"""
    <form phx-change="update_repo_url" phx-submit="clone_repo" class="space-y-2">
      <input
        type="url"
        name="repo_url"
        value={@repo_url}
        placeholder="repository url"
        class="min-h-11 w-full rounded-lg border border-base-300 bg-base-200 px-3 py-2.5 text-base outline-none transition focus:border-base-content/40"
      />
      <button
        type="submit"
        class="min-h-11 w-full rounded-lg border border-base-300 bg-base-200 px-3 py-2.5 text-sm text-base-content transition hover:bg-base-300"
      >
        clone
      </button>
    </form>
    """
  end

  attr :projects, :list, required: true
  attr :selected_project_id, :string, required: true

  def project_list(assigns) do
    ~H"""
    <button
      :for={project <- @projects}
      type="button"
      phx-click="select_project"
      phx-value-id={project.id}
      class={[
        project_button_classes(),
        @selected_project_id == project.id && "bg-base-200",
        @selected_project_id != project.id && "hover:bg-base-200/60"
      ]}
    >
      <div class="min-w-0">
        <div class="truncate text-sm font-medium">{project.name}</div>
        <div class="mt-1 truncate text-xs text-base-content/55">{project.branch}</div>
      </div>
      <span class={[
        "ml-3 size-2 rounded-full",
        status_class(project.status)
      ]}>
      </span>
    </button>
    """
  end

  attr :selected_project, :map, required: true

  def chat_header(assigns) do
    ~H"""
    <div class="sticky top-0 z-20 border-b border-base-300 bg-base-100/95 backdrop-blur">
      <div class="flex items-center justify-between gap-3 px-4 py-3 sm:px-6">
        <div class="flex min-w-0 items-center gap-3">
          <button
            type="button"
            phx-click="toggle_sidebar"
            class="min-h-11 rounded-lg border border-base-300 px-3 text-sm lg:hidden"
          >
            projects
          </button>
          <div class="min-w-0">
            <h2 class="truncate text-sm font-medium">{@selected_project.name}</h2>
            <p class="truncate text-xs text-base-content/50">{@selected_project.path}</p>
          </div>
        </div>
        <div class="shrink-0 text-xs text-base-content/50">{@selected_project.branch}</div>
      </div>
    </div>
    """
  end

  attr :messages, :list, required: true

  def message_list(assigns) do
    ~H"""
    <div class="pi-scroll flex-1 space-y-4 overflow-y-auto px-4 py-4 sm:px-6 sm:py-5">
      <.message :for={message <- @messages} message={message} />
    </div>
    """
  end

  attr :message, :map, required: true

  def message(assigns) do
    ~H"""
    <article class={[message_classes(), message_surface_class(@message.role)]}>
      <div class="mb-2 flex items-center gap-2 text-[11px] uppercase tracking-[0.18em]">
        <span class="text-base-content/55">{@message.author}</span>
        <span class="text-base-content/35">{@message.at}</span>
      </div>
      <p class="text-[15px] leading-7 text-base-content/88 sm:text-sm">{@message.body}</p>
    </article>
    """
  end

  attr :message, :string, required: true

  def composer(assigns) do
    ~H"""
    <form
      phx-change="update_message"
      phx-submit="send_message"
      class="sticky bottom-0 border-t border-base-300 bg-base-100 px-4 py-3 sm:px-6 sm:py-4"
    >
      <label class="sr-only" for="chat-message">message</label>
      <div class="rounded-xl border border-base-300 bg-base-200 p-3">
        <textarea
          id="chat-message"
          name="message"
          rows="4"
          placeholder="message"
          class="w-full resize-none bg-transparent text-base leading-7 outline-none placeholder:text-base-content/35"
        >{@message}</textarea>
        <div class="mt-3 flex justify-end border-t border-base-300 pt-3">
          <button
            type="submit"
            class="min-h-11 rounded-lg border border-base-300 bg-base-100 px-4 py-2 text-sm transition hover:bg-base-300"
          >
            send
          </button>
        </div>
      </div>
    </form>
    """
  end

  defp sidebar_shell_classes do
    "fixed inset-y-0 left-0 z-40 flex w-[19rem] flex-col border-r border-base-300 bg-base-100 transition-transform lg:static lg:w-auto lg:translate-x-0 lg:border-r-0"
  end

  defp project_button_classes do
    "flex min-h-14 w-full items-center justify-between border-b border-base-300 px-4 py-4 text-left transition"
  end

  defp message_classes do
    "max-w-3xl rounded-xl border px-4 py-3"
  end

  defp status_class("active"), do: "bg-success"
  defp status_class("idle"), do: "bg-base-content/25"
  defp status_class("syncing"), do: "bg-info"
  defp status_class("queued"), do: "bg-warning"
  defp status_class(_), do: "bg-base-content/25"

  defp message_surface_class(:assistant), do: "border-base-300 bg-base-200"
  defp message_surface_class(:user), do: "ml-auto border-base-300 bg-neutral"
end
