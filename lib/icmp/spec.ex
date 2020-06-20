defmodule Icmp.Spec do
  @moduledoc false
  # just a helper module to get ICMP's ping spec to be correct.

  @pong Application.compile_env(:icmp, :pong, :pong)
  @pang Application.compile_env(:icmp, :pang, :pang)

  defmacro ping_spec do
    pong = @pong
    pang = @pang
    spec3 = {:@, [context: Elixir, import: Kernel],
     [
       {:spec, [context: Elixir],
        [
          {:"::", [],
           [
             {:ping, [], [
               named(:host,
                     {:|, [], [{{:., [], [{:__aliases__, [alias: false], [:IP]}, :addr]}, [], []},
                               {{:., [], [{:__aliases__, [alias: false], [:String]}, :t]}, [], []}]}),
               named(:timeout, {:timeout, [], []}),
               named(:srv, {{:., [], [{:__aliases__, [alias: false], [:GenServer]}, :server]}, [], []}),
             ]},
             {:|, [], [pong, {:|, [], [pang, {:error, {:any, [], Elixir}}]}]}
           ]}
        ]}
     ]}

    spec4 = {:@, [context: Elixir, import: Kernel],
     [
       {:spec, [context: Elixir],
        [
          {:"::", [],
           [
             {:ping_seq, [], [
               named(:host,
                 {:|, [], [{{:., [], [{:__aliases__, [alias: false], [:IP]}, :addr]}, [], []},
                           {{:., [], [{:__aliases__, [alias: false], [:String]}, :t]}, [], []}]}),
               named(:seq, {:non_neg_integer, [], []}),
               named(:timeout, {:timeout, [], []}),
               named(:srv, {{:., [], [{:__aliases__, [alias: false], [:GenServer]}, :server]}, [], []})
             ]},
             {:|, [], [
               {pong, {:non_neg_integer, [], []}},
               {:|, [], [{pang, {:non_neg_integer, [], []}},
                         {:error, {:any, [], Elixir}}]}]}
           ]}
        ]}
     ]}
    quote do
      unquote(spec3)
      unquote(spec4)
    end
  end

  defp named(name, ast) do
    {:"::", [], [{name, [], Elixir}, ast]}
  end

end
