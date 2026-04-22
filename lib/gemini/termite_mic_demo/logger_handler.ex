defmodule Gemini.TermiteMicDemo.LoggerHandler do
  @moduledoc false
  
  # TODO: remove _config arg, maybe even this module entirely
  @spec log(%{
    level: Logger.level(),
    msg: {:string, iodata()} | {:report, any()} | {:io.format(), [term()]}
  }, any()) :: :ok
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
