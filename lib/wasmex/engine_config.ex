defmodule Wasmex.EngineConfig do
  @moduledoc ~S"""
  Configures a `Wasmex.Engine`.

  ## Options

    * `:consume_fuel` - Whether or not to consume fuel when executing Wasm instructions. This defaults to `false`.
    * `:epoch_interruption` - Whether or not Wasm execution can be interrupted when the engine's epoch advances past a store's deadline. This defaults to `false`. See `epoch_interruption/2`.
    * `:cranelift_opt_level` - Optimization level for the Cranelift code generator. This defaults to `:none`.
    * `:wasm_backtrace_details` - Whether or not backtraces in traps will parse debug info in the Wasm file to have filename/line number information. This defaults to `false`.
    * `:debug_info` - Configures whether DWARF debug information will be emitted during compilation. This defaults to `false`.
    * `:memory64` - Whether or not to use 64-bit memory. This defaults to `false`.
    * `:wasm_component_model` - Whether or not to use the WebAssembly component model. This defaults to `true`.

  ## Example

      iex> _config = %Wasmex.EngineConfig{}
      ...>           |> Wasmex.EngineConfig.consume_fuel(true)
      ...>           |> Wasmex.EngineConfig.cranelift_opt_level(:speed)
      ...>           |> Wasmex.EngineConfig.wasm_backtrace_details(false)
  """

  defstruct consume_fuel: false,
            epoch_interruption: false,
            cranelift_opt_level: :none,
            wasm_backtrace_details: false,
            memory64: false,
            wasm_component_model: true,
            debug_info: false

  @type t :: %__MODULE__{
          consume_fuel: boolean(),
          epoch_interruption: boolean(),
          cranelift_opt_level: :none | :speed | :speed_and_size,
          wasm_backtrace_details: boolean(),
          memory64: boolean(),
          wasm_component_model: boolean(),
          debug_info: boolean()
        }

  @doc ~S"""
  Configures whether execution of WebAssembly will "consume fuel" to
  either halt or yield execution as desired.

  This can be used to deterministically prevent infinitely-executing
  WebAssembly code by instrumenting generated code to consume fuel as it
  executes. When fuel runs out a trap is raised.

  Note that a `Wasmex.Store` starts with no fuel, so if you enable this option
  you'll have to be sure to pour some fuel into `Wasmex.Store` before
  executing some code. See `Wasmex.StoreOrCaller.set_fuel/2`.

  ## Example

      iex> config = %Wasmex.EngineConfig{}
      ...>          |> Wasmex.EngineConfig.consume_fuel(true)
      iex> config.consume_fuel
      true
  """
  @spec consume_fuel(t(), boolean()) :: t()
  def consume_fuel(%__MODULE__{} = config, consume_fuel) do
    %__MODULE__{config | consume_fuel: consume_fuel}
  end

  @doc ~S"""
  Configures whether WebAssembly execution can be interrupted by the engine's
  epoch advancing past a store's deadline.

  This is the other way to stop code that would otherwise run forever, and the
  one that answers "stop after N seconds" — fuel counts instructions, which
  are not time. It is also the only mechanism that bounds a guest which is
  *blocked in a host call* rather than spinning in guest code.

  Epochs do not advance on their own. Three parts are needed, and each is
  inert without the others:

    1. an engine configured here;
    2. a deadline per store — `Wasmex.StoreOrCaller.set_epoch_deadline/2`;
    3. something calling `Wasmex.Engine.increment_epoch/1`, usually a timer.

  Cheaper than fuel: fuel instruments generated code to count down on every
  instruction, whereas an epoch check is a load-and-compare at loop backedges
  and function entries against a counter someone else advances.

  ## Example

      iex> config = %Wasmex.EngineConfig{}
      ...>          |> Wasmex.EngineConfig.epoch_interruption(true)
      iex> config.epoch_interruption
      true

  Giving a call one second to live:

      iex> {:ok, engine} = Wasmex.Engine.new(%Wasmex.EngineConfig{epoch_interruption: true})
      iex> {:ok, store} = Wasmex.Store.new(nil, engine)
      iex> Wasmex.StoreOrCaller.set_epoch_deadline(store, 1)
      :ok
      iex> _timer = Process.send_after(self(), :tick, 1_000)
      iex> # on :tick, call Wasmex.Engine.increment_epoch(engine) to trap the guest
  """
  @spec epoch_interruption(t(), boolean()) :: t()
  def epoch_interruption(%__MODULE__{} = config, epoch_interruption) do
    %__MODULE__{config | epoch_interruption: epoch_interruption}
  end

  @doc ~S"""
  Configures whether the WebAssembly memory type is 64-bit.

  ## Example

      iex> config = %Wasmex.EngineConfig{}
      ...>          |> Wasmex.EngineConfig.memory64(true)
      iex> config.memory64
      true
  """
  @spec memory64(t(), boolean()) :: t()
  def memory64(%__MODULE__{} = config, memory64) do
    %__MODULE__{config | memory64: memory64}
  end

  @doc """
  Configures the Cranelift code generator optimization level.

  Allows one of the following values:

  * `:none` - No optimizations performed, minimizes compilation time by disabling most optimizations.
  * `:speed` - Generates the fastest possible code, but may take longer.
  * `:speed_and_size` - Similar to `speed`, but also performs transformations aimed at reducing code size.
  """
  @spec cranelift_opt_level(t(), :none | :speed | :speed_and_size) :: t()
  def cranelift_opt_level(%__MODULE__{} = config, cranelift_opt_level)
      when cranelift_opt_level in [:none, :speed, :speed_and_size] do
    %__MODULE__{config | cranelift_opt_level: cranelift_opt_level}
  end

  @doc ~S"""
  Configures whether backtraces in traps will parse debug info in the Wasm
  file to have filename/line number information.

  When enabled this will causes modules to retain debugging information
  found in Wasm binaries. This debug information will be used when a trap
  happens to symbolicate each stack frame and attempt to print a
  filename/line number for each Wasm frame in the stack trace.

  ## Example

      iex> config = %Wasmex.EngineConfig{}
      ...>          |> Wasmex.EngineConfig.wasm_backtrace_details(true)
      iex> config.wasm_backtrace_details
      true
  """
  @spec wasm_backtrace_details(t(), boolean()) :: t()
  def wasm_backtrace_details(%__MODULE__{} = config, wasm_backtrace_details) do
    %__MODULE__{config | wasm_backtrace_details: wasm_backtrace_details}
  end
end
