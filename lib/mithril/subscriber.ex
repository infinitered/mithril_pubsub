defprotocol Mithril.PubSub.Subscriber do
  @spec pid(__MODULE__.t()) :: pid
  def pid(subscriber)

  @spec topic(__MODULE__.t()) :: Mithril.PubSub.topic()
  def topic(subscriber)
end

if Code.ensure_loaded?(Phoenix.Socket) do
  defimpl Mithril.PubSub.Subscriber, for: Phoenix.Socket do
    def pid(socket), do: socket.channel_pid
    def topic(socket), do: socket.topic
  end
end