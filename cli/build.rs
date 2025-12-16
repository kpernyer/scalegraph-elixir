fn main() -> Result<(), Box<dyn std::error::Error>> {
    let out_dir = std::env::var("OUT_DIR")?;
    let proto_dir = "../proto";
    
    // List of proto files in dependency order (common first, then others)
    let proto_files = vec![
        "common.proto",
        "ledger.proto",
        "business-rules.proto",
        "smart-contracts.proto",
    ];
    
    // Create temporary proto files without Elixir-specific options
    let mut temp_proto_paths = Vec::new();
    
    for proto_file in &proto_files {
        let proto_path = format!("{}/{}", proto_dir, proto_file);
        let proto_content = std::fs::read_to_string(&proto_path)?;
        
        // Strip Elixir-specific options
        let rust_proto_content = proto_content
            .lines()
            .filter(|line| !line.contains("elixir_module_prefix"))
            .collect::<Vec<_>>()
            .join("\n");
        
        let temp_proto_path = format!("{}/{}", out_dir, proto_file);
        std::fs::write(&temp_proto_path, rust_proto_content)?;
        temp_proto_paths.push(temp_proto_path);
    }
    
    // Compile all proto files together
    // Use the out_dir as the include path so imports work correctly
    // The proto files import each other, so they need to be in the same directory
    tonic_build::configure()
        .build_server(false)
        .compile_protos(&temp_proto_paths, &[out_dir])?;
    
    Ok(())
}
