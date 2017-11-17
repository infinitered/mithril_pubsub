defmodule Mithril.PubSub do
  @moduledoc """

  """

  @doc false
  defmacro __using__(_) do
    quote do
      alias Mithril.PubSub

      @type topic :: String.t()
      @type event :: {atom, term}

      @doc """
      Subscribes the current process to a given topic.
      """
      @spec subscribe(topic) :: :ok | {:error, term}
      def subscribe(topic) do
        PubSub.subscribe(__MODULE__, topic)
      end

      @doc """
      Unsubscribes the current process from a given topic.
      """
      @spec unsubscribe(topic) :: :ok | {:error, term}
      def unsubscribe(topic) do
        PubSub.unsubscribe(__MODULE__, topic)
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
      def broadcast_from(subscriber, event) when is_map(subscriber) do
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
          start: {Phoenix.PubSub.PG2, :start_link, [__MODULE__, [pool_size: 1]]},
          type: :supervisor
        }
      end
    end
  end

  alias Mithril.PubSub.Subscriber

  @doc false
  def subscribe(module, topic) do
    Phoenix.PubSub.subscribe(module, topic)
  end

  @doc false
  def unsubscribe(module, topic) do
    Phoenix.PubSub.unsubscribe(module, topic)
  end

  @doc false
  def broadcast(module, topic, event) do
    Phoenix.PubSub.broadcast(module, topic, event)
  end

  @doc false
  def broadcast(module, subscriber, event) when is_map(subscriber) do
    topic = Subscriber.topic(subscriber)
    broadcast(module, topic, event)
  end

  @doc false
  def broadcast!(module, topic, event) do
    Phoenix.PubSub.broadcast!(module, topic, event)
  end

  @doc false
  def broadcast!(module, subscriber, event) when is_map(subscriber) do
    topic = Subscriber.topic(subscriber)
    broadcast!(module, topic, event)
  end

  @doc false
  def broadcast_from(module, from, topic, event) do
    Phoenix.PubSub.broadcast_from(module, from, topic, event)
  end

  @doc false
  def broadcast_from(module, subscriber, event) when is_map(subscriber) do
    from = Subscriber.pid(subscriber)
    topic = Subscriber.topic(subscriber)
    Phoenix.PubSub.broadcast_from(module, from, topic, event)
  end

  @doc false
  def broadcast_from!(module, from, topic, event) do
    Phoenix.PubSub.broadcast_from!(module, from, topic, event)
  end

  @doc false
  def broadcast_from!(module, subscriber, event) when is_map(subscriber) do
    from = Subscriber.from(subscriber)
    topic = Subscriber.topic(subscriber)
    Phoenix.PubSub.broadcast_from!(module, from, topic, event)
  end
end