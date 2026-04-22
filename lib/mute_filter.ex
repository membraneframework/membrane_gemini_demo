defmodule Gemini.TermiteMicDemo.MuteFilter do
  @moduledoc false
  
  use Membrane.Filter

  alias Membrane.RawAudio

  @audio_format %RawAudio{sample_format: :s16le, channels: 1, sample_rate: 16_000}

  def_input_pad :input, accepted_format: RawAudio
  def_output_pad :output, accepted_format: RawAudio

  @impl true
  def handle_init(_ctx, _opts), do: {[], %{muted: false}}

  @impl true
  def handle_buffer(:input, buffer, _ctx, %{muted: true} = state) do
    silence =
      RawAudio.silence(
        @audio_format,
        RawAudio.bytes_to_time(byte_size(buffer.payload), @audio_format)
      )

    {[buffer: {:output, %Membrane.Buffer{payload: silence}}], state}
  end

  def handle_buffer(:input, buffer, _ctx, state),
    do: {[buffer: {:output, buffer}], state}

  @impl true
  def handle_parent_notification(:toggle_mute, _ctx, state),
    do: {[], %{state | muted: !state.muted}}
end
