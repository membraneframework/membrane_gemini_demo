defmodule Membrane.LLM.Demo.App.State do
  @moduledoc """
  The TUI's view model and all of its pure rendering/update logic.
  """

  import Bitwise

  alias Termite.{Screen, Style, Terminal}

  @waveform_char_height 8
  @noise_floor 0.005
  @max_history 200
  @max_samples 200

  @type turn_kind :: :input | :output

  @type event_entry ::
          {:event, String.t()}
          | {:log, Logger.level(), String.t()}
          | {:turn, turn_kind(), String.t()}

  @type t :: %__MODULE__{
          terminal: term(),
          input_buffer: String.t(),
          status: String.t(),
          pipeline_pid: pid(),
          pipeline_mod: module(),
          debug_mode: boolean(),
          muted: boolean(),
          mic_samples: [float()],
          gemini_samples: [float()],
          input_pending_reset: boolean(),
          output_pending_reset: boolean(),
          last_event: String.t(),
          event_history: [event_entry()]
        }

  @enforce_keys [:terminal, :pipeline_pid, :pipeline_mod]

  defstruct @enforce_keys ++
              [
                input_buffer: "",
                status: "Ready. Speak into your mic or type text to send to Gemini.",
                debug_mode: false,
                muted: false,
                mic_samples: [],
                gemini_samples: [],
                input_pending_reset: false,
                output_pending_reset: false,
                last_event: "",
                event_history: []
              ]

  @spec new(term(), pid(), module()) :: t()
  def new(terminal, pipeline_pid, pipeline_mod),
    do: %__MODULE__{terminal: terminal, pipeline_pid: pipeline_pid, pipeline_mod: pipeline_mod}

  @spec update(t(), tuple() | atom()) :: t()
  def update(%__MODULE__{} = state, {:mic_samples, samples}),
    do: %{state | mic_samples: Enum.take(state.mic_samples ++ samples, -@max_samples)}

  def update(%__MODULE__{} = state, {:gemini_samples, samples}),
    do: %{state | gemini_samples: Enum.take(state.gemini_samples ++ samples, -@max_samples)}

  def update(%__MODULE__{} = state, {:input_transcript, text}),
    do: push_turn(state, :input, text)

  def update(%__MODULE__{} = state, {:output_transcript, text}),
    do: push_turn(state, :output, text)

  def update(%__MODULE__{} = state, {:thinking, text}) do
    %{state | last_event: "Thinking..."}
    |> push_history({:event, "Thinking: #{text}"})
  end

  def update(%__MODULE__{} = state, {:event, text}),
    do: %{state | last_event: text} |> push_history({:event, text})

  def update(%__MODULE__{} = state, :clear_transcripts) do
    # ResponseStart: input's prior paragraph stays visible until the user
    # speaks again; the next output delta starts a fresh Gemini paragraph.
    %{state | input_pending_reset: true, output_pending_reset: true}
  end

  def update(%__MODULE__{} = state, {:log, level, text}),
    do: push_history(state, {:log, level, text})

  @spec handle_input(t(), term()) :: t()
  def handle_input(state, {:data, "\r"}), do: handle_submit(state)
  def handle_input(state, {:data, "\n"}), do: handle_submit(state)
  def handle_input(state, {:data, <<127>>}), do: delete_char(state)
  def handle_input(state, {:data, <<23>>}), do: delete_word(state)
  def handle_input(state, {:data, <<21>>}), do: clear_buffer(state)
  def handle_input(state, {:data, char}) when byte_size(char) == 1, do: add_char(state, char)
  def handle_input(state, {:data, _data}), do: state

  def handle_input(state, {:signal, :winch}),
    do: %{state | terminal: Terminal.resize(state.terminal)}

  def handle_input(state, :timeout), do: state
  def handle_input(state, _other), do: state

  @spec terminal_width(t()) :: pos_integer()
  defp terminal_width(%__MODULE__{terminal: %{size: %{width: w}}}) when is_integer(w) and w > 0,
    do: w

  defp terminal_width(_state), do: 80

  @spec terminal_height(t()) :: pos_integer()
  defp terminal_height(%__MODULE__{terminal: %{size: %{height: h}}}) when is_integer(h) and h > 0,
    do: h

  defp terminal_height(_state), do: 24

  @spec render(t()) :: t()
  def render(%__MODULE__{} = state) do
    {color, mic_text} = mic_status_info(state.muted)
    w = terminal_width(state)
    waveform_char_width = max(div(w - 4, 2), 10)

    available_lines = max(terminal_height(state) - 23, 0)

    entries =
      state.event_history
      |> Enum.reverse()
      |> Enum.filter(fn
        {:turn, _, _} -> true
        _ -> state.debug_mode
      end)
      |> with_separators()
      |> Enum.flat_map(&format_history_entry(w, &1))
      |> Enum.take(-available_lines)

    history_title = if state.debug_mode, do: "Transcript & Events", else: "Transcript"

    history_section =
      (Style.bold()
       |> Style.foreground(6)
       |> Style.render_to_string(
         "── #{history_title} #{String.duplicate("─", max(w - String.length(history_title) - 4, 0))}\n"
       )) <>
        Enum.join(entries)

    mic_text_formatted =
      Style.bold() |> Style.foreground(color) |> Style.render_to_string("#{mic_text}\n")

    mic_input_formatted = Style.foreground(6) |> Style.render_to_string("Mic Input")
    gemini_input_formatted = Style.foreground(5) |> Style.render_to_string("Gemini\n")
    waveforms = render_waveforms(state.mic_samples, state.gemini_samples, waveform_char_width)
    input_prompt = Style.bold() |> Style.render_to_string("gemini> ")
    controls_info_map = Style.foreground(4) |> Style.render_to_string("/mute | /debug | /clear")

    frame = """
    #{mic_text_formatted}
    Status: #{state.status}

    #{mic_input_formatted}  #{gemini_input_formatted}
    #{waveforms}

    #{input_prompt} #{state.input_buffer}█
    #{controls_info_map}

    #{history_section}\e[J
    """

    terminal =
      state.terminal
      |> Screen.run_escape_sequence(:cursor_move, [0, 0])
      |> Screen.write(String.replace(frame, "\n", "\e[K\n"))

    %{state | terminal: terminal}
  end

  @spec push_history(t(), event_entry()) :: t()
  defp push_history(%__MODULE__{} = state, entry),
    do: %{state | event_history: Enum.take([entry | state.event_history], @max_history)}

  @spec push_turn(t(), turn_kind(), String.t()) :: t()
  defp push_turn(%__MODULE__{} = state, kind, delta) do
    pending_field = pending_reset_field(kind)
    pending = Map.fetch!(state, pending_field)
    state = Map.put(state, pending_field, false)
    last_event = "#{turn_label(kind)}#{delta}"

    case {pending, state.event_history} do
      {false, [{:turn, ^kind, prev} | rest]} ->
        %{state | event_history: [{:turn, kind, prev <> delta} | rest], last_event: last_event}

      _ ->
        push_history(%{state | last_event: last_event}, {:turn, kind, delta})
    end
  end

  @spec pending_reset_field(turn_kind()) :: atom()
  defp pending_reset_field(:input), do: :input_pending_reset
  defp pending_reset_field(:output), do: :output_pending_reset

  @spec with_separators([event_entry() | :separator]) :: [event_entry() | :separator]
  defp with_separators([]), do: []
  defp with_separators([_entry] = list), do: list

  defp with_separators([a, b | rest]) do
    if entry_kind(a) != entry_kind(b),
      do: [a, :separator | with_separators([b | rest])],
      else: [a | with_separators([b | rest])]
  end

  @spec entry_kind(event_entry()) :: :log | :event | :turn
  defp entry_kind({:log, _level, _text}), do: :log
  defp entry_kind({:event, _text}), do: :event
  defp entry_kind({:turn, _kind, _text}), do: :turn

  @spec turn_label(turn_kind()) :: String.t()
  defp turn_label(:input), do: "You:    "
  defp turn_label(:output), do: "Gemini: "

  @spec turn_color(turn_kind()) :: pos_integer()
  defp turn_color(:input), do: 6
  defp turn_color(:output), do: 5

  @spec format_history_entry(pos_integer(), event_entry() | :separator) :: [iodata()]
  defp format_history_entry(_w, :separator), do: ["\n"]

  defp format_history_entry(w, {:event, text}) do
    text
    |> String.replace("\n", " ")
    |> chunk_text(max(w - 2, 1))
    |> Enum.map(&[Style.foreground(2) |> Style.render_to_string("  " <> &1), "\n"])
  end

  defp format_history_entry(w, {:turn, kind, text}) do
    label = turn_label(kind)
    color = turn_color(kind)
    prefix = "  " <> label
    indent = String.duplicate(" ", String.length(prefix))

    text
    |> String.replace("\n", " ")
    |> chunk_text(max(w - String.length(prefix), 1))
    |> Enum.with_index()
    |> Enum.map(fn {chunk, i} ->
      lead = if i == 0, do: prefix, else: indent
      [Style.foreground(color) |> Style.render_to_string(lead <> chunk), "\n"]
    end)
  end

  defp format_history_entry(w, {:log, level, text}) do
    prefix = "  [#{level}] "
    indent = String.duplicate(" ", String.length(prefix))

    text
    |> String.replace("\n", " ")
    |> chunk_text(max(w - String.length(prefix), 1))
    |> Enum.with_index()
    |> Enum.map(fn {chunk, i} ->
      lead = if i == 0, do: prefix, else: indent
      [Style.foreground(log_color(level)) |> Style.render_to_string(lead <> chunk), "\n"]
    end)
  end

  @spec chunk_text(String.t(), width :: pos_integer()) :: [String.t()]
  defp chunk_text(text, width) do
    text
    |> String.graphemes()
    |> Enum.chunk_every(max(width, 1))
    |> Enum.map(&Enum.join/1)
  end

  @spec log_color(Logger.level()) :: pos_integer()
  defp log_color(:debug), do: 4
  defp log_color(:info), do: 7
  defp log_color(:warning), do: 3
  defp log_color(:error), do: 1
  defp log_color(_level), do: 1

  @spec render_waveforms([float()], [float()], pos_integer()) :: String.t()
  defp render_waveforms(left, right, char_width) do
    left_rows = build_braille_waveform(left, @waveform_char_height, char_width)
    right_rows = build_braille_waveform(right, @waveform_char_height, char_width)

    Enum.zip(left_rows, right_rows)
    |> Enum.map_join(fn {l, r} ->
      (Style.foreground(6) |> Style.render_to_string(l)) <>
        "  " <>
        (Style.foreground(5) |> Style.render_to_string(r)) <>
        "\n"
    end)
  end

  @spec build_braille_waveform([float()], pos_integer(), pos_integer()) :: [String.t()]
  defp build_braille_waveform(samples, char_height, char_width) do
    dot_height = char_height * 4
    num_samples = char_width * 2
    padded = pad_samples(samples, num_samples)
    center = (dot_height - 1) / 2.0

    dot_rows =
      Enum.map(padded, fn s ->
        round(center - s * (dot_height - 1) / 2.0) |> max(0) |> min(dot_height - 1)
      end)

    active_dots =
      dot_rows
      |> Enum.chunk_every(2, 2, :discard)
      |> Enum.with_index()
      |> Enum.reduce(MapSet.new(), fn {[l_row, r_row], char_col}, acc ->
        prev_row = if char_col > 0, do: Enum.at(dot_rows, char_col * 2 - 1), else: l_row

        acc
        |> fill_dots(char_col, 0, prev_row, l_row)
        |> fill_dots(char_col, 1, l_row, r_row)
      end)

    for char_row <- 0..(char_height - 1) do
      Enum.map_join(0..(char_width - 1), fn char_col ->
        value =
          for dot_col <- 0..1,
              local_row <- 0..3,
              MapSet.member?(active_dots, {char_col, char_row, dot_col, local_row}),
              reduce: 0 do
            acc -> acc + (1 <<< braille_bit(dot_col, local_row))
          end

        <<0x2800 + value::utf8>>
      end)
    end
  end

  @spec pad_samples([float()], pos_integer()) :: [float()]
  defp pad_samples(samples, target) do
    n = length(samples)

    padded =
      if n >= target,
        do: Enum.take(samples, -target),
        else: List.duplicate(0.0, target - n) ++ samples

    max_amp = padded |> Enum.map(&abs/1) |> Enum.max() |> max(@noise_floor)
    Enum.map(padded, fn s -> s / max_amp end)
  end

  @spec fill_dots(MapSet.t(), non_neg_integer(), 0 | 1, non_neg_integer(), non_neg_integer()) ::
          MapSet.t()
  defp fill_dots(set, char_col, dot_col, from_row, to_row) do
    Enum.reduce(min(from_row, to_row)..max(from_row, to_row), set, fn abs_row, acc ->
      MapSet.put(acc, {char_col, div(abs_row, 4), dot_col, rem(abs_row, 4)})
    end)
  end

  @spec braille_bit(0 | 1, 0 | 1 | 2 | 3) :: 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7
  defp braille_bit(dot_col, local_row) do
    case {dot_col, local_row} do
      {0, 0} -> 0
      {0, 1} -> 1
      {0, 2} -> 2
      {0, 3} -> 6
      {1, 0} -> 3
      {1, 1} -> 4
      {1, 2} -> 5
      {1, 3} -> 7
    end
  end

  @spec mic_status_info(boolean()) :: {pos_integer(), String.t()}
  defp mic_status_info(false), do: {2, "MIC LIVE - Speaking into microphone"}
  defp mic_status_info(true), do: {1, "MIC MUTED - Microphone is silenced"}

  @spec toggle_debug(t()) :: t()
  defp toggle_debug(%__MODULE__{} = state) do
    new_debug = !state.debug_mode
    %{state | debug_mode: new_debug, status: if(new_debug, do: "Debug on", else: "Debug off")}
  end

  @spec toggle_mute(t()) :: t()
  defp toggle_mute(%__MODULE__{} = state) do
    state.pipeline_mod.toggle_mute(state.pipeline_pid)

    if state.muted do
      %{state | muted: false, status: "Mic unmuted"}
    else
      %{state | muted: true, status: "Mic muted"}
    end
  end

  @spec delete_char(t()) :: t()
  defp delete_char(%__MODULE__{} = state),
    do: %{state | input_buffer: String.slice(state.input_buffer, 0..-2//1)}

  @spec delete_word(t()) :: t()
  defp delete_word(%__MODULE__{} = state) do
    new_buffer =
      state.input_buffer
      |> String.trim_trailing()
      |> String.reverse()
      |> String.split(" ", parts: 2)
      |> case do
        [_word] -> ""
        [_word, rest] -> String.reverse(rest)
        [] -> ""
      end

    %{state | input_buffer: new_buffer}
  end

  @spec clear_buffer(t()) :: t()
  defp clear_buffer(%__MODULE__{} = state), do: %{state | input_buffer: ""}

  @spec add_char(t(), String.t()) :: t()
  defp add_char(%__MODULE__{} = state, char),
    do: %{state | input_buffer: state.input_buffer <> char}

  @spec handle_submit(t()) :: t()
  defp handle_submit(%__MODULE__{} = state) do
    input = String.trim(state.input_buffer)

    cond do
      input == "" ->
        state

      String.starts_with?(input, "/") ->
        handle_command(%{state | input_buffer: ""}, input)

      true ->
        state.pipeline_mod.submit_text(state.pipeline_pid, input)
        %{state | input_buffer: "", status: "Sent to Gemini: #{input}"}
    end
  end

  @spec handle_command(t(), String.t()) :: t()
  defp handle_command(%__MODULE__{} = state, "/clear") do
    state.pipeline_mod.reset_session(state.pipeline_pid)

    %{
      state
      | event_history: [],
        input_pending_reset: false,
        output_pending_reset: false,
        status: "Session reset"
    }
  end

  defp handle_command(%__MODULE__{} = state, "/mute"), do: toggle_mute(state)
  defp handle_command(%__MODULE__{} = state, "/debug"), do: toggle_debug(state)

  defp handle_command(%__MODULE__{} = state, other),
    do: %{state | status: "Unknown command: #{other}"}
end
