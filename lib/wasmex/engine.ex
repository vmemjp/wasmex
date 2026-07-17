defmodule Wasmex.Engine do
  @moduledoc ~S"""
  An `Engine` which is a global context for compilation and management of Wasm
  modules.

  Engines store global configuration preferences such as compilation settings,
  enabled features, etc. You'll likely only need at most one of these for a
  program.

  You can create an engine with default configuration settings using
  `EngineConfig::default()`. Be sure to consult the documentation of
  `Wasmex.EngineConfig` for default settings.

  ## Example

      iex> {:ok, _engine} = Wasmex.Engine.new(%Wasmex.EngineConfig{})
  """

  alias Wasmex.EngineConfig

  @type t :: %__MODULE__{
          resource: binary(),
          reference: reference()
        }

  defstruct resource: nil,
            # The actual NIF store resource.
            # Normally the compiler will happily do stuff like inlining the
            # resource in attributes. This will convert the resource into an
            # empty binary with no warning. This will make that harder to
            # accidentally do.
            reference: nil

  def __wrap_resource__(resource) do
    %__MODULE__{
      resource: resource,
      reference: make_ref()
    }
  end

  @doc ~S"""
  Creates a new `Wasmex.Engine` with the specified options.

  ## Example

      iex> {:ok, _engine} = Wasmex.Engine.new(%Wasmex.EngineConfig{})
  """
  @spec new(EngineConfig.t()) :: {:ok, __MODULE__.t()} | {:error, binary()}
  def new(%EngineConfig{} = config) do
    case Wasmex.Native.engine_new(config) do
      {:error, err} -> {:error, err}
      resource -> {:ok, __wrap_resource__(resource)}
    end
  end

  @doc ~S"""
  Creates a new `Wasmex.Engine` with default settings.

  ## Example

      iex> _engine = Wasmex.Engine.default()
  """
  @spec default() :: __MODULE__.t()
  def default() do
    {:ok, engine} = new(%EngineConfig{})
    engine
  end

  @doc ~S"""
  Ahead-of-time (AOT) compiles a WebAssembly module.

  The `bytes` provided must be in one of two formats:

  * A [binary-encoded][binary] WebAssembly module
  * A [text-encoded][text] instance of the WebAssembly text format

  This method may be used to compile a module for use with a
  different target host. The output of this method may be used with
  `Wasmex.Module.unsafe_deserialize/2` on hosts compatible with the
  `Wasmex.EngineConfig` associated with this `Wasmex.Engine`.

  The output of this method is safe to send to another host machine
  for later execution. As the output is already a compiled module,
  translation and code generation will be skipped and this will
  improve the performance of constructing a `Wasmex.Module` from
  the output of this method.

  [binary]: https://webassembly.github.io/spec/core/binary/index.html
  [text]: https://webassembly.github.io/spec/core/text/index.html

  ## Example

      iex> {:ok, engine} = Wasmex.Engine.new(%Wasmex.EngineConfig{})
      iex> bytes = File.read!(TestHelper.wasm_test_file_path())
      iex> {:ok, _serialized_module} = Wasmex.Engine.precompile_module(engine, bytes)
  """
  @spec precompile_module(__MODULE__.t(), binary()) :: {:ok, binary()} | {:error, binary()}
  def precompile_module(%__MODULE__{resource: resource}, bytes) do
    case Wasmex.Native.engine_precompile_module(resource, bytes) do
      {:error, err} -> {:error, err}
      serialized_module -> {:ok, serialized_module}
    end
  end

  @doc ~S"""
  Advances this engine's epoch by one.

  Any store on this engine whose epoch deadline has now passed traps at its
  next check — see `Wasmex.EngineConfig.epoch_interruption/2` and
  `Wasmex.StoreOrCaller.set_epoch_deadline/2`. Without this call, deadlines
  never arrive: nothing else advances the epoch.

  A relaxed atomic increment, so it is cheap enough to call from a timer, and
  safe to call from any process. On an engine without `epoch_interruption`
  it is a no-op that nothing observes.

  Typically driven either by one timer per call (`Process.send_after/3`, then
  increment once to expire that call's deadline) or by a single periodic
  ticker for all stores, with each store's deadline expressed in ticks.

  ## Example

      iex> {:ok, engine} = Wasmex.Engine.new(%Wasmex.EngineConfig{epoch_interruption: true})
      iex> Wasmex.Engine.increment_epoch(engine)
      :ok
  """
  @spec increment_epoch(__MODULE__.t()) :: :ok | {:error, binary()}
  def increment_epoch(%__MODULE__{resource: resource}) do
    case Wasmex.Native.engine_increment_epoch(resource) do
      {:error, err} -> {:error, err}
      :ok -> :ok
    end
  end
end

defimpl Inspect, for: Wasmex.Engine do
  import Inspect.Algebra

  def inspect(dict, opts) do
    concat(["#Wasmex.Engine<", to_doc(dict.reference, opts), ">"])
  end
end
