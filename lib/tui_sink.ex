defmodule Membrane.LLM.Demo.TuiSink do
  @moduledoc """
  Terminal-UI sink for the demo.

  Two responsibilities, both feeding the `App` TUI given in `app`:

    * **Waveform** — on every buffer it samples `sample_count` evenly-spaced
      values from the raw 16-bit audio and hands them to `on_samples`, which the
      caller uses to push them to the TUI (`App.mic_samples/2` / `App.gemini_samples/2`).
    * **Events** — its `handle_event/4` translates `Membrane.Gemini.Events.*`
      into `App` calls (transcripts, thinking, response start/end). This folds in
      what used to be a separate `Membrane.Debug.Filter` sitting after the Gemini
      bin. Only the sink on the Gemini branch ever receives those events; on the
      mic branch the clause simply falls through.
  """

  use Membrane.Sink

  alias Membrane.Gemini.Events
  alias Membrane.LLM.Demo.App
  alias Membrane.RawAudio

  @sample_count 5

  def_input_pad :input, accepted_format: RawAudio

  def_options origin: [spec: :client | :server],
              app: [spec: App.t()]

  @impl true
  def handle_init(_ctx, opts),
    do: {[], %{origin: opts.origin, app: opts.app}}

  @impl true
  def handle_buffer(:input, buffer, _ctx, %{app: app, origin: origin} = state) do
    send_samples =
      case origin do
        :client -> &App.mic_samples(app, &1)
        :server -> &App.gemini_samples(app, &1)
      end

    buffer.payload
    |> extract_samples(@sample_count)
    |> then(send_samples)

    {[], state}
  end

  @impl true
  def handle_event(:input, event, _ctx, %{origin: :server} = state) do
    case event do
      %Events.Transcript{text: text, audio_origin: :client} ->
        App.input_transcript(state.app, text)

      %Events.Transcript{text: text, audio_origin: :server} ->
        App.output_transcript(state.app, text)

      %Events.Thinking{text: text} ->
        App.thinking(state.app, text)

      %Events.ResponseStart{} ->
        App.clear_transcripts(state.app)
        App.event(state.app, "Response started")

      %Events.ResponseEnd{interrupted?: interrupted?} ->
        App.event(
          state.app,
          if(interrupted?, do: "Response interrupted", else: "Response complete")
        )

      _event ->
        :ok
    end

    {[], state}
  end

  @impl true
  def handle_event(:input, _event, _ctx, %{origin: :client} = state) do
    {[], state}
  end

  @spec extract_samples(binary(), pos_integer()) :: [float()]
  defp extract_samples(binary, count) when byte_size(binary) >= 2 do
    total = div(byte_size(binary), 2)
    block_size = max(div(total, count), 1)
    num_blocks = min(count, div(total, block_size))

    if num_blocks == 0 do
      []
    else
      for i <- 0..(num_blocks - 1) do
        start = i * block_size

        <<_head::binary-size(start * 2), sample::signed-little-16, _tail::binary>> = binary
        sample / 32_768.0
      end
    end
  end

  defp extract_samples(_binary, _count), do: []
end
