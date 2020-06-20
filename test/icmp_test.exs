defmodule IcmpTest do
  use ExUnit.Case

  import IP

  @cloudflare ~i"1.1.1.1"
  @localhost ~i"127.0.0.1"
  @google "www.google.com"

  describe "with a new icmp connection" do
    test "we can ping cloudflare 1.1.1.1" do
      {:ok, srv} = Icmp.start_link()
      assert :pong = Icmp.ping(@cloudflare, 5000, srv)
    end

    test "we can ping localhost" do
      {:ok, srv} = Icmp.start_link()
      assert :pong = Icmp.ping(@localhost, 5000, srv)
    end

    test "with a string" do
      {:ok, srv} = Icmp.start_link()
      assert :pong = Icmp.ping(@google, 5000, srv)
    end
  end

  describe "with the global icmp server" do
    test "we can ping cloudflare 1.1.1.1" do
      assert :pong = Icmp.ping(@cloudflare)
    end

    test "we can ping localhost" do
      assert :pong = Icmp.ping(@localhost)
    end

    test "with a string" do
      assert :pong = Icmp.ping(@google)
    end
  end
end
