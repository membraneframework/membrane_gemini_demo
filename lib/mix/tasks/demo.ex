defmodule Mix.Tasks.Demo do
  @shortdoc "Run the Gemini Termite TUI microphone demo"
  @moduledoc false

  use Mix.Task

  # Mix.Task behaviour has no PLT info; suppress the spurious callback_info_missing warning.
  @dialyzer :no_behaviours

  @requirements ["app.start"]

  @spec run(any()) :: no_return()
  def run(_args) do
    Gemini.TermiteMicDemo.App.start([])
  end
end
