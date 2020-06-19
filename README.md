# Icmp

Icmp Ping server for Elixir

## Usage

- Only tested on Linux.
- You must run the following on your `beam.smp` before using this library:

  ```bash
  sudo setcap cap_net_raw=+ep /path/to/beam.smp
  ```

  Note that the path may be different if you're using a global elixir installation, an elixir installation managed by `asdf`, or a production
  release deployed using `mix release`.

- Provides an *ICMP service* by default.  You may disable this service and
  manage and supervise your ICMP servers manually by setting

  ```elixir
  config :icmp, active: false
  ```

  in your configuration.

- IPV4 only (for now)

## Installation

The package can be installed by adding `icmp` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:icmp, "~> 0.1.0"}
  ]
end
```

Docs can be found at [https://hexdocs.pm/icmp](https://hexdocs.pm/icmp).

