defmodule Gemini.TermiteMicDemo.LoggerHandler do
  @moduledoc false

  @spec adding_handler(:logger.handler_config()) :: {:ok, :logger.handler_config()}
  def adding_handler(config), do: {:ok, config}

  @spec removing_handler(:logger.handler_config()) :: :ok
  def removing_handler(_config), do: :ok

  @spec log(
          %{level: Logger.level(), msg: {:string, iodata()} | {:report, term()} | {:io.format(), [term()]}},
          %{config: %{tui_pid: pid()}}
        ) :: :ok
  def log(%{level: level, msg: msg}, %{config: %{tui_pid: tui_pid}}) do
    text =
      case msg do
        {:string, iodata} -> IO.iodata_to_binary(iodata)
        {:report, report} -> inspect(report, limit: 50)
        {fmt, args} -> :io_lib.format(fmt, args) |> IO.iodata_to_binary()
      end
      |> String.trim()

    send(tui_pid, {:log, level, text})
  end
end
