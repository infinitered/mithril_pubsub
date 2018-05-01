# Mithril.PubSub

[![Build Status](https://travis-ci.org/infinitered/mithril_pubsub.svg?branch=master)](https://travis-ci.org/infinitered/mithril_pubsub)

PubSub and Presence implementations that don't create a dependency between your
business logic and your Phoenix web app.

## Why

Phoenix 1.3 and higher encourages us to keep our business logic separate from our
Phoenix web application. PubSub topics, event handling, and presence **are often 
core business logic concerns**.

The current architecture of Phoenix forces your business logic to call 
`Phoenix.Endpoint` to broadcast events to websockets. Presence information about
a topic is likewise tied up in a web app `Presence` module.

This makes your business logic depend on your Phoenix application, rather
than the other way around.

![Logic depends on Phoenix](assets/phoenix_dependency.png)

`Mithril.PubSub` allows you to reverse that dependency, making your
Phoenix app, Endpoint, and Channels depend on your business logic instead.

![Phoenix depends on Logic](assets/logic_dependency.png)

## Included Modules

Read their documentation for more information.

- `Mithril.PubSub`
- `Mithril.PubSub.Subscriber`
- `Mithril.Presence`

## How It Works

Phoenix has already extracted its PubSub and CRDT-based presence tracking 
system to a small package called [phoenix_pubsub][pp]. Sadly, 
`Phoenix.Presence` is not in this package, because it relies on 
Phoenix-specific data types, such as `Phoenix.Socket.Message` and 
`Phoenix.Socket.Broadcast`.

However, `Phoenix.Presence` is only a tiny wrapper around `Phoenix.Tracker`,
which _is_ part of [phoenix_pubsub][pp].

It was therefore very easy to fork `Phoenix.Presence` to remove its reliance
on Phoenix-only data-types, producing `Mithril.Presence`.

Likewise, `Mithril.PubSub` is a lightweight wrapper around `Phoenix.PubSub`.

## Installation

The package can be installed by adding `mithril_pubsub` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mithril_pubsub, github: "infinitered/mithril_pubsub"}
  ]
end
```

## Usage

Define a `PubSub` module in your logic application:

```elixir
defmodule MyApp.PubSub do
  use Mithril.PubSub, otp_app: :my_app
end
```

Configure that `PubSub` module to use an adapter:

```elixir
# config/config.exs
config :my_app, MyApp.PubSub,
  adapter: Phoenix.PubSub.PG2,
  pool_size: 5
```

If using Phoenix, replace the `:pubsub` option on your Endpoint configuration
with your new `PubSub` module:

```elixir
config :my_app_web, MyAppWeb.Endpoint,
  pubsub: [name: MyApp.PubSub]
```

Update your `lib/my_app_web.ex` or `apps/my_app_web/lib/my_app_web.ex` file to
pull in functions from your new `PubSub` module instead of the defaults from
`Phoenix.Channel`:

```elixir
def channel do
  quote do
    use Phoenix.Channel

    import Phoenix.Channel,
      except: [
        broadcast: 3,
        broadcast!: 3,
        broadcast_from: 3,
        broadcast_from!: 3
      ]

    import MyApp.PubSub,
      only: [
        broadcast: 2,
        broadcast!: 2,
        broadcast_from: 2,
        broadcast_from!: 2
      ]
  end
end
```

Then, broadcast regular Elixir tuple messages over your PubSub within your channel:

```elixir
defmodule MyAppWeb.RoomChannel do
  use MyAppWeb, :channel

  alias MyApp.Presence

  def join("room:lobby", payload, socket) do
    {:ok, socket}
  end

  def handle_in("message", message, socket) do
    # Broadcasts the event as a simple Erlang term, instead of a
    # custom Phoenix one. This allows listeners in the business
    # logic app to easily subscribe to them.
    broadcast!(socket, {:message, message})
    {:noreply, socket}
  end

  # Channels will receive messages for their topic from the PubSub
  # server as regular Erlang process messages.
  #
  # It's up to each channel to handle these messages and forward
  # them on to the websocket using `Phoenix.Channel.push/3`.
  def handle_info({:message, message}, socket) do
    push(socket, "message", message)
    {:noreply, socket}
  end
end
```

## Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc).

[pp]: https://hexdocs.pm/phoenix_pubsub
