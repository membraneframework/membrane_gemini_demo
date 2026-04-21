defmodule Gemini.TermiteMicDemo.App do
  import Bitwise

  alias Termite.{Screen, Style, Terminal}

  @waveform_char_height 8

  # Minimum amplitude used for waveform normalization. Raising this prevents quiet
  # noise from being amplified to fill the full waveform height.
  # 1.0e-4 = normalize everything (very sensitive); 0.05 = ignore signals below 5% full scale.
  @noise_floor 0.005

  def start do
    :logger.remove_handler(:default)
    :logger.add_handler(:tui, Gemini.TermiteMicDemo.LoggerHandler, %{})

    {:ok, _supervisor, pipeline} =
      Membrane.Pipeline.start_link(Gemini.TermiteMicDemo.Pipeline, [])

    terminal = Terminal.start()

    term =
      terminal
      |> Screen.run_escape_sequence(:screen_alt)
      |> Screen.run_escape_sequence(:cursor_hide)

    state = %{
      term: term,
      input_buffer: "",
      status: "Ready. Speak into your mic or type text to send to Gemini.",
      pipeline_pid: pipeline,
      debug_mode: false,
      muted: false
    }

    term = Screen.run_escape_sequence(term, :screen_clear)
    loop(%{state | term: term})
  end

  defp loop(state) do
    state = render(state)

    case Terminal.poll(state.term, 50) do
      {:data, "\r"} -> handle_submit(state) |> loop()
      {:data, "\n"} -> handle_submit(state) |> loop()
      {:data, <<127>>} -> delete_char(state) |> loop()
      {:data, <<23>>} -> delete_word(state) |> loop()
      {:data, <<21>>} -> clear_buffer(state) |> loop()
      {:data, "d"} when state.input_buffer == "" -> toggle_debug(state) |> loop()
      {:data, "m"} when state.input_buffer == "" -> toggle_mute(state) |> loop()
      {:data, char} when byte_size(char) == 1 -> add_char(state, char) |> loop()
      {:data, _data} -> loop(state)
      :timeout -> loop(state)
      _other -> loop(state)
    end
  end

  defp term_width do
    case :io.columns() do
      {:ok, w} -> w
      _ -> 80
    end
  end

  defp term_height do
    case :io.rows() do
      {:ok, h} -> h
      _ -> 24
    end
  end

  defp render(state) do
    shared = Gemini.TermiteMicDemo.State.get_state()
    {color, mic_text} = mic_status_info(state.muted)
    w = term_width()
    waveform_char_width = max(div(w - 4, 2), 10)

    history_section =
      if state.debug_mode do
        available_lines = max(term_height() - 23, 0)

        entries =
          shared.event_history
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
        render_waveforms(shared.mic_samples, shared.gemini_samples, waveform_char_width) <>
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

  defp with_separators([]), do: []
  defp with_separators([_] = list), do: list

  defp with_separators([a, b | rest]) do
    if entry_kind(a) != entry_kind(b),
      do: [a, :separator | with_separators([b | rest])],
      else: [a | with_separators([b | rest])]
  end

  defp entry_kind({:log, _, _}), do: :log
  defp entry_kind({:event, _}), do: :event

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

  defp chunk_text(text, width) do
    text
    |> String.graphemes()
    |> Enum.chunk_every(max(width, 1))
    |> Enum.map(&Enum.join/1)
  end

  defp log_color(:debug), do: 4
  defp log_color(:info), do: 7
  defp log_color(:warning), do: 3
  defp log_color(:error), do: 1
  defp log_color(_), do: 1

  defp render_waveforms(left, right, char_width) do
    left_rows = build_braille_waveform(left, @waveform_char_height, char_width)
    right_rows = build_braille_waveform(right, @waveform_char_height, char_width)

    Enum.zip(left_rows, right_rows)
    |> Enum.map(fn {l, r} ->
      (Style.foreground(6) |> Style.render_to_string(l)) <>
        "  " <>
        (Style.foreground(5) |> Style.render_to_string(r)) <>
        "\n"
    end)
    |> Enum.join("")
  end

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
      0..(char_width - 1)
      |> Enum.map(fn char_col ->
        value =
          for dot_col <- 0..1,
              local_row <- 0..3,
              MapSet.member?(active_dots, {char_col, char_row, dot_col, local_row}),
              reduce: 0 do
            acc -> acc + (1 <<< braille_bit(dot_col, local_row))
          end

        <<0x2800 + value::utf8>>
      end)
      |> Enum.join("")
    end
  end

  defp pad_samples(samples, target) do
    n = length(samples)

    padded =
      if n >= target,
        do: Enum.take(samples, -target),
        else: List.duplicate(0.0, target - n) ++ samples

    max_amp = padded |> Enum.map(&abs/1) |> Enum.max() |> max(@noise_floor)
    Enum.map(padded, fn s -> s / max_amp end)
  end

  defp fill_dots(set, char_col, dot_col, from_row, to_row) do
    Enum.reduce(min(from_row, to_row)..max(from_row, to_row), set, fn abs_row, acc ->
      MapSet.put(acc, {char_col, div(abs_row, 4), dot_col, rem(abs_row, 4)})
    end)
  end

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

  defp mic_status_info(false), do: {2, "MIC LIVE - Speaking into microphone"}
  defp mic_status_info(true), do: {1, "MIC MUTED - Microphone is silenced"}

  defp toggle_debug(state), do: %{state | debug_mode: !state.debug_mode}

  defp toggle_mute(state) do
    send(state.pipeline_pid, :toggle_mute)
    new_muted = !state.muted
    status = if new_muted, do: "Mic muted", else: "Mic unmuted"
    %{state | muted: new_muted, status: status}
  end

  defp delete_char(state),
    do: %{state | input_buffer: String.slice(state.input_buffer, 0..-2//1)}

  defp delete_word(state) do
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

  defp clear_buffer(state), do: %{state | input_buffer: ""}

  defp add_char(state, char), do: %{state | input_buffer: state.input_buffer <> char}

  defp handle_submit(state) do
    input = String.trim(state.input_buffer)

    if input == "" do
      state
    else
      {message, description} =
        cond do
          input == "/clear" -> {:reset_session, "Reset session"}
          true -> {{:text, input}, "Sent to Gemini: #{input}"}
        end

      send(state.pipeline_pid, message)
      %{state | input_buffer: "", status: description}
    end
  end

  defp cleanup_and_exit(state) do
    state.term
    |> Screen.run_escape_sequence(:cursor_show)
    |> Screen.run_escape_sequence(:screen_alt_exit)
    |> Screen.run_escape_sequence(:screen_clear)

    :timer.sleep(10)
    System.halt()
  end
end
