defmodule Wasmex.Native do
  @moduledoc false

  mix_config = Mix.Project.config()
  version = mix_config[:version]

  # FORK-ONLY — do not upstream.
  #
  # This fork carries Rust patches, so tessi's precompiled NIFs are never the
  # right artifact for it. It used to pin `force_build: true`, which compiled
  # the crate with cargo on every machine that compiled this dependency. Rust
  # builds now run only inside an isolated build VM (vigilix:
  # ~/.config/nix scripts/rust-vm.sh), because build.rs and proc macros run
  # arbitrary code at build time.
  #
  # So the NIF is built once in that VM and pinned here by checksum:
  # checksum-Elixir.Wasmex.Native.exs lists the one artifact this fork accepts.
  # RustlerPrecompiled looks for it in its cache first and downloads from
  # `base_url` only when it is missing, and it refuses any file whose sha256
  # does not match — an unpatched NIF cannot load in its place. There is no
  # cargo fallback: a missing artifact is a compile error, not a host build.
  # Only x86_64 Linux is built.
  use RustlerPrecompiled,
    otp_app: :wasmex,
    base_url: "https://github.com/vmemjp/wasmex/releases/download/vigilix-v#{version}",
    version: version,
    targets: ~w(x86_64-unknown-linux-gnu),
    nif_versions: ["2.15"],
    force_build: false

  def engine_new(_engine_config), do: error()
  def engine_precompile_module(_engine_resource, _bytes), do: error()
  def engine_increment_epoch(_engine_resource), do: error()

  def module_compile(_store_or_caller_resource, _bytes), do: error()
  def module_exports(_module_resource), do: error()
  def module_imports(_module_resource), do: error()
  def module_name(_module_resource), do: error()
  def module_serialize(_module_resource), do: error()
  def module_unsafe_deserialize(_binary, _engine_resource), do: error()

  def instance_new(_store_or_caller_resource, _module_resource, _imports, _links), do: error()

  def instance_function_export_exists(
        _store_or_caller_resource,
        _instance_resource,
        _function_name
      ),
      do: error()

  def instance_receive_callback_result(_callback_token, _success, _params), do: error()

  def instance_call_exported_function(
        _store_or_caller_resource,
        _instance_resource,
        _function_name,
        _params,
        _from
      ),
      do: error()

  def instance_get_global_value(_store_or_caller_resource, _instance_resource, _global_name),
    do: error()

  def instance_set_global_value(
        _store_or_caller_resource,
        _instance_resource,
        _global_name,
        _new_value
      ),
      do: error()

  def memory_from_instance(_store_resource, _memory_resource), do: error()
  def memory_size(_store_resource, _memory_resource), do: error()
  def memory_grow(_store_resource, _memory_resource, _pages), do: error()
  def memory_get_byte(_store_or_caller_resource, _memory_resource, _index), do: error()
  def memory_set_byte(_store_or_caller_resource, _memory_resource, _index, _value), do: error()
  def memory_read_binary(_store_resource, _memory_resource, _index, _length), do: error()
  def memory_write_binary(_store_resource, _memory_resource, _index, _binary), do: error()

  def pipe_new(_capacity), do: error()
  def pipe_size(_pipe_resource), do: error()
  def pipe_seek(_pipe_resource, _pos_from_start), do: error()
  def pipe_read_binary(_pipe_resource), do: error()
  def pipe_write_binary(_pipe_resource, _binary), do: error()

  def store_new(_store_limits, _engine_resource), do: error()
  def store_new_wasi(_wasi_options, _store_limits, _engine_resource), do: error()

  def component_store_new(_store_limits, _engine_resource), do: error()
  def component_store_new_wasi(_wasi_options, _store_limits, _engine_resource), do: error()

  def store_or_caller_get_fuel(_store_or_caller_resource), do: error()
  def store_or_caller_set_fuel(_store_or_caller_resource, _fuel), do: error()
  def store_or_caller_set_epoch_deadline(_store_or_caller_resource, _ticks_beyond_current),
    do: error()

  def component_new(_store, _component_bytes), do: error()
  def component_instance_new(_store, _component, _imports), do: error()
  def component_call_function(_store, _instance, _function_name_path, _params, _from), do: error()

  def component_receive_callback_result(_component_resource, _token, _success, _result),
    do: error()

  def wit_exported_functions(_path, _wit), do: error()

  def wat_to_wasm(_wat), do: error()

  # When the NIF is loaded, it will override functions in this module.
  # Calling error is handles the case when the nif could not be loaded.
  defp error, do: :erlang.nif_error(:nif_not_loaded)
end
