defmodule IcmpTest.Mocked.SocketOpenTest do
  use ExUnit.Case

  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  # mocking the process of opening sockets

  test "if the socket created it is instrumented into the process" do
    MockSocket
    |> expect(:open, fn _, _, _ -> {:ok, :socket} end)
    {:ok, _} = Icmp.start(module: MockSocket)
  end

  test "if the socket creation errors, the process is not created" do
    MockSocket
    |> expect(:open, fn _, _, _ -> {:error, :mock_error} end)
    {:error, :mock_error} = Icmp.start(module: MockSocket)
  end
end
