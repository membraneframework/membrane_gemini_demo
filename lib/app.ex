defmodule Membrane.LLM.Demo.App do
  @moduledoc false
  use GenServer

  alias Membrane.LLM.Demo.{App, LoggerHandler}
  alias Termite.{Screen, Terminal}

  @type t :: pid()

  @render_interval 50
  @playing_timeout 30_000

  @spec signal_pipeline_playing(t(), pid()) :: :ok
  def signal_pipeline_playing(app, pipeline \\ self()),
    do: send(app, {:pipeline_playing, pipeline})

  @spec mic_samples(t(), [float()]) :: :ok
  def mic_samples(app, samples), do: GenServer.cast(app, {:mic_samples, samples})

  @spec gemini_samples(t(), [float()]) :: :ok
  def gemini_samples(app, samples), do: GenServer.cast(app, {:gemini_samples, samples})

  @spec input_transcript(t(), String.t()) :: :ok
  def input_transcript(app, text), do: GenServer.cast(app, {:input_transcript, text})

  @spec output_transcript(t(), String.t()) :: :ok
  def output_transcript(app, text), do: GenServer.cast(app, {:output_transcript, text})

  @spec thinking(t(), String.t()) :: :ok
  def thinking(app, text), do: GenServer.cast(app, {:thinking, text})

  @spec event(t(), String.t()) :: :ok
  def event(app, text), do: GenServer.cast(app, {:event, text})

  @spec clear_transcripts(t()) :: :ok
  def clear_transcripts(app), do: GenServer.cast(app, :clear_transcripts)

  @spec log(t(), Logger.level(), String.t()) :: :ok
  def log(app, level, text), do: GenServer.cast(app, {:log, level, text})

  # :infinity because the call may arrive while the App is still in
  # handle_continue/2 waiting for the pipeline to reach :playing; the wait is
  # bounded there by @playing_timeout, which crashes the App (and so this call)
  # if it elapses.
  @spec get_terminal(t()) :: struct()
  def get_terminal(app), do: GenServer.call(app, :get_terminal, :infinity)

  @spec start_link(keyword()) :: {:ok, pid()}
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @spec new(keyword()) :: t()
  def new(opts) do
    {:ok, pid} = start_link(opts)
    pid
  end

  # Setup is deferred to handle_continue/2 so we don't block — or call
  # Kino.start_child/1 (via the terminal adapter) — inside init/1. That keeps the
  # App startable with Kino.start_child/1: init/1 returns at once, freeing Kino's
  # supervisor before the terminal widget is built.
  @impl true
  def init(opts), do: {:ok, opts, {:continue, :setup}}

  @impl true
  def handle_continue(:setup, opts) do
    app = self()
    terminal_factory = Keyword.get(opts, :terminal_factory, &Terminal.start/0)
    pipeline_pid = Keyword.fetch!(opts, :pipeline_pid)
    pipeline_mod = Keyword.fetch!(opts, :pipeline_mod)

    :logger.remove_handler(:default)
    :logger.add_handler(:tui, LoggerHandler, %{config: %{app: app}})

    # The pipeline is started before us; hand it our pid so it can build its
    # spec, then wait for it to reach :playing.
    pipeline_mod.set_app(pipeline_pid, app)

    receive do
      {:pipeline_playing, ^pipeline_pid} -> :ok
    after
      @playing_timeout ->
        raise "pipeline did not reach :playing within #{@playing_timeout}ms"
    end

    # The terminal MUST be created inside this process: adapters like
    # KinoTermite capture `self()` to route keystroke messages back to us.
    terminal = terminal_factory.()

    terminal =
      terminal
      |> Screen.run_escape_sequence(:screen_alt)
      |> Screen.run_escape_sequence(:cursor_hide)
      |> Screen.run_escape_sequence(:screen_clear)

    Process.send_after(self(), :render_tick, @render_interval)

    {:noreply, App.State.new(terminal, pipeline_pid, pipeline_mod)}
  end

  @impl true
  def handle_cast(msg, state),
    do: {:noreply, App.State.update(state, msg)}

  @impl true
  def handle_call(:get_terminal, _from, %App.State{terminal: terminal} = state),
    do: {:reply, terminal, state}

  @impl true
  def handle_info(
        {reader, payload},
        %App.State{terminal: %Terminal{reader: reader}} = state
      ) do
    {:noreply, App.State.handle_input(state, payload)}
  end

  def handle_info(:render_tick, state) do
    Process.send_after(self(), :render_tick, @render_interval)
    {:noreply, App.State.render(state)}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
