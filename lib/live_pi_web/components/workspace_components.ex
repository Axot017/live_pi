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
    display_items = prepare_display_items(assigns.items)
    visible_count = Enum.count(display_items, &(&1.kind != :system_notice))

    assigns =
      assigns
      |> assign(:display_items, display_items)
      |> assign(:visible_count, visible_count)

    ~H"""
    <div
      id="workspace-transcript"
      phx-hook="StickyTranscript"
      data-project-id={@project_id}
      data-item-count={@visible_count}
      class="pi-scroll min-h-0 flex-1 space-y-4 overflow-y-auto px-4 py-4 sm:px-6 sm:py-5"
    >
      <.transcript_item :for={item <- @display_items} item={item} expanded={@expanded} />
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

      <div class="space-y-2.5">
        <.assistant_block :for={block <- @item.blocks} block={block} expanded={@expanded} />
      </div>
    </article>
    """
  end

  def transcript_item(%{item: %{kind: :tool_run}} = assigns) do
    assigns = assign(assigns, :output_preview, preview_text(assigns.item.output, 220))

    ~H"""
    <article class="max-w-3xl px-1 text-sm text-base-content/52">
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0 flex-1 space-y-1">
          <div class="flex flex-wrap items-center gap-x-2 gap-y-1 text-[11px] uppercase tracking-[0.18em] text-base-content/38">
            <span>tool</span>
            <span class="normal-case tracking-normal text-base-content/58">{@item.tool_name}</span>
            <span class={[
              "rounded-md px-1.5 py-0.5 normal-case tracking-normal",
              tool_status_class(@item.status)
            ]}>
              {tool_status_label(@item.status)}
            </span>
          </div>

          <p :if={Map.get(@item, :summary)} class="pi-raw-line text-xs leading-6 text-base-content/48">
            {@item.summary}
          </p>

          <div :if={Map.get(@item, :output)} class="text-xs leading-6 text-base-content/44">
            <div :if={!Map.get(@expanded, @item.id, false)} class="pi-terminal pi-raw-line">
              {@output_preview}
            </div>
            <pre :if={Map.get(@expanded, @item.id, false)} class="pi-terminal pi-raw-block">{@item.output}</pre>
          </div>

          <div
            :if={meta = Map.get(@item, :meta)}
            class="flex flex-wrap gap-x-3 gap-y-1 text-[11px] text-base-content/36"
          >
            <span :for={{label, value} <- meta}>
              {label}: {value}
            </span>
          </div>
        </div>

        <button
          :if={expandable_text?(@item.output, 220)}
          type="button"
          phx-click="toggle_expand"
          phx-value-key={@item.id}
          class="shrink-0 text-[11px] uppercase tracking-[0.18em] text-base-content/38 transition hover:text-base-content/60"
        >
          {if Map.get(@expanded, @item.id, false), do: "less", else: "more"}
        </button>
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
    assigns = assign(assigns, :preview, preview_text(assigns.block.text, 180))

    ~H"""
    <div class="flex items-start justify-between gap-3 px-1 text-xs leading-6 text-base-content/42">
      <div class="min-w-0 flex-1">
        <div class="mb-0.5 text-[11px] uppercase tracking-[0.18em] text-base-content/34">
          thinking
        </div>
        <div :if={!Map.get(@expanded, @block.id, false)} class="pi-raw-line pi-terminal">
          {@preview}
        </div>
        <div :if={Map.get(@expanded, @block.id, false)} class="pi-raw-block pi-terminal">
          {@block.text}
        </div>
      </div>
      <button
        :if={expandable_text?(@block.text, 180)}
        type="button"
        phx-click="toggle_expand"
        phx-value-key={@block.id}
        class="shrink-0 text-[11px] uppercase tracking-[0.18em] text-base-content/36 transition hover:text-base-content/58"
      >
        {if Map.get(@expanded, @block.id, false), do: "less", else: "more"}
      </button>
    </div>
    """
  end

  defp assistant_block(%{block: %{kind: :tool_call}} = assigns) do
    assigns =
      assigns
      |> assign(:preview, preview_text(assigns.block.arguments, 180))
      |> assign(:tool_run, Map.get(assigns.block, :tool_run))
      |> assign(:tool_meta, get_in(assigns.block, [:tool_run, :meta]))
      |> assign(:output_preview, preview_text(get_in(assigns.block, [:tool_run, :output]), 220))

    ~H"""
    <div class="flex items-start justify-between gap-3 px-1 text-xs leading-6 text-base-content/42">
      <div class="min-w-0 flex-1 space-y-1">
        <div class="flex flex-wrap items-center gap-x-2 gap-y-1 text-[11px] uppercase tracking-[0.18em] text-base-content/34">
          <span>tool call</span>
          <span class="normal-case tracking-normal text-base-content/52">{@block.name}</span>
          <span
            :if={@tool_run}
            class={[
              "rounded-md px-1.5 py-0.5 normal-case tracking-normal",
              tool_status_class(@tool_run.status)
            ]}
          >
            {tool_status_label(@tool_run.status)}
          </span>
        </div>

        <div :if={!Map.get(@expanded, @block.id, false)} class="pi-raw-line pi-terminal">
          {@preview}
        </div>
        <pre :if={Map.get(@expanded, @block.id, false)} class="pi-raw-block pi-terminal">{@block.arguments}</pre>

        <div :if={@tool_run && @tool_run.output} class="text-[11px] leading-6 text-base-content/40">
          <div :if={!Map.get(@expanded, @tool_run.id, false)} class="pi-terminal pi-raw-line">
            {@output_preview}
          </div>
          <pre :if={Map.get(@expanded, @tool_run.id, false)} class="pi-raw-block pi-terminal">{@tool_run.output}</pre>
        </div>

        <div
          :if={@tool_run && @tool_meta}
          class="flex flex-wrap gap-x-3 gap-y-1 text-[11px] text-base-content/34"
        >
          <span :for={{label, value} <- @tool_meta}>{label}: {value}</span>
        </div>
      </div>

      <div class="flex shrink-0 items-center gap-3">
        <button
          :if={expandable_text?(@block.arguments, 180)}
          type="button"
          phx-click="toggle_expand"
          phx-value-key={@block.id}
          class="text-[11px] uppercase tracking-[0.18em] text-base-content/36 transition hover:text-base-content/58"
        >
          {if Map.get(@expanded, @block.id, false), do: "less", else: "more"}
        </button>
        <button
          :if={@tool_run && expandable_text?(@tool_run.output, 220)}
          type="button"
          phx-click="toggle_expand"
          phx-value-key={@tool_run.id}
          class="text-[11px] uppercase tracking-[0.18em] text-base-content/36 transition hover:text-base-content/58"
        >
          {if Map.get(@expanded, @tool_run.id, false), do: "hide output", else: "show output"}
        </button>
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

  defp prepare_display_items(items) do
    tool_runs =
      items
      |> Enum.filter(&(&1.kind == :tool_run && Map.get(&1, :tool_call_id)))
      |> Map.new(fn item -> {item.tool_call_id, item} end)

    paired_tool_run_ids =
      items
      |> Enum.flat_map(fn item ->
        if item.kind == :assistant_turn do
          item.blocks
          |> Enum.map(&Map.get(&1, :tool_call_id))
          |> Enum.reject(&is_nil/1)
        else
          []
        end
      end)
      |> MapSet.new()

    items
    |> Enum.map(fn item ->
      if item.kind == :assistant_turn do
        blocks =
          Enum.map(item.blocks, fn block ->
            if block.kind == :tool_call do
              Map.put(block, :tool_run, tool_runs[Map.get(block, :tool_call_id)])
            else
              block
            end
          end)

        %{item | blocks: blocks}
      else
        item
      end
    end)
    |> Enum.reject(fn item ->
      item.kind == :tool_run && Map.get(item, :tool_call_id) &&
        MapSet.member?(paired_tool_run_ids, item.tool_call_id)
    end)
  end

  defp preview_text(nil, _limit), do: ""

  defp preview_text(text, limit) do
    text = String.trim(text)

    if String.length(text) > limit do
      String.slice(text, 0, limit) <> "…"
    else
      text
    end
  end

  defp expandable_text?(nil, _limit), do: false
  defp expandable_text?(text, limit), do: String.length(String.trim(text)) > limit
end
