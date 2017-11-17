defmodule Mithril.PubSubTest do
  use ExUnit.Case
  doctest Mithril.PubSub

  test "greets the world" do
    assert Mithril.PubSub.hello() == :world
  end
end
