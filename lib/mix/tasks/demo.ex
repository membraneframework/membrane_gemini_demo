defmodule Mix.Tasks.Demo do
  @shortdoc "Run the Gemini Termite TUI microphone demo"
  @moduledoc false

  use Mix.Task

  @requirements ["app.start"]

  @spec run(any()) :: no_return()
  def run(_args) do
    Gemini.TermiteMicDemo.App.start()
  end
end
