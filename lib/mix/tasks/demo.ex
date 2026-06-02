defmodule Mix.Tasks.Demo do
  @shortdoc "Run the Gemini Termite TUI microphone demo"
  @moduledoc false

  use Mix.Task

  import Membrane.ChildrenSpec
  require Membrane.Pad

  alias Gemini.TermiteMicDemo
  alias Membrane.{Time, Pad}

  # __jm__ are these necessary??
  # Mix.Task behaviour has no PLT info; suppress the spurious callback_info_missing warning.
  @dialyzer :no_behaviours

  @requirements ["app.start"]

  @chunk_ms 40

  @spec run(any()) :: no_return()
  def run(_args) do
    pid = TermiteMicDemo.App.start_link(spec_fn: &native_spec/1)
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, reason} -> exit(reason)
    end
  end

  defp native_spec(app) do
    [
      child(:mic, %Membrane.PortAudio.Source{
        sample_format: :s16le,
        channels: 1,
        sample_rate: 16_000
      })
      |> child(:mute_filter, TermiteMicDemo.MuteFilter)
      |> child(:mic_pts_normalizer, %Membrane.RawAudioParser{overwrite_pts?: true})
      |> child(:mic_chunker, %TermiteMicDemo.ChunkerFilter{
        chunk_duration: Time.milliseconds(@chunk_ms)
      })
      |> child(:mic_tee, Membrane.Tee),
      get_child(:mic_tee)
      |> via_out(Pad.ref(:output, :tui))
      |> child(:mic_realtimer, Membrane.Realtimer)
      |> child(:mic_tui_sink, %TermiteMicDemo.TuiSink{origin: :client, app: app}),
      get_child(:mic_tee)
      |> via_out(Pad.ref(:output, :main))
      |> via_in(:audio_input)
      |> child(:gemini, Membrane.Gemini.Bin)
      |> child(:gemini_pts_normalizer, %Membrane.RawAudioParser{overwrite_pts?: true})
      |> child(:gemini_chunker, %TermiteMicDemo.ChunkerFilter{
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
      |> child(:gemini_tui_sink, %TermiteMicDemo.TuiSink{origin: :server, app: app}),
      child(:text_source, TermiteMicDemo.TextSource)
      |> via_in(:text_input)
      |> get_child(:gemini)
    ]
  end
end
