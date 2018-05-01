defmodule Mithril.PubSub do
  @moduledoc """
  A generic PubSub server, fully compatible with `Phoenix.PubSub`.

  ## Definition

  Define a `PubSub` module in your project:

      defmodule MyApp.PubSub do
        use Mithril.PubSub, otp_app: :my_app
      end

  ## Configuration

  You must configure your adapter with its settings. You may use any
  adapter supported by `Phoenix.PubSub`.

      config :my_app, MyApp.PubSub,
        adapter: Phoenix.PubSub.PG2,
        pool_size: 1

  You must also add `MyApp.PubSub` to your application's supervision
  tree:

      Supervisor.start_link([
        MyApp.PubSub
      ], strategy: :one_for_one, name: MyApp.Supervisor)

  ## Basic Usage

  You can then use your new PubSub module subscribe and broadcast on
  topics:

      # From a process that wants to receive messages
      MyApp.PubSub.subscribe("topic")

      # From a process that sends messages
      MyApp.PubSub.broadcast("topic", {:message, "message"})

      # Messages will be sent to the subscriber process mailbox
      Process.info(self())[:messages]
      # => [message: "message"]

  ## Using with Phoenix

  If using Phoenix, you can drop in your `PubSub` module as the
  PubSub module that your Phoenix Endpoint uses:

      config :my_app_web, MyAppWeb.Endpoint,
        pubsub: [name: MyApp.PubSub]

  Phoenix will then use the given PubSub process for Phoenix Channels.

  ### Phoenix Channels

  `Mithril.PubSub` expects messages on topics to be **ordinary Erlang terms**.
  This allows your business logic to use generic terms to describe messages
  and avoids any dependency on a specific library.

  However, while Phoenix Channels do broadcast over the the Endpoint's
  configured PubSub server, they do so with specialized, Phoenix-specific
  messages like `Phoenix.Socket.Message` and `Phoenix.Socket.Broadcast`.

  You should therefore update your `channel` definition in
  `lib/my_app_web.ex` to exclude the `Phoenix.Channel` functions and use
  your `PubSub` module's functions instead.

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

  You can then use the `PubSub` functions instead of the Phoenix ones to
  publish messages on topics. Here's an example:

      defmodule MyAppWeb.RoomChannel do
        use MyAppWeb, :channel

        alias MyApp.Presence

        def join("room:lobby", payload, socket) do
          {:ok, socket}
        end

        def handle_in("message", message, socket) do
          # Broadcasts the message as a simple Erlang term, instead of a
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

  This structure allows your logic application in `apps/my_app` or
  `lib/my_app` to broadcast messages on topics with zero dependencies on
  Phoenix.

      # Phoenix is configured to use `MyApp.PubSub` as its PubSub,
      # so any Phoenix channels subscribed to "room:lobby" will
      # recieve this message in their `handle_info/2` callback.
      MyApp.PubSub.broadcast("room:lobby", {:message, message})

  ## More details

  `Mithril.PubSub` will generate comprehensive documentation into your
  PubSub module. Read that documentation with ExDoc's `mix docs` for
  more details on what your PubSub module can do.
  """

  @doc false
  defmacro __using__(opts) do
    quote do
      alias Mithril.PubSub

      @opts unquote(opts)
      @otp_app @opts[:otp_app] ||
                 raise(ArgumentError, "Mithril.PubSub expects :otp_app to be given")
      @config Application.get_env(@opts[:otp_app], __MODULE__) ||
                raise(
                  ArgumentError,
                  "No configuration for #{inspect(__MODULE__)} found in #{inspect(@otp_app)}"
                )
      @adapter @config[:adapter] ||
                 raise(ArgumentError, "#{inspect(__MODULE__)} expects :adapter to be configured")
      @adapter_args Keyword.drop(@config, [:adapter])

      @type topic :: String.t()
      @type message :: {atom, term}

      @doc """
      Starts the PubSub server.
      """
      def start_link(_opts \\ []) do
        @adapter.start_link(__MODULE__, @adapter_args)
      end

      @doc """
      Subscribes the current process to a given topic.
      """
      @spec subscribe(topic | Subscriber.t()) :: :ok | {:error, term}
      def subscribe(topic_or_subscriber) do
        PubSub.subscribe(__MODULE__, topic_or_subscriber)
      end

      @doc """
      Unsubscribes the current process from a given topic.
      """
      @spec unsubscribe(topic | Subscriber.t()) :: :ok | {:error, term}
      def unsubscribe(topic_or_subscriber) do
        PubSub.unsubscribe(__MODULE__, topic_or_subscriber)
      end

      @doc """
      Broadcasts a message on a given topic, to all subscribers.
      """
      @spec broadcast(topic, message) :: :ok | {:error, term}
      def broadcast(topic, message) when is_binary(topic) do
        PubSub.broadcast(__MODULE__, topic, message)
      end

      @doc """
      Broadcasts a message on the topic extracted from `subscriber`.

      Subscriber must implement the `Mithril.PubSub.Subscriber` protocol.
      """
      @spec broadcast(Subscriber.t(), message) :: :ok | {:error, term}
      def broadcast(subscriber, message) when is_map(subscriber) do
        PubSub.broadcast(__MODULE__, subscriber, message)
      end

      @doc """
      Broadcasts a message on a given topic.

      Raises `Phoenix.PubSub.BroadcastError` if broadcast fails.
      """
      @spec broadcast!(topic, message) :: :ok | no_return
      def broadcast!(topic, message) when is_binary(topic) do
        PubSub.broadcast!(__MODULE__, topic, message)
      end

      @doc """
      Broadcasts a message on the topic subscribed to by `subscriber`.

      `subscriber` must implement the `Mithril.PubSub.Subscriber` protocol.

      Raises `Phoenix.PubSub.BroadcastError` if broadcast fails.
      """
      @spec broadcast!(Subscriber.t(), message) :: :ok | no_return
      def broadcast!(subscriber, message) when is_map(subscriber) do
        PubSub.broadcast!(__MODULE__, subscriber, message)
      end

      @doc """
      Broadcasts message on a topic to all subscribers except the given `from` pid.
      """
      @spec broadcast_from(pid, topic, message) :: :ok | {:error, term}
      def broadcast_from(from, topic, message) do
        PubSub.broadcast_from(__MODULE__, from, topic, message)
      end

      @doc """
      Broadcasts message on the topic subscribed to by `subscriber` to all other
      subscribers.

      `subscriber` must implement the `Mithril.PubSub.Subscriber` protocol.
      """
      @spec broadcast_from(Subscriber.t(), message) :: :ok | {:error, term}
      def broadcast_from(subscriber, message) do
        PubSub.broadcast_from(__MODULE__, subscriber, message)
      end

      @doc """
      Broadcasts message on a topic to all subscribers except the given `from` pid.

      Raises `Phoenix.PubSub.BroadcastError` if broadcast fails.
      """
      @spec broadcast_from!(pid, topic, message) :: :ok | no_return
      def broadcast_from!(from, topic, message) do
        PubSub.broadcast_from!(__MODULE__, from, topic, message)
      end

      @doc """
      Broadcasts message on the topic subscribed to by `subscriber` to all other
      subscribers.

      `subscriber` must implement the `Mithril.PubSub.Subscriber` protocol.

      Raises `Phoenix.PubSub.BroadcastError` if broadcast fails.
      """
      @spec broadcast_from!(Subscriber.t(), message) :: :ok | no_return
      def broadcast_from!(subscriber, message) do
        PubSub.broadcast_from!(__MODULE__, subscriber, message)
      end

      @doc """
      Broadcasts message on given topic, to a single node.

      See `Phoenix.PubSub.direct_broadcast/4`.
      """
      @spec direct_broadcast(Phoenix.PubSub.node_name(), topic | Subscriber.t(), message) ::
              :ok | {:error, term}
      def direct_broadcast(node_name, topic_or_subscriber, message) do
        PubSub.direct_broadcast(node_name, __MODULE__, topic_or_subscriber, message)
      end

      @doc """
      Broadcasts message on given topic, to a single node.

      Raises `Phoenix.PubSub.BroadcastError` if broadcast fails.

      See `Phoenix.PubSub.direct_broadcast!/4`.
      """
      @spec direct_broadcast!(Phoenix.PubSub.node_name(), topic | Subscriber.t(), message) ::
              :ok | {:error, term}
      def direct_broadcast!(node_name, topic_or_subscriber, message) do
        PubSub.direct_broadcast!(node_name, __MODULE__, topic_or_subscriber, message)
      end

      @doc """
      Broadcasts message to all but from_pid on given topic, to a single node.

      See `Phoenix.PubSub.direct_broadcast_from/5`.
      """
      @spec direct_broadcast_from(Phoenix.PubSub.node_name(), pid, topic, message) ::
              :ok | {:error, term}
      def direct_broadcast_from(node_name, from_pid, topic, message) do
        PubSub.direct_broadcast_from(node_name, __MODULE__, from_pid, topic, message)
      end

      @doc """
      Broadcasts message to all but the current subscriber, to a single node.

      See `direct_broadcast_from/4`.
      """
      @spec direct_broadcast_from(Phoenix.PubSub.node_name(), Subscriber.t(), message) ::
              :ok | {:error, term}
      def direct_broadcast_from(node_name, subscriber, message) do
        PubSub.direct_broadcast_from(node_name, __MODULE__, subscriber, message)
      end

      @doc """
      Broadcasts message to all but from_pid on given topic, to a single node.

      Raises Phoenix.PubSub.BroadcastError if broadcast fails.

      See `Phoenix.PubSub.direct_broadcast_from!/5`.
      """
      @spec direct_broadcast_from!(Phoenix.PubSub.node_name(), pid, topic, message) ::
              :ok | {:error, term}
      def direct_broadcast_from!(node_name, from_pid, topic, message) do
        PubSub.direct_broadcast_from!(node_name, __MODULE__, from_pid, topic, message)
      end

      @doc """
      Broadcasts message to all but the current subscriber, to a single node.

      See `direct_broadcast_from!/4`
      """
      @spec direct_broadcast_from!(Phoenix.PubSub.node_name(), Subscriber.t(), message) ::
              :ok | {:error, term}
      def direct_broadcast_from!(node_name, subscriber, message) do
        PubSub.direct_broadcast_from!(node_name, __MODULE__, subscriber, message)
      end

      @doc false
      def child_spec(_opts) do
        %{
          id: __MODULE__,
          start: {@adapter, :start_link, [__MODULE__, @adapter_args]},
          type: :supervisor
        }
      end
    end
  end

  alias Mithril.PubSub.Subscriber

  @doc false
  def subscribe(module, topic) when is_binary(topic) do
    Phoenix.PubSub.subscribe(module, topic)
  end

  @doc false
  def subscribe(module, subscriber) when is_map(subscriber) do
    topic = Subscriber.topic(subscriber)
    subscribe(module, topic)
  end

  @doc false
  def unsubscribe(module, topic) when is_binary(topic) do
    Phoenix.PubSub.unsubscribe(module, topic)
  end

  @doc false
  def unsubscribe(module, subscriber) when is_map(subscriber) do
    topic = Subscriber.topic(subscriber)
    unsubscribe(module, topic)
  end

  @doc false
  def broadcast(module, topic, message) when is_binary(topic) do
    Phoenix.PubSub.broadcast(module, topic, message)
  end

  @doc false
  def broadcast(module, subscriber, message) when is_map(subscriber) do
    topic = Subscriber.topic(subscriber)
    broadcast(module, topic, message)
  end

  @doc false
  def broadcast!(module, topic, message) when is_binary(topic) do
    Phoenix.PubSub.broadcast!(module, topic, message)
  end

  @doc false
  def broadcast!(module, subscriber, message) when is_map(subscriber) do
    topic = Subscriber.topic(subscriber)
    broadcast!(module, topic, message)
  end

  @doc false
  def broadcast_from(module, from, topic, message) when is_binary(topic) do
    Phoenix.PubSub.broadcast_from(module, from, topic, message)
  end

  @doc false
  def broadcast_from(module, subscriber, message) when is_map(subscriber) do
    from = Subscriber.pid(subscriber)
    topic = Subscriber.topic(subscriber)
    Phoenix.PubSub.broadcast_from(module, from, topic, message)
  end

  @doc false
  def broadcast_from!(module, from, topic, message) when is_binary(topic) do
    Phoenix.PubSub.broadcast_from!(module, from, topic, message)
  end

  @doc false
  def broadcast_from!(module, subscriber, message) when is_map(subscriber) do
    from = Subscriber.pid(subscriber)
    topic = Subscriber.topic(subscriber)
    Phoenix.PubSub.broadcast_from!(module, from, topic, message)
  end

  @doc false
  def direct_broadcast(node_name, module, topic, message) when is_binary(topic) do
    Phoenix.PubSub.direct_broadcast(node_name, module, topic, message)
  end

  @doc false
  def direct_broadcast(node_name, module, subscriber, message) when is_map(subscriber) do
    topic = Subscriber.topic(subscriber)
    direct_broadcast(node_name, module, topic, message)
  end

  @doc false
  def direct_broadcast!(node_name, module, topic, message) when is_binary(topic) do
    Phoenix.PubSub.direct_broadcast!(node_name, module, topic, message)
  end

  @doc false
  def direct_broadcast!(node_name, module, subscriber, message) when is_map(subscriber) do
    topic = Subscriber.topic(subscriber)
    direct_broadcast!(node_name, module, topic, message)
  end

  @doc false
  def direct_broadcast_from(node_name, module, from_pid, topic, message) when is_binary(topic) do
    Phoenix.PubSub.direct_broadcast_from(node_name, module, from_pid, topic, message)
  end

  @doc false
  def direct_broadcast_from(node_name, module, subscriber, message) when is_map(subscriber) do
    from = Subscriber.pid(subscriber)
    topic = Subscriber.topic(subscriber)
    direct_broadcast_from(node_name, module, from, topic, message)
  end

  @doc false
  def direct_broadcast_from!(node_name, module, from_pid, topic, message) when is_binary(topic) do
    Phoenix.PubSub.direct_broadcast_from!(node_name, module, from_pid, topic, message)
  end

  @doc false
  def direct_broadcast_from!(node_name, module, subscriber, message) when is_map(subscriber) do
    from = Subscriber.pid(subscriber)
    topic = Subscriber.topic(subscriber)
    direct_broadcast_from!(node_name, module, from, topic, message)
  end
end
