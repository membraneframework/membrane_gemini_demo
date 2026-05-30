defmodule Mix.Tasks.Demo do
  @shortdoc "Run the Gemini Termite TUI microphone demo"
  @moduledoc false

  use Mix.Task

  import Membrane.ChildrenSpec

  alias Gemini.TermiteMicDemo.{Pipeline, MuteFilter, TextSource, VisualizerBin}

  # Mix.Task behaviour has no PLT info; suppress the spurious callback_info_missing warning.
  @dialyzer :no_behaviours

  @requirements ["app.start"]

  @spec run(any()) :: no_return()
  def run(_args) do
    Gemini.TermiteMicDemo.App.start(spec_fn: &native_spec/1)
  end

  defp native_spec(tui_pid) do
    [
      child(:mic, %Membrane.PortAudio.Source{
        sample_format: :s16le,
        channels: 1,
        sample_rate: 16_000
      })
      |> child(:mute_filter, MuteFilter)
      |> child(:mic_visualizer, %VisualizerBin{
        on_samples: fn samples -> send(tui_pid, {:mic_samples, samples}) end
      })
      |> via_in(:audio_input)
      |> child(:gemini, Membrane.Gemini.Bin)
      |> child(:event_handler, %Membrane.Debug.Filter{
        handle_event: &Pipeline.handle_gemini_event(&1, tui_pid)
      })
      |> child(:gemini_visualizer, %VisualizerBin{
        on_samples: fn samples -> send(tui_pid, {:gemini_samples, samples}) end
      })
      |> child(:gemini_speaker, %Membrane.PortAudio.Sink{
        ringbuffer_size: 32_768,
        portaudio_buffer_size: 512
      }),
      child(:text_source, TextSource)
      |> via_in(:text_input)
      |> get_child(:gemini)
    ]
  end
end
