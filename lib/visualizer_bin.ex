defmodule Gemini.TermiteMicDemo.VisualizerBin do
  @moduledoc """
  This bin is used to receive raw audio streams and process them appropriately before feeding them
  to the `on_samples` anonymous function. The buffers are chunked if deemed too large
  (e.g. Google Live API would start its response with a 960ms buffer followed by 40ms deltas),
  and realtimed before being sent to `Gemini.TermiteMicDemo.VisSink`, which samples `@sample_count`
  evenly-spaced samples from each buffer.
  """

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
      |> via_out(Pad.ref(:output, :bin_output))
      |> bin_output(:output),
      get_child(:tee)
      |> via_out(Pad.ref(:output, :visualizer_sink))
      |> child(:realtimer, Membrane.Realtimer)
      |> child(:vis_sink, %Gemini.TermiteMicDemo.VisSink{
        on_samples: opts.on_samples,
        sample_count: @sample_count
      })
    ]

    {[spec: spec], %{}}
  end
end
