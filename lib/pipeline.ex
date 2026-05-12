defmodule Gemini.TermiteMicDemo.Pipeline do
  @moduledoc false

  use Membrane.Pipeline

  alias Membrane.RawAudio

  @gemini_input_format %RawAudio{sample_format: :s16le, channels: 1, sample_rate: 16_000}
  @opus_sample_rate 48_000
  @opus_format %RawAudio{sample_format: :s16le, channels: 1, sample_rate: @opus_sample_rate}

  @spec reset_session(pipeline :: pid()) :: :reset_session
  def reset_session(pipeline), do:
    send(pipeline, :reset_session)

  @spec submit_text(pipeline :: pid(), String.t()) :: {:text, String.t()}
  def submit_text(pipeline, text), do:
    send(pipeline, {:text, text})

  @impl true
  def handle_init(_ctx, opts) do
    tui_pid = Keyword.fetch!(opts, :tui_pid)
    audio_io = Keyword.get(opts, :audio_io, :portaudio)

    audio_input_head = audio_input_head(audio_io, opts)
    audio_output_tail = audio_output_tail(audio_io, opts)

    spec = [
      audio_input_head
      |> child(:mute_filter, Gemini.TermiteMicDemo.MuteFilter)
      |> child(:mic_visualizer, %Gemini.TermiteMicDemo.VisualizerBin{
        on_samples: fn samples -> send(tui_pid, {:mic_samples, samples}) end
      })
      |> via_in(:audio_input)
      |> child(:gemini, Membrane.Gemini.Bin)
      |> child(:event_handler, %Membrane.Debug.Filter{
        handle_event: fn event -> handle_gemini_event(event, tui_pid) end
      })
      |> child(:gemini_visualizer, %Gemini.TermiteMicDemo.VisualizerBin{
        on_samples: fn samples -> send(tui_pid, {:gemini_samples, samples}) end
      })
      |> then(audio_output_tail),
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

  defp audio_input_head(:portaudio, _opts) do
    child(:mic, %Membrane.PortAudio.Source{
      sample_format: :s16le,
      channels: 1,
      sample_rate: 16_000
    })
  end

  defp audio_input_head(:webrtc, opts) do
    signaling = Keyword.fetch!(opts, :webrtc_source_signaling)

    child(:webrtc_source, %Membrane.WebRTC.Source{signaling: signaling})
    |> via_out(Pad.ref(:output, :main_audio), options: [kind: :audio])
    |> child(:opus_decoder, %Membrane.Opus.Decoder{sample_rate: @opus_sample_rate})
    |> child(:input_resampler, %Membrane.FFmpeg.SWResample.Converter{
      output_stream_format: @gemini_input_format
    })
  end

  defp audio_output_tail(:portaudio, _opts) do
    fn builder ->
      builder
      |> child(:gemini_speaker, %Membrane.PortAudio.Sink{
        ringbuffer_size: 32_768,
        portaudio_buffer_size: 512
      })
    end
  end

  defp audio_output_tail(:webrtc, opts) do
    signaling = Keyword.fetch!(opts, :webrtc_sink_signaling)

    fn builder ->
      builder
      |> child(:output_resampler, %Membrane.FFmpeg.SWResample.Converter{
        output_stream_format: @opus_format
      })
      |> child(:opus_encoder, %Membrane.Opus.Encoder{application: :voip})
      |> via_in(Pad.ref(:input, :main_audio), options: [kind: :audio])
      |> child(:webrtc_sink, %Membrane.WebRTC.Sink{
        signaling: signaling,
        tracks: [:audio]
      })
    end
  end

  defp handle_gemini_event(event, tui_pid) do
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
end
