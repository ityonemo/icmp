defmodule SocketApi do
  @moduledoc false

  # api definition that mimics erlang's :socket module, or, really,
  # just enough of the :socket module to be able to make a mock module
  # using the Mox library.

  @callback open(:socket.domain, :socket.type, :socket.protocol)
    :: {:ok, :socket.socket} | {:error, :socket.errcode()}
  @callback sendto(:socket.socket, binary, :socket.sockaddr())
    :: :ok | {:error, :socket.errcode | :closed | :timeout | integer}
  @callback recvfrom(:socket.socket, [], :nowait)
    :: {:ok, {:socket.sockaddr, binary}} |
       {:select, :socket.select_info()} |
       {:error, :socket.errcode | :closed | :timeout}
  @callback close(:socket.socket) :: :socket.errcode | :closed | :timeout

end

Mox.defmock(MockSocket, for: SocketApi)
