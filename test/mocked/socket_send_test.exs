defmodule IcmpTest.Mocked.SocketSendTest do
  use ExUnit.Case

  import Mox
  import IP
  @cloudflare ~i"1.1.1.1"

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    # pause with a select in place.
    MockSocket
    |> expect(:open, fn _, _, _ -> {:ok, :socket} end)
    |> stub(:recvfrom, fn :socket, [], :nowait -> {:select, :mock_select} end)
    |> stub(:close, fn _ -> :ok end)
    :ok
  end

  # mocking the process of opening sockets

  test "if there's data waiting, it gets processed." do
    test_pid = self()

    MockSocket
    |> expect(:sendto, fn :socket, <<8, 0>> <> _, ~i"1.1.1.1:0"->
      send(test_pid, :sent)
      :ok
    end)

    {:ok, srv} = Icmp.start(module: MockSocket)

    spawn fn ->
      # since we haven't instrumented a recvfrom, it should pang, with timeout.
      assert :pang = Icmp.ping(@cloudflare, 100, srv)
      send(test_pid, :done)
    end

    assert_receive :sent

    # the icmp server should be able to still respend to messages while
    # waiting for the ping response
    assert {:socket, state = %{select: :mock_select}} =
      Icmp.info(srv)

    # check to make sure the internal state entry is allreet
    assert [{_, %{ip: @cloudflare, seq: 0}}] =
      Enum.filter(state, fn {k, _v} -> is_integer(k) end)

    receive do :done -> :ok end
  end

  test "if the send errors, the icmp server crashes." do
    test_pid = self()

    MockSocket
    |> expect(:sendto, fn :socket, <<8, 0>> <> _, ~i"1.1.1.1:0"->
      {:error, :mock_error}
    end)

    {:ok, srv} = Icmp.start(module: MockSocket)

    spawn fn ->
      # since we haven't instrumented a recvfrom, it should pang, with timeout.
      assert {:error, _} = Icmp.ping(@cloudflare, 100, srv)
      send(test_pid, :done)
    end

    receive do :done -> :ok end

    refute Process.alive?(srv)
  end

end
