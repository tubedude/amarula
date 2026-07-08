defmodule Bench do
  @moduledoc """
  Adversarial memory/process-count benchmark: does NOT take the library's word
  for it — boots real processes from the compiled `amarula` app and measures
  actual BEAM memory via `:erlang.memory/1`, no mocks, no synthetic numbers.

  Run: mix run scripts/bench_registry_memory.exs

  ## Scope — read before citing these numbers

  This measures **structural, at-rest overhead only**: what the process topology
  (partitioned `InstanceRegistry`, connection trees, idle `SessionCustodian`/
  `ConversationSender` processes) costs to have *existing*, with zero real traffic
  through it. No message is ever actually encrypted/decrypted/sent here.

  It does NOT measure: throughput or latency under real concurrent load, memory
  growth over sustained usage (hours/days of real conversations), real mailbox
  contention, or CPU/scheduling cost. Those need a load-driving benchmark against
  real ciphertext, not this one — don't cite this script as evidence for those
  claims.
  """

  def kb(bytes), do: Float.round(bytes / 1024, 1)

  def snapshot do
    :erlang.garbage_collect()
    Process.list() |> Enum.each(&:erlang.garbage_collect/1)
    %{
      procs: length(Process.list()),
      total_kb: kb(:erlang.memory(:total)),
      processes_kb: kb(:erlang.memory(:processes)),
      ets_kb: kb(:erlang.memory(:ets))
    }
  end

  def delta(before, aft) do
    %{
      procs: aft.procs - before.procs,
      total_kb: Float.round(aft.total_kb - before.total_kb, 1),
      processes_kb: Float.round(aft.processes_kb - before.processes_kb, 1),
      ets_kb: Float.round(aft.ets_kb - before.ets_kb, 1)
    }
  end

  def report(label, d) do
    IO.puts(
      "  #{String.pad_trailing(label, 46)} " <>
        "+#{d.procs} procs   " <>
        "total: #{d.total_kb} KB   " <>
        "processes: #{d.processes_kb} KB   " <>
        "ets: #{d.ets_kb} KB"
    )
  end

  # A throwaway process that just registers itself in `registry` under `key`
  # and parks — mirrors what a real ConversationSender/SessionCustodian holds
  # in the registry (one live registration per key), without pulling in any
  # Amarula code for this isolated Registry-only comparison.
  def register_and_park(registry, key) do
    spawn(fn ->
      Registry.register(registry, key, nil)
      receive do
        :stop -> :ok
      end
    end)
  end
end

IO.puts("\n== Amarula memory benchmark (mix run scripts/bench_registry_memory.exs) ==")
IO.puts("Erlang/OTP #{System.otp_release()}, Elixir #{System.version()}")
IO.puts("schedulers_online: #{System.schedulers_online()}\n")

n_keys = 20

# ---------------------------------------------------------------------------
# Part 1 — the actual question: partitions: 1 vs partitions: schedulers_online()
# on an OTHERWISE IDENTICAL Registry, same key count, isolated from everything
# else Amarula does. This isolates exactly the cost partitioning adds.
# ---------------------------------------------------------------------------
IO.puts("Part 1 — Registry partitioning cost in isolation (#{n_keys} keys registered)\n")

before1 = Bench.snapshot()
{:ok, reg1} = Registry.start_link(keys: :unique, name: :bench_unpartitioned, partitions: 1)
pids1 = for i <- 1..n_keys, do: Bench.register_and_park(:bench_unpartitioned, {:k, i})
after1 = Bench.snapshot()
Bench.report("partitions: 1", Bench.delta(before1, after1))
Enum.each(pids1, &send(&1, :stop))
Supervisor.stop(reg1)

before2 = Bench.snapshot()

{:ok, reg2} =
  Registry.start_link(
    keys: :unique,
    name: :bench_partitioned,
    partitions: System.schedulers_online()
  )

pids2 = for i <- 1..n_keys, do: Bench.register_and_park(:bench_partitioned, {:k, i})
after2 = Bench.snapshot()
Bench.report("partitions: schedulers_online()", Bench.delta(before2, after2))
Enum.each(pids2, &send(&1, :stop))
Supervisor.stop(reg2)

d1 = Bench.delta(before1, after1)
d2 = Bench.delta(before2, after2)

IO.puts(
  "\n  => partitioning #{n_keys} keys across #{System.schedulers_online()} partitions costs " <>
    "#{Float.round(d2.total_kb - d1.total_kb, 1)} KB and " <>
    "#{d2.procs - d1.procs} extra processes vs. a single partition.\n"
)

# ---------------------------------------------------------------------------
# Part 2 — the real, end-to-end picture: Amarula.Supervisor (as a consumer
# adds it) + real connection trees (real ConnectionSupervisor.start_instance,
# NOT connected to a real socket) + real SessionCustodian/ConversationSender
# processes started the same way the library starts them.
# ---------------------------------------------------------------------------
IO.puts("Part 2 — realistic at-rest footprint (no network I/O, real OTP processes)\n")

before_sup = Bench.snapshot()
{:ok, _sup} = Amarula.Supervisor.start_link()
after_sup = Bench.snapshot()
Bench.report("Amarula.Supervisor (ProfileRegistry + InstanceRegistry + ConnectionsSupervisor)", Bench.delta(before_sup, after_sup))

alias Amarula.Protocol.Socket.ConnectionSupervisor

defmodule BenchConn do
  def new(profile) do
    dir = Path.join(System.tmp_dir!(), "amarula_bench_#{profile}_#{System.unique_integer([:positive])}")

    %{profile: profile, storage: {Amarula.Storage.File, root: dir}}
    |> Amarula.Config.merge()
    |> Amarula.Conn.new()
  end
end

before_trees = Bench.snapshot()
conn_a = BenchConn.new(:bench_profile_a)
conn_b = BenchConn.new(:bench_profile_b)
{:ok, _sup_a, connection_a} = ConnectionSupervisor.start_instance(conn_a)
{:ok, _sup_b, _connection_b} = ConnectionSupervisor.start_instance(conn_b)
after_trees = Bench.snapshot()
Bench.report("2 connection trees (custodian_sup + Connection + sender_sup each, idle, no socket)", Bench.delta(before_trees, after_trees))

# One tree, 50 distinct 1:1 session custodians + 50 distinct group sender-key
# custodians + 50 distinct ConversationSenders — real find-or-start through the
# real Registry, same code path a live send/receive would use.
alias Amarula.Protocol.Signal.SessionCustodian
alias Amarula.Protocol.Signal.Group.SenderKeyName
alias Amarula.Protocol.Messages.ConversationSender

# Recover the instance_id ConnectionSupervisor minted for tree A (it's opaque —
# find it via the Connection pid's own state instead of guessing).
instance_id_a = :sys.get_state(connection_a).instance_id

before_records = Bench.snapshot()

custodians =
  for i <- 1..50 do
    {:ok, pid} = SessionCustodian.for_address(instance_id_a, conn_a, "155500000#{i}.0")
    pid
  end

sender_key_custodians =
  for i <- 1..50 do
    name = SenderKeyName.from_jids("12036300#{i}-15550000000@g.us", "155500000#{i}:0@s.whatsapp.net")
    {:ok, pid} = SessionCustodian.for_sender_key(instance_id_a, conn_a, name)
    pid
  end

# Start senders the same way `deliver/2` would (real find-or-start against the
# real Registry + real sender_supervisor), but stop short of sending anything —
# no socket exists on this Connection, so a real send would just block on an IQ
# timeout. We only want the idle-process footprint here.
senders =
  for i <- 1..50 do
    opts = [
      registry: ConnectionSupervisor.registry_name(instance_id_a),
      supervisor: ConnectionSupervisor.name(instance_id_a, :sender_supervisor),
      recipient_jid: "155500001#{i}@s.whatsapp.net",
      cm: connection_a,
      conn: conn_a,
      creds: %{},
      instance_id: instance_id_a
    ]

    {:ok, pid} = DynamicSupervisor.start_child(Keyword.fetch!(opts, :supervisor), {ConversationSender, opts})
    pid
  end

after_records = Bench.snapshot()
d3 = Bench.delta(before_records, after_records)
Bench.report("50 SessionCustodians + 50 group-key custodians + 50 ConversationSenders", d3)

total_new = Enum.count(custodians) + Enum.count(sender_key_custodians) + Enum.count(senders)
per_process = if d3.procs > 0, do: Float.round(d3.total_kb / d3.procs, 2), else: 0.0
IO.puts("  => #{total_new} processes requested, #{d3.procs} actually alive; ~#{per_process} KB/process\n")

IO.puts("== done ==\n")
