defmodule Icmp do

  defmodule Entry do
    @moduledoc false
    # just a struct that describes what an icmp wait entry looks like.

    @enforce_keys [:ip, :seq, :from, :ttl]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
      ip: IP.t,
      seq: 0..0xFFFF,
      from: GenServer.from,
      ttl: DateTime.t
    }
  end

  @type state :: %{
    optional(0..0xFFFF) => Entry.t,
    select: reference(),
    module: module(),
  }

  @init_state %{select: nil, module: :socket}

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
  def init_it(parent, _, _, name, args, _opts) do
    name && Process.register(self(), name)
    Process.flag(:trap_exit, true)

    state = args
    |> Keyword.take([:module])
    |> Enum.into(@init_state)

    case state.module.open(:inet, :raw, :icmp) do
      {:ok, socket} ->
        :proc_lib.init_ack(parent, {:ok, self()})
        Process.monitor(parent)
        do_loop(socket, state)
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

  def do_loop(socket, state) do
    msg_or_icmp(socket, clear_dead(state))
  end

  defp msg_or_icmp(socket, state) do
    receive do
      msg ->
        handle_msg(msg, socket, state)
    after
      0 ->
        check_socket(socket, state)
    end
  end

  defp check_socket(socket, state! = %{module: module}) do
    with {:ok, {ip, data}} <- module.recvfrom(socket, [], :nowait),
         {:ok, state!} <- handle_ping(ip, data, state!) do
      do_loop(socket, state!)
    else
      {:select, select_ref} ->
        do_loop(socket, Map.put(state!, :select, select_ref))
      _error ->
        do_loop(socket, state!)
    end
  end

  defp handle_msg({:"$socket", socket, :select, ref},
                  socket,
                  state = %{select: {_, _, ref}}) do
    # return to the socket loop
    check_socket(socket, Map.delete(state, :select))
  end
  defp handle_msg({:"$socket", _, _, _}, socket, state) do
    # drop unidentifiable socket messages.
    do_loop(socket, state)
  end
  defp handle_msg({:"$gen_call", from, {:ping, ip, seq, timeout}}, socket, state) do
    packet = %Packet{id: Packet.hash(from), seq: seq}
    |> Packet.encode()

    case state.module.sendto(socket, packet, addr(ip)) do
      :ok ->
        entry = %Entry{
          from: from,
          ip: ip,
          seq: seq,
          ttl: DateTime.add(DateTime.utc_now(), timeout, :millisecond)
        }

        do_loop(socket, Map.put(state, Packet.hash(from), entry))
      _error ->
        do_loop(socket, state)
    end
  end
  defp handle_msg({:EXIT, _, _}, socket, state) do
    # trap exits and clean up the socket gracefully.
    state.module.close(socket)
  end

  defp handle_ping(sockaddr, data, state) when is_binary(data) do
    # TODO: change this to a `with` chain.
    packet = data
    |> Packet.behead
    |> Packet.decode

    if packet do
      handle_ping(sockaddr.addr, packet, state)
    else
      {:error, :foo}
    end
  end

  defp handle_ping(ip, %{id: id, seq: seq, type: :echo_reply}, state)
      when is_map_key(state, id) do
    # verify that everything else matches.
    entry = state[id]
    cond do
      ip != entry.ip ->
        {:error, :ip}
      seq != entry.seq ->
        {:error, :seq}
      true ->
        GenServer.reply(entry.from, :pong)
    end
    {:ok, Map.delete(state, id)}
  end
  defp handle_ping(_, _, state), do: {:ok, state}

  #defp hibernate(socket, state) do
  #  :proc_lib.hibernate(__MODULE__, :do_loop, [socket, state])
  #end

  defp addr(ip), do: %IP.SockAddr{
    family: :inet,
    port: 0,
    addr: ip
  }

  defp clear_dead(state) do
    state
    |> Enum.filter(fn {k, v} ->
      is_atom(k) or
      (DateTime.compare(v.ttl, DateTime.utc_now) == :gt)
    end)
    |> Enum.into(%{})
  end
end
