#! /usr/bin/env elixir
#
# Native PortAudio variant of the Gemini Termite demo, as a standalone script.
#
# Run with:
#
#     GEMINI_API_KEY="your key" elixir native.exs
#
# This mirrors `demo.livemd` (the WebRTC variant) for symmetry: deps come from
# `Mix.install` and the pipeline is defined inline here, so the script is
# self-contained the same way the livebook is. The path dep pulls in everything
# the native demo needs (PortAudio, Termite, the Gemini plugin, the project's
# own filters/sinks), so it keeps working even after `kino`/
# `membrane_webrtc_plugin` are dropped from `mix.exs`.
#
# A note on structure: the pipeline is wrapped in a module on purpose. In a
# plain `.exs`, `use`/`import`/`require` directives — and struct literals like
# `%App{}` — are resolved while the file is *compiled*, which happens before
# `Mix.install` runs, so referencing a freshly-installed module at the top level
# fails with "module not loaded". Top-level expressions are evaluated in order,
# though, so by the time the `defmodule` is compiled `Mix.install` has loaded
# the deps. (Livebook dodges this because each cell is compiled separately.) The
# driving code at the bottom therefore avoids struct literals and only makes
# plain runtime calls.

Mix.install([
  {:membrane_gemini_demo, path: __DIR__}
])

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
  @moduledoc """
  The native (PortAudio) pipeline for the demo.

  Same shape as `Gemini.TermiteMicDemo.Pipeline` — it notifies the TUI on
  `:playing` and relays the `:text`/`:reset_session`/`:toggle_mute` control
  messages to named children — but the audio I/O spec is baked into
  `handle_init/2` rather than supplied via a `spec_fn`. The middle of the
  pipeline (mute → chunk → tee → Gemini → tee) matches the inline WebRTC spec
  in `demo.livemd`; only the ends differ (PortAudio source/sink here).
  """

  use Membrane.Pipeline

  import Membrane.ChildrenSpec
  require Membrane.Pad

  alias Gemini.TermiteMicDemo
  alias Membrane.{Pad, Time}

  @chunk_ms 40

  @impl true
  def handle_init(_ctx, opts) do
    app = Keyword.fetch!(opts, :app)
    {[spec: spec(app)], %{app: app}}
  end

  @impl true
  def handle_playing(_ctx, state) do
    # Bootstrap handshake the App's handle_continue/2 blocks on before creating
    # the terminal (see Gemini.TermiteMicDemo.App's moduledoc).
    send(state.app.pid, {:pipeline_playing, self()})
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

  defp spec(app) do
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

# Driving code: start the TUI on top of the native pipeline, then block until it
# exits so the VM stays alive (the equivalent of the `mix demo` task's receive
# loop). Field access (`app.pid`) is used instead of a `%App{}` match to keep
# this top-level code free of compile-time struct expansion.
app = Gemini.TermiteMicDemo.App.new(pipeline: Native.Pipeline)
pid = app.pid
ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, reason} -> exit(reason)
end
