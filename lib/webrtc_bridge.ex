defmodule Gemini.TermiteMicDemo.WebRTCBridge do
  @moduledoc """
  Kino widget that hosts both peer connections in a single iframe so the
  browser's echo canceller sees mic capture and `<audio>` playback on the
  same page.

  The Elixir side acts as the JSON peer on two `Membrane.WebRTC.Signaling`
  channels — one for the source (mic), one for the sink (speaker) — and
  forwards messages to/from the JS over Kino's pubsub. Messages that arrive
  before a JS client has connected are buffered so the sink's initial SDP
  offer is never lost.
  """

  use Kino.JS, assets_path: "lib/assets/webrtc_bridge"
  use Kino.JS.Live

  alias Membrane.WebRTC.Signaling

  @spec new(Signaling.t(), Signaling.t()) :: Kino.JS.Live.t()
  def new(source_signaling, sink_signaling) do
    Kino.JS.Live.new(__MODULE__, %{source: source_signaling, sink: sink_signaling})
  end

  @impl true
  def init(%{source: source, sink: sink}, ctx) do
    Signaling.register_peer(source, message_format: :json_data)
    Signaling.register_peer(sink, message_format: :json_data)

    {:ok,
     assign(ctx,
       source: source,
       sink: sink,
       source_queue: [],
       sink_queue: [],
       drained?: false
     )}
  end

  @impl true
  def handle_connect(ctx) do
    payload = %{
      source_queue: Enum.reverse(ctx.assigns.source_queue),
      sink_queue: Enum.reverse(ctx.assigns.sink_queue)
    }

    {:ok, payload, assign(ctx, source_queue: [], sink_queue: [], drained?: true)}
  end

  @impl true
  def handle_event("signal_source", message, ctx) do
    Signaling.signal(ctx.assigns.source, message)
    {:noreply, ctx}
  end

  def handle_event("signal_sink", message, ctx) do
    Signaling.signal(ctx.assigns.sink, message)
    {:noreply, ctx}
  end

  @impl true
  def handle_info({:membrane_webrtc_signaling, pid, message, _meta}, ctx) do
    {channel, queue_key} =
      cond do
        pid == ctx.assigns.source.pid -> {"source_signal", :source_queue}
        pid == ctx.assigns.sink.pid -> {"sink_signal", :sink_queue}
      end

    if ctx.assigns.drained? do
      broadcast_event(ctx, channel, message)
      {:noreply, ctx}
    else
      {:noreply, update(ctx, queue_key, &[message | &1])}
    end
  end
end
