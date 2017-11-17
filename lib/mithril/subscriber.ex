defprotocol Mithril.PubSub.Subscriber do
  @moduledoc """
  A protocol for extracting `pid` and `topic` from a struct, for use
  in `Mithril.PubSub` or `Mithril.Presence`.

  If Phoenix is present in your environment, this protocol will 
  automatically be implemented for `Phoenix.Socket`, so you can use 
  sockets in PubSub functions, for example:

      PubSub.broadcast(socket, {:message, "message"})
  """

  @doc """
  Extracts a PID for the subscribing process.
  """
  @spec pid(__MODULE__.t()) :: pid
  def pid(subscriber)

  @doc """
  Extracts a PubSub topic.
  """
  @spec topic(__MODULE__.t()) :: Mithril.PubSub.topic()
  def topic(subscriber)
end

if Code.ensure_loaded?(Phoenix.Socket) do
  defimpl Mithril.PubSub.Subscriber, for: Phoenix.Socket do
    def pid(socket), do: socket.channel_pid
    def topic(socket), do: socket.topic
  end
end