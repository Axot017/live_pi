defmodule LivePiWeb.WorkspaceComponents do
  use LivePiWeb, :html

  alias Phoenix.HTML

  attr :sidebar_open, :boolean, required: true
  attr :projects, :list, required: true
  attr :selected_project_id, :string, default: nil
  attr :repo_url, :string, required: true
  attr :projects_root, :string, required: true

  def sidebar(assigns) do
    ~H"""
    <aside class={[
      sidebar_shell_classes(),
      @sidebar_open && "translate-x-0",
      !@sidebar_open && "-translate-x-full"
    ]}>
      <div class="flex items-center justify-between border-b border-base-300 px-5 py-4 lg:justify-start">
        <h1 class="text-base font-medium tracking-tight">pi</h1>
        <button
          type="button"
          phx-click="close_sidebar"
          class="rounded-lg border border-base-300 px-3 py-2 text-sm lg:hidden"
        >
          close
        </button>
      </div>

      <div class="border-b border-base-300 px-4 py-4">
        <p class="mb-3 text-xs leading-5 text-base-content/55">
          loading projects from
          <span class="font-mono text-[11px] text-base-content/70">{@projects_root}</span>
        </p>
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
  attr :selected_project_id, :string, default: nil

  def project_list(assigns) do
    ~H"""
    <div :if={Enum.empty?(@projects)} class="px-4 py-5 text-sm leading-6 text-base-content/55">
      No projects found in the configured directory.
    </div>

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

  attr :selected_project, :map, default: nil
  attr :session_ready, :boolean, required: true
  attr :session_alive, :boolean, required: true
  attr :session_streaming, :boolean, required: true
  attr :session_compacting, :boolean, required: true
  attr :session_error, :string, default: nil

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
          <div :if={@selected_project} class="min-w-0">
            <h2 class="truncate text-sm font-medium">{@selected_project.name}</h2>
            <p class="truncate text-xs text-base-content/50">{@selected_project.path}</p>
          </div>
          <div :if={is_nil(@selected_project)} class="min-w-0">
            <h2 class="truncate text-sm font-medium">No project selected</h2>
            <p class="truncate text-xs text-base-content/50">
              Configure LIVE_PI_PROJECTS_DIR and add folders.
            </p>
          </div>
        </div>
        <div class="flex shrink-0 items-center gap-2 text-xs text-base-content/50">
          <span :if={@selected_project}>{@selected_project.branch}</span>
          <span
            :if={
              status =
                session_status(
                  @session_ready,
                  @session_alive,
                  @session_streaming,
                  @session_compacting
                )
            }
            class={status_badge_class(status)}
          >
            {status_label(status)}
          </span>
        </div>
      </div>
      <div :if={@session_error} class="border-t border-base-300 px-4 py-2 text-xs text-error sm:px-6">
        {@session_error}
      </div>
    </div>
    """
  end

  attr :items, :list, required: true
  attr :expanded, :map, required: true
  attr :project_id, :string, default: nil

  def transcript(assigns) do
    ~H"""
    <div
      id="workspace-transcript"
      phx-hook="StickyTranscript"
      data-project-id={@project_id}
      data-item-count={Enum.count(@items, &(&1.kind != :system_notice))}
      class="pi-scroll min-h-0 flex-1 space-y-4 overflow-y-auto px-4 py-4 sm:px-6 sm:py-5"
    >
      <.transcript_item :for={item <- @items} item={item} expanded={@expanded} />
    </div>
    """
  end

  attr :item, :map, required: true
  attr :expanded, :map, required: true

  def transcript_item(%{item: %{kind: :user_message}} = assigns) do
    ~H"""
    <article class="ml-auto max-w-3xl rounded-xl border border-base-300 bg-neutral px-4 py-3">
      <div class="mb-2 flex items-center gap-2 text-[11px] uppercase tracking-[0.18em] text-base-content/45">
        <span>{@item.author}</span>
        <span>{@item.at}</span>
      </div>
      <p class="text-[15px] leading-7 text-base-content/88 sm:text-sm">{@item.body}</p>
    </article>
    """
  end

  def transcript_item(%{item: %{kind: :assistant_turn}} = assigns) do
    ~H"""
    <article class="max-w-3xl rounded-xl border border-base-300 bg-base-200 px-4 py-3">
      <div class="mb-3 flex items-center gap-2 text-[11px] uppercase tracking-[0.18em] text-base-content/45">
        <span>{@item.author}</span>
        <span>{@item.at}</span>
      </div>

      <div class="space-y-3">
        <.assistant_block :for={block <- @item.blocks} block={block} expanded={@expanded} />
      </div>
    </article>
    """
  end

  def transcript_item(%{item: %{kind: :tool_run}} = assigns) do
    ~H"""
    <article class="max-w-3xl rounded-xl border border-base-300/90 bg-base-100 px-4 py-3">
      <div class="flex items-center justify-between gap-3 text-[11px] uppercase tracking-[0.18em] text-base-content/45">
        <div class="flex items-center gap-2">
          <span>tool</span>
          <span class="rounded-md border border-base-300 bg-base-200 px-2 py-1 normal-case tracking-normal text-base-content/70">
            {@item.tool_name}
          </span>
        </div>
        <span class={[
          "rounded-md px-2 py-1 normal-case tracking-normal",
          tool_status_class(@item.status)
        ]}>
          {tool_status_label(@item.status)}
        </span>
      </div>

      <p :if={Map.get(@item, :summary)} class="mt-3 text-sm leading-6 text-base-content/75">
        {@item.summary}
      </p>

      <div :if={Map.get(@item, :output)} class="mt-3">
        <button
          type="button"
          phx-click="toggle_expand"
          phx-value-key={@item.id}
          class="flex w-full items-center justify-between rounded-lg border border-base-300 bg-base-200/40 px-3 py-2 text-left text-xs uppercase tracking-[0.18em] text-base-content/50 transition hover:bg-base-200/70"
        >
          <span>output</span>
          <span>{if Map.get(@expanded, @item.id, false), do: "hide", else: "show"}</span>
        </button>

        <pre
          :if={Map.get(@expanded, @item.id, false)}
          class="pi-terminal mt-2 overflow-x-auto rounded-lg border border-base-300 bg-base-200/60 p-3 text-xs leading-6 text-base-content/78"
        >{@item.output}</pre>
      </div>

      <div
        :if={meta = Map.get(@item, :meta)}
        class="mt-3 flex flex-wrap gap-2 text-xs text-base-content/50"
      >
        <span :for={{label, value} <- meta} class="rounded-md border border-base-300 px-2 py-1">
          {label}: {value}
        </span>
      </div>
    </article>
    """
  end

  def transcript_item(%{item: %{kind: :ui_request}} = assigns) do
    ~H"""
    <article class="max-w-3xl rounded-xl border border-info/25 bg-info/8 px-4 py-3">
      <div class="flex items-center gap-2 text-[11px] uppercase tracking-[0.18em] text-info/80">
        <span>ui request</span>
        <span class="rounded-md border border-info/20 px-2 py-1 normal-case tracking-normal text-info/70">
          {@item.method}
        </span>
      </div>

      <h3 class="mt-3 text-sm font-medium text-base-content">{@item.title}</h3>
      <p :if={Map.get(@item, :message)} class="mt-2 text-sm leading-6 text-base-content/72">
        {@item.message}
      </p>

      <div :if={options = Map.get(@item, :options)} class="mt-3 flex flex-wrap gap-2">
        <span
          :for={option <- options}
          class="rounded-md border border-info/20 bg-base-100/60 px-2.5 py-1.5 text-xs text-base-content/70"
        >
          {option}
        </span>
      </div>
    </article>
    """
  end

  def transcript_item(%{item: %{kind: :system_notice}} = assigns) do
    ~H"""
    <span class="hidden"></span>
    """
  end

  attr :block, :map, required: true
  attr :expanded, :map, required: true

  defp assistant_block(%{block: %{kind: :text}} = assigns) do
    assigns = assign(assigns, :markdown_html, render_assistant_markdown(assigns.block.text))

    ~H"""
    <div class="pi-markdown text-[15px] leading-7 text-base-content/88 sm:text-sm">
      {raw(@markdown_html)}
    </div>
    """
  end

  defp assistant_block(%{block: %{kind: :thinking}} = assigns) do
    ~H"""
    <div class="rounded-lg border border-base-300 bg-base-100/45">
      <button
        type="button"
        phx-click="toggle_expand"
        phx-value-key={@block.id}
        class="flex w-full items-center justify-between px-3 py-2 text-left text-xs uppercase tracking-[0.18em] text-base-content/50"
      >
        <span>thinking</span>
        <span>{if Map.get(@expanded, @block.id, false), do: "hide", else: "show"}</span>
      </button>
      <div
        :if={Map.get(@expanded, @block.id, false)}
        class="border-t border-base-300 px-3 py-3 text-sm leading-6 text-base-content/65"
      >
        {@block.text}
      </div>
    </div>
    """
  end

  defp assistant_block(%{block: %{kind: :tool_call}} = assigns) do
    ~H"""
    <div class="rounded-lg border border-base-300 bg-base-100/45">
      <button
        type="button"
        phx-click="toggle_expand"
        phx-value-key={@block.id}
        class="flex w-full items-center justify-between px-3 py-2 text-left text-xs uppercase tracking-[0.18em] text-base-content/50"
      >
        <span>tool call · {@block.name}</span>
        <span>{if Map.get(@expanded, @block.id, false), do: "hide", else: "show"}</span>
      </button>
      <div :if={Map.get(@expanded, @block.id, false)} class="border-t border-base-300 px-3 py-3">
        <pre class="pi-terminal overflow-x-auto text-xs leading-6 text-base-content/72">{@block.arguments}</pre>
      </div>
    </div>
    """
  end

  attr :message, :string, required: true
  attr :disabled, :boolean, required: true
  attr :busy, :boolean, required: true

  def composer(assigns) do
    ~H"""
    <form
      id="chat-composer"
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
          placeholder={composer_placeholder(@disabled, @busy)}
          disabled={@disabled or @busy}
          class="w-full resize-none bg-transparent text-base leading-7 outline-none placeholder:text-base-content/35 disabled:cursor-not-allowed disabled:opacity-60"
        >{@message}</textarea>
        <div class="mt-3 flex justify-end border-t border-base-300 pt-3">
          <button
            type="submit"
            disabled={@disabled or @busy}
            class="min-h-11 rounded-lg border border-base-300 bg-base-100 px-4 py-2 text-sm transition hover:bg-base-300 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {composer_button_label(@busy)}
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

  defp status_class("active"), do: "bg-success"
  defp status_class("idle"), do: "bg-base-content/25"
  defp status_class("syncing"), do: "bg-info"
  defp status_class("queued"), do: "bg-warning"
  defp status_class(_), do: "bg-base-content/25"

  defp tool_status_class(:running), do: "border border-warning/20 bg-warning/12 text-warning"
  defp tool_status_class(:ok), do: "border border-success/20 bg-success/12 text-success"
  defp tool_status_class(:error), do: "border border-error/20 bg-error/12 text-error"
  defp tool_status_class(_), do: "border border-base-300 bg-base-200 text-base-content/65"

  defp tool_status_label(:running), do: "running"
  defp tool_status_label(:ok), do: "ok"
  defp tool_status_label(:error), do: "error"
  defp tool_status_label(value), do: to_string(value)

  defp session_status(false, false, _streaming, _compacting), do: :starting
  defp session_status(_ready, false, _streaming, _compacting), do: :offline
  defp session_status(_ready, true, _streaming, true), do: :compacting
  defp session_status(_ready, true, true, _compacting), do: :streaming
  defp session_status(true, true, false, false), do: :ready
  defp session_status(false, true, false, false), do: :starting

  defp status_badge_class(:ready),
    do: "rounded-md border border-success/20 bg-success/12 px-2 py-1 text-success"

  defp status_badge_class(:streaming),
    do: "rounded-md border border-warning/20 bg-warning/12 px-2 py-1 text-warning"

  defp status_badge_class(:compacting),
    do: "rounded-md border border-info/20 bg-info/12 px-2 py-1 text-info"

  defp status_badge_class(:offline),
    do: "rounded-md border border-error/20 bg-error/12 px-2 py-1 text-error"

  defp status_badge_class(:starting),
    do: "rounded-md border border-base-300 bg-base-200 px-2 py-1 text-base-content/65"

  defp status_label(:ready), do: "ready"
  defp status_label(:streaming), do: "streaming"
  defp status_label(:compacting), do: "compacting"
  defp status_label(:offline), do: "offline"
  defp status_label(:starting), do: "starting"

  defp composer_placeholder(true, _busy), do: "session unavailable"
  defp composer_placeholder(false, true), do: "pi is responding…"
  defp composer_placeholder(false, false), do: "message"

  defp composer_button_label(true), do: "running"
  defp composer_button_label(false), do: "send"

  defp render_assistant_markdown(text) do
    text
    |> Earmark.as_html!(%Earmark.Options{code_class_prefix: "language-", breaks: true})
    |> HtmlSanitizeEx.basic_html()
  rescue
    _ ->
      text
      |> HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()
      |> String.replace("\n", "<br>")
  end
end
