defmodule Gemini.TermiteMicDemo.Pipeline do
  @moduledoc """
  Thin wrapper around `Membrane.Pipeline` for the demo.

  The pipeline does not know anything about the audio I/O: the caller
  builds the full `Membrane.ChildrenSpec` (using a `spec_fn` that captures
  the TUI pid) and passes it in. The pipeline merely runs it and notifies
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

  @doc """
  Translate a Gemini bin event into a message for the TUI process.

  Plugged in as the `:handle_event` callback of a `Membrane.Debug.Filter`
  sitting downstream of the Gemini bin. Always returns the event so the
  filter can forward it.
  """
  @spec handle_gemini_event(Membrane.Event.t(), pid()) :: Membrane.Event.t()
  def handle_gemini_event(event, tui_pid) do
    case event do
      %Membrane.Gemini.Events.Transcript{text: text, audio_origin: :client} ->
        send(tui_pid, {:input_transcript, text})

      %Membrane.Gemini.Events.Transcript{text: text, audio_origin: :server} ->
        send(tui_pid, {:output_transcript, text})

      %Membrane.Gemini.Events.Thinking{text: text} ->
        send(tui_pid, {:thinking, text})

      %Membrane.Gemini.Events.ResponseStart{} ->
        send(tui_pid, :clear_transcripts)
        send(tui_pid, {:event, "Response started"})

      %Membrane.Gemini.Events.ResponseEnd{interrupted?: interrupted?} ->
        send(tui_pid, {:event, if(interrupted?, do: "Response interrupted", else: "Response complete")})

      _event ->
        :ok
    end

    event
  end

  @impl true
  def handle_init(_ctx, opts) do
    tui_pid = Keyword.fetch!(opts, :tui_pid)
    spec_fn = Keyword.fetch!(opts, :spec_fn)
    {[spec: spec_fn.(tui_pid)], %{tui_pid: tui_pid}}
  end

  @impl true
  def handle_playing(_ctx, state) do
    send(state.tui_pid, {:pipeline_playing, self()})
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
