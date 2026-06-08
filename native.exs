Mix.install([{:membrane_gemini_demo, path: __DIR__}])

case System.fetch_env("GEMINI_API_KEY") do
  {:ok, api_key} ->
    Application.put_env(:gemini_ex, :api_key, api_key)

  :error ->
    raise """
    A key for the Gemini Live API is required to run this example.
    Please set the GEMINI_API_KEY environment variable, e.g.

        GEMINI_API_KEY="your key" elixir native.exs
    """
end

defmodule Native.Pipeline do
  use Membrane.Pipeline

  import Membrane.ChildrenSpec
  require Membrane.Pad

  alias Membrane.LLM.Demo
  alias Membrane.{Pad, Time}

  @chunk_ms 40

  @spec submit_text(pipeline :: pid(), String.t()) :: {:text, String.t()}
  def submit_text(pipeline, text), do: send(pipeline, {:text, text})

  @spec reset_session(pipeline :: pid()) :: :reset_session
  def reset_session(pipeline), do: send(pipeline, :reset_session)

  @spec toggle_mute(pipeline :: pid()) :: :toggle_mute
  def toggle_mute(pipeline), do: send(pipeline, :toggle_mute)

  @impl true
  def handle_init(_ctx, opts) do
    %Demo.App{} = app = Keyword.fetch!(opts, :app)

    spec = [
      child(:mic, %Membrane.PortAudio.Source{
        sample_format: :s16le,
        channels: 1,
        sample_rate: 16_000
      })
      |> child(:mute_filter, Demo.MuteFilter)
      |> child(:mic_pts_normalizer, %Membrane.RawAudioParser{overwrite_pts?: true})
      |> child(:mic_chunker, %Demo.ChunkFilter{
        chunk_duration: Time.milliseconds(@chunk_ms)
      })
      |> child(:mic_tee, Membrane.Tee),
      get_child(:mic_tee)
      |> via_out(Pad.ref(:output, :tui))
      |> child(:mic_realtimer, Membrane.Realtimer)
      |> child(:mic_tui_sink, %Demo.TuiSink{origin: :client, app: app}),
      get_child(:mic_tee)
      |> via_out(Pad.ref(:output, :main))
      |> via_in(:audio_input)
      |> child(:gemini, Membrane.Gemini.Bin)
      |> child(:gemini_pts_normalizer, %Membrane.RawAudioParser{overwrite_pts?: true})
      |> child(:gemini_chunker, %Demo.ChunkFilter{
        chunk_duration: Time.milliseconds(@chunk_ms)
      })
      |> child(:gemini_tee, Membrane.Tee),
      get_child(:gemini_tee)
      |> via_out(Pad.ref(:output, :main))
      |> child(:gemini_speaker, %Membrane.PortAudio.Sink{
        ringbuffer_size: 32_768,
        portaudio_buffer_size: 512
      }),
      get_child(:gemini_tee)
      |> via_out(Pad.ref(:output, :tui))
      |> child(:gemini_realtimer, Membrane.Realtimer)
      |> child(:gemini_tui_sink, %Demo.TuiSink{origin: :server, app: app}),
      child(:text_source, Demo.TextSource)
      |> via_in(:text_input)
      |> get_child(:gemini)
    ]

    {[spec: spec], %{app: app}}
  end

  @impl true
  def handle_playing(_ctx, %{app: app} = state) do
    Demo.App.signal_pipeline_playing(app)
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

app = Membrane.LLM.Demo.App.new(pipeline: Native.Pipeline)
pid = app.pid
ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, reason} -> exit(reason)
end
