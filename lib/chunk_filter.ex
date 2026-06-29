defmodule Membrane.LLM.Demo.ChunkFilter do
  @moduledoc false

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
  def handle_buffer(:input, %Buffer{payload: payload, pts: pts}, _ctx, state) do
    chunk_size = RawAudio.time_to_bytes(state.chunk_duration, state.stream_format)
    buffers = chunk_bin(payload, chunk_size, pts, state.chunk_duration)
    {[{:buffer, {:output, buffers}}], state}
  end

  @spec chunk_bin(
          binary(),
          chunk_size :: pos_integer(),
          buffer_pts :: Time.t(),
          chunk_duration :: Time.t()
        ) :: [Buffer.t()]
  defp chunk_bin(bin, chunk_size, buffer_pts, chunk_duration) do
    {chunked_buffers, _pts} = chunk_bin(bin, chunk_size, buffer_pts, chunk_duration, [])
    chunked_buffers
  end

  @spec chunk_bin(
          binary(),
          chunk_size :: pos_integer(),
          buffer_pts :: Time.t(),
          chunk_duration :: Time.t(),
          acc :: [Buffer.t()]
        ) :: {[Buffer.t()], Time.t()}
  defp chunk_bin(<<>>, _size, pts, _dur, acc), do: {Enum.reverse(acc), pts}

  defp chunk_bin(bin, size, pts, dur, acc) when byte_size(bin) <= size,
    do: {Enum.reverse([%Buffer{payload: bin, pts: pts} | acc]), pts + dur}

  defp chunk_bin(bin, size, pts, dur, acc) do
    <<chunk::binary-size(^size), rest::binary>> = bin

    chunk_bin(rest, size, pts + dur, dur, [%Buffer{payload: chunk, pts: pts} | acc])
  end
end
