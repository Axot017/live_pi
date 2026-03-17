defmodule LivePiWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use LivePiWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen bg-[radial-gradient(circle_at_top,_oklch(0.97_0.03_250),_transparent_32%),linear-gradient(180deg,_oklch(0.99_0_0),_oklch(0.96_0.01_250))] text-base-content dark:bg-[radial-gradient(circle_at_top,_oklch(0.28_0.04_250),_transparent_28%),linear-gradient(180deg,_oklch(0.19_0.02_250),_oklch(0.15_0.02_250))]">
      <header class="border-b border-base-300/70 bg-base-100/75 backdrop-blur-xl">
        <div class="mx-auto flex max-w-[92rem] items-center justify-between gap-4 px-4 py-4 sm:px-6 lg:px-8">
          <div class="flex items-center gap-3">
            <div class="flex size-11 items-center justify-center rounded-2xl bg-primary/15 text-primary shadow-sm shadow-primary/10">
              <.icon name="hero-command-line" class="size-5" />
            </div>
            <div>
              <p class="text-xs font-semibold uppercase tracking-[0.22em] text-primary/80">Live Pi</p>
              <h1 class="text-lg font-semibold tracking-tight">Pi agent workspace</h1>
            </div>
          </div>
          <div class="flex items-center gap-3">
            <div class="hidden rounded-2xl border border-base-300/70 bg-base-100/80 px-3 py-2 text-xs text-base-content/60 sm:block">
              Server-side projects · LiveView UI · RPC streaming
            </div>
            <.theme_toggle />
          </div>
        </div>
      </header>

      <main class="mx-auto max-w-[92rem] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  def theme_toggle(assigns) do
    ~H"""
    <div class="relative flex flex-row items-center rounded-full border border-base-300/80 bg-base-200/80 p-1">
      <div class="absolute left-1 h-9 w-9 rounded-full bg-base-100 shadow-sm transition-[left] [[data-theme=light]_&]:left-10 [[data-theme=dark]_&]:left-[4.75rem]" />

      <button
        class="relative z-10 flex size-9 cursor-pointer items-center justify-center rounded-full text-base-content/70 transition hover:text-base-content"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        type="button"
      >
        <.icon name="hero-computer-desktop" class="size-4" />
      </button>

      <button
        class="relative z-10 flex size-9 cursor-pointer items-center justify-center rounded-full text-base-content/70 transition hover:text-base-content"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        type="button"
      >
        <.icon name="hero-sun" class="size-4" />
      </button>

      <button
        class="relative z-10 flex size-9 cursor-pointer items-center justify-center rounded-full text-base-content/70 transition hover:text-base-content"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        type="button"
      >
        <.icon name="hero-moon" class="size-4" />
      </button>
    </div>
    """
  end
end
