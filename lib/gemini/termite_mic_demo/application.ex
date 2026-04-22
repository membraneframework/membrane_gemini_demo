defmodule Gemini.TermiteMicDemo.Application do
  @moduledoc false
  
  use Application

  @impl true
  def start(_type, _args) do
    children = [Gemini.TermiteMicDemo.State]
    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end
end
