defmodule Membrane.LLM.Demo.TextSource do
  @moduledoc false
  
  use Membrane.Source

  def_output_pad :output,
    accepted_format: %Membrane.RemoteStream{type: :bytestream},
    flow_control: :push

  @impl true
  def handle_init(_ctx, _opts),
    do: {[], %{eos?: false}}

  @impl true
  def handle_playing(_ctx, state),
    do: {[stream_format: {:output, %Membrane.RemoteStream{type: :bytestream}}], state}

  @impl true
  def handle_parent_notification({:text, line}, %{playback: :playing}, %{eos?: false} = state),
    do: {[buffer: {:output, %Membrane.Buffer{payload: line}}], state}

  def handle_parent_notification(:eos, _ctx, state),
    do: {[end_of_stream: :output], %{state | eos?: true}}
end
