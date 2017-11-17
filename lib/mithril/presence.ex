defmodule Mithril.Presence do
  @moduledoc """
  Provides Presence tracking to processes and channels. **It is
  a slight fork of `Phoenix.Presence`, removing Phoenix-specific
  data structures.**

  This behaviour provides presence features such as fetching
  presences for a given topic, as well as handling diffs of
  join and leave events as they occur in real-time. Using this
  module defines a supervisor and allows the calling module to
  implement the `Phoenix.Tracker` behaviour which starts a
  tracker process to handle presence information.

  ## Example Usage

  Start by defining a presence module within your application
  which uses `Mithril.Presence` and provide the `:otp_app` which
  holds your configuration, as well as the `:pubsub_server`.

      defmodule MyApp.Presence do
        use Mithril.Presence, otp_app: :my_app,
                              pubsub_server: MyApp.PubSub
      end

  The `:pubsub_server` must point to an existing pubsub server
  running in your application. Ideally, a pubsub server defined 
  with `Mithril.PubSub`.

  Next, add the new supervisor to your supervision tree in `lib/my_app.ex`:

      children = [
        ...
        supervisor(MyApp.Presence, []),
      ]

  Once added, presences can be tracked in your channel after joining:

      defmodule MyApp.MyChannel do
        use MyAppWeb, :channel
        alias MyApp.Presence

        def join("some:topic", _params, socket) do
          send(self(), :after_join)
          {:ok, socket}
        end

        def handle_info(:after_join, socket) do
          push socket, "presence_state", Presence.list(socket)
          {:ok, _} = Presence.track(socket, socket.assigns.user_id, %{
            online_at: System.system_time(:seconds)
          })
          {:noreply, socket}
        end

        # New presence information will be sent to your channel as a regular
        # process message, so you'll need to implement this callback to push
        # it to your subscriber.
        def handle_info({:presence_diff, diff}, socket) do
          push socket, "presence_diff", diff

          {:noreply, socket}
        end
      end

  In the example above, the current presence information for
  the socket's topic is pushed to the client as a `"presence_state"` event.
  Next, `Presence.track` is used to register this
  channel's process as a presence for the socket's user ID, with
  a map of metadata.

  Finally, a diff of presence join and leave events will be sent to the
  channel process as they happen in real-time with the :presence_diff message.
  The diff structure will be a map of `:joins` and `:leaves` of the form:

      %{joins: %{"123" => %{metas: [%{status: "away", phx_ref: ...}]},
        leaves: %{"456" => %{metas: [%{status: "online", phx_ref: ...}]},

  See `Mithril.Presence.list/2` for more information on the presence
  data structure.

  ## Fetching Presence Information

  Presence metadata should be minimized and used to store small,
  ephemeral state, such as a user's "online" or "away" status.
  More detailed information, such as user details that need to
  be fetched from the database, can be achieved by overriding the `fetch/2`
  function. The `fetch/2` callback is triggered when using `list/1`
  and serves as a mechanism to fetch presence information a single time,
  before broadcasting the information to all channel subscribers.
  This prevents N query problems and gives you a single place to group
  isolated data fetching to extend presence metadata. The function must
  return a map of data matching the outlined Presence data structure,
  including the `:metas` key, but can extend the map of information
  to include any additional information. For example:

      def fetch(_topic, entries) do
        query =
          from u in User,
            where: u.id in ^Map.keys(entries),
            select: {u.id, u}

        users = query |> Repo.all |> Enum.into(%{})

        for {key, %{metas: metas}} <- entries, into: %{} do
          {key, %{metas: metas, user: users[key]}}
        end
      end

  The function above fetches all users from the database who
  have registered presences for the given topic. The fetched
  information is then extended with a `:user` key of the user's
  information, while maintaining the required `:metas` field from the
  original presence data.
  """

  alias Mithril.PubSub.Subscriber

  @type presences :: %{String.t() => %{metas: [map()]}}
  @type presence :: %{key: String.t(), meta: map()}
  @type topic :: String.t()

  @callback start_link(Keyword.t()) :: {:ok, pid()} | {:error, reason :: term()} :: :ignore
  @callback init(Keyword.t()) :: {:ok, state :: term} | {:error, reason :: term}
  @callback track(subscriber :: Subscriber.t(), key :: String.t(), meta :: map()) ::
              {:ok, binary()} | {:error, reason :: term()}
  @callback track(pid, topic, key :: String.t(), meta :: map()) ::
              {:ok, binary()} | {:error, reason :: term()}
  @callback untrack(subscriber :: Subscriber.t(), key :: String.t()) :: :ok
  @callback untrack(pid, topic, key :: String.t()) :: :ok
  @callback update(
              subscriber :: Subscriber.t(),
              key :: String.t(),
              meta :: map() | (map() -> map())
            ) :: {:ok, binary()} | {:error, reason :: term()}
  @callback update(pid, topic, key :: String.t(), meta :: map() | (map() -> map())) ::
              {:ok, binary()} | {:error, reason :: term()}
  @callback fetch(topic, presences) :: presences
  @callback list(topic) :: presences
  @callback handle_diff(%{topic => {joins :: presences, leaves :: presences}}, state :: term) ::
              {:ok, state :: term}

  defmacro __using__(opts) do
    quote do
      @opts unquote(opts)
      @otp_app @opts[:otp_app] || raise("presence expects :otp_app to be given")
      @behaviour unquote(__MODULE__)
      @task_supervisor Module.concat(__MODULE__, TaskSupervisor)

      def start_link(opts \\ []) do
        opts = Keyword.merge(@opts, opts)
        Mithril.Presence.start_link(__MODULE__, @otp_app, @task_supervisor, opts)
      end

      def init(opts) do
        server = Keyword.fetch!(opts, :pubsub_server)

        {:ok, %{
          pubsub_server: server,
          node_name: Phoenix.PubSub.node_name(server),
          task_sup: @task_supervisor
        }}
      end

      def track(%{channel_pid: pid, topic: topic}, key, meta) do
        track(pid, topic, key, meta)
      end

      def track(pid, topic, key, meta) do
        Phoenix.Tracker.track(__MODULE__, pid, topic, key, meta)
      end

      def untrack(%{channel_pid: pid, topic: topic}, key) do
        untrack(pid, topic, key)
      end

      def untrack(pid, topic, key) do
        Phoenix.Tracker.untrack(__MODULE__, pid, topic, key)
      end

      def update(%{channel_pid: pid, topic: topic}, key, meta) do
        Phoenix.Tracker.update(pid, topic, key, meta)
      end

      def update(pid, topic, key, meta) do
        Phoenix.Tracker.update(__MODULE__, pid, topic, key, meta)
      end

      def fetch(_topic, presences), do: presences

      def list(%{topic: topic}) do
        list(topic)
      end

      def list(topic) do
        Mithril.Presence.list(__MODULE__, topic)
      end

      def handle_diff(diff, state) do
        Mithril.Presence.handle_diff(
          __MODULE__,
          diff,
          state.node_name,
          state.pubsub_server,
          state.task_sup
        )

        {:ok, state}
      end

      defoverridable fetch: 2
    end
  end

  @doc false
  def start_link(module, otp_app, task_supervisor, opts) do
    import Supervisor.Spec

    opts =
      opts
      |> Keyword.merge(Application.get_env(otp_app, module) || [])
      |> Keyword.put(:name, module)

    children = [
      supervisor(Task.Supervisor, [[name: task_supervisor]]),
      worker(Phoenix.Tracker, [module, opts, opts])
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  @doc false
  def handle_diff(module, diff, node_name, pubsub_server, sup_name) do
    Task.Supervisor.start_child(sup_name, fn ->
      for {topic, {joins, leaves}} <- diff do
        msg =
          {:presence_diff, %{
            joins: module.fetch(topic, group(joins)),
            leaves: module.fetch(topic, group(leaves))
          }}

        Phoenix.PubSub.direct_broadcast!(node_name, pubsub_server, topic, msg)
      end
    end)
  end

  @doc """
  Returns presences for a topic.

  ## Presence data structure

  The presence information is returned as a map with presences grouped
  by key, cast as a string, and accumulated metadata, with the following form:

      %{key => %{metas: [%{phx_ref: ..., ...}, ...]}}

  For example, imagine a user with id `123` online from two
  different devices, as well as a user with id `456` online from
  just one device. The following presence information might be returned:

      %{"123" => %{metas: [%{status: "away", phx_ref: ...},
                           %{status: "online", phx_ref: ...}]},
        "456" => %{metas: [%{status: "online", phx_ref: ...}]}}

  The keys of the map will usually point to a resource ID. The value
  will contain a map with a `:metas` key containing a list of metadata
  for each resource. Additionally, every metadata entry will contain a
  `:phx_ref` key which can be used to uniquely identify metadata for a
  given key. In the event that the metadata was previously updated,
  a `:phx_ref_prev` key will be present containing the previous
  `:phx_ref` value.
  """
  def list(module, topic) do
    grouped =
      module
      |> Phoenix.Tracker.list(topic)
      |> group()

    module.fetch(topic, grouped)
  end

  defp group(presences) do
    presences
    |> Enum.reverse()
    |> Enum.reduce(%{}, fn {key, meta}, acc ->
         Map.update(acc, to_string(key), %{metas: [meta]}, fn %{metas: metas} ->
           %{metas: [meta | metas]}
         end)
       end)
  end
end