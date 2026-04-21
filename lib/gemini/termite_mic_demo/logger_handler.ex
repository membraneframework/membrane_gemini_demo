defmodule Gemini.TermiteMicDemo.LoggerHandler do
  def adding_handler(config), do: {:ok, config}
  def removing_handler(_config), do: :ok

  def log(%{level: level, msg: msg}, _config) do
    text =
      case msg do
        {:string, iodata} -> IO.iodata_to_binary(iodata)
        {:report, report} -> inspect(report, limit: 50)
        {fmt, args} -> :io_lib.format(fmt, args) |> IO.iodata_to_binary()
      end
      |> String.trim()

    Gemini.TermiteMicDemo.State.push_log(level, text)
  end
end
