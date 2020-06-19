defmodule Icmp do

  defmodule Entry do
    @enforce_keys [:ip, :seq, :from, :ttl]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
      ip: IP.t,
      seq: 0..0xFFFF,
      from: GenServer.from,
      ttl: DateTime.t
    }
  end

  @init %{select: nil}

  alias Icmp.Packet
  require IP

  @spec start_link() :: {:ok, pid()} | {:error, term}
  def start_link(opts \\ []) do
    :gen.start(__MODULE__, :link, opts[:name], opts, [])
  end

  @spec start() :: {:ok, pid()} | {:error, term}
  def start(opts \\ []) do
    :gen.start(__MODULE__, :nolink, opts[:name], opts, [])
  end

  # :gen callback
  def init_it(parent, _, _, name, _args, _opts) do
    name && Process.register(self(), name)
    Process.flag(:trap_exit, true)
    case :socket.open(:inet, :raw, :icmp) do
      {:ok, socket} ->
        :proc_lib.init_ack(parent, {:ok, self()})
        Process.monitor(parent)
        do_loop(socket, @init)
      error = {:error, _} ->
        :proc_lib.init_ack(parent, error)
    end
  end

  # API
  def ping(icmp \\ __MODULE__, addr, timeout \\ 5000, seq \\ nil) do
    do_ping(icmp, addr, timeout, seq)
  end

  def do_ping(icmp, addr, timeout, seq) when is_binary(addr) do
    do_ping(icmp, String.to_charlist(addr), timeout, seq)
  end

  def do_ping(icmp, addr, timeout, seq) when is_list(addr) do
    case :inet.getaddrs(addr, :inet) do
      {:ok, []} -> {:error, :enoaddr}
      {:ok, lst} when is_list(lst) ->
        do_ping(icmp, hd(lst), timeout, seq)
      error -> error
    end
  end

  def do_ping(icmp, addr, timeout, seq) when IP.is_ipv4(addr) do
    res = GenServer.call(icmp, {:ping, addr, seq || 0, timeout}, timeout)
    if seq, do: {res, seq}, else: res
  catch
    :exit, {:timeout, _} ->
      if seq, do: {:pang, seq}, else: :pang
  end

  def do_loop(socket, targets) do
    msg_or_icmp(socket, clear_dead(targets))
  end

  defp msg_or_icmp(socket, targets) do
    receive do
      msg ->
        handle_msg(msg, socket, targets)
    after
      0 ->
        check_socket(socket, targets)
    end
  end

  defp check_socket(socket, targets!) do
    with {:ok, {ip, data}} <- :socket.recvfrom(socket, [], :nowait),
         {:ok, targets!} <- handle_ping(ip, data, targets!) do
      do_loop(socket, targets!)
    else
      {:select, select_ref} ->
        do_loop(socket, Map.put(targets!, :select, select_ref))
      _error ->
        do_loop(socket, targets!)
    end
  end

  defp handle_msg({:"$socket", socket, :select, ref},
                  socket,
                  targets = %{select: {_, _, ref}}) do
    # return to the socket loop
    check_socket(socket, Map.delete(targets, :select))
  end
  defp handle_msg({:"$socket", _, _, _}, socket, targets) do
    # drop unidentifiable socket messages.
    do_loop(socket, targets)
  end
  defp handle_msg({:"$gen_call", from, {:ping, ip, seq, timeout}}, socket, targets) do
    packet = %Packet{id: Packet.hash(from), seq: seq}
    |> Packet.encode()

    case :socket.sendto(socket, packet, addr(ip)) do
      :ok ->
        entry = %Entry{
          from: from,
          ip: ip,
          seq: seq,
          ttl: DateTime.add(DateTime.utc_now(), timeout, :millisecond)
        }

        do_loop(socket, Map.put(targets, Packet.hash(from), entry))
      _error ->
        do_loop(socket, targets)
    end
  end
  defp handle_msg({:EXIT, _, _}, socket, _) do
    # trap exits and clean up the socket gracefully.
    :socket.close(socket)
  end

  defp handle_ping(sockaddr, data, targets) when is_binary(data) do
    # TODO: change this to a `with` chain.
    packet = data
    |> Packet.behead
    |> Packet.decode

    if packet do
      handle_ping(sockaddr.addr, packet, targets)
    else
      {:error, :foo}
    end
  end

  defp handle_ping(ip, %{id: id, seq: seq, type: :echo_reply}, targets)
      when is_map_key(targets, id) do
    # verify that everything else matches.
    entry = targets[id]
    cond do
      ip != entry.ip ->
        {:error, :ip}
      seq != entry.seq ->
        {:error, :seq}
      true ->
        GenServer.reply(entry.from, :pong)
    end
    {:ok, Map.delete(targets, id)}
  end
  defp handle_ping(_, _, targets), do: {:ok, targets}

  #defp hibernate(socket, targets) do
  #  :proc_lib.hibernate(__MODULE__, :do_loop, [socket, targets])
  #end

  defp addr(ip), do: %IP.SockAddr{
    family: :inet,
    port: 0,
    addr: ip
  }

  defp clear_dead(targets) do
    targets
    |> Enum.filter(fn {k, v} ->
      is_atom(k) or
      (DateTime.compare(v.ttl, DateTime.utc_now) == :gt)
    end)
    |> Enum.into(%{})
  end
end
