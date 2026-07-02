defmodule Membrane.LLM.Demo.TuiSink do
  @moduledoc """
  TUI sink for the demo, facilitating communication between
  the Membrane pipeline and the App module in two ways:

    * **Waveform** — on every buffer, samples `@sample_count` evenly-spaced
      values from the raw 16-bit audio and forwards them to the TUI.
    * **Events** — translates `Membrane.Gemini.Events.*`
      into `App` calls (transcripts, thinking, response start/end).
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

        <<_head::binary-size(^start * 2), sample::signed-little-16, _tail::binary>> = binary
        sample / 32_768.0
      end
    end
  end

  defp extract_samples(_binary, _count), do: []
end
