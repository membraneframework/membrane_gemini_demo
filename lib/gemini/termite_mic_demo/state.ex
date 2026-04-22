defmodule Gemini.TermiteMicDemo.State do
  @moduledoc false

  use Agent

  @max_history 200

  defmodule State do
    @moduledoc false

    @type event_entry ::
            {:event, String.t()}
            | {:log, Logger.level(), String.t()}

    @type t :: %__MODULE__{
            mic_samples: [float()],
            gemini_samples: [float()],
            input_transcript: String.t(),
            output_transcript: String.t(),
            thinking: String.t(),
            last_event: String.t(),
            event_history: [event_entry()]
          }

    defstruct mic_samples: [],
              gemini_samples: [],
              input_transcript: "",
              output_transcript: "",
              thinking: "",
              last_event: "",
              event_history: []
  end

  @spec start_link(any()) :: Agent.on_start()
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %State{} end, name: __MODULE__)
  end

  @spec add_mic_samples([float()]) :: :ok
  def add_mic_samples(samples) do
    Agent.update(__MODULE__, fn %State{} = state ->
      %{state | mic_samples: Enum.take(state.mic_samples ++ samples, -200)}
    end)
  end

  @spec add_gemini_samples([float()]) :: :ok
  def add_gemini_samples(samples) do
    Agent.update(__MODULE__, fn %State{} = state ->
      %{state | gemini_samples: Enum.take(state.gemini_samples ++ samples, -200)}
    end)
  end

  @spec set_input_transcript(String.t()) :: :ok
  def set_input_transcript(text) do
    entry = "Input:   #{text}"

    Agent.update(__MODULE__, fn %State{} = state ->
      %{state | input_transcript: text, last_event: entry} |> push_history({:event, entry})
    end)
  end

  @spec set_output_transcript(String.t()) :: :ok
  def set_output_transcript(text) do
    entry = "Output:  #{text}"

    Agent.update(__MODULE__, fn %State{} = state ->
      %{state | output_transcript: text, last_event: entry} |> push_history({:event, entry})
    end)
  end

  @spec set_thinking(String.t()) :: :ok
  def set_thinking(text) do
    entry = "Thinking: #{text}"

    Agent.update(__MODULE__, fn %State{} = state ->
      %{state | thinking: text, last_event: "Thinking..."} |> push_history({:event, entry})
    end)
  end

  @spec set_event(String.t()) :: :ok
  def set_event(event) do
    Agent.update(__MODULE__, fn %State{} = state ->
      %{state | last_event: event} |> push_history({:event, event})
    end)
  end

  @spec clear_transcripts() :: :ok
  def clear_transcripts,
    do: Agent.update(__MODULE__, fn %State{} = state -> %{state | output_transcript: "", thinking: ""} end)

  @spec push_log(Logger.level(), String.t()) :: :ok
  def push_log(level, text),
    do: Agent.update(__MODULE__, &push_history(&1, {:log, level, text}))

  @spec get_state() :: State.t()
  def get_state, do: Agent.get(__MODULE__, & &1)

  @spec push_history(State.t(), State.event_entry()) :: State.t()
  defp push_history(%State{} = state, entry),
    do: %{state | event_history: Enum.take([entry | state.event_history], @max_history)}
end
