use Mix.Config

config :mithril_pubsub, Mithril.Test.PubSub,
  adapter: Phoenix.PubSub.PG2,
  pool_size: 5