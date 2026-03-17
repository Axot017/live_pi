defmodule LivePiWeb.WorkspaceComponents do
  @moduledoc """
  UI components for the pi workspace.
  """

  use LivePiWeb, :html

  attr :project, :map, required: true
  attr :selected, :boolean, default: false

  def project_card(assigns) do
    ~H"""
    <div class={[
      "group flex w-full items-start justify-between rounded-2xl border px-4 py-3 text-left transition duration-200",
      @selected && "border-primary/60 bg-primary/10 shadow-sm",
      !@selected && "border-base-300/80 bg-base-100/70 hover:border-primary/40 hover:bg-base-200/70"
    ]}>
      <div class="min-w-0 space-y-1">
        <p class="truncate font-medium text-base-content">{@project.name}</p>
        <p class="truncate text-xs text-base-content/60">{@project.path}</p>
      </div>
      <span class="ml-4 rounded-full bg-base-200 px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-[0.18em] text-base-content/60">
        {@project.source || :existing}
      </span>
    </div>
    """
  end

  attr :message, :map, required: true

  def chat_message(assigns) do
    role = Map.get(assigns.message, "role") || Map.get(assigns.message, :role)
    content = message_text(assigns.message)
    assigns = assign(assigns, role: role, content: content)

    ~H"""
    <article class={[
      "max-w-3xl rounded-3xl border px-4 py-3 shadow-sm transition duration-200 sm:px-5",
      @role == "user" && "ml-auto border-primary/30 bg-primary/10 text-base-content",
      @role == "assistant" && "mr-auto border-base-300 bg-base-100"
    ]}>
      <div class="mb-2 flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.18em] text-base-content/50">
        <span class={[
          "inline-flex size-6 items-center justify-center rounded-full",
          @role == "user" && "bg-primary/20 text-primary",
          @role == "assistant" && "bg-secondary/15 text-secondary"
        ]}>
          <.icon name={if @role == "user", do: "hero-user", else: "hero-cpu-chip"} class="size-3.5" />
        </span>
        {if @role == "user", do: "You", else: "Pi"}
      </div>
      <div class="whitespace-pre-wrap text-sm leading-6 text-base-content/85">{@content}</div>
    </article>
    """
  end

  attr :text, :string, required: true

  def streaming_message(assigns) do
    ~H"""
    <article class="mr-auto max-w-3xl rounded-3xl border border-secondary/20 bg-secondary/5 px-4 py-3 shadow-sm sm:px-5">
      <div class="mb-2 flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.18em] text-secondary/80">
        <span class="inline-flex size-6 items-center justify-center rounded-full bg-secondary/15 text-secondary">
          <.icon name="hero-cpu-chip" class="size-3.5" />
        </span>
        Pi is replying
        <span class="inline-flex items-center gap-1 text-[0.65rem] text-secondary/70">
          <span class="size-1.5 rounded-full bg-secondary motion-safe:animate-pulse"></span> streaming
        </span>
      </div>
      <div class="whitespace-pre-wrap text-sm leading-6 text-base-content/85">{@text}</div>
    </article>
    """
  end

  defp message_text(message) do
    content = Map.get(message, "content") || Map.get(message, :content)

    cond do
      is_binary(content) ->
        content

      is_list(content) ->
        content
        |> Enum.map(fn item ->
          case item do
            %{"type" => "text", "text" => text} -> text
            %{type: "text", text: text} -> text
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n")

      true ->
        ""
    end
  end
end
