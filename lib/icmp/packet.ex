defmodule Icmp.Packet do

  @moduledoc false

  @empty_payload <<0::56 * 8>>

  defstruct [:id,
    type: :request,
    seq: 0,
    payload: @empty_payload
  ]

  @type icmp_types :: :request | :echo_reply

  @type t :: %__MODULE__{
    id: 0..0xFFFF,
    type: icmp_types,
    seq: non_neg_integer,
    payload: binary
  }

  @type_to_code %{request: <<8, 0>>, echo_reply: <<0, 0>>}
  @empty_checksum <<0, 0>>

  #############################################################################
  ## API

  def encode(list) when is_list(list), do: encode(struct(__MODULE__, list))
  def encode(%__MODULE__{type: type, id: id, seq: seq, payload: payload}) do
    insert_checksum(
      <<@type_to_code[type] :: binary, @empty_checksum :: binary,
        id :: 16, seq :: 16, payload :: binary>>)
  end

  @spec behead(binary) :: {:ok, binary}
  @doc """
  strips the IPv4 header from the incoming data
  """
  def behead(<<_version_ihl, _dscp_ecn, _length::16, _id::16,
               _flags_frag_offset::16, _ttl, _proto, _header_cksum::16,
               _src_ip::32, _dst_ip::32>> <> payload) do
    {:ok, payload}
  end

  @spec decode(binary) :: {:ok, t} | {:error, :packet}
  @doc """
  decodes an icmp packet and converts it to a structured datatype.
  """
  def decode(<<0, 0, _checksum :: 16, id :: 16, seq :: 16, payload :: binary>>) do
    {:ok, %__MODULE__{type: :echo_reply, seq: seq, id: id, payload: payload}}
  end
  def decode(_), do: {:error, :packet}

  #############################################################################
  ## helper functions: encode

  defp insert_checksum(payload = <<first::16, @empty_checksum>> <> rest) do
    <<first::16, sum16compl(payload) :: 16, rest :: binary>>
  end

  defp sum16compl(binary, sum16 \\ 0)
  defp sum16compl(<<first::16>>, sum16) do
    Bitwise.~~~(first + sum16)
  end
  defp sum16compl(<<first::16>> <> rest, sum16) do
    sum16compl(rest, first + sum16)
  end

  ##############################################################################
  ## tools:  hash

  @spec hash(term) :: 0..0xFFFF
  def hash(term) do
    import Bitwise
    :erlang.phash2(term) &&& 0xFFFF
  end

end
