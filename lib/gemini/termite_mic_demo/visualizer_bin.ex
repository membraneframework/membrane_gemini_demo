defmodule Gemini.TermiteMicDemo.VisualizerBin do
  use Membrane.Bin
  alias Membrane.{RawAudio, Time}

  def_input_pad :input, accepted_format: RawAudio
  def_output_pad :output, accepted_format: RawAudio

  def_options on_samples: [spec: ([float()] -> :ok)]

  @chunk_ms 40
  @sample_count 5

  @impl true
  def handle_init(_ctx, opts) do
    spec = [
      bin_input(:input)
      |> child(:pts_normalizer, %Membrane.RawAudioParser{overwrite_pts?: true})
      |> child(:chunker, %Gemini.TermiteMicDemo.ChunkerFilter{
        chunk_duration: Time.milliseconds(@chunk_ms)
      })
      |> child(:tee, Membrane.Tee),
      get_child(:tee)
      |> via_out(:output)
      |> bin_output(:output),
      get_child(:tee)
      |> via_out(:push_output)
      |> child(:realtimer, Membrane.Realtimer)
      |> child(:vis_sink, %Gemini.TermiteMicDemo.VisSink{
        on_samples: opts.on_samples,
        sample_count: @sample_count,
      })
    ]

    {[spec: spec], %{}}
  end
end
