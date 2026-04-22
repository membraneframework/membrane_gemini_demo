defmodule Gemini.TermiteMicDemo.App do
  @moduledoc false

  import Bitwise

  alias Termite.{Screen, Style, Terminal}

  @waveform_char_height 8
  @noise_floor 0.005
  @max_history 200

  @type event_entry ::
          {:event, String.t()}
          | {:log, Logger.level(), String.t()}

  @type t :: %__MODULE__{
          term: term(),
          input_buffer: String.t(),
          status: String.t(),
          pipeline_pid: pid(),
          debug_mode: boolean(),
          muted: boolean(),
          mic_samples: [float()],
          gemini_samples: [float()],
          input_transcript: String.t(),
          output_transcript: String.t(),
          thinking: String.t(),
          last_event: String.t(),
          event_history: [event_entry()]
        }

  defstruct [
    :term,
    :pipeline_pid,
    input_buffer: "",
    status: "Ready. Speak into your mic or type text to send to Gemini.",
    debug_mode: false,
    muted: false,
    mic_samples: [],
    gemini_samples: [],
    input_transcript: "",
    output_transcript: "",
    thinking: "",
    last_event: "",
    event_history: []
  ]

  @spec start() :: no_return()
  def start do
    tui_pid = self()

    :logger.remove_handler(:default)
    :logger.add_handler(:tui, Gemini.TermiteMicDemo.LoggerHandler, %{config: %{tui_pid: tui_pid}})

    {:ok, _supervisor, pipeline} =
      Membrane.Pipeline.start_link(Gemini.TermiteMicDemo.Pipeline, tui_pid: tui_pid)

    terminal = Terminal.start()

    term =
      terminal
      |> Screen.run_escape_sequence(:screen_alt)
      |> Screen.run_escape_sequence(:cursor_hide)
      |> Screen.run_escape_sequence(:screen_clear)

    loop(%__MODULE__{term: term, pipeline_pid: pipeline})
  end

  @spec loop(t()) :: no_return()
  defp loop(state) do
    state =
      state
      |> drain_mailbox()
      |> render()

    state
    |> handle_poll(Terminal.poll(state.term, 50))
    |> loop()
  end

  @spec drain_mailbox(t()) :: t()
  defp drain_mailbox(%__MODULE__{} = state) do
    receive do
      {:mic_samples, samples} ->
        drain_mailbox(%{state | mic_samples: Enum.take(state.mic_samples ++ samples, -200)})

      {:gemini_samples, samples} ->
        drain_mailbox(%{state | gemini_samples: Enum.take(state.gemini_samples ++ samples, -200)})

      {:input_transcript, text} ->
        entry = "Input:   #{text}"
        drain_mailbox(%{state | input_transcript: text, last_event: entry} |> push_history({:event, entry}))

      {:output_transcript, text} ->
        entry = "Output:  #{text}"
        drain_mailbox(%{state | output_transcript: text, last_event: entry} |> push_history({:event, entry}))

      {:thinking, text} ->
        entry = "Thinking: #{text}"
        drain_mailbox(%{state | thinking: text, last_event: "Thinking..."} |> push_history({:event, entry}))

      {:event, text} ->
        drain_mailbox(%{state | last_event: text} |> push_history({:event, text}))

      :clear_transcripts ->
        drain_mailbox(%{state | output_transcript: "", thinking: ""})

      {:log, level, text} ->
        drain_mailbox(push_history(state, {:log, level, text}))
    after
      0 -> state
    end
  end

  @spec handle_poll(t(), term()) :: t()
  defp handle_poll(state, {:data, "\r"}), do: handle_submit(state)
  defp handle_poll(state, {:data, "\n"}), do: handle_submit(state)
  defp handle_poll(state, {:data, <<127>>}), do: delete_char(state)
  defp handle_poll(state, {:data, <<23>>}), do: delete_word(state)
  defp handle_poll(state, {:data, <<21>>}), do: clear_buffer(state)
  defp handle_poll(state, {:data, "d"}) when state.input_buffer == "", do: toggle_debug(state)
  defp handle_poll(state, {:data, "m"}) when state.input_buffer == "", do: toggle_mute(state)
  defp handle_poll(state, {:data, char}) when byte_size(char) == 1, do: add_char(state, char)
  defp handle_poll(state, {:data, _data}), do: state
  defp handle_poll(state, :timeout), do: state
  defp handle_poll(state, _other), do: state

  @spec term_width() :: pos_integer()
  defp term_width do
    case :io.columns() do
      {:ok, w} -> w
      _error -> 80
    end
  end

  @spec term_height() :: pos_integer()
  defp term_height do
    case :io.rows() do
      {:ok, h} -> h
      _error -> 24
    end
  end

  @spec render(t()) :: t()
  defp render(%__MODULE__{} = state) do
    {color, mic_text} = mic_status_info(state.muted)
    w = term_width()
    waveform_char_width = max(div(w - 4, 2), 10)

    history_section =
      if state.debug_mode do
        available_lines = max(term_height() - 23, 0)

        entries =
          state.event_history
          |> Enum.reverse()
          |> with_separators()
          |> Enum.flat_map(&format_history_entry(w, &1))
          |> Enum.take(-available_lines)

        (Style.bold()
         |> Style.foreground(6)
         |> Style.render_to_string("── Event History #{String.duplicate("─", max(w - 18, 0))}\n")) <>
          Enum.join(entries)
      else
        ""
      end

    frame =
      (Style.bold() |> Style.foreground(color) |> Style.render_to_string("#{mic_text}\n")) <>
        "Status: #{state.status}\n\n" <>
        (Style.foreground(6) |> Style.render_to_string("Mic Input")) <>
        "  " <>
        (Style.foreground(5) |> Style.render_to_string("Gemini\n")) <>
        render_waveforms(state.mic_samples, state.gemini_samples, waveform_char_width) <>
        "\n" <>
        (Style.bold() |> Style.render_to_string("gemini> ")) <>
        "#{state.input_buffer}█\n\n" <>
        (Style.foreground(4)
         |> Style.render_to_string("m=mute | d=debug\n")) <>
        history_section <>
        "\e[J"

    term =
      state.term
      |> Screen.run_escape_sequence(:cursor_move, [0, 0])
      |> Screen.write(String.replace(frame, "\n", "\e[K\n"))

    %{state | term: term}
  end

  @spec push_history(t(), event_entry()) :: t()
  defp push_history(%__MODULE__{} = state, entry),
    do: %{state | event_history: Enum.take([entry | state.event_history], @max_history)}

  @spec with_separators([event_entry() | :separator]) :: [event_entry() | :separator]
  defp with_separators([]), do: []
  defp with_separators([_entry] = list), do: list

  defp with_separators([a, b | rest]) do
    if entry_kind(a) != entry_kind(b),
      do: [a, :separator | with_separators([b | rest])],
      else: [a | with_separators([b | rest])]
  end

  @spec entry_kind(event_entry()) :: :log | :event
  defp entry_kind({:log, _level, _text}), do: :log
  defp entry_kind({:event, _text}), do: :event

  @spec format_history_entry(pos_integer(), event_entry() | :separator) :: [iodata()]
  defp format_history_entry(_w, :separator), do: ["\n"]

  defp format_history_entry(w, {:event, text}) do
    text
    |> String.replace("\n", " ")
    |> chunk_text(max(w - 2, 1))
    |> Enum.map(&[Style.foreground(2) |> Style.render_to_string("  " <> &1), "\n"])
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
  defp toggle_debug(%__MODULE__{} = state), do: %{state | debug_mode: !state.debug_mode}

  @spec toggle_mute(t()) :: t()
  defp toggle_mute(%__MODULE__{} = state) do
    send(state.pipeline_pid, :toggle_mute)
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
  defp add_char(%__MODULE__{} = state, char), do: %{state | input_buffer: state.input_buffer <> char}

  @spec handle_submit(t()) :: t()
  defp handle_submit(%__MODULE__{} = state) do
    input = String.trim(state.input_buffer)

    if input == "" do
      state
    else
      {message, description} =
        case input do
          "/clear" -> {:reset_session, "Reset session"}
          _input -> {{:text, input}, "Sent to Gemini: #{input}"}
        end

      send(state.pipeline_pid, message)
      %{state | input_buffer: "", status: description}
    end
  end
end
