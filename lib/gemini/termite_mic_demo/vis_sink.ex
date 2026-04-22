defmodule Gemini.TermiteMicDemo.VisSink do
  @moduledoc false

  use Membrane.Sink
  alias Membrane.RawAudio

  def_input_pad :input, accepted_format: RawAudio

  def_options on_samples: [spec: ([float()] -> :ok)],
              sample_count: [spec: pos_integer()]

  @impl true
  def handle_init(_ctx, opts),
    do: {[], %{on_samples: opts.on_samples, sample_count: opts.sample_count}}

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    state.on_samples.(extract_samples(buffer.payload, state.sample_count))
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
