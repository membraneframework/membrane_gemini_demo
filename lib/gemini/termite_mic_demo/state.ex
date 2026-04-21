defmodule Gemini.TermiteMicDemo.State do
  @moduledoc false
  
  use Agent

  @max_history 200

  def start_link(_opts \\ []) do
    Agent.start_link(
      fn ->
        %{
          mic_samples: [],
          gemini_samples: [],
          input_transcript: "",
          output_transcript: "",
          thinking: "",
          last_event: "",
          event_history: []
        }
      end,
      name: __MODULE__
    )
  end

  def add_mic_samples(samples) do
    Agent.update(__MODULE__, fn state ->
      %{state | mic_samples: Enum.take(state.mic_samples ++ samples, -200)}
    end)
  end

  def add_gemini_samples(samples) do
    Agent.update(__MODULE__, fn state ->
      %{state | gemini_samples: Enum.take(state.gemini_samples ++ samples, -200)}
    end)
  end

  def set_input_transcript(text) do
    entry = "Input:   #{text}"

    Agent.update(__MODULE__, fn state ->
      %{state | input_transcript: text, last_event: entry} |> push_history({:event, entry})
    end)
  end

  def set_output_transcript(text) do
    entry = "Output:  #{text}"

    Agent.update(__MODULE__, fn state ->
      %{state | output_transcript: text, last_event: entry} |> push_history({:event, entry})
    end)
  end

  def set_thinking(text) do
    entry = "Thinking: #{text}"

    Agent.update(__MODULE__, fn state ->
      %{state | thinking: text, last_event: "Thinking..."} |> push_history({:event, entry})
    end)
  end

  def set_event(event) do
    Agent.update(__MODULE__, fn state ->
      %{state | last_event: event} |> push_history({:event, event})
    end)
  end

  def clear_transcripts,
    do: Agent.update(__MODULE__, &%{&1 | output_transcript: "", thinking: ""})

  def push_log(level, text),
    do: Agent.update(__MODULE__, &push_history(&1, {:log, level, text}))

  def get_state, do: Agent.get(__MODULE__, & &1)

  defp push_history(state, entry),
    do: %{state | event_history: Enum.take([entry | state.event_history], @max_history)}
end
