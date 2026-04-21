defmodule Mix.Tasks.Demo do
  use Mix.Task

  @shortdoc "Run the Gemini Termite TUI microphone demo"

  @requirements ["app.start"]

  def run(_args) do
    Gemini.TermiteMicDemo.App.start()
  end
end
