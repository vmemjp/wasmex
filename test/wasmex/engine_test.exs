defmodule Wasmex.EngineTest do
  use ExUnit.Case, async: true
  import TestHelper, only: [t: 1]

  alias Wasmex.Engine
  alias Wasmex.EngineConfig
  alias Wasmex.Module

  doctest Engine

  describe t(&Engine.new/1) do
    test "creates a new Engine" do
      assert {:ok, %Engine{}} = Engine.new(%EngineConfig{})
    end
  end

  describe t(&Engine.default/1) do
    test "creates an Engine with default config" do
      assert %Engine{} = Engine.default()
    end

    test "creates an Engine with a changed config" do
      assert {:ok, %Engine{}} =
               %EngineConfig{}
               |> EngineConfig.consume_fuel(true)
               |> EngineConfig.cranelift_opt_level(:speed)
               |> EngineConfig.memory64(true)
               |> Engine.new()
    end
  end

  describe t(&Engine.precompile/2) do
    test "precompiles a module" do
      {:ok, engine} = Engine.new(%EngineConfig{})
      wasm_bytes = File.read!(TestHelper.wasm_test_file_path())

      assert {:ok, serialized_module} = Engine.precompile_module(engine, wasm_bytes)
      assert is_binary(serialized_module)

      {:ok, deserialized_module} = Module.unsafe_deserialize(serialized_module)
      %{module: module} = TestHelper.wasm_module()

      assert Module.exports(module) == Module.exports(deserialized_module)
    end
  end

  describe t(&Engine.increment_epoch/1) do
    test "interrupts a guest whose epoch deadline has passed" do
      {:ok, engine} = Engine.new(%EngineConfig{epoch_interruption: true})
      {:ok, store} = Wasmex.Store.new(nil, engine)
      :ok = Wasmex.StoreOrCaller.set_epoch_deadline(store, 1)
      {:ok, module} = Module.compile(store, File.read!(TestHelper.wasm_test_file_path()))
      {:ok, pid} = Wasmex.start_link(%{store: store, module: module})

      spawn(fn ->
        Process.sleep(50)
        Engine.increment_epoch(engine)
      end)

      # `endless_loop` never returns on its own. The call timeout is a
      # backstop for a *failing* test, not the mechanism under test: it would
      # only stop this process waiting, leaving the guest spinning.
      assert {:error, reason} = Wasmex.call_function(pid, "endless_loop", [], 10_000)
      assert reason =~ "interrupt"
    end

    test "is a no-op on an engine without epoch_interruption" do
      {:ok, engine} = Engine.new(%EngineConfig{})
      assert :ok = Engine.increment_epoch(engine)
    end

    test "a guest inside its deadline runs untouched" do
      {:ok, engine} = Engine.new(%EngineConfig{epoch_interruption: true})
      {:ok, store} = Wasmex.Store.new(nil, engine)
      :ok = Wasmex.StoreOrCaller.set_epoch_deadline(store, 1)
      {:ok, module} = Module.compile(store, File.read!(TestHelper.wasm_test_file_path()))
      {:ok, pid} = Wasmex.start_link(%{store: store, module: module})

      # No increment_epoch, so the deadline never arrives.
      assert {:ok, [42]} = Wasmex.call_function(pid, "arity_0", [])
    end
  end
end
