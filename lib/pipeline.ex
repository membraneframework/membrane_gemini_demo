defmodule Gemini.TermiteMicDemo.Pipeline do
  @moduledoc """
  Thin wrapper around `Membrane.Pipeline` for the demo.

  The pipeline does not know anything about the audio I/O: the caller
  builds the full `Membrane.ChildrenSpec` (using a `spec_fn` that captures
  the `App` wrapper) and passes it in. The pipeline merely runs it and notifies
  the TUI process once it transitions to `:playing`, so the TUI can wait
  for playback before starting to feed user input.

  The pipeline still relays a few control messages to named children
  (`:gemini`, `:mute_filter`, `:text_source`), which the spec must
  contain.
  """

  use Membrane.Pipeline

  @spec submit_text(pipeline :: pid(), String.t()) :: {:text, String.t()}
  def submit_text(pipeline, text), do: send(pipeline, {:text, text})

  @spec reset_session(pipeline :: pid()) :: :reset_session
  def reset_session(pipeline), do: send(pipeline, :reset_session)

  @spec toggle_mute(pipeline :: pid()) :: :toggle_mute
  def toggle_mute(pipeline), do: send(pipeline, :toggle_mute)

  @impl true
  def handle_init(_ctx, opts) do
    app = Keyword.fetch!(opts, :app)
    spec_fn = Keyword.fetch!(opts, :spec_fn)
    {[spec: spec_fn.(app)], %{app: app}}
  end

  @impl true
  def handle_playing(_ctx, state) do
    # Bootstrap handshake: a raw send the App's handle_continue/2 blocks on
    # before creating the terminal (see App's moduledoc).
    send(state.app.pid, {:pipeline_playing, self()})
    {[], state}
  end

  @impl true
  def handle_info({:text, _text} = msg, _ctx, state),
    do: {[notify_child: {:text_source, msg}], state}

  @impl true
  def handle_info(:reset_session, _ctx, state),
    do: {[notify_child: {:gemini, :reset_session}], state}

  @impl true
  def handle_info(:toggle_mute, _ctx, state),
    do: {[notify_child: {:mute_filter, :toggle_mute}], state}
end
