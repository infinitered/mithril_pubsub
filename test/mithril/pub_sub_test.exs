defmodule Mithril.PubSubTest do
  use ExUnit.Case

  alias Mithril.Test.ExampleSubscriber
  alias Mithril.Test.PubSub

  describe "use" do
    test "raises error if :otp_app not given" do
      assert_raise ArgumentError, "Mithril.PubSub expects :otp_app to be given", fn ->
        defmodule WithoutOTP do
          use Mithril.PubSub
        end
      end
    end

    test "raises error if not configured" do
      assert_raise ArgumentError,
                   "No configuration for Mithril.PubSubTest.WithoutConfig found in :mithril_pubsub",
                   fn ->
                     defmodule WithoutConfig do
                       use Mithril.PubSub, otp_app: :mithril_pubsub
                     end
                   end
    end

    test "raises error if :adapter not found in configuration" do
      Application.put_env(:mithril_pubsub, Mithril.PubSubTest.WithoutAdapter, [])

      assert_raise ArgumentError,
                   "Mithril.PubSubTest.WithoutAdapter expects :adapter to be configured",
                   fn ->
                     defmodule WithoutAdapter do
                       use Mithril.PubSub, otp_app: :mithril_pubsub
                     end
                   end
    end

    test "puts adapter config into `child_spec/1` function" do
      assert PubSub.child_spec([]) == %{
               id: PubSub,
               start: {Phoenix.PubSub.PG2, :start_link, [PubSub, [pool_size: 5]]},
               type: :supervisor
             }
    end
  end

  describe "subscribing" do
    test "can subscribe/unsubscribe/broadcast on topics" do
      # Before you subscribe, you get no messages
      assert_no_messages_before_subscribe("topic")

      # After you subscribe, you get messages
      assert_messages_after_subscribe("topic")

      # After you unsubscribe, you no longer receive messages
      assert_unsubscribe("topic")
    end

    test "can subscribe/unsubscribe/broadcast on subscribers" do
      subscriber = %ExampleSubscriber{pid: self(), topic: "topic"}

      # Before you subscribe, you get no messages
      assert_no_messages_before_subscribe(subscriber)

      # After you subscribe, you get messages
      assert_messages_after_subscribe(subscriber)

      # After you unsubscribe, you no longer receive messages
      assert_unsubscribe(subscriber)
    end
  end

  defp assert_no_messages_before_subscribe(topic_or_subscriber) do
    assert :ok == PubSub.broadcast(topic_or_subscriber, {:message, "message"})
    refute_received {:message, "message"}
  end

  defp assert_messages_after_subscribe(topic_or_subscriber) do
    # Subscribe
    assert :ok == PubSub.subscribe(topic_or_subscriber)

    # Send message with broadcast/2
    assert :ok == PubSub.broadcast(topic_or_subscriber, {:message, "message"})
    assert_received {:message, "message"}

    # Send message with broadcast!/2
    assert :ok == PubSub.broadcast!(topic_or_subscriber, {:broadcast!, "message"})
    assert_received {:broadcast!, "message"}

    # Send message with broadcast_from/2
    case topic_or_subscriber do
      %ExampleSubscriber{} ->
        assert :ok == PubSub.broadcast_from(topic_or_subscriber, {:broadcast_from, "message"})

      _ ->
        assert :ok ==
                 PubSub.broadcast_from(self(), topic_or_subscriber, {:broadcast_from, "message"})
    end

    refute_received {:broadcast_from, "message"}

    # Send message with broadcast_from!/2
    case topic_or_subscriber do
      %ExampleSubscriber{} ->
        assert :ok == PubSub.broadcast_from!(topic_or_subscriber, {:broadcast_from, "message"})

      _ ->
        assert :ok ==
                 PubSub.broadcast_from(self(), topic_or_subscriber, {:broadcast_from, "message"})
    end

    refute_received {:broadcast_from!, "message"}
  end

  defp assert_unsubscribe(topic_or_subscriber) do
    assert :ok == PubSub.unsubscribe(topic_or_subscriber)
    assert :ok == PubSub.broadcast(topic_or_subscriber, {:message, "message"})
    refute_received {:message, "message"}
  end
end