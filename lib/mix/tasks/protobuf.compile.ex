defmodule Mix.Tasks.Protobuf.Compile do
  @moduledoc """
  Compiles protobuf files to Elixir code.
  
  This task generates Elixir code from proto/ledger.proto into lib/scalegraph/proto/ledger.pb.ex
  """
  use Mix.Task

  @shortdoc "Compiles protobuf files to Elixir code"

  @impl Mix.Task
  def run(_args) do
    proto_file = Path.join([File.cwd!(), "proto", "ledger.proto"])
    output_dir = Path.join([File.cwd!(), "lib"])
    generated_file = Path.join([output_dir, "scalegraph", "proto", "ledger.pb.ex"])
    
    unless File.exists?(proto_file) do
      Mix.raise("Proto file not found: #{proto_file}")
    end
    
    # Check if we need to recompile
    needs_recompile = 
      !File.exists?(generated_file) ||
      (File.exists?(generated_file) && File.stat!(proto_file).mtime > File.stat!(generated_file).mtime)
    
    if needs_recompile do
      Mix.shell().info("Compiling protobuf files...")
      
      # Check if protoc-gen-elixir is available
      protoc_gen_elixir = find_protoc_gen_elixir()
      
      unless protoc_gen_elixir do
        if File.exists?(generated_file) do
          Mix.shell().info("⚠️  protoc-gen-elixir not found, using existing generated file")
        else
          Mix.raise("""
          protoc-gen-elixir not found and no generated file exists. Please install it:
          
            mix escript.install hex protobuf
          
          Then ensure ~/.mix/escripts is in your PATH.
          """)
        end
      else
        compile_proto(proto_file, output_dir, protoc_gen_elixir)
      end
    end
  end
  
  defp compile_proto(proto_file, output_dir, protoc_gen_elixir) do
    
    # Run protoc
    proto_path = Path.dirname(proto_file)
    proto_name = Path.basename(proto_file)
    
    case System.cmd("protoc", [
      "--elixir_out=plugins=grpc:#{output_dir}",
      "--plugin=protoc-gen-elixir=#{protoc_gen_elixir}",
      "--proto_path=#{proto_path}",
      proto_name
    ], cd: proto_path, stderr_to_stdout: true) do
      {output, 0} ->
        if output != "", do: Mix.shell().info(output)
        Mix.shell().info("✅ Protobuf compilation successful")
        
      {_output, _code} ->
        # Try without the elixir_module_prefix option by creating a temp file
        Mix.shell().info("⚠️  Direct compilation failed, trying with temp file...")
        compile_with_temp_file(proto_file, output_dir, protoc_gen_elixir)
    end
  end
  
  defp find_protoc_gen_elixir do
    # Check common locations
    default_path = Path.expand("~/.mix/escripts/protoc-gen-elixir")
    executable_path = System.find_executable("protoc-gen-elixir")
    
    paths = [default_path]
    paths = if executable_path, do: [executable_path | paths], else: paths
    
    Enum.find(paths, fn path -> path && File.exists?(path) end)
  end
  
  defp compile_with_temp_file(proto_file, output_dir, protoc_gen_elixir) do
    # Read proto file and remove elixir-specific options
    proto_content = File.read!(proto_file)
    temp_content = 
      proto_content
      |> String.split("\n")
      |> Enum.reject(&String.contains?(&1, "elixir_module_prefix"))
      |> Enum.join("\n")
    
    # Create temp file
    temp_file = System.tmp_dir!() |> Path.join("ledger_temp.proto")
    File.write!(temp_file, temp_content)
    
    try do
      proto_name = Path.basename(temp_file)
      
      case System.cmd("protoc", [
        "--elixir_out=plugins=grpc:#{output_dir}",
        "--plugin=protoc-gen-elixir=#{protoc_gen_elixir}",
        "--proto_path=#{System.tmp_dir!()}",
        proto_name
      ], cd: System.tmp_dir!(), stderr_to_stdout: true) do
        {output, 0} ->
          if output != "", do: Mix.shell().info(output)
          
          # Verify the generated file exists
          generated_file = Path.join([output_dir, "scalegraph", "proto", "ledger.pb.ex"])
          if File.exists?(generated_file) do
            # The module prefix is handled by the package name, so we might not need to modify
            Mix.shell().info("✅ Protobuf compilation successful")
          else
            Mix.raise("Generated file not found: #{generated_file}")
          end
          
        {output, code} ->
          Mix.raise("""
          Protobuf compilation failed with exit code #{code}:
          #{output}
          """)
      end
    after
      File.rm(temp_file)
    end
  end
end

