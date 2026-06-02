defmodule Gemini.TermiteMicDemo.App do
  @moduledoc """
  The TUI application, as a GenServer.

  `%App{}` is a thin wrapper around the server pid. The server's internal
  bookkeeping is `%{app:, reader:, pipeline:, state:}`, where `state` is the
  `Gemini.TermiteMicDemo.App.State` view model (don't confuse the wrapper
  struct, the bookkeeping map, and the `%State{}`).

  All messages the server reacts to arrive through the public functions below
  (each takes the `%App{}` wrapper and casts), rather than via raw `send/2`.
  The one exception is the `{:pipeline_playing, pid}` bootstrap handshake: the
  pipeline `send/2`s it directly so `handle_continue/2` can block on it before
  the terminal is created — this preserves "the TUI only appears once the
  pipeline is `:playing`" and the start-up timeout.

  Terminal input is the other thing that arrives as raw messages: the
  `Termite.Terminal` reader sends `{reader_ref, payload}` to this process, which
  `handle_info/2` forwards to `State.handle_input/2`.
  """

  use GenServer

  alias Gemini.TermiteMicDemo.{App, LoggerHandler, Pipeline}
  alias Termite.{Screen, Terminal}

  @type t :: %__MODULE__{pid: pid()}
  defstruct [:pid]

  @render_interval 50
  @playing_timeout 30_000

  @spec mic_samples(t(), [float()]) :: :ok
  def mic_samples(%App{pid: pid}, samples), do: GenServer.cast(pid, {:mic_samples, samples})

  @spec gemini_samples(t(), [float()]) :: :ok
  def gemini_samples(%App{pid: pid}, samples), do: GenServer.cast(pid, {:gemini_samples, samples})

  @spec input_transcript(t(), String.t()) :: :ok
  def input_transcript(%App{pid: pid}, text), do: GenServer.cast(pid, {:input_transcript, text})

  @spec output_transcript(t(), String.t()) :: :ok
  def output_transcript(%App{pid: pid}, text), do: GenServer.cast(pid, {:output_transcript, text})

  @spec thinking(t(), String.t()) :: :ok
  def thinking(%App{pid: pid}, text), do: GenServer.cast(pid, {:thinking, text})

  @spec event(t(), String.t()) :: :ok
  def event(%App{pid: pid}, text), do: GenServer.cast(pid, {:event, text})

  @spec clear_transcripts(t()) :: :ok
  def clear_transcripts(%App{pid: pid}), do: GenServer.cast(pid, :clear_transcripts)

  @spec log(t(), Logger.level(), String.t()) :: :ok
  def log(%App{pid: pid}, level, text), do: GenServer.cast(pid, {:log, level, text})

  @spec get_terminal(t()) :: struct()
  def get_terminal(%App{pid: pid}), do: GenServer.call(pid, :get_terminal)

  # defmodule State do
  #   @type t :: %__MODULE__{
  #           app: App.t(),
  #           pipeline: pid(),
  #           terminal_factory: (-> struct()),
  #           state: App.State.t() | nil,
  #         }

  #   @enforce_keys [:app, :pipeline, :terminal_factory]
  #   defstruct @enforce_keys ++ [:state]
  # end

  @spec start_link(keyword()) :: {:ok, pid()}
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @spec new(keyword()) :: t()
  def new(opts) do
    {:ok, pid} = start_link(opts)
    %__MODULE__{pid: pid}
  end

  @impl true
  def init(opts) do
    app = %App{pid: self()}
    spec_fn = Keyword.fetch!(opts, :spec_fn)
    terminal_factory = Keyword.get(opts, :terminal_factory, &Terminal.start/0)

    :logger.remove_handler(:default)
    :logger.add_handler(:tui, LoggerHandler, %{config: %{app: app}})

    {:ok, _supervisor, pipeline} =
      Membrane.Pipeline.start_link(Pipeline, app: app, spec_fn: spec_fn)

    {:ok, %{app: app, pipeline: pipeline, terminal_factory: terminal_factory},
     {:continue, :await_playing}}
  end

  @impl true
  def handle_continue(
        :await_playing,
        %{pipeline: pipeline, terminal_factory: terminal_factory} = g
      ) do
    receive do
      {:pipeline_playing, ^pipeline} -> :ok
    after
      @playing_timeout ->
        raise "pipeline did not reach :playing within #{@playing_timeout}ms"
    end

    # The terminal MUST be created inside this process: adapters like
    # KinoTermite capture `self()` to route keystroke messages back to us.
    terminal = terminal_factory.()

    term =
      terminal
      |> Screen.run_escape_sequence(:screen_alt)
      |> Screen.run_escape_sequence(:cursor_hide)
      |> Screen.run_escape_sequence(:screen_clear)

    Process.send_after(self(), :render_tick, @render_interval)

    {:noreply, Map.merge(g, %{state: App.State.new(term, pipeline)})}
  end

  @impl true
  def handle_cast(msg, %{state: state} = g),
    do: {:noreply, %{g | state: App.State.update(state, msg)}}

  @impl true
  def handle_call(:get_terminal, _from, %{state: %App.State{term: term}} = state),
    do: {:reply, term, state}

  @impl true
  def handle_info(
        {reader, payload},
        %{state: %App.State{term: %Terminal{reader: reader}} = state} = g
      ) do
    {:noreply, %{g | state: App.State.handle_input(state, payload)}}
  end

  def handle_info(:render_tick, %{state: state} = g) do
    Process.send_after(self(), :render_tick, @render_interval)
    {:noreply, %{g | state: App.State.render(state)}}
  end

  def handle_info(_msg, g), do: {:noreply, g}
end
