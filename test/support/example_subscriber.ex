defmodule Mithril.Test.ExampleSubscriber do
  defstruct pid: nil, topic: nil
end

defimpl Mithril.PubSub.Subscriber, for: Mithril.Test.ExampleSubscriber do
  def pid(subscriber), do: subscriber.pid
  def topic(subscriber), do: subscriber.topic
end