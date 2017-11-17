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

  `Mithril.PubSub` expects events on topics to be **ordinary Erlang terms**.
  This allows your business logic to use generic terms to describe events
  and avoids any dependency on a specific library.

  However, while Phoenix Channels do broadcast over the the Endpoint's
  configured PubSub server, they do so with specialized, Phoenix-specific 
  events like `Phoenix.Socket.Message` and `Phoenix.Socket.Broadcast`.

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
              broadcast: 2
              broadcast!: 2
              broadcast_from: 2,
              broadcast_from!: 2
            ]
        end
      end

  You can then use the `PubSub` functions instead of the Phoenix ones to
  publish events on topics. Here's an example:

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

  This structure allows your logic application in `apps/my_app` or 
  `lib/my_app` to broadcast events on topics with zero dependencies on
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
      @type event :: {atom, term}

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
      Broadcasts an event on a given topic, to all subscribers.
      """
      @spec broadcast(topic, event) :: :ok | {:error, term}
      def broadcast(topic, event) do
        PubSub.broadcast(__MODULE__, topic, event)
      end

      @doc """
      Broadcasts an event on the topic extracted from `subscriber`.

      Subscriber must implement the `Mithril.PubSub.Subscriber` protocol.
      """
      @spec broadcast(Subscriber.t(), event) :: :ok | {:error, term}
      def broadcast(subscriber, event) when is_map(subscriber) do
        PubSub.broadcast(__MODULE__, subscriber, event)
      end

      @doc """
      Broadcasts an event on a given topic.

      Raises `Phoenix.PubSub.BroadcastError` if broadcast fails.
      """
      @spec broadcast!(topic, event) :: :ok | no_return
      def broadcast!(topic, event) do
        PubSub.broadcast!(__MODULE__, topic, event)
      end

      @doc """
      Broadcasts an event on the topic subscribed to by `subscriber`.

      `subscriber` must implement the `Mithril.PubSub.Subscriber` protocol.

      Raises `Phoenix.PubSub.BroadcastError` if broadcast fails.
      """
      @spec broadcast!(Subscriber.t(), event) :: :ok | no_return
      def broadcast!(subscriber, event) when is_map(subscriber) do
        PubSub.broadcast!(__MODULE__, subscriber, event)
      end

      @doc """
      Broadcasts event on a topic to all subscribers except the given `from` pid.
      """
      @spec broadcast_from(pid, topic, event) :: :ok | {:error, term}
      def broadcast_from(from, topic, event) do
        PubSub.broadcast_from(__MODULE__, from, topic, event)
      end

      @doc """
      Broadcasts event on the topic subscribed to by `subscriber` to all other
      subscribers.

      `subscriber` must implement the `Mithril.PubSub.Subscriber` protocol.
      """
      @spec broadcast_from(Subscriber.t(), event) :: :ok | {:error, term}
      def broadcast_from(subscriber, event) do
        PubSub.broadcast_from(__MODULE__, subscriber, event)
      end

      @doc """
      Broadcasts event on a topic to all subscribers except the given `from` pid.

      Raises `Phoenix.PubSub.BroadcastError` if broadcast fails.
      """
      @spec broadcast_from!(pid, topic, event) :: :ok | no_return
      def broadcast_from!(from, topic, event) do
        PubSub.broadcast_from!(__MODULE__, from, topic, event)
      end

      @doc """
      Broadcasts event on the topic subscribed to by `subscriber` to all other
      subscribers.

      `subscriber` must implement the `Mithril.PubSub.Subscriber` protocol.

      Raises `Phoenix.PubSub.BroadcastError` if broadcast fails.
      """
      @spec broadcast_from!(Subscriber.t(), event) :: :ok | no_return
      def broadcast_from!(subscriber, event) do
        PubSub.broadcast_from!(__MODULE__, subscriber, event)
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
  def broadcast(module, topic, event) when is_binary(topic) do
    Phoenix.PubSub.broadcast(module, topic, event)
  end

  @doc false
  def broadcast(module, subscriber, event) when is_map(subscriber) do
    topic = Subscriber.topic(subscriber)
    broadcast(module, topic, event)
  end

  @doc false
  def broadcast!(module, topic, event) when is_binary(topic) do
    Phoenix.PubSub.broadcast!(module, topic, event)
  end

  @doc false
  def broadcast!(module, subscriber, event) when is_map(subscriber) do
    topic = Subscriber.topic(subscriber)
    broadcast!(module, topic, event)
  end

  @doc false
  def broadcast_from(module, from, topic, event) when is_binary(topic) do
    Phoenix.PubSub.broadcast_from(module, from, topic, event)
  end

  @doc false
  def broadcast_from(module, subscriber, event) when is_map(subscriber) do
    from = Subscriber.pid(subscriber)
    topic = Subscriber.topic(subscriber)
    Phoenix.PubSub.broadcast_from(module, from, topic, event)
  end

  @doc false
  def broadcast_from!(module, from, topic, event) when is_binary(topic) do
    Phoenix.PubSub.broadcast_from!(module, from, topic, event)
  end

  @doc false
  def broadcast_from!(module, subscriber, event) when is_map(subscriber) do
    from = Subscriber.pid(subscriber)
    topic = Subscriber.topic(subscriber)
    Phoenix.PubSub.broadcast_from!(module, from, topic, event)
  end
end