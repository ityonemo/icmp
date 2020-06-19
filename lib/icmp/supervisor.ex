defmodule Icmp.Supervisor do
  use Supervisor

  def start_link(opts), do: Supervisor.start_link(__MODULE__, :ok, opts)

  @impl true
  def init(:ok), do: Supervisor.init([%{
    id: Icmp,
    start: {Icmp, :start_link, [[name: Icmp]]}
  }], strategy: :one_for_one)
end
