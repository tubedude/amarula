defmodule Amarula.Group do
  @moduledoc """
  Group chats — the `%Amarula.Group{}` struct *and* every group operation.

  The struct is the consumer-facing view of group metadata (addresses as
  `Amarula.Address`); you get one from `metadata/2` and `list/1`. The operations
  (`create/3`, `leave/2`, `update_subject/3`, participant and invite management,
  join-request approval) build a `w:g2` IQ and parse the reply. Each returns
  `:ok` / `{:ok, value}` / `{:error, {:group_op_failed, code, text}}`.

  `group` is a `@g.us` jid string (e.g. from a group's `:address`).

  A group is a *container* of participants, not a person: `:address` names the
  group (`:group` kind), `:participants` are the member `Amarula.Address`es.
  """

  alias Amarula.Address
  alias Amarula.Connection
  alias Amarula.Protocol.Groups.Metadata
  alias Amarula.Protocol.Groups.Ops, as: GroupOps

  @type conn :: GenServer.server()

  @typedoc "Affected participant in a group op: `%{jid, status}` (status \"200\" = ok)."
  @type affected :: %{jid: String.t() | nil, status: String.t()}

  @type participant :: %{
          address: Address.t(),
          admin: :admin | :superadmin | nil
        }

  @type t :: %__MODULE__{
          address: Address.t(),
          subject: String.t() | nil,
          owner: Address.t() | nil,
          size: non_neg_integer(),
          participants: [participant()]
        }

  @enforce_keys [:address]
  defstruct [:address, :subject, :owner, :participants, size: 0]

  @doc "Build a `Group` from a `Amarula.Protocol.Groups.Metadata` map."
  @spec from_metadata(map()) :: t()
  def from_metadata(meta) do
    %__MODULE__{
      address: Address.parse(meta.id),
      subject: Map.get(meta, :subject),
      owner: meta |> Map.get(:owner) |> maybe_address(),
      size: Map.get(meta, :size, 0),
      participants: Enum.map(meta.participants, &participant/1)
    }
  end

  # A participant's id may be a PN or LID; parse to its Address. `admin` is the
  # raw `type` attr ("admin"/"superadmin"/nil).
  defp participant(%{id: id, admin: admin}) do
    %{address: Address.parse(id), admin: admin_kind(admin)}
  end

  defp admin_kind("superadmin"), do: :superadmin
  defp admin_kind("admin"), do: :admin
  defp admin_kind(_), do: nil

  defp maybe_address(nil), do: nil
  defp maybe_address(jid), do: Address.parse(jid)

  # --- operations ---

  @doc "Fetch a group's metadata (`%Amarula.Group{}`). `group` is an `Address` or jid."
  @spec metadata(conn(), Address.t() | String.t()) :: {:ok, t()} | {:error, term()}
  defdelegate metadata(conn, group), to: Connection, as: :group_metadata

  @doc "List all groups we participate in (`[%Amarula.Group{}]`)."
  @spec list(conn()) :: {:ok, [t()]} | {:error, term()}
  defdelegate list(conn), to: Connection, as: :list_groups

  @doc """
  Create a group named `subject` with the given participant jids. Returns the new
  group's metadata.
  """
  @spec create(conn(), String.t(), [String.t()]) :: {:ok, t()} | {:error, term()}
  def create(conn, subject, participants) do
    Connection.group_op(conn, GroupOps.create(subject, participants), &meta_result/1)
  end

  @doc "Leave a group."
  @spec leave(conn(), String.t()) :: :ok | {:error, term()}
  def leave(conn, group) do
    Connection.group_op(conn, GroupOps.leave(group), &ok_result/1)
  end

  @doc "Change a group's subject (title)."
  @spec update_subject(conn(), String.t(), String.t()) :: :ok | {:error, term()}
  def update_subject(conn, group, subject) do
    Connection.group_op(conn, GroupOps.update_subject(group, subject), &ok_result/1)
  end

  @doc "Set (or clear, with `nil`/`\"\"`) a group's description."
  @spec update_description(conn(), String.t(), String.t() | nil) :: :ok | {:error, term()}
  def update_description(conn, group, description) do
    Connection.group_op(conn, GroupOps.update_description(group, description), &ok_result/1)
  end

  @doc """
  Add/remove/promote/demote participants. `action` is `:add`/`:remove`/`:promote`/
  `:demote`. Returns the affected participants with per-jid status.
  """
  @spec participants(conn(), String.t(), [String.t()], GroupOps.action()) ::
          {:ok, [affected()]} | {:error, term()}
  def participants(conn, group, participants, action) do
    Connection.group_op(conn, GroupOps.participants_update(group, participants, action), fn r ->
      r |> reply_node() |> GroupOps.parse_participants(action) |> reply_or_error(r)
    end)
  end

  @doc """
  Change a group setting: `:announcement`/`:not_announcement` (only admins post),
  `:locked`/`:unlocked` (only admins edit info).
  """
  @spec update_setting(conn(), String.t(), GroupOps.setting()) :: :ok | {:error, term()}
  def update_setting(conn, group, setting) do
    Connection.group_op(conn, GroupOps.setting_update(group, setting), &ok_result/1)
  end

  @doc "Who may add members: `:admin_add` (admins only) or `:all_member_add`."
  @spec member_add_mode(conn(), String.t(), :admin_add | :all_member_add) ::
          :ok | {:error, term()}
  def member_add_mode(conn, group, mode) do
    Connection.group_op(conn, GroupOps.member_add_mode(group, mode), &ok_result/1)
  end

  @doc "Turn join-approval (admin approves joiners) `:on`/`:off`."
  @spec join_approval_mode(conn(), String.t(), :on | :off) :: :ok | {:error, term()}
  def join_approval_mode(conn, group, mode) do
    Connection.group_op(conn, GroupOps.join_approval_mode(group, mode), &ok_result/1)
  end

  @doc "Toggle disappearing messages. `0` = off; otherwise seconds of expiration."
  @spec toggle_ephemeral(conn(), String.t(), non_neg_integer()) :: :ok | {:error, term()}
  def toggle_ephemeral(conn, group, expiration) do
    Connection.group_op(conn, GroupOps.toggle_ephemeral(group, expiration), &ok_result/1)
  end

  @doc "Fetch the group's invite code."
  @spec invite_code(conn(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def invite_code(conn, group) do
    Connection.group_op(conn, GroupOps.invite_code(group), fn r ->
      r |> reply_node() |> GroupOps.parse_invite_code() |> reply_or_error(r)
    end)
  end

  @doc "Revoke + regenerate the group's invite code. Returns the new code."
  @spec revoke_invite(conn(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def revoke_invite(conn, group) do
    Connection.group_op(conn, GroupOps.revoke_invite(group), fn r ->
      r |> reply_node() |> GroupOps.parse_invite_code() |> reply_or_error(r)
    end)
  end

  @doc "Join a group by invite `code`. Returns the joined group's jid."
  @spec accept_invite(conn(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def accept_invite(conn, code) do
    Connection.group_op(conn, GroupOps.accept_invite(code), fn r ->
      r |> reply_node() |> GroupOps.parse_accepted_jid() |> reply_or_error(r)
    end)
  end

  @doc "Look up group metadata from an invite `code` without joining."
  @spec invite_info(conn(), String.t()) :: {:ok, t()} | {:error, term()}
  def invite_info(conn, code) do
    Connection.group_op(conn, GroupOps.invite_info(code), &meta_result/1)
  end

  @doc """
  List pending join-approval requests as
  `[%{jid: Amarula.Address.t(), requested_at: integer | nil}]` — who asked to join
  and when. Approve/reject them with `request_update/4`.
  """
  @spec requests(conn(), String.t()) ::
          {:ok, [%{jid: Address.t(), requested_at: integer | nil}]} | {:error, term()}
  def requests(conn, group) do
    Connection.group_op(conn, GroupOps.request_list(group), fn r ->
      r |> reply_node() |> GroupOps.parse_request_list() |> reply_or_error(r)
    end)
  end

  @doc "Approve/reject pending join requests for `participants`. `action` is `:approve`/`:reject`."
  @spec request_update(conn(), String.t(), [String.t()], :approve | :reject) ::
          {:ok, [affected()]} | {:error, term()}
  def request_update(conn, group, participants, action) do
    Connection.group_op(conn, GroupOps.request_update(group, participants, action), fn r ->
      r |> reply_node() |> GroupOps.parse_request_update(action) |> reply_or_error(r)
    end)
  end

  # --- reply transforms (mirror the IQ {:ok,_}/{:error,_} into the consumer shape) ---

  defp reply_node({:ok, node}), do: node
  defp reply_node({:error, node}), do: node

  defp reply_or_error(_parsed, {:error, node}), do: {:error, iq_error(node)}
  defp reply_or_error(parsed, {:ok, _node}), do: parsed

  defp ok_result({:ok, _node}), do: :ok
  defp ok_result({:error, node}), do: {:error, iq_error(node)}

  defp meta_result({:ok, node}) do
    with {:ok, meta} <- Metadata.parse(node), do: {:ok, from_metadata(meta)}
  end

  defp meta_result({:error, node}), do: {:error, iq_error(node)}

  # Extract {:group_op_failed, code, text} from an error IQ's <error> child.
  defp iq_error(%Amarula.Protocol.Binary.Node{} = node) do
    case Amarula.Protocol.Binary.NodeUtils.get_binary_node_child(node, "error") do
      %Amarula.Protocol.Binary.Node{} = err ->
        {:group_op_failed, Amarula.Protocol.Binary.NodeUtils.get_attr(err, "code"),
         Amarula.Protocol.Binary.NodeUtils.get_attr(err, "text")}

      _ ->
        :unknown
    end
  end
end
