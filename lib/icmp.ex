defmodule Icmp do

  @moduledoc """
  An OTP-supervised ping (ICMP Echo) server written in pure elixir.

  ## Prerequisites

  Currently, this only supports ICMP socket opened in `:raw` mode.  In
  linux, to use this feature, you must have your `beam.smp` executable
  set with raw capabilities:

  ```bash
  sudo setcap cap_net_raw=+ep /path/to/beam.smp
  ```

  Note that this path may depend on if you installed elixir globally, via
  a manager such as `asdf`, or if you are running off of a release artifact.

  ## Usage

  The Icmp library starts a global ICMP Echo server named `Icmp` in the
  VM supervision tree;  To use this library, call `Icmp.ping/1`

  ## Other options

  The Echo server is designed to emit `:pong` on success and
  `:pang` on failure, to be consistent with the symbols emitted by the
  `Node` module and erlang distribution.  However, these symbols can be
  difficult to distinguish in a code setting, leading to errors.  If you
  would like to change the nature of these values, you may set them
  in config:

  ```elixir
  config :icmp, pong: <your symbol>,
                pang: <your symbol>
  ```

  """

  @pong Application.compile_env(:icmp, :pong, :pong)
  @pang Application.compile_env(:icmp, :pang, :pang)

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
  @spec start_link(keyword) :: {:ok, pid()} | {:error, term}
  @doc """
  starts a standalone ICMP Echo server.

  ### Options

  - `:name` assigns a name to the server.
  """
  def start_link(opts \\ []) do
    :gen.start(__MODULE__, :link, opts[:name], opts, [])
  end

  @spec start() :: {:ok, pid()} | {:error, term}
  @spec start(keyword) :: {:ok, pid()} | {:error, term}
  @doc """
  like `start_link/1`, but without linking to the calling process.
  """
  def start(opts \\ []) do
    :gen.start(__MODULE__, :nolink, opts[:name], opts, [])
  end

  @doc false
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

  #############################################################################
  ## PROCESS LOOP

  @doc false
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
        hibernate(socket, Map.put(state!, :select, select_ref))
      _error ->
        do_loop(socket, state!)
    end
  end

  #############################################################################
  ## API
  require Icmp.Spec
  Icmp.Spec.ping_spec()
  @doc """
  Issues an ICMP Echo request to `host`.

  Responds with `#{inspect @pong}` on success, and `#{inspect @pang}` on
  failure to recieve a reply within the specified `timeout`.
  """
  def ping(addr, timeout \\ 5000, srv \\ __MODULE__) do
    do_ping(srv, addr, timeout, nil)
  end

  @doc """
  Issues an ICMP Echo request to `host`, with a sequence number.

  Responds with `{#{inspect @pong}, seq}` on success, and `{#{inspect @pang}, seq}` on
  failure to recieve a reply within the specified `timeout`.
  """
  def ping_seq(addr, seq, timeout \\ 5000, srv \\ __MODULE__) do
    do_ping(srv, addr, timeout, seq)
  end

  defp do_ping(srv, host, timeout, seq) when is_binary(host) do
    do_ping(srv, String.to_charlist(host), timeout, seq)
  end
  defp do_ping(srv, host, timeout, seq) when is_list(host) do
    case :inet.getaddrs(host, :inet) do
      {:ok, []} -> {:error, :enoaddr}
      {:ok, lst} when is_list(lst) ->
        do_ping(srv, hd(lst), timeout, seq)
      error -> error
    end
  end
  defp do_ping(srv, addr, timeout, seq) when IP.is_ipv4(addr) do
    res = GenServer.call(srv, {:ping, addr, seq || 0, timeout}, timeout)
    if seq, do: {res, seq}, else: res
  catch
    :exit, {:timeout, _} ->
      if seq, do: {:pang, seq}, else: @pang
    :exit, error ->
      {:error, error}
  end

  defp ping_impl(from, ip, seq, timeout, socket, state) do
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
        state.module.close(socket)
    end
  end

  @doc false
  # private "info" method to query the contents of the server.
  def info(srv), do: GenServer.call(srv, :info)

  defp info_impl(from, socket, state) do
    GenServer.reply(from, {socket, state})
  end

  #######################################################################
  ## ROUTER

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
    ping_impl(from, ip, seq, timeout, socket, state)
  end
  defp handle_msg({:"$gen_call", from, :info}, socket, state) do
    info_impl(from, socket, state)
    do_loop(socket, state)
  end
  defp handle_msg({:EXIT, _, _}, socket, state) do
    # trap exits and clean up the socket gracefully.
    state.module.close(socket)
  end

  #######################################################################

  defp handle_ping(sockaddr, data, state) when is_binary(data) do
    with {:ok, packet_bin} <- Packet.behead(data),
         {:ok, packet}     <- Packet.decode(packet_bin) do
      handle_ping(sockaddr.addr, packet, state)
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
        GenServer.reply(entry.from, @pong)
    end
    {:ok, Map.delete(state, id)}
  end
  defp handle_ping(_, _, state), do: {:ok, state}

  defp hibernate(socket, state) do
    :proc_lib.hibernate(__MODULE__, :do_loop, [socket, state])
  end

  #######################################################################

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
