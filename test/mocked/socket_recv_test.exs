defmodule IcmpTest.Mocked.SocketRecvTest do
  use ExUnit.Case

  import Mox
  import IP
  @cloudflare ~i"1.1.1.1"
  @empty_payload <<0::56 * 8>>

  alias Icmp.Packet

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

  def add_ip_header(packet) do
    IO.iodata_to_binary([<<0::8 * 20>>, packet])
  end

  @tag :one
  test "happy path with sane packet result" do
    test_pid = self()

    MockSocket
    |> expect(:sendto, fn :socket, <<8, 0>> <> _, ~i"1.1.1.1:0" ->
      send(test_pid, :sent)
      :ok
    end)

    {:ok, srv} = Icmp.start(module: MockSocket)

    spawn fn ->
      # since we haven't instrumented a recvfrom, it should pang, with timeout.
      assert :pong = Icmp.ping(srv, @cloudflare, 100)
      send(test_pid, :done)
    end

    assert_receive :sent

    # pull some important information from the internal state of the packet
    assert {:socket, state = %{select: :mock_select}} =
      Icmp.info(srv)

    # grab the id value.
    assert [{id, %{ip: @cloudflare, seq: 0}}] =
      Enum.filter(state, fn {k, _v} -> is_integer(k) end)

    packet = %Packet{type: :echo_reply, seq: 0, id: id, payload: @empty_payload}
    |> Packet.encode
    |> add_ip_header

    # instrument a packet into the recvfrom.
    MockSocket
    |> expect(:recvfrom, fn :socket, [], :nowait ->
      {:ok, {~i"1.1.1.1:0", packet}}
    end)

    # send the socket a select message to indicate that data are ready to go.
    send(srv, {:"$socket", :socket, :select, :mock_select})

    receive do :done -> :ok end
  end
end
