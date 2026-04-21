defmodule Gemini.TermiteMicDemo.ChunkerFilter do
  use Membrane.Filter
  alias Membrane.{Buffer, RawAudio, Time}

  def_input_pad :input, accepted_format: RawAudio
  def_output_pad :output, accepted_format: RawAudio

  def_options chunk_duration: [spec: Time.t(), default: Time.milliseconds(40)]

  @impl true
  def handle_init(_ctx, opts),
    do: {[], %{chunk_duration: opts.chunk_duration, stream_format: nil}}

  @impl true
  def handle_stream_format(:input, fmt, _ctx, state),
    do: {[stream_format: {:output, fmt}], %{state | stream_format: fmt}}

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    chunk_size = RawAudio.time_to_bytes(state.chunk_duration, state.stream_format)
    {actions, _} = do_chunk(buffer.payload, chunk_size, buffer.pts, state.chunk_duration, [])
    {actions, state}
  end

  @spec do_chunk(
          binary(),
          chunk_size :: pos_integer(),
          pts :: Time.t(),
          chunk_duration :: Time.t(),
          acc :: [{:buffer, {:output, Buffer.t()}}]
        ) :: {[{:buffer, {:output, Buffer.t()}}], Time.t()}
  defp do_chunk(<<>>, _size, pts, _dur, acc), do: {Enum.reverse(acc), pts}

  defp do_chunk(bin, size, pts, dur, acc) when byte_size(bin) <= size,
    do: {Enum.reverse([{:buffer, {:output, %Buffer{payload: bin, pts: pts}}} | acc]), pts + dur}

  defp do_chunk(bin, size, pts, dur, acc) do
    <<chunk::binary-size(size), rest::binary>> = bin

    do_chunk(rest, size, pts + dur, dur, [
      {:buffer, {:output, %Buffer{payload: chunk, pts: pts}}} | acc
    ])
  end
end
