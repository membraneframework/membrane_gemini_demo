defmodule Gemini.TermiteMicDemo.Pipeline do
  @moduledoc false

  use Membrane.Pipeline

  alias Gemini.TermiteMicDemo.State

  @impl true
  def handle_init(_ctx, _opts) do
    spec = [
      child(:mic, %Membrane.PortAudio.Source{
        sample_format: :s16le,
        channels: 1,
        sample_rate: 16_000
      })
      |> child(:mute_filter, Gemini.TermiteMicDemo.MuteFilter)
      |> child(:mic_visualizer, %Gemini.TermiteMicDemo.VisualizerBin{
        on_samples: &State.add_mic_samples/1
      })
      # |> child(:fake, Membrane.Fake.Sink)
      |> via_in(:audio_input)
      |> child(:gemini, %Membrane.Gemini.Bin{})
      |> child(:event_handler, %Membrane.Debug.Filter{handle_event: &handle_gemini_event/1})
      |> child(:gemini_visualizer, %Gemini.TermiteMicDemo.VisualizerBin{
        on_samples: &State.add_gemini_samples/1
      })
      |> child(:gemini_speaker, %Membrane.PortAudio.Sink{
        ringbuffer_size: 32_768,
        portaudio_buffer_size: 512
      }),
      child(:text_source, Gemini.TermiteMicDemo.TextSource)
      |> via_in(:text_input)
      |> get_child(:gemini)
    ]

    {[spec: spec], %{}}
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

  defp handle_gemini_event(event) do
    case event do
      %Membrane.Gemini.Events.Transcript{text: text, audio_origin: :client} ->
        State.set_input_transcript(text)

      %Membrane.Gemini.Events.Transcript{text: text, audio_origin: :server} ->
        State.set_output_transcript(text)

      %Membrane.Gemini.Events.Thinking{text: text} ->
        State.set_thinking(text)

      %Membrane.Gemini.Events.ResponseStart{} ->
        State.clear_transcripts()
        State.set_event("Response started")

      %Membrane.Gemini.Events.ResponseEnd{interrupted?: interrupted?} ->
        State.set_event(if interrupted?, do: "Response interrupted", else: "Response complete")

      _event ->
        :ok
    end

    event
  end
end
